import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _hidePassword = true;
  bool _hideConfirmPassword = true;
  bool _animateIn = false;

  String? _selectedRole;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _animateIn = true);
    });
  }

  // ---------------- VALIDATIONS ----------------

  bool _isStrongPassword(String password) {
    final regex =
        RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[!@#\$%^&*()_\-+=<>?]).{6,}$');
    return regex.hasMatch(password);
  }

  bool _isValidEmail(String email) {
    final regex = RegExp(
        r"^[a-zA-Z0-9]+([._%+-]?[a-zA-Z0-9]+)*@[a-zA-Z0-9-]+(\.[a-zA-Z]{2,})+$");
    return regex.hasMatch(email);
  }

  // ---------------- SIGNUP LOGIC ----------------

  Future<void> _signup(String role) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final user = cred.user;
      if (user == null) throw FirebaseAuthException(code: 'user-null');

      await user.sendEmailVerification();

      await _firestore.collection('users').doc(user.uid).set({
        'name': name,
        'email': email,
        'role': role,
        'status': role == 'driver' ? 'pending' : 'active',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Verification email sent!')),
      );
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      String msg = '';
      if (e.code == 'email-already-in-use') msg = 'Email already registered.';
      else if (e.code == 'invalid-email') msg = 'Enter a valid email.';
      else if (e.code == 'weak-password') msg = 'Password too weak.';
      else msg = e.message ?? 'Signup failed.';
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } finally {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  // ---------------- UI HELPERS ----------------

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.primary),
      suffixIcon: suffix,
      filled: true,
      fillColor: Theme.of(context).colorScheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  // ---------------- BUILD ----------------

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppTheme.pageGradient),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 48, vertical: 24),
            child: Center(
              child: Column(
                children: [
                  const SizedBox(height: 24),

                  // Header
                  AnimatedScale(
                    scale: _animateIn ? 1 : 0.92,
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutBack,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).colorScheme.primary,
                            AppTheme.primaryDark,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(22),
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.person_add,
                        size: 48,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  Text(
                    "Create Account",
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    "Join us today and get started",
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Theme.of(context).colorScheme.onBackground.withOpacity(0.6)),
                  ),

                  const SizedBox(height: 32),

                  // Form
                  AnimatedSlide(
                    offset: _animateIn ? Offset.zero : const Offset(0, 0.08),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: _animateIn ? 1 : 0,
                      duration: const Duration(milliseconds: 450),
                      child: Container(
                        constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 500),
                        padding: const EdgeInsets.all(28),
                        decoration: AppTheme.glassCardDecoration,
                        child: Form(
                          key: _formKey,
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                          _label("Full Name"),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _nameController,
                            decoration: _inputDecoration(hint: "John Doe", icon: Icons.person_outline),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) return 'Enter your full name';
                              if (!RegExp(r'^[A-Za-z ]+$').hasMatch(value.trim())) return 'Only alphabets allowed';
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),

                          _label("Email Address"),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: _inputDecoration(hint: "you@example.com", icon: Icons.email_outlined),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) return 'Enter your email';
                              if (!_isValidEmail(value.trim())) return 'Enter a valid email';
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),

                          _label("Password"),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _hidePassword,
                            decoration: _inputDecoration(
                              hint: "Min 6 chars, upper, lower, number & special",
                              icon: Icons.lock_outline,
                              suffix: IconButton(
                                icon: Icon(_hidePassword ? Icons.visibility_off : Icons.visibility),
                                onPressed: () => setState(() => _hidePassword = !_hidePassword),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) return 'Enter password';
                              if (!_isStrongPassword(value)) return 'Weak password: min 6 chars, upper, lower, number & special char';
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),

                          _label("Confirm Password"),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: _hideConfirmPassword,
                            decoration: _inputDecoration(
                              hint: "Re-enter password",
                              icon: Icons.lock_outline,
                              suffix: IconButton(
                                icon: Icon(_hideConfirmPassword ? Icons.visibility_off : Icons.visibility),
                                onPressed: () => setState(() => _hideConfirmPassword = !_hideConfirmPassword),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) return 'Confirm your password';
                              if (value != _passwordController.text) return 'Passwords do not match';
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),

                          _label("Select Role"),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _selectedRole,
                            decoration: _inputDecoration(hint: "Choose role", icon: Icons.badge_outlined),
                            items: const [
                              DropdownMenuItem(value: 'parent', child: Text('Parent')),
                              DropdownMenuItem(value: 'driver', child: Text('Driver')),
                            ],
                            onChanged: (value) => setState(() => _selectedRole = value),
                            validator: (value) => value == null ? 'Please select a role' : null,
                          ),
                          const SizedBox(height: 28),

                          ElevatedButton(
                            onPressed: _isLoading
                                ? null
                                : () {
                                    if (_selectedRole == null) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Please select a role')));
                                      return;
                                    }
                                    _signup(_selectedRole!);
                                  },
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 56),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            ),
                            child: _isLoading
                                ? const CircularProgressIndicator(strokeWidth: 2)
                                : const Text("Create Account"),
                          ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Already have an account? "),
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text("Sign In")),
                    ],
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
