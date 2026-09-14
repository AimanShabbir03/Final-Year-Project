import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show FieldPath;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import 'admin_dashboard.dart';
import 'gps_controller.dart';
import 'driver_location_screen.dart';
import 'driver_parent_location_screen.dart';
import 'driver_ride_map_screen.dart';
import 'parent_dashboard.dart';
import '../services/directions_service.dart';
import '../services/financial_accounting_service.dart';

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({Key? key, this.initialIndex = 0}) : super(key: key);

  final int initialIndex;

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  final _firestore = FirebaseFirestore.instance;
  final _storage = FirebaseStorage.instance;
  final _user = FirebaseAuth.instance.currentUser!;
  int _index = 0;
  final Map<String, Future<DocumentSnapshot>> _parentFutures = {};

  Future<DocumentSnapshot> _getParentFuture(String parentId) {
    if (!_parentFutures.containsKey(parentId)) {
      _parentFutures[parentId] = _firestore.collection('users').doc(parentId).get();
    }
    return _parentFutures[parentId]!;
  }

  Uint8List? _profilePic, _cnicPic, _licensePic, _vehiclePic;
  bool _loadingProfile = false, _loadingCnic = false, _loadingLicense = false, _loadingVehicle = false;

  final _nameC = TextEditingController();
  final _cnicC = TextEditingController();
  final _phoneC = TextEditingController();
  final _licenseC = TextEditingController();
  final _vehicleNameC = TextEditingController();
  final _vehicleNumberC = TextEditingController();
  final _seatsC = TextEditingController();

  String? _selectedSchool;
  String? _selectedRoute;
  final Set<String> _childrenOnRide = {};
  final Map<String, String> _childToParent = {};
  final Map<String, String> _activeRideDocIdByChild = {};
  bool _savingProfile = false;
  String? _rideActionChildId;
  static const double _rideActionAllowedMeters = 100.0;
  final Map<String, _RideMode> _selectedRideModeByChild = {};
  bool _sendingAvailability = false;
  final Set<String> _flaggingReviewIds = {};
  String _earningsParentQuery = '';
  String _earningsRouteQuery = '';
  String _earningsTransactionQuery = '';
  String _earningsStatusFilter = 'all';
  DateTime? _earningsDateFilter;
  String _feedbackCommentQuery = '';
  String _feedbackRatingFilter = 'all';
  String _feedbackSentimentFilter = 'all';
  DateTime? _feedbackDateFilter;
  static const List<MapEntry<String, String>> _weekDays = [
    MapEntry('monday', 'Monday'),
    MapEntry('tuesday', 'Tuesday'),
    MapEntry('wednesday', 'Wednesday'),
    MapEntry('thursday', 'Thursday'),
    MapEntry('friday', 'Friday'),
    MapEntry('saturday', 'Saturday'),
    MapEntry('sunday', 'Sunday'),
  ];

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, 6);
  }

  List<String> _uniqueNonEmptyNames(QuerySnapshot snap) {
    final unique = <String>{};
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final name = (data['name'] ?? '').toString().trim();
      if (name.isNotEmpty) unique.add(name);
    }
    return unique.toList();
  }

  String? _safeSelectedValue(String? selectedValue, List<String> items) {
    if (selectedValue == null) return null;
    return items.contains(selectedValue) ? selectedValue : null;
  }

  Widget _premiumCard({
    required Widget child,
    EdgeInsetsGeometry? margin,
    EdgeInsetsGeometry? padding,
    Color? baseColor,
  }) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            baseColor ?? Colors.white,
            AppTheme.subtleSurface.withOpacity(0.4),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.06),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.white,
            blurRadius: 0,
            offset: const Offset(-2, -2),
          ),
        ],
        border: Border.all(color: Colors.white.withOpacity(0.8), width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: padding ?? EdgeInsets.all(AppTheme.horizontalPadding(context)),
          child: child,
        ),
      ),
    );
  }

  Widget _drawerNavTile({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? AppTheme.primary.withOpacity(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: selected ? AppTheme.primary : AppTheme.textSecondary,
          size: 22,
        ),
        title: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppTheme.primary : AppTheme.textPrimary,
          ),
        ),
        onTap: onTap,
      ),
    );
  }

  @override
  void dispose() {
    _nameC.dispose();
    _cnicC.dispose();
    _phoneC.dispose();
    _licenseC.dispose();
    _vehicleNameC.dispose();
    _vehicleNumberC.dispose();
    _seatsC.dispose();
    super.dispose();
  }

  Future<void> _pickUpload(String type) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    setState(() {
      if (type == 'profilePic') _loadingProfile = true;
      if (type == 'cnicPic') _loadingCnic = true;
      if (type == 'licensePic') _loadingLicense = true;
      if (type == 'vehiclePic') _loadingVehicle = true;
    });

    try {
      final bytes = await picked.readAsBytes();
      final ref = _storage.ref('drivers/${_user.uid}/$type.jpg');
      await ref.putData(bytes);
      final url = await ref.getDownloadURL();
      await _firestore.collection('users').doc(_user.uid).set({type: url}, SetOptions(merge: true));
      setState(() {
        if (type == 'profilePic') _profilePic = bytes;
        if (type == 'cnicPic') _cnicPic = bytes;
        if (type == 'licensePic') _licensePic = bytes;
        if (type == 'vehiclePic') _vehiclePic = bytes;
      });
    } finally {
      setState(() {
        if (type == 'profilePic') _loadingProfile = false;
        if (type == 'cnicPic') _loadingCnic = false;
        if (type == 'licensePic') _loadingLicense = false;
        if (type == 'vehiclePic') _loadingVehicle = false;
      });
    }
  }

  Widget _imgRow(String label, Uint8List? local, String? url, String type, BuildContext context) {
    ImageProvider? img = local != null
        ? MemoryImage(local)
        : (url != null && url.isNotEmpty ? NetworkImage(url) : null);
    
    bool isLoading = (type == 'profilePic')
        ? _loadingProfile
        : (type == 'cnicPic')
            ? _loadingCnic
            : (type == 'licensePic')
                ? _loadingLicense
                : _loadingVehicle;

    return _premiumCard(
      margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.primary.withOpacity(0.1), width: 2),
                ),
                child: CircleAvatar(
                  radius: 28,
                  backgroundImage: img,
                  backgroundColor: AppTheme.subtleSurface,
                  child: img == null ? const Icon(Icons.person_rounded, color: AppTheme.textSecondary) : null,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16, color: AppTheme.textPrimary),
                ),
              ),
              if (isLoading)
                const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              else if (AppTheme.isNarrow(context))
                const SizedBox.shrink()
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _smallButton(context, 'Upload', () => _pickUpload(type), false),
                    if (img != null) ...[
                      const SizedBox(width: 8),
                      _smallButton(context, 'View', () => _viewImage(label, img!), false),
                    ],
                  ],
                ),
            ],
          ),
          if (AppTheme.isNarrow(context)) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _smallButton(context, 'Upload', () => _pickUpload(type), false)),
                if (img != null) ...[
                  const SizedBox(width: 8),
                  Expanded(child: _smallButton(context, 'View', () => _viewImage(label, img!), false)),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _smallButton(BuildContext context, String label, VoidCallback onPressed, bool loading) {
    if (loading) return const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));
    return SizedBox(
      height: 38,
      child: label == 'Upload'
          ? ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                minimumSize: Size.zero,
              ),
              child: Text(label),
            )
          : OutlinedButton(
              onPressed: onPressed,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                minimumSize: Size.zero,
              ),
              child: Text(label),
            ),
    );
  }

  void _viewImage(String label, ImageProvider img) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: Text(label),
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: InteractiveViewer(
            child: Center(
              child: Image(image: img, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openParentLocationForChild(Map<String, dynamic> child) async {
    final lat = (child['parentLatitude'] as num?)?.toDouble();
    final lng = (child['parentLongitude'] as num?)?.toDouble();
    if (lat == null || lng == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Parent location is not available for this child.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final routeName = (child['route'] ?? '').toString();
    double schoolLat = 0, schoolLng = 0;
    if (routeName.isNotEmpty) {
      final bounds = await getRouteBoundsByRouteName(_firestore, routeName);
      if (bounds != null) {
        schoolLat = bounds.startLat;
        schoolLng = bounds.startLng;
      }
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverParentLocationScreen(
          childName: (child['name'] ?? 'Child').toString(),
          parentLatitude: lat,
          parentLongitude: lng,
          schoolLatitude: schoolLat,
          schoolLongitude: schoolLng,
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    final ctx = context;
    if (_nameC.text.isEmpty || _cnicC.text.length != 13 || _phoneC.text.length != 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill Name, CNIC (13 digits), and Phone (11 digits)')),
      );
      return;
    }
    setState(() => _savingProfile = true);
    try {
      await _firestore.collection('users').doc(_user.uid).set({
        'name': _nameC.text.trim(),
        'cnic': _cnicC.text.trim(),
        'phone': _phoneC.text.trim(),
        'licenseNumber': _licenseC.text.trim(),
        'vehicleName': _vehicleNameC.text.trim(),
        'vehicleNumber': _vehicleNumberC.text.trim(),
        'school': _selectedSchool ?? '',
        'route': _selectedRoute ?? '',
        'seats': _seatsC.text.trim(),
        'profileCompleted': true,
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.pushReplacement(
        ctx,
        MaterialPageRoute(builder: (_) => const DriverDashboard(initialIndex: 1)),
      );
    } finally {
      if (mounted) {
        setState(() => _savingProfile = false);
      }
    }
  }

  bool _isProfileComplete(Map<String, dynamic> d) {
    final requiredFields = [
      'name', 'cnic', 'phone', 'licenseNumber', 
      'vehicleName', 'vehicleNumber', 'school', 'route', 'seats',
      'profilePic', 'cnicPic', 'licensePic', 'vehiclePic'
    ];
    for (final field in requiredFields) {
      if ((d[field] ?? '').toString().trim().isEmpty) return false;
    }
    // Specific checks
    if ((d['cnic'] ?? '').toString().length != 13) return false;
    if ((d['phone'] ?? '').toString().length != 11) return false;
    
    return true;
  }

  Future<Position?> _resolveCurrentPosition() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
    }
    return Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
  }

  Widget _profile(Map<String, dynamic> d) {
    _nameC.text = d['name'] ?? '';
    _cnicC.text = d['cnic'] ?? '';
    _phoneC.text = d['phone'] ?? '';
    _licenseC.text = d['licenseNumber'] ?? '';
    _vehicleNameC.text = d['vehicleName'] ?? '';
    _vehicleNumberC.text = d['vehicleNumber'] ?? '';
    _seatsC.text = d['seats'] ?? '';
    if (_selectedSchool == null && d['school'] != null && d['school'].toString().isNotEmpty) _selectedSchool = d['school'];
    if (_selectedRoute == null && d['route'] != null && d['route'].toString().isNotEmpty) _selectedRoute = d['route'];

    final padding = AppTheme.contentPadding(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        return SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: AppTheme.maxContentWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Documents & photos', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                SizedBox(height: AppTheme.verticalSpacing(context)),
                _imgRow('Profile', _profilePic, d['profilePic'], 'profilePic', context),
                _imgRow('CNIC', _cnicPic, d['cnicPic'], 'cnicPic', context),
                _imgRow('License', _licensePic, d['licensePic'], 'licensePic', context),
                _imgRow('Vehicle', _vehiclePic, d['vehiclePic'], 'vehiclePic', context),
                SizedBox(height: AppTheme.verticalSpacing(context) * 2),
                Text('Personal & vehicle info', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                SizedBox(height: AppTheme.verticalSpacing(context)),
                TextField(controller: _nameC, decoration: const InputDecoration(labelText: 'Name'), textInputAction: TextInputAction.next),
                SizedBox(height: AppTheme.verticalSpacing(context)),
                TextField(controller: _cnicC, decoration: const InputDecoration(labelText: 'CNIC (13 digits)'), keyboardType: TextInputType.number, inputFormatters: [LengthLimitingTextInputFormatter(13)], textInputAction: TextInputAction.next),
                SizedBox(height: AppTheme.verticalSpacing(context)),
                TextField(controller: _phoneC, decoration: const InputDecoration(labelText: 'Phone (11 digits)'), keyboardType: TextInputType.phone, inputFormatters: [LengthLimitingTextInputFormatter(11)], textInputAction: TextInputAction.next),
                SizedBox(height: AppTheme.verticalSpacing(context)),
                TextField(controller: _licenseC, decoration: const InputDecoration(labelText: 'License Number'), textInputAction: TextInputAction.next),
                SizedBox(height: AppTheme.verticalSpacing(context)),
                TextField(controller: _vehicleNameC, decoration: const InputDecoration(labelText: 'Vehicle Name'), textInputAction: TextInputAction.next),
                SizedBox(height: AppTheme.verticalSpacing(context)),
                TextField(controller: _vehicleNumberC, decoration: const InputDecoration(labelText: 'Vehicle Number'), textInputAction: TextInputAction.next),
                SizedBox(height: AppTheme.verticalSpacing(context)),
                StreamBuilder<QuerySnapshot>(
                  stream: _firestore.collection('schools').snapshots(),
                  builder: (context, schoolSnap) {
                    if (!schoolSnap.hasData) return const Center(child: CircularProgressIndicator());
                    final schoolList = _uniqueNonEmptyNames(schoolSnap.data!);
                    final selectedSchool = _safeSelectedValue(_selectedSchool, schoolList);
                    return DropdownButtonFormField<String>(
                      value: selectedSchool,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'School'),
                      hint: const Text('Select School'),
                      items: schoolList.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis, maxLines: 1))).toList(),
                      onChanged: (v) => setState(() => _selectedSchool = v),
                    );
                  },
                ),
                SizedBox(height: AppTheme.verticalSpacing(context)),
                StreamBuilder<QuerySnapshot>(
                  stream: _firestore.collection('routes').snapshots(),
                  builder: (context, routeSnap) {
                    if (!routeSnap.hasData) return const Center(child: CircularProgressIndicator());
                    final routeList = _uniqueNonEmptyNames(routeSnap.data!);
                    final selectedRoute = _safeSelectedValue(_selectedRoute, routeList);
                    return DropdownButtonFormField<String>(
                      value: selectedRoute,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Route'),
                      hint: const Text('Select Area'),
                      items: routeList.map((r) => DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis, maxLines: 1))).toList(),
                      onChanged: (v) => setState(() => _selectedRoute = v),
                    );
                  },
                ),
                SizedBox(height: AppTheme.verticalSpacing(context)),
                TextField(controller: _seatsC, decoration: const InputDecoration(labelText: 'Seats'), keyboardType: TextInputType.number, textInputAction: TextInputAction.done),
                SizedBox(height: AppTheme.verticalSpacing(context) * 2),
                FilledButton.icon(
                  onPressed: _savingProfile ? null : _saveProfile,
                  icon: const Icon(Icons.save_rounded, size: 20),
                  label: Text(_savingProfile ? 'Saving…' : 'Save profile'),
                ),
                SizedBox(height: MediaQuery.paddingOf(context).bottom + 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _dashboard(Map<String, dynamic> d) {
    final padding = AppTheme.contentPadding(context);
    final isOnRide = _childrenOnRide.isNotEmpty;
    final isAvailable = d['availability'] == true;
    final statusLabel = isOnRide ? 'On Ride' : (isAvailable ? 'Online' : 'Offline');
    final statusColor = isOnRide
        ? AppTheme.success
        : (isAvailable ? AppTheme.primary : AppTheme.textSecondary);
    final routeSummary = '${(d['route'] ?? 'Not set').toString()} • ${(d['school'] ?? 'School not set').toString()}';
    return SingleChildScrollView(
      padding: padding,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: AppTheme.maxContentWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _premiumCard(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundImage: d['profilePic'] != null ? NetworkImage(d['profilePic']) : null,
                    backgroundColor: AppTheme.primary.withOpacity(0.2),
                    child:
                        d['profilePic'] == null ? const Icon(Icons.person, size: 32, color: AppTheme.primary) : null,
                  ),
                  SizedBox(width: AppTheme.horizontalPadding(context)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d['name'] ?? 'Driver',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isOnRide ? Icons.directions_car_filled_rounded : Icons.circle,
                                size: 14,
                                color: statusColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                statusLabel,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        StreamBuilder<QuerySnapshot>(
                          stream: _firestore
                              .collection('reviews')
                              .where('driverId', isEqualTo: _user.uid)
                              .snapshots(),
                          builder: (context, snap) {
                            final reviewDocs = snap.data?.docs ?? [];
                            double sum = 0;
                            int count = 0;
                            for (final doc in reviewDocs) {
                              final data = doc.data() as Map<String, dynamic>? ?? {};
                              final rating = (data['rating'] as num?)?.toDouble();
                              if (rating != null && rating > 0) {
                                sum += rating;
                                count += 1;
                              }
                            }
                            final avg = count == 0 ? 0 : sum / count;
                            return Row(
                              children: [
                                ...List.generate(5, (i) {
                                  return Icon(
                                    i < avg.round() ? Icons.star_rounded : Icons.star_border_rounded,
                                    size: 18,
                                    color: Colors.amber.shade700,
                                  );
                                }),
                                const SizedBox(width: 8),
                                Text(
                                  count == 0 ? 'No ratings yet' : '${avg.toStringAsFixed(1)} ($count)',
                                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: AppTheme.verticalSpacing(context)),

            LayoutBuilder(
              builder: (context, constraints) {
                final crossCount = constraints.maxWidth >= 760 ? 4 : 2;
                return GridView.count(
                  crossAxisCount: crossCount,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    StreamBuilder<QuerySnapshot>(
                      stream:
                          _firestore.collection('rides').where('driverId', isEqualTo: _user.uid).snapshots(),
                      builder: (context, snap) {
                        final totalTrips = snap.data?.docs.length ?? 0;
                        return _dashboardStatCard(
                          icon: Icons.route_rounded,
                          label: 'Total Trips',
                          value: '$totalTrips',
                        );
                      },
                    ),
                    StreamBuilder<QuerySnapshot>(
                      stream:
                          _firestore.collection('rides').where('driverId', isEqualTo: _user.uid).snapshots(),
                      builder: (context, snap) {
                        final now = DateTime.now();
                        final todayStart = DateTime(now.year, now.month, now.day);
                        final docs = snap.data?.docs ?? const [];
                        final todayTrips = docs.where((doc) {
                          final data = doc.data() as Map<String, dynamic>? ?? {};
                          final ts = data['startTime'] ?? data['createdAt'];
                          if (ts is! Timestamp) return false;
                          final dt = ts.toDate();
                          return !dt.isBefore(todayStart);
                        }).length;
                        return _dashboardStatCard(
                          icon: Icons.today_rounded,
                          label: 'Today Trips',
                          value: '$todayTrips',
                        );
                      },
                    ),
                    StreamBuilder<QuerySnapshot>(
                      stream: _firestore
                          .collection('earnings_ledger')
                          .where('driverId', isEqualTo: _user.uid)
                          .snapshots(),
                      builder: (context, snap) {
                        final docs = snap.data?.docs ?? const [];
                        final total = docs.fold<double>(0, (sum, doc) {
                          final data = doc.data() as Map<String, dynamic>? ?? {};
                          return sum + ((data['driverAmount'] as num?)?.toDouble() ?? 0);
                        });
                        return _dashboardStatCard(
                          icon: Icons.payments_rounded,
                          label: 'Total Earnings',
                          value: 'PKR ${total.toStringAsFixed(0)}',
                        );
                      },
                    ),
                    StreamBuilder<QuerySnapshot>(
                      stream: _firestore
                          .collection('requests')
                          .where('driverId', isEqualTo: _user.uid)
                          .where('status', isEqualTo: 'approved')
                          .snapshots(),
                      builder: (context, snap) {
                        final docs = snap.data?.docs ?? const [];
                        int childrenCount = 0;
                        for (final doc in docs) {
                          final data = doc.data() as Map<String, dynamic>? ?? {};
                          final childIds = data['childIds'];
                          if (childIds is List) {
                            childrenCount += childIds.length;
                          } else {
                            childrenCount += 1;
                          }
                        }
                        return _dashboardStatCard(
                          icon: Icons.groups_rounded,
                          label: 'Assigned Children',
                          value: '$childrenCount',
                        );
                      },
                    ),
                  ],
                );
              },
            ),

            SizedBox(height: AppTheme.verticalSpacing(context)),
            _premiumCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Active Ride',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(
                        isOnRide ? Icons.directions_car_filled_rounded : Icons.pause_circle_outline_rounded,
                        color: statusColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        statusLabel,
                        style: TextStyle(fontWeight: FontWeight.w600, color: statusColor),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    routeSummary,
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => setState(() => _index = 2),
                      icon: Icon(isOnRide ? Icons.stop_circle_outlined : Icons.play_circle_outline_rounded),
                      label: Text(isOnRide ? 'End Ride' : 'Start Ride'),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: AppTheme.verticalSpacing(context)),
            _premiumCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Quick Actions',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _quickActionChip(
                        icon: Icons.people_alt_rounded,
                        label: 'View Children',
                        onTap: () => setState(() => _index = 2),
                      ),
                      _quickActionChip(
                        icon: Icons.calendar_month_rounded,
                        label: 'Weekly Availability',
                        onTap: () => setState(() => _index = 3),
                      ),
                      _quickActionChip(
                        icon: Icons.feedback_outlined,
                        label: 'View Feedback',
                        onTap: () => setState(() => _index = 5),
                      ),
                      _quickActionChip(
                        icon: Icons.payments_outlined,
                        label: 'Earnings',
                        onTap: () => setState(() => _index = 6),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            SizedBox(height: MediaQuery.paddingOf(context).bottom + 16),
          ],
        ),
      ),
    );
  }

  Widget _dashboardStatCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primary.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.primary.withOpacity(0.12),
            child: Icon(icon, color: AppTheme.primary, size: 18),
          ),
          const Spacer(),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _quickActionChip({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: onTap == null ? AppTheme.subtleSurface : AppTheme.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: onTap == null ? AppTheme.textSecondary : AppTheme.primary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: onTap == null ? AppTheme.textSecondary : AppTheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, bool> _normalizeWeeklyAvailability(Map<String, dynamic> d) {
    final weeklyRaw = d['weeklyAvailability'];
    final result = {
      for (final day in _weekDays) day.key: false,
    };
    if (weeklyRaw is Map) {
      for (final day in _weekDays) {
        result[day.key] = weeklyRaw[day.key] == true;
      }
    }
    return result;
  }

  Future<void> _updateWeeklyAvailabilityDay({
    required String dayKey,
    required String dayLabel,
    required bool available,
  }) async {
    setState(() => _sendingAvailability = true);
    try {
      final requestsSnap = await _firestore
          .collection('requests')
          .where('driverId', isEqualTo: _user.uid)
          .where('status', isEqualTo: 'approved')
          .get();

      final parentIds = requestsSnap.docs
          .map((doc) => (doc.data())['parentId'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      final driverSnap = await _firestore.collection('users').doc(_user.uid).get();
      final driverName = driverSnap.data()?['name'] ?? 'Driver';
      final message = available
          ? 'Driver will be available on $dayLabel.'
          : 'Driver will be unavailable on $dayLabel.';

      if (parentIds.isNotEmpty) {
        final batch = _firestore.batch();
        for (final pId in parentIds) {
          final notifRef = _firestore.collection('notifications').doc();
          batch.set(notifRef, {
            'parentId': pId,
            'type': 'driver_availability',
            'driverId': _user.uid,
            'driverName': driverName,
            'message': message,
            'timestamp': FieldValue.serverTimestamp(),
            'read': false,
          });
        }
        await batch.commit();
      }

      await _firestore.collection('users').doc(_user.uid).set({
        'weeklyAvailability': {dayKey: available},
        'lastAvailabilityUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              parentIds.isEmpty
                  ? '$dayLabel updated. No connected parents to notify.'
                  : 'Updated $dayLabel and notified ${parentIds.length} parent(s).',
            ),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sendingAvailability = false);
      }
    }
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return _premiumCard(
      margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context)),
      padding: EdgeInsets.zero,
      child: ListTile(
          leading: CircleAvatar(radius: 22, backgroundColor: AppTheme.primary.withOpacity(0.12), child: Icon(icon, color: AppTheme.primary, size: 22)),
          title: Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          subtitle: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
      ),
    );
  }

  Future<void> _sendRideNotificationToParent({required String type, required String parentId, required String childName}) async {
    if (parentId.isEmpty) return;
    try {
      final driverSnap = await _firestore.collection('users').doc(_user.uid).get();
      final driverName = driverSnap.data()?['name'] ?? 'Driver';
      final message = type == 'ride_started'
          ? 'Child Picked Up: $childName.'
          : 'Child Dropped Off: $childName.';
      await _firestore.collection('notifications').add({
        'parentId': parentId,
        'type': type,
        'driverId': _user.uid,
        'driverName': driverName,
        'childName': childName,
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
      });
    } catch (e) {
      debugPrint('Error sending ride notification: $e');
    }
  }

  Future<void> _updateAvailability(bool available) async {
    setState(() => _sendingAvailability = true);
    try {
      final message = available
          ? "Driver is available for today's ride"
          : "Sorry for inconvenience driver is not available";

      final requestsSnap = await _firestore
          .collection('requests')
          .where('driverId', isEqualTo: _user.uid)
          .where('status', isEqualTo: 'approved')
          .get();

      final parentIds = requestsSnap.docs
          .map((doc) => (doc.data())['parentId'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      if (parentIds.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No parents connected to notify.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final driverSnap = await _firestore.collection('users').doc(_user.uid).get();
      final driverName = driverSnap.data()?['name'] ?? 'Driver';

      final batch = _firestore.batch();
      for (final pId in parentIds) {
        final notifRef = _firestore.collection('notifications').doc();
        batch.set(notifRef, {
          'parentId': pId,
          'type': 'driver_availability',
          'driverId': _user.uid,
          'driverName': driverName,
          'message': message,
          'timestamp': FieldValue.serverTimestamp(),
          'read': false,
        });
      }
      await batch.commit();

      await _firestore.collection('users').doc(_user.uid).update({
        'availability': available,
        'lastAvailabilityUpdate': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Availability notification sent to ${parentIds.length} parents.'),
            backgroundColor: AppTheme.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sendingAvailability = false);
      }
    }
  }

  _RideMode _getRideModeForChild(String childId) {
    return _selectedRideModeByChild[childId] ?? _RideMode.morning;
  }

  Widget _assignedChildren(Map<String, dynamic> driverData) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('requests').where('driverId', isEqualTo: _user.uid).where('status', isEqualTo: 'approved').snapshots(),
      builder: (context, driverReqSnap) {
        if (!driverReqSnap.hasData) return const Center(child: CircularProgressIndicator());
        final driverRequests = driverReqSnap.data!.docs;
        if (driverRequests.isEmpty) {
          return Center(
            child: Padding(
              padding: AppTheme.contentPadding(context),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 64, color: AppTheme.textSecondary.withOpacity(0.5)),
                  const SizedBox(height: 16),
                  Text('No children assigned yet', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.textSecondary)),
                  const SizedBox(height: 8),
                  Text('Assigned children will appear here.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary)),
                ],
              ),
            ),
          );
        }
        final uniqueParentIds = driverRequests.map((d) => (d.data() as Map<String, dynamic>)['parentId'] as String?).whereType<String>().toSet().toList();

        return SingleChildScrollView(
          padding: AppTheme.contentPadding(context),
          child: Column(
            children: uniqueParentIds.map((parentId) {
              return FutureBuilder<DocumentSnapshot>(
                future: _getParentFuture(parentId),
                builder: (context, parentSnap) {
                  if (!parentSnap.hasData) return const SizedBox();
                  final parentData = parentSnap.data!.data() as Map<String, dynamic>? ?? {};
                  final children = parentData['children'] as List<dynamic>? ?? [];
                  final assignedChildren = children.where((c) => c['assignedDriver'] == _user.uid).toList();
                  if (assignedChildren.isEmpty) return const SizedBox();
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    bool changed = false;
                    for (final c in assignedChildren) {
                      final id = c['id']?.toString();
                      if (id != null && _childToParent[id] != parentId) {
                        _childToParent[id] = parentId;
                        changed = true;
                      }
                    }
                    if (changed) {
                      setState(() {});
                    }
                  });

                  return Column(
                    children: assignedChildren.map((child) {
                      final picUrl = child['photo'] ?? '';
                      final childId = child['id'] as String? ?? '';
                      final isChildOnRide = _childrenOnRide.contains(childId);
                      final isActionLoading = _rideActionChildId == childId;
                      final selectedRideMode = _getRideModeForChild(childId);
                      final pickupLabel = selectedRideMode == _RideMode.morning ? "Parent's Home" : 'School';
                      final destinationLabel = selectedRideMode == _RideMode.morning ? 'School' : "Parent's Home";
                      return _premiumCard(
                        margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context)),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () {
                                      if (picUrl.toString().isNotEmpty) {
                                        _viewImage(child['name'] ?? 'Child', NetworkImage(picUrl.toString()));
                                      }
                                    },
                                    child: CircleAvatar(
                                      radius: 28,
                                      backgroundImage: picUrl.toString().isNotEmpty ? NetworkImage(picUrl) : null,
                                      backgroundColor: AppTheme.primary.withOpacity(0.15),
                                      child: picUrl.toString().isEmpty ? const Icon(Icons.person, size: 28, color: AppTheme.primary) : null,
                                    ),
                                  ),
                                  SizedBox(width: AppTheme.horizontalPadding(context)),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(child['name'] ?? 'Unknown', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                                        const SizedBox(height: 2),
                                        Text('Age: ${child['age'] ?? '—'} • ${child['school'] ?? '—'}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                                        Text('Route: ${child['route'] ?? '—'}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                                        Text('Parent: ${parentData['name'] ?? 'Unknown'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: AppTheme.verticalSpacing(context)),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final narrow = constraints.maxWidth < 320;
                                  return Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      SegmentedButton<_RideMode>(
                                        segments: const [
                                          ButtonSegment<_RideMode>(
                                            value: _RideMode.morning,
                                            label: Text('Morning Ride'),
                                            icon: Icon(Icons.wb_sunny_outlined, size: 16),
                                          ),
                                          ButtonSegment<_RideMode>(
                                            value: _RideMode.evening,
                                            label: Text('Evening Ride'),
                                            icon: Icon(Icons.nightlight_round, size: 16),
                                          ),
                                        ],
                                        selected: {selectedRideMode},
                                        onSelectionChanged: isChildOnRide
                                            ? null
                                            : (selection) {
                                                setState(() {
                                                  _selectedRideModeByChild[childId] = selection.first;
                                                });
                                              },
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: isActionLoading
                                            ? null
                                            : () async {
                                                final routeName = (driverData['route'] ?? '').toString();
                                                if (routeName.isEmpty) {
                                                  if (mounted) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(
                                                        content: Text('Route is not set for this driver.'),
                                                        behavior: SnackBarBehavior.floating,
                                                      ),
                                                    );
                                                  }
                                                  return;
                                                }
                                                final bounds = await getRouteBoundsByRouteName(
                                                  _firestore,
                                                  routeName,
                                                );
                                                 if (bounds == null || !mounted) return;
                                                 final parentLat = (child['parentLatitude'] as num?)?.toDouble();
                                                 final parentLng = (child['parentLongitude'] as num?)?.toDouble();

                                                 await Navigator.push(
                                                   context,
                                                   MaterialPageRoute(
                                                     builder: (_) => DriverRideMapScreen(
                                                       childName: (child['name'] ?? 'Child').toString(),
                                                       rideModeLabel: selectedRideMode == _RideMode.morning
                                                           ? 'Morning Ride'
                                                           : 'Evening Ride',
                                                       parentLocation: LatLng(parentLat ?? bounds.startLat, parentLng ?? bounds.startLng),
                                                       schoolLocation: LatLng(bounds.startLat, bounds.startLng),
                                                       isMorningRide: selectedRideMode == _RideMode.morning,
                                                       liveTrackingMode: isChildOnRide,
                                                      ),
                                                    ),
                                                  );
                                                },
                                        icon: const Icon(Icons.map_outlined, size: 18),
                                        label: Text(narrow ? 'Map' : 'Show map'),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: () async {
                                          final telUri = Uri(scheme: 'tel', path: parentData['phone'] ?? '');
                                          if (await canLaunchUrl(telUri)) await launchUrl(telUri);
                                        },
                                        icon: const Icon(Icons.phone_outlined, size: 18),
                                        label: Text(narrow ? 'Call' : 'Call parent'),
                                      ),
                                      if (isChildOnRide)
                                        OutlinedButton.icon(
                                          onPressed: () => _openParentLocationForChild(
                                            child,
                                          ),
                                          icon: const Icon(
                                            Icons.location_on_outlined,
                                            size: 18,
                                          ),
                                          label: Text(
                                            narrow
                                                ? 'Location'
                                                : 'Parent location',
                                          ),
                                        ),
                                      FilledButton.icon(
                                        onPressed: isActionLoading
                                            ? null
                                            : () async {
                                                setState(() => _rideActionChildId = childId);
                                                try {
                                                  final newRideOn = !isChildOnRide;
                                                  final routeName =
                                                      (driverData['route'] ?? '').toString();
                                                  if (routeName.isEmpty) {
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            'Route is not set. Please update your route before starting/stopping ride.',
                                                          ),
                                                          behavior: SnackBarBehavior.floating,
                                                        ),
                                                      );
                                                    }
                                                    return;
                                                  }

                                                  final bounds =
                                                      await getRouteBoundsByRouteName(
                                                    _firestore,
                                                    routeName,
                                                  );
                                                  if (bounds == null) {
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            'Unable to verify route location for this ride.',
                                                          ),
                                                          behavior: SnackBarBehavior.floating,
                                                        ),
                                                      );
                                                    }
                                                    return;
                                                  }

                                                  final routeFareSnap = await _firestore
                                                      .collection('routes')
                                                      .where('name', isEqualTo: routeName)
                                                      .limit(1)
                                                      .get();
                                                  final routeFareData = routeFareSnap.docs.isNotEmpty
                                                      ? routeFareSnap.docs.first.data()
                                                      : null;
                                                  final routeFare = (routeFareData?['fare'] as num?)?.toDouble();
                                                  if (routeFare == null || routeFare <= 0) {
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        const SnackBar(
                                                          content: Text('Route fare is missing. Ask admin to set fare first.'),
                                                          behavior: SnackBarBehavior.floating,
                                                        ),
                                                      );
                                                    }
                                                    return;
                                                  }

                                                  final currentPosition =
                                                      await _resolveCurrentPosition();
                                                  if (currentPosition == null) {
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(context).showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            'Location permission is required to start/stop ride.',
                                                          ),
                                                          behavior: SnackBarBehavior.floating,
                                                        ),
                                                      );
                                                    }
                                                    return;
                                                  }

                                                  final parentLat = (child['parentLatitude'] as num?)?.toDouble();
                                                  final parentLng = (child['parentLongitude'] as num?)?.toDouble();
                                                  
                                                  // Set GPS tracking bounds based on ride mode
                                                  double startLatForBounds, startLngForBounds, endLatForBounds, endLngForBounds;
                                                  
                                                  if (selectedRideMode == _RideMode.morning) {
                                                    // Morning ride: Parent home → School
                                                    startLatForBounds = parentLat ?? bounds.startLat;
                                                    startLngForBounds = parentLng ?? bounds.startLng;
                                                    endLatForBounds = bounds.startLat;
                                                    endLngForBounds = bounds.startLng;
                                                  } else {
                                                    // Evening ride: School → Parent home
                                                    startLatForBounds = bounds.startLat;
                                                    startLngForBounds = bounds.startLng;
                                                    endLatForBounds = parentLat ?? bounds.endLat;
                                                    endLngForBounds = parentLng ?? bounds.endLng;
                                                  }

                                                  if (!newRideOn) {
                                                    final distanceToDest = Geolocator.distanceBetween(
                                                      currentPosition.latitude,
                                                      currentPosition.longitude,
                                                      endLatForBounds,
                                                      endLngForBounds,
                                                    );
                                                    if (distanceToDest > 50) {
                                                      if (mounted) {
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          const SnackBar(
                                                            content: Text('Move within 50m of destination to stop the ride.'),
                                                            backgroundColor: AppTheme.error,
                                                            behavior: SnackBarBehavior.floating,
                                                          ),
                                                        );
                                                      }
                                                      return;
                                                    }
                                                  }

                                                  final childName = child['name'] ?? 'your child';
                                                  await _sendRideNotificationToParent(type: newRideOn ? 'ride_started' : 'ride_ended', parentId: parentId, childName: childName);
                                                  if (newRideOn) {
                                                    final rideRef = _firestore.collection('rides').doc();
                                                    await rideRef.set({
                                                      'rideId': rideRef.id,
                                                      'parentId': parentId,
                                                      'driverId': _user.uid,
                                                      'childId': childId,
                                                      'childName': childName,
                                                      'rideStatus': 'in_progress',
                                                      'paymentStatus': 'pending',
                                                      'fare': routeFare,
                                                      'rideMode': selectedRideMode == _RideMode.morning ? 'morning' : 'evening',
                                                      'route': routeName,
                                                      'startTime': FieldValue.serverTimestamp(),
                                                      'updatedAt': FieldValue.serverTimestamp(),
                                                    });
                                                    _activeRideDocIdByChild[childId] = rideRef.id;
                                                  } else {
                                                    DocumentReference<Map<String, dynamic>>? rideRef;
                                                    final rideDocId = _activeRideDocIdByChild[childId];
                                                    if (rideDocId != null && rideDocId.isNotEmpty) {
                                                      rideRef = _firestore.collection('rides').doc(rideDocId);
                                                    } else {
                                                      final activeRideSnap = await _firestore
                                                          .collection('rides')
                                                          .where('driverId', isEqualTo: _user.uid)
                                                          .where('childId', isEqualTo: childId)
                                                          .where('rideStatus', isEqualTo: 'in_progress')
                                                          .limit(1)
                                                          .get();
                                                      if (activeRideSnap.docs.isNotEmpty) {
                                                        rideRef = activeRideSnap.docs.first.reference;
                                                      }
                                                    }

                                                    if (rideRef != null) {
                                                      await rideRef.set({
                                                        'rideStatus': 'completed',
                                                        'paymentStatus': 'pending',
                                                        'endTime': FieldValue.serverTimestamp(),
                                                        'updatedAt': FieldValue.serverTimestamp(),
                                                      }, SetOptions(merge: true));
                                                    } else {
                                                      final fallbackRideRef = _firestore.collection('rides').doc();
                                                      await fallbackRideRef.set({
                                                        'rideId': fallbackRideRef.id,
                                                        'parentId': parentId,
                                                        'driverId': _user.uid,
                                                        'childId': childId,
                                                        'childName': childName,
                                                        'rideStatus': 'completed',
                                                        'paymentStatus': 'pending',
                                                        'fare': routeFare,
                                                        'rideMode': selectedRideMode == _RideMode.morning ? 'morning' : 'evening',
                                                        'route': routeName,
                                                        'startTime': FieldValue.serverTimestamp(),
                                                        'endTime': FieldValue.serverTimestamp(),
                                                        'updatedAt': FieldValue.serverTimestamp(),
                                                      });
                                                    }
                                                    _activeRideDocIdByChild.remove(childId);
                                                  }
                                                  setState(() {
                                                    if (newRideOn) {
                                                      _childrenOnRide.add(childId);
                                                    } else {
                                                      _childrenOnRide.remove(childId);
                                                    }
                                                  });
                                                  if (_childrenOnRide.isNotEmpty) {
                                                    final parentIds = _childrenOnRide.map((c) => _childToParent[c]).whereType<String>().toSet().toList();
                                                    
                                                    final routePoints = await getRoadRoutePoints(
                                                      originLat: startLatForBounds,
                                                      originLng: startLngForBounds,
                                                      destLat: endLatForBounds,
                                                      destLng: endLngForBounds,
                                                    );

                                                    final driverBounds = DriverRouteBounds(
                                                      startLat: startLatForBounds,
                                                      startLng: startLngForBounds,
                                                      endLat: endLatForBounds,
                                                      endLng: endLngForBounds,
                                                      polylinePoints: routePoints?.map((p) => (p.latitude, p.longitude)).toList(),
                                                    );
                                                    
                                                    // Initialize driverLocations doc immediately so parent sees driver right away
                                                    if (newRideOn) {
                                                      try {
                                                        await _firestore.collection('driverLocations').doc(_user.uid).set({
                                                          'status': 'onRide',
                                                          'timestamp': FieldValue.serverTimestamp(),
                                                          'latitude': currentPosition.latitude,
                                                          'longitude': currentPosition.longitude,
                                                        }, SetOptions(merge: true));
                                                      } catch (e) {
                                                        print('Failed to initialize driverLocations: $e');
                                                      }
                                                    }
                                                    
                                                    if (GPSController.isTracking) {
                                                      GPSController.updateRideParents(parentIds);
                                                    } else {
                                                      await GPSController.startTracking(_user.uid, routeBounds: driverBounds, parentIds: parentIds);
                                                      // Give GPS a moment to start
                                                      await Future.delayed(const Duration(milliseconds: 500));
                                                      if (!GPSController.isTracking) {
                                                        if (mounted) {
                                                          ScaffoldMessenger.of(context).showSnackBar(
                                                            SnackBar(
                                                              content: const Text('GPS failed to start. Please check location services in settings.'),
                                                              backgroundColor: AppTheme.error,
                                                              behavior: SnackBarBehavior.floating,
                                                            ),
                                                          );
                                                        }
                                                      }
                                                    }
                                                  } else {
                                                    GPSController.stopTracking();
                                                    await GPSController.clearRideStatus(_user.uid);
                                                  }
                                                  await _firestore.collection('users').doc(_user.uid).set({'rideStatus': _childrenOnRide.isNotEmpty ? 'on' : 'off'}, SetOptions(merge: true));
                                                } catch (e) {
                                                  if (mounted) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        content: Text('Error: $e'),
                                                        backgroundColor: AppTheme.error,
                                                        behavior: SnackBarBehavior.floating,
                                                      ),
                                                    );
                                                  }
                                                } finally {
                                                  if (mounted) {
                                                    setState(() => _rideActionChildId = null);
                                                  }
                                                }
                                              },
                                        style: FilledButton.styleFrom(backgroundColor: isChildOnRide ? AppTheme.error : AppTheme.success),
                                        icon: isActionLoading
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                              )
                                            : Icon(isChildOnRide ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 18),
                                        label: Text(
                                          isActionLoading
                                              ? 'Please wait…'
                                              : (isChildOnRide ? 'Stop ride' : 'Start ride'),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                      );
                    }).toList(),
                  );
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _manageRoute() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore.collection('routes').snapshots(),
      builder: (context, routeSnap) {
        if (!routeSnap.hasData) return const Center(child: CircularProgressIndicator());
        final routeList = _uniqueNonEmptyNames(routeSnap.data!);
        final selectedRoute = _safeSelectedValue(_selectedRoute, routeList);
        return StreamBuilder<QuerySnapshot>(
          stream: _firestore.collection('schools').snapshots(),
          builder: (context, schoolSnap) {
            if (!schoolSnap.hasData) return const Center(child: CircularProgressIndicator());
            final schoolList = _uniqueNonEmptyNames(schoolSnap.data!);
            final selectedSchool = _safeSelectedValue(_selectedSchool, schoolList);
            final padding = AppTheme.contentPadding(context);
            return SingleChildScrollView(
              padding: padding,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: AppTheme.maxContentWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      value: selectedSchool,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'School'),
                      hint: const Text('Select School'),
                      items: schoolList.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis, maxLines: 1))).toList(),
                      onChanged: (v) => setState(() => _selectedSchool = v),
                    ),
                    SizedBox(height: AppTheme.verticalSpacing(context)),
                    DropdownButtonFormField<String>(
                      value: selectedRoute,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Route'),
                      hint: const Text('Select Area'),
                      items: routeList.map((r) => DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis, maxLines: 1))).toList(),
                      onChanged: (v) => setState(() => _selectedRoute = v),
                    ),
                    SizedBox(height: AppTheme.verticalSpacing(context)),
                    TextField(controller: _vehicleNameC, decoration: const InputDecoration(labelText: 'Vehicle name')),
                    SizedBox(height: AppTheme.verticalSpacing(context)),
                    TextField(controller: _seatsC, decoration: const InputDecoration(labelText: 'Seats'), keyboardType: TextInputType.number),
                    SizedBox(height: AppTheme.verticalSpacing(context) * 2),
                    FilledButton.icon(
                      onPressed: () async {
                        if (_selectedSchool == null || _selectedRoute == null) return;
                        await _firestore.collection('driverRoutes').add({
                          'driverId': _user.uid,
                          'school': _selectedSchool!,
                          'route': _selectedRoute!,
                          'vehicle': _vehicleNameC.text,
                          'seats': _seatsC.text,
                        });
                        await _firestore.collection('users').doc(_user.uid).set({'school': _selectedSchool!, 'route': _selectedRoute!}, SetOptions(merge: true));
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: const Text('Route saved'), backgroundColor: AppTheme.success, behavior: SnackBarBehavior.floating),
                          );
                        }
                      },
                      icon: const Icon(Icons.add_road_rounded, size: 20),
                      label: const Text('Add route'),
                    ),
                    SizedBox(height: MediaQuery.paddingOf(context).bottom + 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _availability(Map<String, dynamic> d) {
    final padding = AppTheme.contentPadding(context);
    final weeklyAvailability = _normalizeWeeklyAvailability(d);
    return SingleChildScrollView(
      padding: padding,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: AppTheme.maxContentWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Set your weekly availability',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Parents are notified whenever a day is updated.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
            SizedBox(height: AppTheme.verticalSpacing(context) * 2),
            ..._weekDays.map((day) {
              final isAvailable = weeklyAvailability[day.key] == true;
              return _premiumCard(
                margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      isAvailable ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      color: isAvailable ? AppTheme.success : AppTheme.error,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        day.value,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    Switch.adaptive(
                      value: isAvailable,
                      onChanged: _sendingAvailability
                          ? null
                          : (next) => _updateWeeklyAvailabilityDay(
                                dayKey: day.key,
                                dayLabel: day.value,
                                available: next,
                              ),
                    ),
                  ],
                ),
              );
            }),
            if (_sendingAvailability)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Center(
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        'Saving weekly availability...',
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            SizedBox(height: MediaQuery.paddingOf(context).bottom + 16),
          ],
        ),
      ),
    );
  }

  Widget _availabilityActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: _sendingAvailability ? null : onTap,
      borderRadius: BorderRadius.circular(24),
      child: _premiumCard(
        padding: const EdgeInsets.all(20),
        baseColor: color.withOpacity(0.05),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 16, color: color.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }

  Widget _empty(String title, IconData icon) {
    return Center(
      child: Padding(
        padding: AppTheme.contentPadding(context),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: AppTheme.textSecondary.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text('$title', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Future<Map<String, String>> _fetchParentNamesByIds(List<String> parentIds) async {
    if (parentIds.isEmpty) return const <String, String>{};
    final uniqueIds = parentIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (uniqueIds.isEmpty) return const <String, String>{};

    final futures = uniqueIds.map((id) async {
      final snap = await _firestore.collection('users').doc(id).get();
      final data = snap.data();
      final label = (data?['name'] ?? data?['email'] ?? '').toString().trim();
      return MapEntry(id, label.isEmpty ? id : label);
    }).toList();

    final results = await Future.wait(futures);
    return {for (final entry in results) entry.key: entry.value};
  }

  String _compactId(String value) {
    final text = value.trim();
    if (text.length <= 16) return text;
    return '${text.substring(0, 10)}...${text.substring(text.length - 4)}';
  }

  Future<void> _copyValue(String label, String value) async {
    final text = value.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _earningsDetailRow({
    required IconData icon,
    required String text,
    String? copyLabel,
    String? copyValue,
    Color iconColor = AppTheme.textSecondary,
    FontWeight fontWeight = FontWeight.normal,
    Color textColor = AppTheme.textSecondary,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: textColor,
                fontWeight: fontWeight,
              ),
            ),
          ),
          if (copyValue != null && copyValue.isNotEmpty)
            IconButton(
              onPressed: () => _copyValue(copyLabel ?? 'Value', copyValue),
              tooltip: copyLabel == null ? 'Copy' : 'Copy $copyLabel',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              icon: const Icon(Icons.copy_rounded, size: 18),
            ),
        ],
      ),
    );
  }

  Widget _buildDriverFilterWrap({
    required List<Widget> children,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final useSingleColumn = maxWidth < 520;
        final columnWidth =
            useSingleColumn ? maxWidth : (maxWidth - 10) / 2;
        final textFieldWidth =
            useSingleColumn ? maxWidth : math.min(250.0, columnWidth);
        final dropdownWidth = useSingleColumn
            ? maxWidth
            : math.min(maxWidth, math.max(columnWidth, 200.0));
        final actionButtonWidth =
            useSingleColumn ? maxWidth : math.min(columnWidth, 220.0);

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: children.map((child) {
            if (child is _DriverFilterField) {
              final width = switch (child.kind) {
                _DriverFilterFieldKind.text => child.preferredWidth == null
                    ? textFieldWidth
                    : (useSingleColumn
                        ? maxWidth
                        : math.min(child.preferredWidth!, columnWidth)),
                _DriverFilterFieldKind.dropdown => dropdownWidth,
                _DriverFilterFieldKind.action => actionButtonWidth,
                _DriverFilterFieldKind.plain => null,
              };
              if (width == null) return child.child;
              return SizedBox(width: width, child: child.child);
            }
            return child;
          }).toList(),
        );
      },
    );
  }

  Widget _driverFilterTextField({
    required Widget child,
    double? preferredWidth,
  }) {
    return _DriverFilterField(
      kind: _DriverFilterFieldKind.text,
      preferredWidth: preferredWidth,
      child: child,
    );
  }

  Widget _driverFilterDropdown({required Widget child}) {
    return _DriverFilterField(
      kind: _DriverFilterFieldKind.dropdown,
      child: child,
    );
  }

  Widget _driverFilterAction({required Widget child}) {
    return _DriverFilterField(
      kind: _DriverFilterFieldKind.action,
      child: child,
    );
  }

  Future<void> _pickEarningsDateFilter() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _earningsDateFilter ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null || !mounted) return;
    setState(() => _earningsDateFilter = picked);
  }

  void _resetEarningsFilters() {
    setState(() {
      _earningsParentQuery = '';
      _earningsRouteQuery = '';
      _earningsTransactionQuery = '';
      _earningsStatusFilter = 'all';
      _earningsDateFilter = null;
    });
  }

  Future<void> _pickFeedbackDateFilter() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _feedbackDateFilter ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null || !mounted) return;
    setState(() => _feedbackDateFilter = picked);
  }

  void _resetFeedbackFilters() {
    setState(() {
      _feedbackCommentQuery = '';
      _feedbackRatingFilter = 'all';
      _feedbackSentimentFilter = 'all';
      _feedbackDateFilter = null;
    });
  }

  Widget _earningsPage() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('earnings_ledger')
          .where('driverId', isEqualTo: _user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final entries = snapshot.data!.docs
            .map((d) => {'id': d.id, ...(d.data() as Map<String, dynamic>)})
            .toList();

        entries.sort((a, b) {
          final aTs = a['createdAt'] as Timestamp?;
          final bTs = b['createdAt'] as Timestamp?;
          if (aTs == null && bTs == null) return 0;
          if (aTs == null) return 1;
          if (bTs == null) return -1;
          return bTs.compareTo(aTs);
        });

        final total = entries.fold<double>(
          0,
          (sum, item) => sum + ((item['driverAmount'] as num?)?.toDouble() ?? 0),
        );

        if (entries.isEmpty) {
          return Center(
            child: Padding(
              padding: AppTheme.contentPadding(context),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.payments_outlined, size: 56, color: AppTheme.textSecondary.withOpacity(0.5)),
                  const SizedBox(height: 16),
                  Text(
                    'No earnings yet',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          );
        }

        final rideIds = entries
            .map((e) => (e['rideId'] ?? '').toString())
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();

        return StreamBuilder<QuerySnapshot>(
          stream: _firestore
              .collection('rides')
              .where(FieldPath.documentId, whereIn: rideIds.isEmpty ? ['__none__'] : rideIds)
              .snapshots(),
          builder: (context, ridesSnap) {
            final ridesById = {
              for (final d in (ridesSnap.data?.docs ?? const []))
                d.id: (d.data() as Map<String, dynamic>),
            };
            final driverAccountId = FinancialAccountingService.buildAccountId(
              role: 'driver',
              userId: _user.uid,
            );
            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _firestore
                  .collection('financial_accounts')
                  .doc(driverAccountId)
                  .snapshots(),
              builder: (context, accountSnap) {
                final accountData =
                    accountSnap.data?.data() ?? const <String, dynamic>{};
                final accountId =
                    (accountData['accountId'] ?? driverAccountId).toString();
                final totalEarningsFromAccount =
                    (accountData['totalEarnings'] as num?)?.toDouble() ?? total;
                final totalPaidRides = (accountData['totalPaidRides'] as num?)
                        ?.toInt() ??
                    entries.length;
                final parentIds = ridesById.values
                    .map((ride) => (ride['parentId'] ?? '').toString().trim())
                    .where((id) => id.isNotEmpty)
                    .toSet()
                    .toList();

                return FutureBuilder<Map<String, String>>(
                  future: _fetchParentNamesByIds(parentIds),
                  builder: (context, parentNamesSnap) {
                    final parentNamesById =
                        parentNamesSnap.data ?? const <String, String>{};

                    bool sameDay(DateTime a, DateTime b) =>
                        a.year == b.year &&
                        a.month == b.month &&
                        a.day == b.day;

                    final filteredEntries = entries.where((entry) {
                      final rideId = (entry['rideId'] ?? '').toString();
                      final rideData =
                          ridesById[rideId] ?? const <String, dynamic>{};
                      final parentId =
                          (rideData['parentId'] ?? '').toString().trim();
                      final parentNameFromRide =
                          (rideData['parentName'] ?? '').toString().trim();
                      final parentName = parentNameFromRide.isNotEmpty
                          ? parentNameFromRide
                          : (parentNamesById[parentId] ?? parentId);
                      final route = (rideData['route'] ??
                              rideData['routeName'] ??
                              '')
                          .toString()
                          .trim();
                      final transactionId =
                          (entry['transactionId'] ?? '').toString().trim();
                      final paymentStatusRaw = (entry['paymentStatus'] ??
                              entry['status'] ??
                              rideData['paymentStatus'] ??
                              'paid')
                          .toString()
                          .toLowerCase()
                          .trim();
                      final paymentStatus = paymentStatusRaw.isEmpty
                          ? 'paid'
                          : paymentStatusRaw;
                      final paymentDateValue =
                          entry['paymentDateTime'] ?? entry['createdAt'];
                      DateTime? paymentDate;
                      if (paymentDateValue is Timestamp) {
                        paymentDate = paymentDateValue.toDate();
                      } else if (paymentDateValue is DateTime) {
                        paymentDate = paymentDateValue;
                      }

                      final parentMatches = _earningsParentQuery.trim().isEmpty ||
                          parentName
                              .toLowerCase()
                              .contains(_earningsParentQuery.trim().toLowerCase());
                      final routeMatches = _earningsRouteQuery.trim().isEmpty ||
                          route
                              .toLowerCase()
                              .contains(_earningsRouteQuery.trim().toLowerCase());
                      final transactionMatches =
                          _earningsTransactionQuery.trim().isEmpty ||
                              transactionId
                                  .toLowerCase()
                                  .contains(_earningsTransactionQuery.trim().toLowerCase());
                      final statusMatches = _earningsStatusFilter == 'all' ||
                          paymentStatus == _earningsStatusFilter;
                      final dateMatches = _earningsDateFilter == null ||
                          (paymentDate != null &&
                              sameDay(paymentDate, _earningsDateFilter!));

                      return parentMatches &&
                          routeMatches &&
                          transactionMatches &&
                          statusMatches &&
                          dateMatches;
                    }).toList();

                    return ListView(
                      padding: AppTheme.contentPadding(context),
                      children: [
                        _premiumCard(
                          margin: EdgeInsets.only(
                            bottom: AppTheme.verticalSpacing(context),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Financial Account',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textPrimary,
                                    ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Account ID: ${accountId.trim().isEmpty ? '-' : accountId}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              Text(
                                'Total Earnings: PKR ${totalEarningsFromAccount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              Text(
                                'Total Paid Rides: $totalPaidRides',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _premiumCard(
                          margin: EdgeInsets.only(
                            bottom: AppTheme.verticalSpacing(context),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Total Earnings',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'PKR ${total.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _premiumCard(
                          margin: EdgeInsets.only(
                            bottom: AppTheme.verticalSpacing(context),
                          ),
                          child: _buildDriverFilterWrap(
                            children: [
                              _driverFilterTextField(
                                preferredWidth: 220,
                                child: TextFormField(
                                  key: ValueKey('earnings-parent-$_earningsParentQuery'),
                                  initialValue: _earningsParentQuery,
                                  onChanged: (value) =>
                                      setState(() => _earningsParentQuery = value),
                                  decoration: const InputDecoration(
                                    labelText: 'Filter Parent Name',
                                    prefixIcon: Icon(Icons.person_search_rounded),
                                  ),
                                ),
                              ),
                              _driverFilterTextField(
                                preferredWidth: 210,
                                child: TextFormField(
                                  key: ValueKey('earnings-route-$_earningsRouteQuery'),
                                  initialValue: _earningsRouteQuery,
                                  onChanged: (value) =>
                                      setState(() => _earningsRouteQuery = value),
                                  decoration: const InputDecoration(
                                    labelText: 'Filter Route',
                                    prefixIcon: Icon(Icons.alt_route_rounded),
                                  ),
                                ),
                              ),
                              _driverFilterTextField(
                                preferredWidth: 250,
                                child: TextFormField(
                                  key: ValueKey(
                                    'earnings-transaction-$_earningsTransactionQuery',
                                  ),
                                  initialValue: _earningsTransactionQuery,
                                  onChanged: (value) => setState(
                                    () => _earningsTransactionQuery = value,
                                  ),
                                  decoration: const InputDecoration(
                                    labelText: 'Filter Transaction ID',
                                    prefixIcon: Icon(Icons.receipt_long_rounded),
                                  ),
                                ),
                              ),
                              _driverFilterDropdown(
                                child: DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  value: _earningsStatusFilter,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'all',
                                      child: Text('Status: All'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'paid',
                                      child: Text('Status: Paid'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setState(() => _earningsStatusFilter = value);
                                  },
                                  decoration: const InputDecoration(
                                    labelText: 'Payment Status',
                                  ),
                                ),
                              ),
                              _driverFilterAction(
                                child: OutlinedButton.icon(
                                  onPressed: _pickEarningsDateFilter,
                                  icon: const Icon(Icons.date_range_rounded),
                                  label: Text(
                                    _earningsDateFilter == null
                                        ? 'Filter Date'
                                        : '${_earningsDateFilter!.day.toString().padLeft(2, '0')}/${_earningsDateFilter!.month.toString().padLeft(2, '0')}/${_earningsDateFilter!.year}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              _DriverFilterField(
                                kind: _DriverFilterFieldKind.plain,
                                child: TextButton.icon(
                                  onPressed: _resetEarningsFilters,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Reset'),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (filteredEntries.isEmpty)
                          _premiumCard(
                            margin: EdgeInsets.only(
                              bottom: AppTheme.verticalSpacing(context),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                'No earnings found for the selected filters.',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ...filteredEntries.map((entry) {
                          final amount =
                              (entry['driverAmount'] as num?)?.toDouble() ?? 0;
                          final rideId = (entry['rideId'] ?? '').toString();
                          final rideData =
                              ridesById[rideId] ?? const <String, dynamic>{};
                          final parentId =
                              (rideData['parentId'] ?? '').toString().trim();
                          final parentNameFromRide =
                              (rideData['parentName'] ?? '').toString().trim();
                          final parentName = parentNameFromRide.isNotEmpty
                              ? parentNameFromRide
                              : (parentNamesById[parentId] ?? parentId);
                          final route = (rideData['route'] ??
                                  rideData['routeName'] ??
                                  '—')
                              .toString();
                          final startTime = rideData['startTime'] is Timestamp
                              ? (rideData['startTime'] as Timestamp).toDate()
                              : null;
                          final rideDate = startTime != null
                              ? _formatReviewDate(startTime)
                              : '—';
                          final transactionId =
                              (entry['transactionId'] ?? '').toString().trim();
                          final paymentIntentId =
                              (entry['stripePaymentIntentId'] ?? '')
                                  .toString()
                                  .trim();
                          final paymentMethodRaw = (entry['paymentMethod'] ??
                                  entry['method'] ??
                                  'stripe')
                              .toString()
                              .toLowerCase()
                              .trim();
                          final paymentMethod = paymentMethodRaw.contains('stripe')
                              ? 'Stripe'
                              : (paymentMethodRaw.isEmpty
                                  ? '-'
                                  : paymentMethodRaw);
                          final paymentStatusRaw = (entry['paymentStatus'] ??
                                  entry['status'] ??
                                  rideData['paymentStatus'] ??
                                  'paid')
                              .toString()
                              .toLowerCase()
                              .trim();
                          final paymentStatus = paymentStatusRaw.isEmpty
                              ? 'paid'
                              : paymentStatusRaw;
                          final paymentDateValue =
                              entry['paymentDateTime'] ?? entry['createdAt'];
                          final paymentDateLabel = paymentDateValue is Timestamp
                              ? _formatReviewDate(paymentDateValue.toDate())
                              : '-';

                          return _premiumCard(
                            margin: EdgeInsets.only(
                              bottom: AppTheme.verticalSpacing(context),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        parentName.isEmpty
                                            ? 'Parent: Not available'
                                            : 'Parent: $parentName',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      fit: FlexFit.loose,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFD1FAE5),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          paymentStatus == 'paid'
                                              ? 'Paid'
                                              : paymentStatus,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF065F46),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                _earningsDetailRow(
                                  icon: Icons.alt_route_rounded,
                                  text: 'Route: $route',
                                ),
                                _earningsDetailRow(
                                  icon: Icons.event_rounded,
                                  text: 'Ride Date: $rideDate',
                                ),
                                const SizedBox(height: 4),
                                _earningsDetailRow(
                                  icon: Icons.payments_rounded,
                                  text: 'PKR ${amount.toStringAsFixed(2)}',
                                  iconColor: AppTheme.success,
                                  textColor: AppTheme.success,
                                  fontWeight: FontWeight.w700,
                                ),
                                const SizedBox(height: 8),
                                _earningsDetailRow(
                                  icon: Icons.receipt_long_rounded,
                                  text:
                                      'Transaction ID: ${transactionId.isEmpty ? '-' : _compactId(transactionId)}',
                                  copyLabel: 'Transaction ID',
                                  copyValue: transactionId,
                                ),
                                _earningsDetailRow(
                                  icon: Icons.qr_code_rounded,
                                  text:
                                      'Stripe PaymentIntent ID: ${paymentIntentId.isEmpty ? '-' : _compactId(paymentIntentId)}',
                                  copyLabel: 'PaymentIntent ID',
                                  copyValue: paymentIntentId,
                                ),
                                _earningsDetailRow(
                                  icon: Icons.credit_card_rounded,
                                  text: 'Payment Method: $paymentMethod',
                                ),
                                _earningsDetailRow(
                                  icon: Icons.schedule_rounded,
                                  text: 'Payment Date & Time: $paymentDateLabel',
                                ),
                              ],
                            ),
                          );
                        }),
                        SizedBox(height: MediaQuery.paddingOf(context).bottom + 16),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _feedbackPage() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('reviews')
          .where('driverId', isEqualTo: _user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final reviewDocs = (snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
          .where((doc) {
            final status = (doc.data()['status'] ?? 'active')
                .toString()
                .toLowerCase()
                .trim();
            return status != 'deleted' && status != 'removed_by_admin';
          })
          .toList()
          ..sort((a, b) {
            final aTs = a.data()['createdAt'] as Timestamp?;
            final bTs = b.data()['createdAt'] as Timestamp?;
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return bTs.compareTo(aTs);
          });

        if (reviewDocs.isEmpty) {
          return Center(child: _empty('No feedback available yet', Icons.feedback_outlined));
        }

        final ratings = reviewDocs
            .map((d) => (d.data()['rating'] as num?)?.toDouble() ?? 0)
            .where((r) => r > 0)
            .toList();
        final averageRating = ratings.isEmpty
            ? 0.0
            : ratings.reduce((a, b) => a + b) / ratings.length;

        bool sameDay(DateTime a, DateTime b) =>
            a.year == b.year && a.month == b.month && a.day == b.day;

        final filteredReviewDocs = reviewDocs.where((doc) {
          final review = doc.data();
          final rating = ((review['rating'] as num?)?.toInt() ?? 0).clamp(0, 5);
          final comment = (review['comment'] ?? '').toString().toLowerCase().trim();
          final sentiment = (review['sentiment'] ?? 'neutral')
              .toString()
              .toLowerCase()
              .trim();
          final createdAt = (review['createdAt'] as Timestamp?)?.toDate();

          final commentMatches = _feedbackCommentQuery.trim().isEmpty ||
              comment.contains(_feedbackCommentQuery.trim().toLowerCase());
          final ratingMatches = _feedbackRatingFilter == 'all' ||
              rating.toString() == _feedbackRatingFilter;
          final sentimentMatches = _feedbackSentimentFilter == 'all' ||
              sentiment == _feedbackSentimentFilter;
          final dateMatches = _feedbackDateFilter == null ||
              (createdAt != null && sameDay(createdAt, _feedbackDateFilter!));

          return commentMatches &&
              ratingMatches &&
              sentimentMatches &&
              dateMatches;
        }).toList();

        return ListView(
          padding: AppTheme.contentPadding(context),
          children: [
            _premiumCard(
              margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context)),
              child: Row(
                children: [
                  const Icon(Icons.star_rounded, color: Colors.amber),
                  const SizedBox(width: 8),
                  Text(
                    '${averageRating.toStringAsFixed(1)} Average Rating',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                  ),
                ],
              ),
            ),
            _premiumCard(
              margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context)),
              child: _buildDriverFilterWrap(
                children: [
                  _driverFilterTextField(
                    preferredWidth: 240,
                    child: TextFormField(
                      key: ValueKey('feedback-comment-$_feedbackCommentQuery'),
                      initialValue: _feedbackCommentQuery,
                      onChanged: (value) =>
                          setState(() => _feedbackCommentQuery = value),
                      decoration: const InputDecoration(
                        labelText: 'Search Review Comment',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                  ),
                  _driverFilterDropdown(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _feedbackRatingFilter,
                      isDense: true,
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All Ratings')),
                        DropdownMenuItem(value: '1', child: Text('⭐1')),
                        DropdownMenuItem(value: '2', child: Text('⭐2')),
                        DropdownMenuItem(value: '3', child: Text('⭐3')),
                        DropdownMenuItem(value: '4', child: Text('⭐4')),
                        DropdownMenuItem(value: '5', child: Text('⭐5')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _feedbackRatingFilter = value);
                      },
                      decoration: const InputDecoration(
                        labelText: 'Rating',
                      ),
                    ),
                  ),
                  _driverFilterDropdown(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _feedbackSentimentFilter,
                      isDense: true,
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All')),
                        DropdownMenuItem(value: 'positive', child: Text('Positive')),
                        DropdownMenuItem(value: 'neutral', child: Text('Neutral')),
                        DropdownMenuItem(value: 'negative', child: Text('Negative')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _feedbackSentimentFilter = value);
                      },
                      decoration: const InputDecoration(
                        labelText: 'Sentiment',
                      ),
                    ),
                  ),
                  _driverFilterAction(
                    child: OutlinedButton.icon(
                      onPressed: _pickFeedbackDateFilter,
                      icon: const Icon(Icons.date_range_rounded),
                      label: Text(
                        _feedbackDateFilter == null
                            ? 'Filter Date'
                            : '${_feedbackDateFilter!.day.toString().padLeft(2, '0')}/${_feedbackDateFilter!.month.toString().padLeft(2, '0')}/${_feedbackDateFilter!.year}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  _DriverFilterField(
                    kind: _DriverFilterFieldKind.plain,
                    child: TextButton.icon(
                      onPressed: _resetFeedbackFilters,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Clear Filters'),
                    ),
                  ),
                ],
              ),
            ),
            if (filteredReviewDocs.isEmpty)
              _premiumCard(
                margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context)),
                child: const Text(
                  'No feedback found for the selected filters.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ...filteredReviewDocs.map((doc) {
              final review = doc.data();
              final rating = ((review['rating'] as num?)?.toInt() ?? 0).clamp(0, 5);
              final comment = (review['comment'] ?? '').toString().trim();
              final sentimentRaw = (review['sentiment'] ?? 'neutral').toString().toLowerCase();
              final status = (review['status'] ?? '').toString().toLowerCase();
              final isFlagged = status == 'flagged';
              final isFlagging = _flaggingReviewIds.contains(doc.id);
              final adminResponse =
                  (review['adminResponse'] as Map<String, dynamic>?) ??
                      const <String, dynamic>{};
              final adminResponseMessage =
                  (adminResponse['message'] ?? '').toString().trim();
              final adminResponseStatus =
                  (adminResponse['status'] ?? '').toString().toLowerCase().trim();
              final createdAt = (review['createdAt'] as Timestamp?)?.toDate();

              Color chipColor = AppTheme.warning;
              String sentimentLabel = 'Neutral';
              if (sentimentRaw == 'positive') {
                chipColor = AppTheme.success;
                sentimentLabel = 'Positive';
              } else if (sentimentRaw == 'negative') {
                chipColor = AppTheme.error;
                sentimentLabel = 'Negative';
              }

              final dateLabel = createdAt == null ? 'Unknown date' : _formatReviewDate(createdAt);

              return _premiumCard(
                margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ...List.generate(5, (index) {
                          final filled = index < rating;
                          return Padding(
                            padding: const EdgeInsets.only(right: 2),
                            child: Icon(
                              filled ? Icons.star_rounded : Icons.star_border_rounded,
                              color: Colors.amber,
                              size: 20,
                            ),
                          );
                        }),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: chipColor.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            sentimentLabel,
                            style: TextStyle(
                              color: chipColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      comment.isEmpty ? 'No comment provided.' : comment,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                    if (adminResponseMessage.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.subtleSurface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppTheme.divider),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                const Text(
                                  'Admin Response:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: adminResponseStatus == 'resolved'
                                        ? AppTheme.success.withOpacity(0.15)
                                        : adminResponseStatus == 'dismissed'
                                            ? AppTheme.error.withOpacity(0.15)
                                            : AppTheme.warning.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    adminResponseStatus == 'resolved'
                                        ? 'Resolved'
                                        : adminResponseStatus == 'dismissed'
                                            ? 'Dismissed'
                                            : 'Under Review',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: adminResponseStatus == 'resolved'
                                          ? AppTheme.success
                                          : adminResponseStatus == 'dismissed'
                                              ? AppTheme.error
                                              : AppTheme.warning,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              adminResponseMessage,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      dateLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: isFlagged
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'Flagged for Review',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            )
                          : OutlinedButton.icon(
                              onPressed: isFlagging
                                  ? null
                                  : () async {
                                      setState(() => _flaggingReviewIds.add(doc.id));
                                      try {
                                        await doc.reference.set({
                                          'status': 'flagged',
                                          'flaggedAt': FieldValue.serverTimestamp(),
                                        }, SetOptions(merge: true));
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('Review flagged for admin review'),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      } catch (e) {
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text('Failed to flag review: $e'),
                                            behavior: SnackBarBehavior.floating,
                                            backgroundColor: AppTheme.error,
                                          ),
                                        );
                                      } finally {
                                        if (mounted) {
                                          setState(() => _flaggingReviewIds.remove(doc.id));
                                        }
                                      }
                                    },
                              icon: isFlagging
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.flag_outlined),
                              label: Text(isFlagging ? 'Flagging...' : 'Flag Review'),
                            ),
                    ),
                  ],
                ),
              );
            }),
            SizedBox(height: MediaQuery.paddingOf(context).bottom + 16),
          ],
        );
      },
    );
  }

  String _formatReviewDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months[date.month - 1];
    return '${date.day.toString().padLeft(2, '0')} $month ${date.year}';
  }

  static const List<_NavItem> _navItems = [
    _NavItem('Profile', Icons.person_rounded),
    _NavItem('Dashboard', Icons.dashboard_rounded),
    _NavItem('Assigned Children', Icons.people_rounded),
    _NavItem('Availability', Icons.event_available_rounded),
    _NavItem('Manage Route', Icons.route_rounded),
    _NavItem('Feedback', Icons.feedback_outlined),
    _NavItem('Earnings', Icons.payments_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: _firestore.collection('users').doc(_user.uid).snapshots(),
      builder: (_, snap) {
        if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final data = snap.data!.data() as Map<String, dynamic>? ?? {};
        final isComplete = _isProfileComplete(data);
        
        // Force profile tab if incomplete
        if (!isComplete && _index != 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _index != 0) setState(() => _index = 0);
          });
        }

        final pages = [
          _profile(data),
          _dashboard(data),
          _assignedChildren(data),
          _availability(data),
          _manageRoute(),
          _feedbackPage(),
          _earningsPage(),
        ];

        return Scaffold(
          backgroundColor: AppTheme.surface,
          drawer: _drawer(data, isComplete),
          appBar: AppBar(
            title: Text(_navItems[_index].label),
            actions: [
              if (_index == 0 && isComplete)
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: () => setState(() => _index = 2),
                ),
            ],
          ),
          body: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppTheme.primary.withOpacity(0.04),
                        AppTheme.surface,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -80,
                right: -80,
                child: CircleAvatar(
                  radius: 120,
                  backgroundColor: AppTheme.primary.withOpacity(0.03),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    if (!isComplete)
                      Container(
                        width: double.infinity,
                        color: AppTheme.error.withOpacity(0.1),
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: AppTheme.error, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Complete your profile to unlock all features',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.error),
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(child: pages[_index]),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _drawer(Map<String, dynamic> data, bool isComplete) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(AppTheme.horizontalPadding(context)),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.primary, AppTheme.primaryDark],
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  CircleAvatar(
                    radius: 40,
                    backgroundImage: data['profilePic'] != null ? NetworkImage(data['profilePic']) : null,
                    backgroundColor: Colors.white24,
                    child: data['profilePic'] == null ? const Icon(Icons.person, size: 40, color: Colors.white) : null,
                  ),
                  const SizedBox(height: 12),
                  Text(data['name'] ?? 'Driver', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
                  const SizedBox(height: 4),
                  Text(data['phone'] ?? '', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.9))),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.symmetric(vertical: AppTheme.verticalSpacing(context)),
                children: [
                  ..._navItems.asMap().entries.map((e) {
                    final isProfileTab = e.key == 0;
                    final enabled = isProfileTab || isComplete;
                    final selected = _index == e.key;
                    
                    return Opacity(
                      opacity: enabled ? 1.0 : 0.5,
                      child: _drawerNavTile(
                        icon: e.value.icon,
                        label: e.value.label + (enabled ? '' : ' 🔒'),
                        selected: selected,
                        onTap: () {
                          if (enabled) {
                            setState(() => _index = e.key);
                            Navigator.pop(context);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please complete and save your profile first')),
                            );
                          }
                        },
                      ),
                    );
                  }),
                  const Divider(height: 24),
                  _drawerNavTile(
                    icon: Icons.logout_rounded,
                    label: 'Logout',
                    selected: false,
                    onTap: () async {
                      await FirebaseAuth.instance.signOut();
                      if (!context.mounted) return;
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  const _NavItem(this.label, this.icon);
}

enum _RideMode { morning, evening }

enum _DriverFilterFieldKind { text, dropdown, action, plain }

class _DriverFilterField extends StatelessWidget {
  const _DriverFilterField({
    required this.kind,
    required this.child,
    this.preferredWidth,
  });

  final _DriverFilterFieldKind kind;
  final Widget child;
  final double? preferredWidth;

  @override
  Widget build(BuildContext context) => child;
}
