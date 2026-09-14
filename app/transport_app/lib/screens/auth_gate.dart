import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'admin_dashboard.dart';
import 'driver_dashboard.dart';
import 'login_screen.dart';
import 'pending_approval_screen.dart';
import 'parent_dashboard.dart';
import 'profile_completion_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Future<DocumentSnapshot<Map<String, dynamic>>> _fetchLatestUserDoc(String uid) async {
    final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
    try {
      await FirebaseAuth.instance.currentUser?.reload();
    } catch (_) {
      // Keep routing resilient even when auth reload fails transiently.
    }
    // Always fetch a fresh document from server after login.
    return docRef.get(const GetOptions(source: Source.server));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final user = authSnap.data;
        if (user == null) {
          return const LoginScreen();
        }

        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          key: ValueKey<String>(user.uid),
          future: _fetchLatestUserDoc(user.uid),
          builder: (context, freshUserSnap) {
            if (freshUserSnap.connectionState != ConnectionState.done) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            if (freshUserSnap.hasError) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Unable to refresh account state.'),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () => FirebaseAuth.instance.signOut(),
                          child: const Text('Back to Login'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
              builder: (context, userDocSnap) {
                if (!userDocSnap.hasData) {
                  return const Scaffold(body: Center(child: CircularProgressIndicator()));
                }

                final doc = userDocSnap.data;
                if (doc == null || !doc.exists) {
                  return Scaffold(
                    body: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Profile record not found.'),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: () => FirebaseAuth.instance.signOut(),
                              child: const Text('Back to Login'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                final data = doc.data() ?? <String, dynamic>{};
                final role = (data['role'] ?? '').toString().toLowerCase().trim();
                final profileCompleted = data['profileCompleted'] == true;
                final emailVerified =
                    FirebaseAuth.instance.currentUser?.emailVerified ?? false;
                final isApprovedRaw = data['isApproved'];
                var isApproved = isApprovedRaw is bool && isApprovedRaw;
                final status = (data['status'] ?? '').toString().toLowerCase().trim();
                // Backward compatibility: older approved drivers may only have status=active.
                // Sync isApproved once so future checks use the primary auth field.
                if (role == 'driver' && !isApproved && status == 'active') {
                  isApproved = true;
                  FirebaseFirestore.instance.collection('users').doc(user.uid).set(
                    {'isApproved': true},
                    SetOptions(merge: true),
                  );
                }
                print('Driver approval status: $isApproved');

                // Strict driver approval guard.
                if (role == 'driver' && isApproved != true) {
                  return PendingApprovalScreen(
                    emailVerified: emailVerified,
                    isApproved: isApproved,
                  );
                }
                // Keep email verification guard for drivers.
                if (role == 'driver' && !emailVerified) {
                  return PendingApprovalScreen(
                    emailVerified: emailVerified,
                    isApproved: isApproved,
                  );
                }

                if (!profileCompleted) {
                  return ProfileCompletionScreen(
                    userId: user.uid,
                    role: role,
                    initialData: data,
                  );
                }

                if (role == 'parent') return const ParentDashboard();
                if (role == 'driver') return const DriverDashboard(initialIndex: 1);
                if (role == 'admin') return const AdminDashboard();

                return Scaffold(
                  body: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Unsupported role: ${role.isEmpty ? 'unknown' : role}'),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () => FirebaseAuth.instance.signOut(),
                            child: const Text('Back to Login'),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

