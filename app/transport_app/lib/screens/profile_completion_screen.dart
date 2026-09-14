import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'admin_dashboard.dart';
import 'driver_dashboard.dart';
import 'parent_dashboard.dart';

class ProfileCompletionScreen extends StatefulWidget {
  const ProfileCompletionScreen({
    super.key,
    required this.userId,
    required this.role,
    required this.initialData,
  });

  final String userId;
  final String role;
  final Map<String, dynamic> initialData;

  @override
  State<ProfileCompletionScreen> createState() => _ProfileCompletionScreenState();
}

class _ProfileCompletionScreenState extends State<ProfileCompletionScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  late final TextEditingController _nameC;
  late final TextEditingController _phoneC;
  late final TextEditingController _cityC;

  late final TextEditingController _cnicC;
  late final TextEditingController _licenseC;
  late final TextEditingController _vehicleNameC;
  late final TextEditingController _vehicleNumberC;
  late final TextEditingController _routeC;

  @override
  void initState() {
    super.initState();
    _nameC = TextEditingController(text: (widget.initialData['name'] ?? '').toString());
    _phoneC = TextEditingController(text: (widget.initialData['phone'] ?? '').toString());
    _cityC = TextEditingController(text: (widget.initialData['city'] ?? '').toString());
    _cnicC = TextEditingController(text: (widget.initialData['cnic'] ?? '').toString());
    _licenseC = TextEditingController(text: (widget.initialData['licenseNumber'] ?? '').toString());
    _vehicleNameC = TextEditingController(text: (widget.initialData['vehicleName'] ?? '').toString());
    _vehicleNumberC = TextEditingController(text: (widget.initialData['vehicleNumber'] ?? '').toString());
    _routeC = TextEditingController(text: (widget.initialData['route'] ?? '').toString());
  }

  @override
  void dispose() {
    _nameC.dispose();
    _phoneC.dispose();
    _cityC.dispose();
    _cnicC.dispose();
    _licenseC.dispose();
    _vehicleNameC.dispose();
    _vehicleNumberC.dispose();
    _routeC.dispose();
    super.dispose();
  }

  bool _filled(String text) => text.trim().isNotEmpty;

  Future<void> _saveProfileCompletion() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final update = <String, dynamic>{};
      final role = widget.role.toLowerCase().trim();

      if (role == 'parent') {
        update['name'] = _nameC.text.trim();
        update['phone'] = _phoneC.text.trim();
        update['city'] = _cityC.text.trim();
      } else if (role == 'driver') {
        update['cnic'] = _cnicC.text.trim();
        update['licenseNumber'] = _licenseC.text.trim();
        update['vehicleName'] = _vehicleNameC.text.trim();
        update['vehicleNumber'] = _vehicleNumberC.text.trim();
        update['route'] = _routeC.text.trim();
      } else if (role == 'admin') {
        update['name'] = _nameC.text.trim();
        update['phone'] = _phoneC.text.trim();
      } else {
        throw Exception('Unsupported role');
      }

      update['profileCompleted'] = true;

      final userRef = FirebaseFirestore.instance.collection('users').doc(widget.userId);
      await userRef.set(
            update,
            SetOptions(merge: true),
          );

      final refreshed = await userRef.get();
      final refreshedData = refreshed.data() ?? <String, dynamic>{};
      final refreshedRole = (refreshedData['role'] ?? role).toString().toLowerCase().trim();

      if (!mounted) return;
      Widget? target;
      if (refreshedRole == 'parent') {
        target = const ParentDashboard();
      } else if (refreshedRole == 'driver') {
        target = const DriverDashboard();
      } else if (refreshedRole == 'admin') {
        target = const AdminDashboard();
      }

      if (target != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => target!),
        );
        return;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile saved, but role is not supported for navigation.'),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save profile.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.role.toLowerCase();
    final title = role.isEmpty ? 'Complete Profile' : 'Complete ${role[0].toUpperCase()}${role.substring(1)} Profile';
    final awaitingApproval = role == 'driver' &&
        (_filled(_cnicC.text) &&
            _filled(_licenseC.text) &&
            (_filled(_vehicleNameC.text) || _filled(_vehicleNumberC.text)) &&
            _filled(_routeC.text)) &&
        !(widget.initialData['adminApproved'] == true ||
            (widget.initialData['status'] ?? '').toString().toLowerCase() == 'approved');

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (awaitingApproval)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Your details are saved. Please wait for admin approval.',
                    style: TextStyle(color: Colors.orange),
                  ),
                ),
              if (role == 'parent' || role == 'admin') ...[
                TextFormField(
                  controller: _nameC,
                  decoration: const InputDecoration(labelText: 'Name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneC,
                  decoration: const InputDecoration(labelText: 'Phone'),
                  keyboardType: TextInputType.phone,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Phone is required' : null,
                ),
              ],
              if (role == 'parent') ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _cityC,
                  decoration: const InputDecoration(labelText: 'City'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'City is required' : null,
                ),
              ],
              if (role == 'driver') ...[
                TextFormField(
                  controller: _cnicC,
                  decoration: const InputDecoration(labelText: 'CNIC'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'CNIC is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _licenseC,
                  decoration: const InputDecoration(labelText: 'License Number'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'License number is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _vehicleNameC,
                  decoration: const InputDecoration(labelText: 'Vehicle Name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Vehicle name is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _vehicleNumberC,
                  decoration: const InputDecoration(labelText: 'Vehicle Number'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Vehicle number is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _routeC,
                  decoration: const InputDecoration(labelText: 'Route'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Route is required' : null,
                ),
                const SizedBox(height: 12),
                if (!(widget.initialData['adminApproved'] == true ||
                    (widget.initialData['status'] ?? '').toString().toLowerCase() == 'approved'))
                  const Text(
                    'Driver dashboard unlocks after admin approval.',
                    style: TextStyle(color: Colors.orange),
                  ),
              ],
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saving ? null : _saveProfileCompletion,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save and Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

