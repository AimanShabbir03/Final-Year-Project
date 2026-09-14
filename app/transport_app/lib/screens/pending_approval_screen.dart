import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({
    super.key,
    required this.emailVerified,
    required this.isApproved,
  });

  final bool emailVerified;
  final bool isApproved;

  @override
  Widget build(BuildContext context) {
    final waitingOnEmail = !emailVerified;
    final waitingOnApproval = !isApproved;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Approval'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.hourglass_top_rounded, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              const Text(
                'Driver access is currently locked.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              if (waitingOnEmail)
                const Text(
                  'Please verify your email before continuing.',
                  textAlign: TextAlign.center,
                ),
              if (waitingOnApproval)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Your account is waiting for admin approval.',
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 20),
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
}
