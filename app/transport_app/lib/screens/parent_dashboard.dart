import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_stripe/flutter_stripe.dart';
import '../theme/app_theme.dart';
import '../services/web_notifications.dart';
import '../services/local_notifications.dart';
import '../services/review_service.dart';
import '../services/stripe_web_payment_helper.dart' as stripe_web;
import '../services/financial_accounting_service.dart';
import '../config/api_config.dart';
import '../config/maps_config.dart';
import 'admin_dashboard.dart';
import 'driver_dashboard.dart';
import 'driver_location_screen.dart';

class ParentDashboard extends StatefulWidget {
  const ParentDashboard({Key? key}) : super(key: key);

  @override
  State<ParentDashboard> createState() => _ParentDashboardState();
}

class _PaymentIntentData {
  const _PaymentIntentData({
    required this.clientSecret,
    required this.paymentIntentId,
  });

  final String clientSecret;
  final String paymentIntentId;
}

class _PaymentCancelledException implements Exception {
  const _PaymentCancelledException();
}

class _ParentDashboardState extends State<ParentDashboard> {
  final _firestore = FirebaseFirestore.instance;
  final _currentUser = FirebaseAuth.instance.currentUser!;
  int _selectedIndex = 2;
  String? _payingRideId;
  final Set<String> _shownNotificationIds = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _notifSub;
  bool _requestedWebNotificationPermission = false;
  bool _savingPersonalInfo = false;
  String? _requestingForChildId;
  final TextEditingController _reviewCommentController = TextEditingController();
  final TextEditingController _editReviewCommentController = TextEditingController();
  String? _selectedReviewDriverId;
  int _reviewRating = 5;
  bool _submittingReview = false;
  String? _editingReviewId;
  String? _deletingReviewId;
  String _paymentsDriverQuery = '';
  String _paymentsRouteQuery = '';
  String _paymentsTransactionQuery = '';
  String _paymentsStatusFilter = 'all';
  String _paymentsMethodFilter = 'all';
  DateTime? _paymentsFromDate;
  DateTime? _paymentsToDate;
  String _reviewDriverQuery = '';
  String _reviewRatingFilter = 'all';
  String _reviewSentimentFilter = 'all';
  DateTime? _reviewDateFilter;

  bool get _supportsStripePayments =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

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
  void initState() {
    super.initState();
    if (kIsWeb && !_requestedWebNotificationPermission) {
      _requestedWebNotificationPermission = true;
      requestNotificationPermission();
    }
    _listenForRideNotifications();
  }

  void _listenForRideNotifications() {
    _notifSub?.cancel();
    _notifSub = _firestore
        .collection('notifications')
        .where('parentId', isEqualTo: _currentUser.uid)
        .snapshots()
        .listen((snapshot) {
      for (final change in snapshot.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final doc = change.doc;
        final data = doc.data();
        if (data == null) continue;
        if (_shownNotificationIds.contains(doc.id)) continue;
        _shownNotificationIds.add(doc.id);
        final type = data['type'] as String? ?? '';
        final message = data['message'] as String? ?? '';
        final childName = data['childName'] as String?;
        final String title;
        if (type == 'route_deviation') {
          title = 'Route deviation';
        } else if (type == 'driver_availability') {
          title = 'Driver Availability';
        } else if (type == 'ride_started') {
          title = 'Child Picked Up';
        } else if (type == 'ride_ended') {
          title = 'Child Dropped Off';
        } else {
          title = 'Notification';
        }
        final String body = message;
        if (kIsWeb) {
          showRideNotification(title, body);
        } else {
          LocalNotificationService.showRideNotification(title, body);
        }
      }
    });
  }

  Uint8List? _childImageBytes;
  bool _isUploading = false;
  final TextEditingController _childNameController = TextEditingController();
  final TextEditingController _childAgeController = TextEditingController();
  final TextEditingController _childRouteDetailsController = TextEditingController();
  final TextEditingController _childSchoolOnController = TextEditingController();
  final TextEditingController _childSchoolOffController = TextEditingController();
  final TextEditingController _locationSearchController = TextEditingController();
  String? _childSchool;
  String? _childRoute;
  int? _editingChildIndex;
  LatLng? _selectedParentLocation;
  bool _loadingParentLocation = false;
  GoogleMapController? _childLocationMapController;
  LatLng? _pendingChildMapCameraTarget;
  static final RegExp _nameRegex = RegExp(r"^[A-Za-z ]{2,40}$");
  static final RegExp _timeRegex =
      RegExp(r"^(0?[1-9]|1[0-2]):[0-5][0-9]\s?(AM|PM|am|pm)$");

  int? _parse12HourTimeToMinutes(String value) {
    final normalized = value.trim().toUpperCase();
    final match = RegExp(r"^(\d{1,2}):(\d{2})\s?(AM|PM)$").firstMatch(normalized);
    if (match == null) return null;
    final hourRaw = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    final period = match.group(3)!;
    if (hourRaw == null || minute == null || hourRaw < 1 || hourRaw > 12) {
      return null;
    }
    int hour24 = hourRaw % 12;
    if (period == 'PM') hour24 += 12;
    return hour24 * 60 + minute;
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _childNameController.dispose();
    _childAgeController.dispose();
    _childRouteDetailsController.dispose();
    _childSchoolOnController.dispose();
    _childSchoolOffController.dispose();
    _locationSearchController.dispose();
    _reviewCommentController.dispose();
    _editReviewCommentController.dispose();
    super.dispose();
  }

  Future<void> _pickTimeForController(TextEditingController controller) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: 'Select time',
    );
    if (picked == null) return;
    final hour = picked.hourOfPeriod == 0 ? 12 : picked.hourOfPeriod;
    final minute = picked.minute.toString().padLeft(2, '0');
    final period = picked.period == DayPeriod.am ? 'AM' : 'PM';
    setState(() {
      controller.text = '$hour:$minute $period';
    });
  }

  String? _validateChildForm(List<Map<String, dynamic>> parentChildren) {
    final name = _childNameController.text.trim();
    final ageText = _childAgeController.text.trim();
    final routeDetails = _childRouteDetailsController.text.trim();
    final schoolOn = _childSchoolOnController.text.trim();
    final schoolOff = _childSchoolOffController.text.trim();

    if (_childSchool == null || _childRoute == null) {
      return 'Please select school and route.';
    }
    if (!_nameRegex.hasMatch(name)) {
      return 'Child name must be 2-40 letters only.';
    }
    final age = int.tryParse(ageText);
    if (age == null || age < 3 || age > 18) {
      return 'Age must be a valid number between 3 and 18.';
    }
    if (routeDetails.length < 5) {
      return 'Route details must be at least 5 characters.';
    }
    if (!_timeRegex.hasMatch(schoolOn) || !_timeRegex.hasMatch(schoolOff)) {
      return 'Use time format like 07:30 AM for school on/off.';
    }
    final onMinutes = _parse12HourTimeToMinutes(schoolOn);
    final offMinutes = _parse12HourTimeToMinutes(schoolOff);
    if (onMinutes == null || offMinutes == null) {
      return 'Please choose valid school on/off times.';
    }
    if (offMinutes - onMinutes < 180) {
      return 'School off time must be at least 3 hours after school on time.';
    }
    if (_selectedParentLocation == null) {
      return 'Please select parent location on the map.';
    }
    
    // Photo mandatory check
    final hasPhoto = _childImageBytes != null || 
                     (_editingChildIndex != null && (parentChildren[_editingChildIndex!]['photo'] ?? '').toString().isNotEmpty);
    if (!hasPhoto) {
      return 'Please upload a child photo.';
    }
    
    return null;
  }

  Future<Position?> _getCurrentParentPosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return null;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _focusChildLocationOnMap(LatLng target, {double zoom = 15}) async {
    final controller = _childLocationMapController;
    if (controller == null) {
      _pendingChildMapCameraTarget = target;
      return;
    }
    try {
      await controller.animateCamera(CameraUpdate.newLatLngZoom(target, zoom));
    } catch (_) {
      // Fallback for platforms where animateCamera can be flaky right after rebuild.
      await controller.moveCamera(CameraUpdate.newLatLngZoom(target, zoom));
    }
  }

  Future<LatLng?> _resolveAddressToLatLng(String query) async {
    final cleaned = query.trim();
    if (cleaned.isEmpty) return null;
    final key = googleMapsApiKey;
    if (key.isNotEmpty) {
      final geocodeUrl = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?address=${Uri.encodeQueryComponent(cleaned)}'
        '&key=$key',
      );
      try {
        final response =
            await http.get(geocodeUrl).timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          if ((data['status'] as String?) == 'OK') {
            final results = data['results'] as List<dynamic>? ?? const [];
            if (results.isNotEmpty) {
              final first = results.first as Map<String, dynamic>;
              final geometry = first['geometry'] as Map<String, dynamic>?;
              final location = geometry?['location'] as Map<String, dynamic>?;
              final lat = (location?['lat'] as num?)?.toDouble();
              final lng = (location?['lng'] as num?)?.toDouble();
              if (lat != null && lng != null) {
                return LatLng(lat, lng);
              }
            }
          }
        }
      } catch (_) {
        // Fallback to geocoding package below.
      }
    }
    try {
      final result = await locationFromAddress(cleaned);
      if (result.isEmpty) return null;
      return LatLng(result.first.latitude, result.first.longitude);
    } catch (_) {
      // Final fallback: OpenStreetMap Nominatim (no API key required).
      final nominatimUrl = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeQueryComponent(cleaned)}'
        '&format=json'
        '&limit=1',
      );
      try {
        final response = await http.get(
          nominatimUrl,
          headers: const {
            'User-Agent': 'transport-app/1.0 (location-search)',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) return null;
        final data = jsonDecode(response.body) as List<dynamic>;
        if (data.isEmpty) return null;
        final first = data.first as Map<String, dynamic>;
        final lat = double.tryParse((first['lat'] ?? '').toString());
        final lng = double.tryParse((first['lon'] ?? '').toString());
        if (lat == null || lng == null) return null;
        return LatLng(lat, lng);
      } catch (_) {
        return null;
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchLocationSuggestions(
      String query) async {
    final cleaned = query.trim();
    final key = googleMapsApiKey;
    if (cleaned.isEmpty) return const [];
    if (key.isEmpty) {
      // If Google key isn't available, still provide suggestions via Nominatim.
      final nominatimUrl = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeQueryComponent(cleaned)}'
        '&format=json'
        '&addressdetails=1'
        '&limit=8',
      );
      try {
        final response = await http.get(
          nominatimUrl,
          headers: const {
            'User-Agent': 'transport-app/1.0 (location-search)',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) return const [];
        final data = jsonDecode(response.body) as List<dynamic>;
        return data
            .map((item) => item as Map<String, dynamic>)
            .map((item) {
              final lat = double.tryParse((item['lat'] ?? '').toString());
              final lng = double.tryParse((item['lon'] ?? '').toString());
              return <String, dynamic>{
                'description': (item['display_name'] ?? '').toString(),
                'placeId': (item['place_id'] ?? '').toString(),
                'lat': lat,
                'lng': lng,
              };
            })
            .where((item) =>
                (item['description'] as String).isNotEmpty &&
                item['lat'] != null &&
                item['lng'] != null)
            .toList();
      } catch (_) {
        return const [];
      }
    }
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/autocomplete/json'
      '?input=${Uri.encodeQueryComponent(cleaned)}'
      '&key=$key',
    );
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return const [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String?;
      if (status == 'OK') {
        final predictions = data['predictions'] as List<dynamic>? ?? const [];
        final placesResults = predictions
            .map((item) => item as Map<String, dynamic>)
            .map((item) => <String, dynamic>{
                  'description': (item['description'] ?? '').toString(),
                  'placeId': (item['place_id'] ?? '').toString(),
                })
            .where((item) =>
                (item['description'] as String).isNotEmpty &&
                (item['placeId'] as String).isNotEmpty)
            .toList();
        if (placesResults.isNotEmpty) return placesResults;
      }

      // Fallback: geocoding API suggestions so dropdown still appears
      // even when Places Autocomplete is unavailable/restricted.
      final geocodeUrl = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?address=${Uri.encodeQueryComponent(cleaned)}'
        '&key=$key',
      );
      final geoResponse = await http.get(geocodeUrl).timeout(
            const Duration(seconds: 8),
          );
      if (geoResponse.statusCode != 200) return const [];
      final geoData = jsonDecode(geoResponse.body) as Map<String, dynamic>;
      final geoStatus = geoData['status'] as String?;
      if (geoStatus != 'OK') return const [];
      final results = geoData['results'] as List<dynamic>? ?? const [];
      return results
          .map((item) => item as Map<String, dynamic>)
          .map((item) {
            final geometry = item['geometry'] as Map<String, dynamic>?;
            final location = geometry?['location'] as Map<String, dynamic>?;
            final lat = (location?['lat'] as num?)?.toDouble();
            final lng = (location?['lng'] as num?)?.toDouble();
            return <String, dynamic>{
              'description': (item['formatted_address'] ?? '').toString(),
              'placeId': (item['place_id'] ?? '').toString(),
              'lat': lat,
              'lng': lng,
            };
          })
          .where((item) =>
              (item['description'] as String).isNotEmpty &&
              item['lat'] != null &&
              item['lng'] != null)
          .take(8)
          .toList();
    } catch (_) {
      // Fallback to Nominatim if Google requests fail/restricted.
      final nominatimUrl = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeQueryComponent(cleaned)}'
        '&format=json'
        '&addressdetails=1'
        '&limit=8',
      );
      try {
        final response = await http.get(
          nominatimUrl,
          headers: const {
            'User-Agent': 'transport-app/1.0 (location-search)',
            'Accept': 'application/json',
          },
        ).timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) return const [];
        final data = jsonDecode(response.body) as List<dynamic>;
        return data
            .map((item) => item as Map<String, dynamic>)
            .map((item) {
              final lat = double.tryParse((item['lat'] ?? '').toString());
              final lng = double.tryParse((item['lon'] ?? '').toString());
              return <String, dynamic>{
                'description': (item['display_name'] ?? '').toString(),
                'placeId': (item['place_id'] ?? '').toString(),
                'lat': lat,
                'lng': lng,
              };
            })
            .where((item) =>
                (item['description'] as String).isNotEmpty &&
                item['lat'] != null &&
                item['lng'] != null)
            .toList();
      } catch (_) {
        return const [];
      }
    }
  }

  Future<LatLng?> _resolvePlaceIdToLatLng(String placeId) async {
    final key = googleMapsApiKey;
    if (placeId.trim().isEmpty || key.isEmpty) return null;
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/details/json'
      '?place_id=${Uri.encodeQueryComponent(placeId)}'
      '&fields=geometry'
      '&key=$key',
    );
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if ((data['status'] as String?) != 'OK') return null;
      final result = data['result'] as Map<String, dynamic>?;
      final geometry = result?['geometry'] as Map<String, dynamic>?;
      final location = geometry?['location'] as Map<String, dynamic>?;
      final lat = (location?['lat'] as num?)?.toDouble();
      final lng = (location?['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      return LatLng(lat, lng);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openParentLocationPickerModal() async {
    var tempSelectedLocation =
        _selectedParentLocation ?? const LatLng(24.8607, 67.0011);
    var loadingCurrent = false;
    var searchingLocation = false;
    var loadingSuggestions = false;
    List<Map<String, dynamic>> suggestions = [];
    Timer? searchDebounce;
    _locationSearchController.clear();

    final picked = await showModalBottomSheet<LatLng>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            // Auto-load current location when modal opens
            Future<void> loadCurrentLocationOnOpen() async {
              try {
                final position = await _getCurrentParentPosition();
                if (position != null && setModalState != null) {
                  final currentLocation = LatLng(position.latitude, position.longitude);
                  setModalState(() => tempSelectedLocation = currentLocation);
                  _pendingChildMapCameraTarget = currentLocation;
                  await _focusChildLocationOnMap(currentLocation, zoom: 16);
                }
              } catch (e) {
                print("Error loading current location: $e");
              }
            }
            
            // Call on first build
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (mounted) {
                await loadCurrentLocationOnOpen();
              }
            });
            
            Future<void> useCurrentInModal() async {
              setModalState(() => loadingCurrent = true);
              try {
                final position = await _getCurrentParentPosition();
                if (position == null) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Unable to fetch current location.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                final point = LatLng(position.latitude, position.longitude);
                setModalState(() => tempSelectedLocation = point);
                await _focusChildLocationOnMap(point, zoom: 16);
              } finally {
                if (mounted) {
                  setModalState(() => loadingCurrent = false);
                }
              }
            }

            Future<void> searchAddressInModal() async {
              final query = _locationSearchController.text.trim();
              if (query.isEmpty) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Enter an address or place name to search.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              setModalState(() => searchingLocation = true);
              try {
                LatLng? point = await _resolveAddressToLatLng(query);
                if (point == null) {
                  final candidates = await _fetchLocationSuggestions(query);
                  if (candidates.isNotEmpty) {
                    final first = candidates.first;
                    final lat = (first['lat'] as num?)?.toDouble();
                    final lng = (first['lng'] as num?)?.toDouble();
                    final placeId = (first['placeId'] ?? '').toString();
                    point =
                        (lat != null && lng != null) ? LatLng(lat, lng) : null;
                    point ??= await _resolvePlaceIdToLatLng(placeId);
                    point ??=
                        await _resolveAddressToLatLng((first['description'] ?? '').toString());
                  }
                }
                if (point == null) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Location not found. Try a more specific address.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                final resolvedPoint = point;
                setModalState(() => tempSelectedLocation = resolvedPoint);
                await _focusChildLocationOnMap(resolvedPoint, zoom: 16);
                if (mounted) {
                  setModalState(() => suggestions = []);
                }
              } finally {
                if (mounted) {
                  setModalState(() => searchingLocation = false);
                }
              }
            }

            Future<void> updateSuggestions(String query) async {
              final cleaned = query.trim();
              if (cleaned.length < 2) {
                if (mounted) {
                  setModalState(() {
                    loadingSuggestions = false;
                    suggestions = [];
                  });
                }
                return;
              }
              setModalState(() => loadingSuggestions = true);
              final results = await _fetchLocationSuggestions(cleaned);
              if (!mounted) return;
              if (_locationSearchController.text.trim() != cleaned) return;
              setModalState(() {
                loadingSuggestions = false;
                suggestions = results;
              });
            }

            Future<void> selectSuggestion(Map<String, dynamic> item) async {
              final description = (item['description'] ?? '').toString();
              final placeId = (item['placeId'] ?? '').toString();
              final lat = (item['lat'] as num?)?.toDouble();
              final lng = (item['lng'] as num?)?.toDouble();
              _locationSearchController.text = description;
              setModalState(() {
                searchingLocation = true;
                suggestions = [];
              });
              try {
                LatLng? point =
                    (lat != null && lng != null) ? LatLng(lat, lng) : null;
                point ??= await _resolvePlaceIdToLatLng(placeId);
                point ??= await _resolveAddressToLatLng(description);
                if (point == null) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Unable to open selected location.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                setModalState(() => tempSelectedLocation = point!);
                await _focusChildLocationOnMap(point, zoom: 16);
              } finally {
                if (mounted) {
                  setModalState(() => searchingLocation = false);
                }
              }
            }

            return SizedBox(
              height: MediaQuery.of(modalContext).size.height * 0.8,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Select parent location',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(modalContext).pop(),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () =>
                              Navigator.of(modalContext).pop(tempSelectedLocation),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _locationSearchController,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => searchAddressInModal(),
                            onChanged: (value) {
                              searchDebounce?.cancel();
                              searchDebounce = Timer(
                                const Duration(milliseconds: 350),
                                () => updateSuggestions(value),
                              );
                            },
                            decoration: const InputDecoration(
                              labelText: 'Search location',
                              hintText: 'e.g. Mirpur Abbottabad',
                              prefixIcon: Icon(Icons.search_rounded),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton(
                          onPressed: searchingLocation ? null : searchAddressInModal,
                          child: searchingLocation
                              ? const SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Search'),
                        ),
                      ],
                    ),
                  ),
                  if (loadingSuggestions)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  if (suggestions.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      constraints: const BoxConstraints(maxHeight: 180),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.black12),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: suggestions.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = suggestions[index];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.place_rounded, size: 18),
                            title: Text(
                              item['description'] ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => selectSuggestion(item),
                          );
                        },
                      ),
                    ),
                  Expanded(
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: tempSelectedLocation,
                        zoom: 15,
                      ),
                      onMapCreated: (controller) {
                        _childLocationMapController = controller;
                        final target =
                            _pendingChildMapCameraTarget ?? tempSelectedLocation;
                        _pendingChildMapCameraTarget = null;
                        _focusChildLocationOnMap(target, zoom: 16);
                      },
                      onTap: (position) {
                        setModalState(() => tempSelectedLocation = position);
                      },
                      markers: {
                        Marker(
                          markerId: const MarkerId('selected_parent_location'),
                          position: tempSelectedLocation,
                          infoWindow: const InfoWindow(
                            title: 'Selected parent location',
                          ),
                        ),
                      },
                      myLocationButtonEnabled: false,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                    child: Row(
                      children: [
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: loadingCurrent ? null : useCurrentInModal,
                          icon: loadingCurrent
                              ? const SizedBox(
                                  height: 14,
                                  width: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.my_location_rounded, size: 16),
                          label: const Text('Use current'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    searchDebounce?.cancel();
    _childLocationMapController = null;
    _pendingChildMapCameraTarget = null;
    _locationSearchController.clear();

    if (picked != null && mounted) {
      setState(() {
        _selectedParentLocation = picked;
      });
    }
  }

  Future<void> _pickChildImage() async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => _childImageBytes = bytes);
  }

  Widget _personalInfo(Map<String, dynamic> data) {
    final name = TextEditingController(text: data['name']?.toString() ?? '');
    final cnic = TextEditingController(text: data['cnic']?.toString() ?? '');
    final phone = TextEditingController(text: data['phone']?.toString() ?? '');

    final padding = AppTheme.contentPadding(context);
    return SingleChildScrollView(
      padding: padding,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: AppTheme.maxContentWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Personal information', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            SizedBox(height: AppTheme.verticalSpacing(context)),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'Name'), textInputAction: TextInputAction.next),
            SizedBox(height: AppTheme.verticalSpacing(context)),
            TextField(controller: cnic, decoration: const InputDecoration(labelText: 'CNIC'), keyboardType: TextInputType.number, textInputAction: TextInputAction.next),
            SizedBox(height: AppTheme.verticalSpacing(context)),
            TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone'), keyboardType: TextInputType.phone, textInputAction: TextInputAction.done),
            SizedBox(height: AppTheme.verticalSpacing(context) * 2),
            FilledButton.icon(
              onPressed: _savingPersonalInfo
                  ? null
                  : () async {
                      final ctx = context;
                      setState(() => _savingPersonalInfo = true);
                      try {
                        await _firestore.collection('users').doc(_currentUser.uid).set({
                          'name': name.text,
                          'cnic': cnic.text,
                          'phone': phone.text,
                          'profileCompleted': true,
                        }, SetOptions(merge: true));

                        final refreshedDoc =
                            await _firestore.collection('users').doc(_currentUser.uid).get();
                        final refreshedData = refreshedDoc.data() ?? <String, dynamic>{};
                        final role =
                            (refreshedData['role'] ?? '').toString().toLowerCase().trim();

                        if (!mounted) return;
                        Widget target;
                        if (role == 'driver') {
                          target = const DriverDashboard();
                        } else if (role == 'admin') {
                          target = const AdminDashboard();
                        } else {
                          target = const ParentDashboard();
                        }
                        Navigator.pushReplacement(
                          ctx,
                          MaterialPageRoute(builder: (_) => target),
                        );
                      } finally {
                        if (mounted) {
                          setState(() => _savingPersonalInfo = false);
                        }
                      }
                    },
              icon: const Icon(Icons.save_rounded, size: 20),
              label: Text(_savingPersonalInfo ? 'Saving…' : 'Save'),
            ),
            SizedBox(height: MediaQuery.paddingOf(context).bottom + 24),
          ],
        ),
      ),
    );
  }

  Widget _notificationsPage() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('notifications').where('parentId', isEqualTo: _currentUser.uid).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        var docs = snapshot.data!.docs;
        docs = docs.toList()
          ..sort((a, b) {
            final ta = a.data()['timestamp'] as Timestamp?;
            final tb = b.data()['timestamp'] as Timestamp?;
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return tb.compareTo(ta);
          });
        if (docs.length > 50) docs = docs.sublist(0, 50);

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: AppTheme.contentPadding(context),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none_rounded, size: 64, color: AppTheme.textSecondary.withOpacity(0.5)),
                  const SizedBox(height: 16),
                  Text('No notifications yet', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.textPrimary)),
                  const SizedBox(height: 8),
                  Text(
                    'You\'ll see "Child Picked Up" and "Child Dropped Off" alerts here when the driver starts or ends your child\'s ride.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          );
        }

        final padding = AppTheme.contentPadding(context);
        return ListView.builder(
          padding: padding,
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final d = doc.data();
            final type = d['type'] as String? ?? '';
            final message = d['message'] as String? ?? '';
            final driverName = d['driverName'] as String? ?? 'Driver';
            final childName = d['childName'] as String?;
            final timestamp = d['timestamp'] as dynamic;
            final read = d['read'] as bool? ?? false;
            final String titleText;
            if (type == 'route_deviation') {
              titleText = 'Route deviation';
            } else if (type == 'driver_availability') {
              titleText = 'Driver Availability';
            } else if (type == 'ride_started') {
              titleText = 'Child Picked Up';
            } else if (type == 'ride_ended') {
              titleText = 'Child Dropped Off';
            } else {
              titleText = 'Notification';
            }

            final Color avatarColor;
            if (type == 'route_deviation') {
              avatarColor = AppTheme.warning;
            } else if (type == 'driver_availability') {
              avatarColor = AppTheme.accent;
            } else if (type == 'ride_started') {
              avatarColor = AppTheme.success;
            } else {
              avatarColor = AppTheme.primary;
            }

            final IconData avatarIcon;
            if (type == 'route_deviation') {
              avatarIcon = Icons.warning_rounded;
            } else if (type == 'driver_availability') {
              avatarIcon = Icons.event_available_rounded;
            } else if (type == 'ride_started') {
              avatarIcon = Icons.directions_car_rounded;
            } else {
              avatarIcon = Icons.check_circle_rounded;
            }

            final Color cardHighlight = read
                ? Colors.transparent
                : (type == 'route_deviation'
                    ? AppTheme.warning.withOpacity(0.08)
                    : (type == 'ride_started'
                        ? AppTheme.success.withOpacity(0.08)
                        : AppTheme.primary.withOpacity(0.08)));

            return _premiumCard(
              margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context)),
              baseColor: cardHighlight == Colors.transparent ? Colors.white : cardHighlight,
              padding: EdgeInsets.symmetric(horizontal: AppTheme.horizontalPadding(context), vertical: 8),
              child: ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: AppTheme.horizontalPadding(context), vertical: 8),
                leading: CircleAvatar(
                  backgroundColor: avatarColor,
                  child: Icon(avatarIcon, color: Colors.white, size: 24),
                ),
                title: Text(
                  titleText,
                  style: TextStyle(fontWeight: read ? FontWeight.normal : FontWeight.w600, color: AppTheme.textPrimary),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    type == 'route_deviation'
                        ? message
                        : '$message — $driverName',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                  ),
                ),
                trailing: timestamp != null && timestamp is Timestamp
                    ? Text(_formatTimestamp(timestamp as Timestamp), style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary))
                    : null,
              ),
            );
          },
        );
      },
    );
  }

  String _formatTimestamp(Timestamp t) {
    final d = t.toDate();
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final year = d.year.toString();
    final hour = d.hour.toString().padLeft(2, '0');
    final minute = d.minute.toString().padLeft(2, '0');
    // Show full date and time for each notification.
    return '$day/$month/$year  $hour:$minute';
  }

  String _compactId(String value) {
    final normalized = value.trim();
    if (normalized.length <= 14) return normalized;
    return '${normalized.substring(0, 8)}...${normalized.substring(normalized.length - 4)}';
  }

  Future<void> _copyToClipboard(String label, String value) async {
    if (value.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value.trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _pickPaymentsDate({
    required bool isFromDate,
  }) async {
    final now = DateTime.now();
    final initialDate = isFromDate
        ? (_paymentsFromDate ?? _paymentsToDate ?? now)
        : (_paymentsToDate ?? _paymentsFromDate ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFromDate) {
        _paymentsFromDate = picked;
      } else {
        _paymentsToDate = picked;
      }
    });
  }

  void _resetPaymentsFilters() {
    setState(() {
      _paymentsDriverQuery = '';
      _paymentsRouteQuery = '';
      _paymentsTransactionQuery = '';
      _paymentsStatusFilter = 'all';
      _paymentsMethodFilter = 'all';
      _paymentsFromDate = null;
      _paymentsToDate = null;
    });
  }

  Future<void> _pickReviewDateFilter() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _reviewDateFilter ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 3),
    );
    if (picked == null || !mounted) return;
    setState(() => _reviewDateFilter = picked);
  }

  void _resetReviewFilters() {
    setState(() {
      _reviewDriverQuery = '';
      _reviewRatingFilter = 'all';
      _reviewSentimentFilter = 'all';
      _reviewDateFilter = null;
    });
  }

  Widget _dashboard(Map<String, dynamic> data) {
    final children = List<Map<String, dynamic>>.from(data['children'] ?? []);
    final padding = AppTheme.contentPadding(context);
    final parentName = (data['name'] ?? 'Parent').toString();
    final assignedChildren = children
        .where((c) => (c['assignedDriver'] ?? '').toString().trim().isNotEmpty)
        .length;

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
                    radius: 28,
                    backgroundColor: AppTheme.primary.withOpacity(0.15),
                    child: Text(
                      parentName.isEmpty ? '?' : parentName[0].toUpperCase(),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  SizedBox(width: AppTheme.horizontalPadding(context)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome, $parentName',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Total registered children: ${children.length}',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                        ),
                        Text(
                          'Active children: $assignedChildren',
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
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
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.15,
                  children: [
                    _parentStatCard(
                      icon: Icons.child_care_rounded,
                      label: 'Children',
                      value: '${children.length}',
                    ),
                    _parentStatCard(
                      icon: Icons.group_rounded,
                      label: 'Assigned Drivers',
                      value: '$assignedChildren',
                    ),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _firestore
                          .collection('rides')
                          .where('parentId', isEqualTo: _currentUser.uid)
                          .snapshots(),
                      builder: (context, snap) {
                        final docs = snap.data?.docs ?? const [];
                        final pendingPayments = docs.where((doc) {
                          final row = doc.data();
                          final rideStatus = (row['rideStatus'] ?? '').toString().toLowerCase();
                          final paymentStatus = (row['paymentStatus'] ?? 'pending').toString().toLowerCase();
                          return rideStatus == 'completed' && paymentStatus != 'paid';
                        }).length;
                        return _parentStatCard(
                          icon: Icons.pending_actions_rounded,
                          label: 'Pending Payments',
                          value: '$pendingPayments',
                        );
                      },
                    ),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _firestore
                          .collection('notifications')
                          .where('parentId', isEqualTo: _currentUser.uid)
                          .snapshots(),
                      builder: (context, snap) {
                        final total = snap.data?.docs.length ?? 0;
                        return _parentStatCard(
                          icon: Icons.notifications_active_rounded,
                          label: 'Notifications',
                          value: '$total',
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
                  Text(
                    'Children Transport Status',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                  ),
                  SizedBox(height: AppTheme.verticalSpacing(context)),
                  if (children.isEmpty)
                    const Text(
                      'No children added yet. Add your first child from Children tab.',
                      style: TextStyle(color: AppTheme.textSecondary),
                    )
                  else
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _firestore
                          .collection('rides')
                          .where('parentId', isEqualTo: _currentUser.uid)
                          .where('rideStatus', isEqualTo: 'in_progress')
                          .snapshots(),
                      builder: (context, rideSnap) {
                        final activeRideByChild = <String, Map<String, dynamic>>{};
                        for (final doc in (rideSnap.data?.docs ?? const [])) {
                          final rideData = doc.data();
                          final childId = (rideData['childId'] ?? '').toString();
                          if (childId.isNotEmpty) activeRideByChild[childId] = rideData;
                        }
                        return Column(
                          children: children.map((child) {
                            final childId = (child['id'] ?? '').toString();
                            final activeRide = activeRideByChild[childId];
                            final driverName = (child['assignedDriverName'] ?? '').toString().trim();
                            final status = activeRide != null
                                ? 'On Ride'
                                : (driverName.isEmpty ? 'Not Assigned' : 'Assigned');
                            final statusColor = activeRide != null
                                ? AppTheme.success
                                : (driverName.isEmpty ? AppTheme.warning : AppTheme.textSecondary);
                            return Container(
                              margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context) * 0.7),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppTheme.primary.withOpacity(0.08)),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: AppTheme.primary.withOpacity(0.15),
                                    child: Text(
                                      (child['name'] ?? '?').toString().substring(0, 1).toUpperCase(),
                                      style: const TextStyle(
                                        color: AppTheme.primary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (child['name'] ?? 'Child').toString(),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Driver: ${driverName.isEmpty ? 'Not assigned' : driverName}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                        Text(
                                          'School: ${(child['school'] ?? '—').toString()}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: statusColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      status,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: statusColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                ],
              ),
            ),

            SizedBox(height: AppTheme.verticalSpacing(context)),
            _premiumCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Recent Notifications',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                  ),
                  SizedBox(height: AppTheme.verticalSpacing(context)),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _firestore
                        .collection('notifications')
                        .where('parentId', isEqualTo: _currentUser.uid)
                        .snapshots(),
                    builder: (context, snap) {
                      final docs = (snap.data?.docs ?? const []).toList()
                        ..sort((a, b) {
                          final ta = a.data()['timestamp'] as Timestamp?;
                          final tb = b.data()['timestamp'] as Timestamp?;
                          if (ta == null && tb == null) return 0;
                          if (ta == null) return 1;
                          if (tb == null) return -1;
                          return tb.compareTo(ta);
                        });
                      final latest = docs.take(3).toList();
                      if (latest.isEmpty) {
                        return const Text(
                          'No recent notifications.',
                          style: TextStyle(color: AppTheme.textSecondary),
                        );
                      }
                      return Column(
                        children: latest.map((doc) {
                          final row = doc.data();
                          final message = (row['message'] ?? 'Notification').toString();
                          final time = row['timestamp'];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.circle, size: 10, color: AppTheme.primary),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        message,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: AppTheme.textPrimary),
                                      ),
                                      if (time is Timestamp)
                                        Text(
                                          _formatTimestamp(time),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.textSecondary,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            ),

            SizedBox(height: AppTheme.verticalSpacing(context)),
            _premiumCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Payment Summary',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                  ),
                  SizedBox(height: AppTheme.verticalSpacing(context)),
                  StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _firestore
                        .collection('payments')
                        .where('parentId', isEqualTo: _currentUser.uid)
                        .snapshots(),
                    builder: (context, snap) {
                      final docs = snap.data?.docs ?? const [];
                      final now = DateTime.now();
                      final monthPaid = docs.where((doc) {
                        final row = doc.data();
                        final status = (row['status'] ?? '').toString().toLowerCase();
                        final paidAt = row['paidAt'];
                        if (status != 'paid' || paidAt is! Timestamp) return false;
                        final dt = paidAt.toDate();
                        return dt.year == now.year && dt.month == now.month;
                      }).length;

                      Timestamp? lastPaidAt;
                      for (final doc in docs) {
                        final row = doc.data();
                        final status = (row['status'] ?? '').toString().toLowerCase();
                        final paidAt = row['paidAt'];
                        if (status == 'paid' && paidAt is Timestamp) {
                          if (lastPaidAt == null || paidAt.compareTo(lastPaidAt) > 0) {
                            lastPaidAt = paidAt;
                          }
                        }
                      }
                      final monthLabel = '${now.month.toString().padLeft(2, '0')}/${now.year}';
                      final lastDate = lastPaidAt == null ? '—' : _formatTimestamp(lastPaidAt);
                      return Row(
                        children: [
                          Expanded(
                            child: _paymentInfoTile(
                              icon: Icons.calendar_month_rounded,
                              label: 'This Month ($monthLabel)',
                              value: monthPaid > 0 ? '$monthPaid payment(s) paid' : 'Pending',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _paymentInfoTile(
                              icon: Icons.schedule_rounded,
                              label: 'Last Payment',
                              value: lastDate,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),

            SizedBox(height: AppTheme.verticalSpacing(context)),
            _premiumCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Quick Actions',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                  ),
                  SizedBox(height: AppTheme.verticalSpacing(context)),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _quickDashboardAction(
                        icon: Icons.people_alt_rounded,
                        label: 'View Drivers',
                        onTap: () => setState(() => _selectedIndex = 3),
                      ),
                      _quickDashboardAction(
                        icon: Icons.person_add_alt_1_rounded,
                        label: 'Add Child',
                        onTap: () => setState(() => _selectedIndex = 4),
                      ),
                      _quickDashboardAction(
                        icon: Icons.payments_outlined,
                        label: 'Payments',
                        onTap: () => setState(() => _selectedIndex = 5),
                      ),
                      _quickDashboardAction(
                        icon: Icons.rate_review_outlined,
                        label: 'Reviews',
                        onTap: () => setState(() => _selectedIndex = 6),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            SizedBox(height: MediaQuery.paddingOf(context).bottom + 24),
          ],
        ),
      ),
    );
  }

  Widget _parentStatCard({
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
            blurRadius: 14,
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
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
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

  Widget _quickDashboardAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paymentInfoTile({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppTheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _childrenPage(Map<String, dynamic> data) {
    final parentChildren = List<Map<String, dynamic>>.from(data['children'] ?? []);

    Future<void> saveChild() async {
      final validationError = _validateChildForm(parentChildren);
      if (validationError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(validationError),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      setState(() => _isUploading = true);

      String photoUrl = '';
      if (_childImageBytes != null) {
        final ref = FirebaseStorage.instance.ref().child('child_photos/${DateTime.now().millisecondsSinceEpoch}.jpg');
        await ref.putData(_childImageBytes!);
        photoUrl = await ref.getDownloadURL();
      } else if (_editingChildIndex != null) {
        photoUrl = parentChildren[_editingChildIndex!]['photo']?.toString() ?? '';
      }

      String? assignedDriver;
      String? assignedDriverName;
      String childId;

      if (_editingChildIndex != null) {
        final old = parentChildren[_editingChildIndex!];
        childId = old['id'] as String? ?? '';
        assignedDriver = old['assignedDriver'] as String?;
        assignedDriverName = old['assignedDriverName'] as String?;
        parentChildren[_editingChildIndex!] = {
          'id': childId,
          'name': _childNameController.text,
          'age': _childAgeController.text,
          'school': _childSchool,
          'route': _childRoute,
          'routeDetails': _childRouteDetailsController.text,
          'schoolOn': _childSchoolOnController.text,
          'schoolOff': _childSchoolOffController.text,
          'photo': photoUrl,
          'assignedDriver': assignedDriver,
          'assignedDriverName': assignedDriverName,
          'parentLatitude': _selectedParentLocation!.latitude,
          'parentLongitude': _selectedParentLocation!.longitude,
        };
      } else {
        childId = _firestore.collection('children').doc().id;
        parentChildren.add({
          'id': childId,
          'name': _childNameController.text,
          'age': _childAgeController.text,
          'school': _childSchool,
          'route': _childRoute,
          'routeDetails': _childRouteDetailsController.text,
          'schoolOn': _childSchoolOnController.text,
          'schoolOff': _childSchoolOffController.text,
          'photo': photoUrl,
          'assignedDriver': null,
          'assignedDriverName': null,
          'parentLatitude': _selectedParentLocation!.latitude,
          'parentLongitude': _selectedParentLocation!.longitude,
        });
      }

      await _firestore.collection('users').doc(_currentUser.uid).set({'children': parentChildren}, SetOptions(merge: true));

      final wasUpdate = _editingChildIndex != null;
      setState(() {
        _childImageBytes = null;
        _editingChildIndex = null;
        _childSchool = null;
        _childRoute = null;
        _childNameController.clear();
        _childAgeController.clear();
        _childRouteDetailsController.clear();
        _childSchoolOnController.clear();
        _childSchoolOffController.clear();
        _selectedParentLocation = null;
        _isUploading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(wasUpdate ? 'Child updated' : 'Child added'), backgroundColor: AppTheme.success, behavior: SnackBarBehavior.floating));
      }
    }

    final padding = AppTheme.contentPadding(context);
    return SingleChildScrollView(
      padding: padding,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: AppTheme.maxContentWidth),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickChildImage,
                child: CircleAvatar(
                  radius: 56,
                  backgroundImage: _childImageBytes != null
                      ? MemoryImage(_childImageBytes!)
                      : (_editingChildIndex != null && (parentChildren[_editingChildIndex!]['photo'] ?? '').toString().isNotEmpty
                          ? NetworkImage(parentChildren[_editingChildIndex!]['photo'].toString()) as ImageProvider
                          : null),
                  backgroundColor: AppTheme.primary.withOpacity(0.1),
                  child: _childImageBytes == null && (_editingChildIndex == null || (parentChildren[_editingChildIndex!]['photo'] ?? '').toString().isEmpty)
                      ? Icon(Icons.camera_alt_rounded, size: 40, color: AppTheme.primary.withOpacity(0.6))
                      : null,
                ),
              ),
            ),
            SizedBox(height: AppTheme.verticalSpacing(context) * 2),
            TextField(controller: _childNameController, decoration: const InputDecoration(labelText: 'Name'), textInputAction: TextInputAction.next),
            SizedBox(height: AppTheme.verticalSpacing(context)),
            TextField(controller: _childAgeController, decoration: const InputDecoration(labelText: 'Age'), keyboardType: TextInputType.number, textInputAction: TextInputAction.next),
            SizedBox(height: AppTheme.verticalSpacing(context)),
            StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('schools').snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final schoolList = snap.data!.docs.map((d) => (d.data() as Map<String, dynamic>)['name'].toString()).toList();
                return DropdownButtonFormField<String>(
                  value: _childSchool,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'School'),
                  items: schoolList.map((s) => DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis, maxLines: 1))).toList(),
                  onChanged: (v) => setState(() => _childSchool = v),
                );
              },
            ),
            SizedBox(height: AppTheme.verticalSpacing(context)),
            StreamBuilder<QuerySnapshot>(
              stream: _firestore.collection('routes').snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final routeList = snap.data!.docs.map((d) => (d.data() as Map<String, dynamic>)['name'].toString()).toList();
                return DropdownButtonFormField<String>(
                  value: _childRoute,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Route'),
                  items: routeList.map((r) => DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis, maxLines: 1))).toList(),
                  onChanged: (v) => setState(() => _childRoute = v),
                );
              },
            ),
            SizedBox(height: AppTheme.verticalSpacing(context)),
            TextField(controller: _childRouteDetailsController, decoration: const InputDecoration(labelText: 'Route details'), textInputAction: TextInputAction.next),
            SizedBox(height: AppTheme.verticalSpacing(context)),
            TextField(
              controller: _childSchoolOnController,
              readOnly: true,
              onTap: () => _pickTimeForController(_childSchoolOnController),
              decoration: InputDecoration(
                labelText: 'School on time',
                hintText: 'Select time',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.access_time_rounded),
                  onPressed: () => _pickTimeForController(_childSchoolOnController),
                ),
              ),
              textInputAction: TextInputAction.next,
            ),
            SizedBox(height: AppTheme.verticalSpacing(context)),
            TextField(
              controller: _childSchoolOffController,
              readOnly: true,
              onTap: () => _pickTimeForController(_childSchoolOffController),
              decoration: InputDecoration(
                labelText: 'School off time',
                hintText: 'Select time',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.access_time_rounded),
                  onPressed: () => _pickTimeForController(_childSchoolOffController),
                ),
              ),
              textInputAction: TextInputAction.done,
            ),
            SizedBox(height: AppTheme.verticalSpacing(context)),
            Text(
              'Parent location',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openParentLocationPickerModal,
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: Text(
                      _selectedParentLocation == null
                          ? 'Open map picker'
                          : 'Update on map',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loadingParentLocation
                        ? null
                        : () async {
                            setState(() => _loadingParentLocation = true);
                            try {
                              final pos = await _getCurrentParentPosition();
                              if (pos != null && mounted) {
                                setState(() {
                                  _selectedParentLocation =
                                      LatLng(pos.latitude, pos.longitude);
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Current location selected'),
                                    backgroundColor: AppTheme.success,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              } else if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Unable to fetch current location.'),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            } finally {
                              if (mounted) {
                                setState(() => _loadingParentLocation = false);
                              }
                            }
                          },
                    icon: _loadingParentLocation
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location_rounded, size: 18),
                    label: const Text('Use current'),
                  ),
                ),
              ],
            ),
            if (_selectedParentLocation != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Location added successfully',
                        style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(height: AppTheme.verticalSpacing(context) * 2),
            if (_isUploading)
              const Center(child: CircularProgressIndicator())
            else
              FilledButton.icon(
                onPressed: saveChild,
                icon: Icon(_editingChildIndex != null ? Icons.edit_rounded : Icons.add_rounded, size: 20),
                label: Text(_editingChildIndex != null ? 'Update child' : 'Add child'),
              ),
            SizedBox(height: AppTheme.verticalSpacing(context) * 2),
            Text('Added children', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
            SizedBox(height: AppTheme.verticalSpacing(context)),
            ...parentChildren.asMap().entries.map((entry) {
              final i = entry.key;
              final child = entry.value;
              final photo = child['photo']?.toString() ?? '';
              return _premiumCard(
                margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context)),
                padding: EdgeInsets.zero,
                child: ListTile(
                  contentPadding: EdgeInsets.symmetric(horizontal: AppTheme.horizontalPadding(context), vertical: 8),
                  leading: photo.isNotEmpty
                      ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(photo, width: 48, height: 48, fit: BoxFit.cover))
                      : CircleAvatar(backgroundColor: AppTheme.primary.withOpacity(0.15), child: const Icon(Icons.child_care_rounded, color: AppTheme.primary)),
                  title: Text(child['name']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text('${child['school'] ?? '—'} • ${child['route'] ?? '—'}', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_rounded, color: AppTheme.primary),
                        onPressed: () {
                          setState(() {
                            _editingChildIndex = i;
                            _childNameController.text = child['name']?.toString() ?? '';
                            _childAgeController.text = child['age']?.toString() ?? '';
                            _childRouteDetailsController.text = child['routeDetails']?.toString() ?? '';
                            _childSchoolOnController.text = child['schoolOn']?.toString() ?? '';
                            _childSchoolOffController.text = child['schoolOff']?.toString() ?? '';
                            _childSchool = child['school']?.toString();
                            _childRoute = child['route']?.toString();
                            _childImageBytes = null;
                            final lat = (child['parentLatitude'] as num?)?.toDouble();
                            final lng = (child['parentLongitude'] as num?)?.toDouble();
                            _selectedParentLocation =
                                (lat != null && lng != null) ? LatLng(lat, lng) : null;
                          });
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_rounded, color: AppTheme.error),
                        onPressed: () async {
                          parentChildren.removeAt(i);
                          await _firestore.collection('users').doc(_currentUser.uid).set({'children': parentChildren}, SetOptions(merge: true));
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              );
            }),
            SizedBox(height: MediaQuery.paddingOf(context).bottom + 24),
          ],
        ),
      ),
    );
  }

  Widget _driversPage(Map<String, dynamic> parentData) {
    final parentChildren = List<Map<String, dynamic>>.from(parentData['children'] ?? []);
    if (parentChildren.isEmpty) {
      return Center(
        child: Padding(
          padding: AppTheme.contentPadding(context),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.people_outline_rounded, size: 64, color: AppTheme.textSecondary.withOpacity(0.5)),
              const SizedBox(height: 16),
              Text('No children added yet', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.textSecondary)),
              const SizedBox(height: 8),
              Text('Add a child first, then request a driver for their route.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary)),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: AppTheme.contentPadding(context),
      itemCount: parentChildren.length,
      itemBuilder: (context, index) {
        final child = parentChildren[index];
        final childId = child['id']?.toString() ?? '';
        final childName = child['name']?.toString() ?? '';
        final childSchool = child['school']?.toString() ?? '';
        final childRoute = child['route']?.toString() ?? '';
        final isRequesting = _requestingForChildId == childId;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context)),
              child: Text('$childName', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _firestore
                  .collection('requests')
                  .where('parentId', isEqualTo: _currentUser.uid)
                  .where('status', whereIn: ['pending', 'approved'])
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));

                final requests = snapshot.data!.docs;
                QueryDocumentSnapshot<Map<String, dynamic>>? approvedRequest;
                try {
                  approvedRequest = requests.firstWhere((r) {
                    final data = r.data();
                    return data['status'] == 'approved' && (data['childIds'] as List).contains(childId);
                  });
                } catch (_) {
                  approvedRequest = null;
                }

                if (approvedRequest != null) {
                  final driverId = approvedRequest.data()['driverId'] as String?;
                  if (driverId == null || driverId.isEmpty) return const SizedBox(height: 48, child: Center(child: Text('Driver not assigned yet')));

                  return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: _firestore.collection('users').doc(driverId).get(),
                    builder: (context, driverSnap) {
                      if (!driverSnap.hasData) return const Center(child: CircularProgressIndicator());
                      final driverData = driverSnap.data?.data();
                      if (driverData == null) return const SizedBox();

                      _updateAssignedDriver(driverId, driverData['name']?.toString() ?? '', childId);

                      return _premiumCard(
                        margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context) * 2),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                child: Padding(
                                  padding: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context) * 2),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        // Child Avatar
                                        GestureDetector(
                                          onTap: () {
                                            final url = child['photo']?.toString() ?? '';
                                            if (url.isNotEmpty) {
                                              _viewImage('Child: ${child['name']}', NetworkImage(url));
                                            }
                                          },
                                          child: _circularAvatar(
                                            imageUrl: child['photo']?.toString() ?? '',
                                            label: 'Child',
                                            radius: 45,
                                          ),
                                        ),
                                        const SizedBox(width: 20),
                                        // Connection Icon
                                        Icon(Icons.swap_horiz_rounded, color: AppTheme.primary.withOpacity(0.3), size: 28),
                                        const SizedBox(width: 20),
                                        // Driver Avatar
                                        GestureDetector(
                                          onTap: () {
                                            final url = driverData['profilePic']?.toString() ?? '';
                                            if (url.isNotEmpty) {
                                              _viewImage('Driver: ${driverData['name']}', NetworkImage(url));
                                            }
                                          },
                                          child: _circularAvatar(
                                            imageUrl: driverData['profilePic']?.toString() ?? '',
                                            label: 'Driver',
                                            radius: 45,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              _driverInfoRow(Icons.person_rounded, 'Driver', driverData['name']?.toString() ?? '—'),
                              _driverInfoRow(Icons.phone_rounded, 'Phone Number', driverData['phone']?.toString() ?? '—'),
                              _driverInfoRow(Icons.directions_car_rounded, 'Vehicle Name', driverData['vehicleName']?.toString() ?? '—'),
                              _driverInfoRow(Icons.numbers_rounded, 'Vehicle Number', driverData['vehicleNumber']?.toString() ?? '—'),
                              _driverInfoRow(Icons.school_rounded, 'School', driverData['school']?.toString() ?? '—'),
                              _driverInfoRow(Icons.route_rounded, 'Route', driverData['route']?.toString() ?? '—'),
                              _driverInfoRow(Icons.event_seat_rounded, 'Seats', driverData['seats']?.toString() ?? '—'),
                              _weeklyAvailabilitySection(driverData),
                              SizedBox(height: AppTheme.verticalSpacing(context)),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(color: AppTheme.success.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                child: Row(children: [
                                  const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text('This driver is assigned to your child', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary))),
                                ]),
                              ),
                              SizedBox(height: AppTheme.verticalSpacing(context)),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => DriverLocationScreen(childId: childId))),
                                      icon: const Icon(Icons.location_on_rounded, size: 20),
                                      label: const Text('Track driver'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        final phone = driverData['phone']?.toString() ?? '';
                                        if (phone.isNotEmpty) {
                                          final telUri = Uri(scheme: 'tel', path: phone);
                                          if (await canLaunchUrl(telUri)) {
                                            await launchUrl(telUri);
                                          }
                                        }
                                      },
                                      icon: const Icon(Icons.phone_rounded, size: 20),
                                      label: const Text('Call driver'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                      );
                    },
                  );
                }

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _firestore.collection('users').where('role', isEqualTo: 'driver').snapshots(),
                  builder: (context, driversSnap) {
                    if (!driversSnap.hasData) return const Center(child: CircularProgressIndicator());
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _firestore
                          .collection('requests')
                          .where('status', isEqualTo: 'approved')
                          .snapshots(),
                      builder: (context, approvedRequestsSnap) {
                        if (!approvedRequestsSnap.hasData) {
                          return const Center(child: CircularProgressIndicator());
                        }

                        final approvedRequests = approvedRequestsSnap.data!.docs;
                        final Map<String, int> occupiedSeatsByDriver = {};
                        for (final req in approvedRequests) {
                          final reqData = req.data();
                          final driverId = (reqData['driverId'] ?? '').toString();
                          if (driverId.isEmpty) continue;
                          final childIds = (reqData['childIds'] as List?) ?? const [];
                          occupiedSeatsByDriver[driverId] =
                              (occupiedSeatsByDriver[driverId] ?? 0) + childIds.length;
                        }

                        final drivers = driversSnap.data!.docs.where((doc) {
                          final d = doc.data();
                          if (d['school'] != childSchool || d['route'] != childRoute) {
                            return false;
                          }
                          final seats = int.tryParse((d['seats'] ?? '').toString()) ?? 0;
                          final occupied = occupiedSeatsByDriver[doc.id] ?? 0;
                          return seats <= 0 || occupied < seats;
                        }).toList();

                        if (drivers.isEmpty) {
                          return _premiumCard(
                            margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context) * 2),
                            child: Text('No drivers available for this route yet.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary)),
                          );
                        }

                        return Column(
                          children: drivers.map((doc) {
                        final d = doc.data();
                        return _premiumCard(
                          margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context)),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if ((d['profilePic'] ?? '').toString().isNotEmpty)
                                  Center(
                                    child: Container(
                                      margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context) * 1.5),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AppTheme.primary.withOpacity(0.1),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(16),
                                        child: Image.network(
                                          d['profilePic'].toString(),
                                          height: 100,
                                          width: 100,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => Container(
                                            height: 100,
                                            width: 100,
                                            color: AppTheme.primary.withOpacity(0.1),
                                            child: Icon(Icons.person_rounded, size: 50, color: AppTheme.primary.withOpacity(0.5)),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                _driverInfoRow(Icons.person_rounded, 'Name', d['name']?.toString() ?? '—'),
                                _driverInfoRow(Icons.badge_rounded, 'CNIC', d['cnic']?.toString() ?? '—'),
                                _driverInfoRow(Icons.directions_car_rounded, 'Vehicle', '${d['vehicleName'] ?? '—'} (${d['vehicleNumber'] ?? '—'})'),
                                _driverInfoRow(Icons.route_rounded, 'Route', d['route']?.toString() ?? '—'),
                                _weeklyAvailabilitySection(d),
                                SizedBox(height: AppTheme.verticalSpacing(context)),
                                FilledButton(
                                  onPressed: isRequesting
                                      ? null
                                      : () async {
                                          setState(() => _requestingForChildId = childId);
                                          try {
                                            // Create a single request document instead of one per admin.
                                            final adminSnapshot = await _firestore
                                                .collection('users')
                                                .where('role', isEqualTo: 'admin')
                                                .limit(1)
                                                .get();
                                            String? adminId;
                                            if (adminSnapshot.docs.isNotEmpty) {
                                              adminId = adminSnapshot.docs.first.id;
                                            }
                                            final requestData = <String, dynamic>{
                                              'parentId': _currentUser.uid,
                                              'driverId': doc.id,
                                              'childIds': [childId],
                                              'status': 'pending',
                                              'timestamp': FieldValue.serverTimestamp(),
                                            };
                                            if (adminId != null) {
                                              requestData['adminId'] = adminId;
                                            }
                                            await _firestore.collection('requests').add(requestData);
                                            if (mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Request sent to admin'),
                                                  backgroundColor: AppTheme.success,
                                                  behavior: SnackBarBehavior.floating,
                                                ),
                                              );
                                            }
                                          } finally {
                                            if (mounted) {
                                              setState(() => _requestingForChildId = null);
                                            }
                                          }
                                        },
                                  child: isRequesting
                                      ? const SizedBox(
                                          height: 18,
                                          width: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : const Text('Request driver'),
                                ),
                              ],
                            ),
                        );
                          }).toList(),
                        );
                      },
                    );
                  },
                );
              },
            ),
            SizedBox(height: AppTheme.verticalSpacing(context) * 2),
          ],
        );
      },
    );
  }

  Widget _paymentsPage(Map<String, dynamic> parentData) {
    final parentChildren = List<Map<String, dynamic>>.from(parentData['children'] ?? []);
    final childIds = parentChildren
        .map((c) => c['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('rides')
          .where('parentId', isEqualTo: _currentUser.uid)
          .snapshots(),
      builder: (context, ridesSnap) {
        if (!ridesSnap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final rides = ridesSnap.data!.docs.where((doc) {
          final data = doc.data();
          final childId = (data['childId'] ?? '').toString();
              final rideStatus = (data['rideStatus'] ?? '').toString().toLowerCase();
              if (rideStatus != 'completed') return false;
          if (childIds.isEmpty) return true;
          return childIds.contains(childId);
        }).toList()
          ..sort((a, b) {
            final aTs = a.data()['endTime'] as Timestamp?;
            final bTs = b.data()['endTime'] as Timestamp?;
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return bTs.compareTo(aTs);
          });

        final rideIds = rides.map((r) => r.id).toSet().toList();
        final driverIds = rides
            .map((r) => (r.data()['driverId'] ?? '').toString().trim())
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();
        final parentAccountId = FinancialAccountingService.buildAccountId(
          role: 'parent',
          userId: _currentUser.uid,
        );

        return FutureBuilder<Map<String, String>>(
          future: _fetchDriverNamesByIds(driverIds),
          builder: (context, driverNamesSnap) {
            final driverNamesById = driverNamesSnap.data ?? const <String, String>{};
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _firestore
                  .collection('earnings_ledger')
                  .where('rideId', whereIn: rideIds.isEmpty ? ['__none__'] : rideIds)
                  .snapshots(),
              builder: (context, ledgerSnap) {
                final _ = ledgerSnap.data?.docs ?? const [];
                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _firestore
                      .collection('payments')
                      .where('parentId', isEqualTo: _currentUser.uid)
                      .snapshots(),
                  builder: (context, paymentsSnap) {
                    final paymentDocs = paymentsSnap.data?.docs ?? const [];
                    final paymentByRideId = <String, Map<String, dynamic>>{};

                    int toMillis(dynamic value) {
                      if (value is Timestamp) return value.millisecondsSinceEpoch;
                      if (value is DateTime) return value.millisecondsSinceEpoch;
                      return 0;
                    }

                    for (final doc in paymentDocs) {
                      final row = doc.data();
                      final rideIdFromPayment =
                          (row['rideId'] ?? '').toString().trim();
                      if (rideIdFromPayment.isEmpty) continue;
                      final candidate = <String, dynamic>{
                        'docId': doc.id,
                        ...row,
                      };
                      final existing = paymentByRideId[rideIdFromPayment];
                      if (existing == null) {
                        paymentByRideId[rideIdFromPayment] = candidate;
                        continue;
                      }
                      final candidateTs = toMillis(
                        candidate['paymentDateTime'] ?? candidate['paidAt'],
                      );
                      final existingTs = toMillis(
                        existing['paymentDateTime'] ?? existing['paidAt'],
                      );
                      if (candidateTs >= existingTs) {
                        paymentByRideId[rideIdFromPayment] = candidate;
                      }
                    }

                    final fallbackPaidTotal = paymentDocs.fold<double>(
                      0,
                      (sum, doc) {
                        final row = doc.data();
                        final status =
                            (row['status'] ?? '').toString().toLowerCase();
                        if (status != 'paid') return sum;
                        final amount = (row['amount'] as num?)?.toDouble() ?? 0;
                        return sum + amount;
                      },
                    );
                    final fallbackTransactionCount = paymentDocs.where((doc) {
                      final status =
                          (doc.data()['status'] ?? '').toString().toLowerCase();
                      return status == 'paid';
                    }).length;

                    return StreamBuilder<
                        DocumentSnapshot<Map<String, dynamic>>>(
                      stream: _firestore
                          .collection('financial_accounts')
                          .doc(parentAccountId)
                          .snapshots(),
                      builder: (context, accountSnap) {
                        final accountData = accountSnap.data?.data() ??
                            const <String, dynamic>{};
                        final accountId = (accountData['accountId'] ?? parentAccountId)
                            .toString();
                        final totalPaid =
                            (accountData['totalPaid'] as num?)?.toDouble() ??
                                fallbackPaidTotal;
                        final totalTransactions =
                            (accountData['totalTransactions'] as num?)?.toInt() ??
                                fallbackTransactionCount;

                        Widget statTile({
                          required String title,
                          required String value,
                          required IconData icon,
                        }) {
                          return Container(
                            constraints: const BoxConstraints(minWidth: 160),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: Colors.white,
                              border: Border.all(color: AppTheme.textSecondary.withOpacity(0.15)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: AppTheme.primary.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(icon, size: 18, color: AppTheme.primary),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSecondary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        value,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        Widget sectionTitle(String text) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              text,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          );
                        }

                        Widget infoRow({
                          required IconData icon,
                          required String label,
                          required String value,
                        }) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(icon, size: 16, color: AppTheme.textSecondary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text.rich(
                                    TextSpan(
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppTheme.textSecondary,
                                      ),
                                      children: [
                                        TextSpan(
                                          text: '$label: ',
                                          style: const TextStyle(fontWeight: FontWeight.w600),
                                        ),
                                        TextSpan(text: value),
                                      ],
                                    ),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        Widget statusBadge(String status) {
                          final normalized = status.toLowerCase();
                          final Color background;
                          final Color foreground;
                          if (normalized == 'paid') {
                            background = const Color(0xFFD1FAE5);
                            foreground = const Color(0xFF065F46);
                          } else if (normalized == 'failed') {
                            background = const Color(0xFFFEE2E2);
                            foreground = const Color(0xFF991B1B);
                          } else {
                            background = const Color(0xFFFFEDD5);
                            foreground = const Color(0xFF9A3412);
                          }
                          final label = normalized.isEmpty
                              ? 'Pending'
                              : '${normalized[0].toUpperCase()}${normalized.substring(1)}';
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: background,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: foreground,
                              ),
                            ),
                          );
                        }

                        final paymentEntries = rides.map((rideDoc) {
                          final ride = rideDoc.data();
                          final rideId = rideDoc.id;
                          final fare = (ride['fare'] as num?)?.toDouble() ?? 0;
                          final paymentStatus = (ride['paymentStatus'] ?? 'pending')
                              .toString()
                              .toLowerCase();
                          final matchedChild = parentChildren.firstWhere(
                            (c) =>
                                (c['id'] ?? '').toString() ==
                                (ride['childId'] ?? '').toString(),
                            orElse: () => <String, dynamic>{},
                          );
                          final childName = (ride['childName'] ??
                                  matchedChild['name'] ??
                                  '')
                              .toString()
                              .trim();
                          final schoolName = (ride['schoolName'] ??
                                  matchedChild['school'] ??
                                  '')
                              .toString()
                              .trim();
                          final routeName = (ride['route'] ??
                                  ride['routeName'] ??
                                  matchedChild['route'] ??
                                  '')
                              .toString()
                              .trim();
                          final driverId =
                              (ride['driverId'] ?? '').toString().trim();
                          final driverNameFromRide =
                              (ride['driverName'] ?? '').toString().trim();
                          final driverName = driverNameFromRide.isNotEmpty
                              ? driverNameFromRide
                              : (driverNamesById[driverId] ?? 'Not available');
                          final isPayingThisRide = _payingRideId == rideId;
                          final canPay =
                              paymentStatus == 'pending' && !isPayingThisRide;
                          final routeLabel = routeName.isNotEmpty
                              ? routeName
                              : 'Not available';
                          final schoolLabel = schoolName.isNotEmpty
                              ? schoolName
                              : 'Not available';
                          final childLabel = childName.isNotEmpty
                              ? childName
                              : 'Not available';
                          final paymentRow = paymentByRideId[rideId];
                          final transactionId = (paymentRow?['transactionId'] ?? '')
                              .toString()
                              .trim();
                          final paymentIntentId =
                              (paymentRow?['stripePaymentIntentId'] ?? '')
                                  .toString()
                                  .trim();
                          final paymentMethodRaw = (paymentRow?['paymentMethod'] ??
                                  paymentRow?['method'] ??
                                  '')
                              .toString()
                              .trim()
                              .toLowerCase();
                          final paymentMethod = paymentMethodRaw.isEmpty
                              ? '-'
                              : (paymentMethodRaw == 'stripe' ||
                                      paymentMethodRaw == 'stripe_payment_intent' ||
                                      paymentMethodRaw.contains('stripe'))
                                  ? 'Stripe'
                                  : paymentMethodRaw;
                          final paymentDateValue = paymentRow?['paymentDateTime'] ??
                              paymentRow?['paidAt'];
                          DateTime? paymentDate;
                          if (paymentDateValue is Timestamp) {
                            paymentDate = paymentDateValue.toDate();
                          } else if (paymentDateValue is DateTime) {
                            paymentDate = paymentDateValue;
                          }
                          final paymentDateLabel = paymentDateValue is Timestamp
                              ? _formatTimestamp(paymentDateValue)
                              : (paymentDateValue is DateTime
                                  ? _formatTimestamp(Timestamp.fromDate(paymentDateValue))
                                  : '-');

                          return <String, dynamic>{
                            'rideDoc': rideDoc,
                            'ride': ride,
                            'rideId': rideId,
                            'fare': fare,
                            'paymentStatus': paymentStatus,
                            'driverName': driverName,
                            'routeLabel': routeLabel,
                            'schoolLabel': schoolLabel,
                            'childLabel': childLabel,
                            'transactionId': transactionId,
                            'paymentIntentId': paymentIntentId,
                            'paymentMethod': paymentMethod,
                            'paymentDate': paymentDate,
                            'paymentDateLabel': paymentDateLabel,
                            'isPayingThisRide': isPayingThisRide,
                            'canPay': canPay,
                          };
                        }).toList();

                        bool dateMatches(DateTime? candidate) {
                          if (_paymentsFromDate == null && _paymentsToDate == null) {
                            return true;
                          }
                          if (candidate == null) return false;
                          final candidateDate =
                              DateTime(candidate.year, candidate.month, candidate.day);
                          if (_paymentsFromDate != null) {
                            final from = DateTime(
                              _paymentsFromDate!.year,
                              _paymentsFromDate!.month,
                              _paymentsFromDate!.day,
                            );
                            if (candidateDate.isBefore(from)) return false;
                          }
                          if (_paymentsToDate != null) {
                            final to = DateTime(
                              _paymentsToDate!.year,
                              _paymentsToDate!.month,
                              _paymentsToDate!.day,
                            );
                            if (candidateDate.isAfter(to)) return false;
                          }
                          return true;
                        }

                        final filteredEntries = paymentEntries.where((entry) {
                          final driverName =
                              (entry['driverName'] ?? '').toString().toLowerCase();
                          final routeLabel =
                              (entry['routeLabel'] ?? '').toString().toLowerCase();
                          final transactionId =
                              (entry['transactionId'] ?? '').toString().toLowerCase();
                          final status =
                              (entry['paymentStatus'] ?? '').toString().toLowerCase();
                          final method =
                              (entry['paymentMethod'] ?? '').toString().toLowerCase();

                          final driverMatch = _paymentsDriverQuery.trim().isEmpty ||
                              driverName.contains(_paymentsDriverQuery.trim().toLowerCase());
                          final routeMatch = _paymentsRouteQuery.trim().isEmpty ||
                              routeLabel.contains(_paymentsRouteQuery.trim().toLowerCase());
                          final transactionMatch =
                              _paymentsTransactionQuery.trim().isEmpty ||
                                  transactionId.contains(
                                    _paymentsTransactionQuery.trim().toLowerCase(),
                                  );
                          final statusMatch = _paymentsStatusFilter == 'all' ||
                              status == _paymentsStatusFilter;
                          final methodMatch = _paymentsMethodFilter == 'all' ||
                              (_paymentsMethodFilter == 'stripe' &&
                                  method.contains('stripe'));
                          final paymentDateMatch =
                              dateMatches(entry['paymentDate'] as DateTime?);
                          return driverMatch &&
                              routeMatch &&
                              transactionMatch &&
                              statusMatch &&
                              methodMatch &&
                              paymentDateMatch;
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
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.account_balance_wallet_rounded,
                                        color: AppTheme.primary.withOpacity(0.85),
                                      ),
                                      const SizedBox(width: 8),
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
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      statTile(
                                        title: 'Account ID',
                                        value: accountId.trim().isEmpty ? '-' : accountId,
                                        icon: Icons.badge_rounded,
                                      ),
                                      statTile(
                                        title: 'Total Paid',
                                        value: 'PKR ${totalPaid.toStringAsFixed(2)}',
                                        icon: Icons.payments_rounded,
                                      ),
                                      statTile(
                                        title: 'Total Transactions',
                                        value: '$totalTransactions',
                                        icon: Icons.receipt_long_rounded,
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            _premiumCard(
                              margin: EdgeInsets.only(
                                bottom: AppTheme.verticalSpacing(context),
                              ),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final maxWidth = constraints.maxWidth;
                                  final useSingleColumn = maxWidth < 520;
                                  final columnWidth = useSingleColumn
                                      ? maxWidth
                                      : (maxWidth - 10) / 2;
                                  final textFieldWidth = useSingleColumn
                                      ? maxWidth
                                      : math.min(240.0, columnWidth);
                                  final dropdownWidth = useSingleColumn
                                      ? maxWidth
                                      : math.min(maxWidth, math.max(columnWidth, 200.0));
                                  final actionButtonWidth = useSingleColumn
                                      ? maxWidth
                                      : math.min(columnWidth, 220.0);
                                  final fromDateLabel = _paymentsFromDate == null
                                      ? 'From Date'
                                      : '${_paymentsFromDate!.day.toString().padLeft(2, '0')}/${_paymentsFromDate!.month.toString().padLeft(2, '0')}/${_paymentsFromDate!.year}';
                                  final toDateLabel = _paymentsToDate == null
                                      ? 'To Date'
                                      : '${_paymentsToDate!.day.toString().padLeft(2, '0')}/${_paymentsToDate!.month.toString().padLeft(2, '0')}/${_paymentsToDate!.year}';

                                  return Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      SizedBox(
                                        width: textFieldWidth,
                                        child: TextFormField(
                                          initialValue: _paymentsDriverQuery,
                                          onChanged: (value) =>
                                              setState(() => _paymentsDriverQuery = value),
                                          decoration: const InputDecoration(
                                            labelText: 'Search Driver Name',
                                            prefixIcon: Icon(Icons.person_search_rounded),
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: textFieldWidth,
                                        child: TextFormField(
                                          initialValue: _paymentsRouteQuery,
                                          onChanged: (value) =>
                                              setState(() => _paymentsRouteQuery = value),
                                          decoration: const InputDecoration(
                                            labelText: 'Search Route',
                                            prefixIcon: Icon(Icons.alt_route_rounded),
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: useSingleColumn ? maxWidth : math.min(240.0, maxWidth),
                                        child: TextFormField(
                                          initialValue: _paymentsTransactionQuery,
                                          onChanged: (value) => setState(
                                            () => _paymentsTransactionQuery = value,
                                          ),
                                          decoration: const InputDecoration(
                                            labelText: 'Search Transaction ID',
                                            prefixIcon: Icon(Icons.receipt_long_rounded),
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: dropdownWidth,
                                        child: DropdownButtonFormField<String>(
                                          isExpanded: true,
                                          value: _paymentsStatusFilter,
                                          items: const [
                                            DropdownMenuItem(value: 'all', child: Text('Status: All')),
                                            DropdownMenuItem(value: 'paid', child: Text('Status: Paid')),
                                            DropdownMenuItem(
                                              value: 'pending',
                                              child: Text('Status: Pending'),
                                            ),
                                          ],
                                          onChanged: (value) {
                                            if (value == null) return;
                                            setState(() => _paymentsStatusFilter = value);
                                          },
                                          decoration: const InputDecoration(
                                            labelText: 'Payment Status',
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: dropdownWidth,
                                        child: DropdownButtonFormField<String>(
                                          isExpanded: true,
                                          value: _paymentsMethodFilter,
                                          items: const [
                                            DropdownMenuItem(value: 'all', child: Text('Method: All')),
                                            DropdownMenuItem(
                                              value: 'stripe',
                                              child: Text('Method: Stripe'),
                                            ),
                                          ],
                                          onChanged: (value) {
                                            if (value == null) return;
                                            setState(() => _paymentsMethodFilter = value);
                                          },
                                          decoration: const InputDecoration(
                                            labelText: 'Payment Method',
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: actionButtonWidth,
                                        child: OutlinedButton.icon(
                                          onPressed: () => _pickPaymentsDate(isFromDate: true),
                                          icon: const Icon(Icons.date_range_rounded),
                                          label: Text(
                                            fromDateLabel,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: actionButtonWidth,
                                        child: OutlinedButton.icon(
                                          onPressed: () => _pickPaymentsDate(isFromDate: false),
                                          icon: const Icon(Icons.event_rounded),
                                          label: Text(
                                            toDateLabel,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                      TextButton.icon(
                                        onPressed: _resetPaymentsFilters,
                                        icon: const Icon(Icons.refresh_rounded),
                                        label: const Text('Reset Filters'),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                            if (filteredEntries.isEmpty)
                              _premiumCard(
                                margin: EdgeInsets.only(
                                  bottom: AppTheme.verticalSpacing(context),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.receipt_long_rounded,
                                      size: 44,
                                      color: AppTheme.textSecondary.withOpacity(0.55),
                                    ),
                                    const SizedBox(height: 10),
                                    const Text(
                                      'No payment history found.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ...filteredEntries.map((entry) {
                              final ride = entry['ride'] as Map<String, dynamic>;
                              final rideId = (entry['rideId'] ?? '').toString();
                              final fare = (entry['fare'] as num?)?.toDouble() ?? 0;
                              final paymentStatus =
                                  (entry['paymentStatus'] ?? 'pending').toString();
                              final driverName =
                                  (entry['driverName'] ?? 'Not available').toString();
                              final routeLabel =
                                  (entry['routeLabel'] ?? 'Not available').toString();
                              final schoolLabel =
                                  (entry['schoolLabel'] ?? 'Not available').toString();
                              final childLabel =
                                  (entry['childLabel'] ?? 'Not available').toString();
                              final transactionId =
                                  (entry['transactionId'] ?? '').toString();
                              final paymentIntentId =
                                  (entry['paymentIntentId'] ?? '').toString();
                              final paymentMethod =
                                  (entry['paymentMethod'] ?? '-').toString();
                              final paymentDateLabel =
                                  (entry['paymentDateLabel'] ?? '-').toString();
                              final isPayingThisRide =
                                  (entry['isPayingThisRide'] as bool?) ?? false;
                              final canPay = (entry['canPay'] as bool?) ?? false;
                              final paymentStatusLabel = paymentStatus.isEmpty
                                  ? 'Pending'
                                  : '${paymentStatus[0].toUpperCase()}${paymentStatus.substring(1)}';

                              return _premiumCard(
                                margin: EdgeInsets.only(
                                  bottom: AppTheme.verticalSpacing(context),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.local_taxi_rounded,
                                          color: AppTheme.primary,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '$childLabel • Ride Payment',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                              color: AppTheme.textPrimary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          fit: FlexFit.loose,
                                          child: statusBadge(paymentStatus),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                    sectionTitle('Ride Information'),
                                    infoRow(
                                      icon: Icons.child_care_rounded,
                                      label: 'Child Name',
                                      value: childLabel,
                                    ),
                                    infoRow(
                                      icon: Icons.person_rounded,
                                      label: 'Driver Name',
                                      value: driverName,
                                    ),
                                    infoRow(
                                      icon: Icons.school_rounded,
                                      label: 'School',
                                      value: schoolLabel,
                                    ),
                                    infoRow(
                                      icon: Icons.alt_route_rounded,
                                      label: 'Route',
                                      value: routeLabel,
                                    ),
                                    const SizedBox(height: 8),
                                    sectionTitle('Payment Information'),
                                    infoRow(
                                      icon: Icons.payments_rounded,
                                      label: 'Fare',
                                      value: 'PKR ${fare.toStringAsFixed(0)}',
                                    ),
                                    infoRow(
                                      icon: Icons.verified_rounded,
                                      label: 'Payment Status',
                                      value: paymentStatusLabel,
                                    ),
                                    infoRow(
                                      icon: Icons.credit_card_rounded,
                                      label: 'Payment Method',
                                      value: paymentMethod,
                                    ),
                                    infoRow(
                                      icon: Icons.schedule_rounded,
                                      label: 'Payment Date',
                                      value: paymentDateLabel,
                                    ),
                                    const SizedBox(height: 8),
                                    sectionTitle('Transaction Information'),
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Icon(
                                            Icons.receipt_rounded,
                                            size: 16,
                                            color: AppTheme.textSecondary,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Transaction ID: ${transactionId.isEmpty ? '-' : _compactId(transactionId)}',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: AppTheme.textSecondary,
                                              ),
                                            ),
                                          ),
                                          if (transactionId.isNotEmpty)
                                            IconButton(
                                              tooltip: 'Copy Transaction ID',
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 36,
                                                minHeight: 36,
                                              ),
                                              onPressed: () => _copyToClipboard(
                                                'Transaction ID',
                                                transactionId,
                                              ),
                                              icon: const Icon(
                                                Icons.copy_rounded,
                                                size: 18,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Icon(
                                            Icons.qr_code_rounded,
                                            size: 16,
                                            color: AppTheme.textSecondary,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Stripe PaymentIntent ID: ${paymentIntentId.isEmpty ? '-' : _compactId(paymentIntentId)}',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 13,
                                                color: AppTheme.textSecondary,
                                              ),
                                            ),
                                          ),
                                          if (paymentIntentId.isNotEmpty)
                                            IconButton(
                                              tooltip: 'Copy PaymentIntent ID',
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 36,
                                                minHeight: 36,
                                              ),
                                              onPressed: () => _copyToClipboard(
                                                'Stripe PaymentIntent ID',
                                                paymentIntentId,
                                              ),
                                              icon: const Icon(
                                                Icons.copy_rounded,
                                                size: 18,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: canPay
                                          ? FilledButton(
                                              onPressed: () async {
                                                if (mounted) {
                                                  setState(
                                                    () => _payingRideId = rideId,
                                                  );
                                                }
                                                try {
                                                  final paymentIntentData =
                                                      await _payRideWithStripe(
                                                    fare: fare,
                                                    rideId: rideId,
                                                  );

                                                  late final DocumentReference<
                                                      Map<String,
                                                          dynamic>> paymentRef;
                                                  final existingPaymentSnap =
                                                      await _firestore
                                                          .collection('payments')
                                                          .where('rideId',
                                                              isEqualTo: rideId)
                                                          .where('parentId',
                                                              isEqualTo:
                                                                  _currentUser
                                                                      .uid)
                                                          .limit(1)
                                                          .get();

                                                  if (existingPaymentSnap
                                                      .docs.isNotEmpty) {
                                                    paymentRef = existingPaymentSnap
                                                        .docs.first.reference;
                                                    await paymentRef.set({
                                                      'amount': fare,
                                                      'status': 'paid',
                                                      'paidAt': FieldValue
                                                          .serverTimestamp(),
                                                      'paymentDateTime':
                                                          FieldValue
                                                              .serverTimestamp(),
                                                      'method':
                                                          'stripe_payment_intent',
                                                      'paymentMethod': 'stripe',
                                                      'stripePaymentIntentId':
                                                          paymentIntentData
                                                              .paymentIntentId,
                                                    }, SetOptions(merge: true));
                                                  } else {
                                                    paymentRef = await _firestore
                                                        .collection('payments')
                                                        .add({
                                                      'rideId': rideId,
                                                      'parentId':
                                                          _currentUser.uid,
                                                      'amount': fare,
                                                      'status': 'paid',
                                                      'paidAt': FieldValue
                                                          .serverTimestamp(),
                                                      'paymentDateTime':
                                                          FieldValue
                                                              .serverTimestamp(),
                                                      'method':
                                                          'stripe_payment_intent',
                                                      'paymentMethod': 'stripe',
                                                      'stripePaymentIntentId':
                                                          paymentIntentData
                                                              .paymentIntentId,
                                                    });
                                                  }

                                                  final ledgerResult =
                                                      await FinancialAccountingService
                                                          .recordSuccessfulPayment(
                                                    firestore: _firestore,
                                                    paymentId: paymentRef.id,
                                                    stripePaymentIntentId:
                                                        paymentIntentData
                                                            .paymentIntentId,
                                                    rideId: rideId,
                                                    parentId: _currentUser.uid,
                                                    driverId:
                                                        (ride['driverId'] ?? '')
                                                            .toString(),
                                                    amount: fare,
                                                    paymentMethod: 'stripe',
                                                    paymentStatus: 'paid',
                                                  );

                                                  await paymentRef.set({
                                                    'transactionId': ledgerResult
                                                        .transactionId,
                                                    'parentAccountId': ledgerResult
                                                        .parentAccountId,
                                                    'driverAccountId': ledgerResult
                                                        .driverAccountId,
                                                    'adminAccountId': ledgerResult
                                                        .adminAccountId,
                                                    'driverShare':
                                                        ledgerResult.driverShare,
                                                    'adminCommission': ledgerResult
                                                        .adminCommission,
                                                  }, SetOptions(merge: true));

                                                  final existingLedgerSnap =
                                                      await _firestore
                                                          .collection(
                                                              'earnings_ledger')
                                                          .where('rideId',
                                                              isEqualTo: rideId)
                                                          .limit(1)
                                                          .get();

                                                  if (existingLedgerSnap
                                                      .docs.isEmpty) {
                                                    await _firestore
                                                        .collection(
                                                            'earnings_ledger')
                                                        .add({
                                                      'rideId': rideId,
                                                      'paymentId': paymentRef.id,
                                                      'driverId':
                                                          (ride['driverId'] ?? '')
                                                              .toString(),
                                                      'driverAmount': double.parse(
                                                          (fare * 0.7)
                                                              .toStringAsFixed(
                                                                  2)),
                                                      'superAdminAmount':
                                                          double.parse((fare * 0.3)
                                                              .toStringAsFixed(
                                                                  2)),
                                                      'split': '70_30',
                                                      'transactionId':
                                                          ledgerResult
                                                              .transactionId,
                                                      'stripePaymentIntentId':
                                                          paymentIntentData
                                                              .paymentIntentId,
                                                      'paymentDateTime':
                                                          FieldValue
                                                              .serverTimestamp(),
                                                      'createdAt': FieldValue
                                                          .serverTimestamp(),
                                                    });
                                                  } else {
                                                    await existingLedgerSnap
                                                        .docs.first.reference
                                                        .set({
                                                      'transactionId':
                                                          ledgerResult
                                                              .transactionId,
                                                      'stripePaymentIntentId':
                                                          paymentIntentData
                                                              .paymentIntentId,
                                                      'paymentDateTime':
                                                          FieldValue
                                                              .serverTimestamp(),
                                                    }, SetOptions(merge: true));
                                                  }

                                                  await _firestore
                                                      .collection('rides')
                                                      .doc(rideId)
                                                      .set({
                                                    'paymentStatus': 'paid',
                                                  }, SetOptions(merge: true));
                                                  if (mounted) {
                                                    ScaffoldMessenger.of(context)
                                                        .showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                            'Payment successful'),
                                                        backgroundColor:
                                                            AppTheme.success,
                                                        behavior: SnackBarBehavior
                                                            .floating,
                                                      ),
                                                    );
                                                  }
                                                } catch (e) {
                                                  _showPaymentOutcomeSnackBar(e);
                                                } finally {
                                                  if (mounted) {
                                                    setState(
                                                      () => _payingRideId = null,
                                                    );
                                                  }
                                                }
                                              },
                                              child: Text(
                                                isPayingThisRide
                                                    ? 'Processing...'
                                                    : 'Pay Now',
                                              ),
                                            )
                                          : const SizedBox.shrink(),
                                    ),
                                  ],
                                ),
                              );
                            }),
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
      },
    );
  }

  Widget _reviewsPage(Map<String, dynamic> parentData) {
    final parentChildren = List<Map<String, dynamic>>.from(parentData['children'] ?? []);
    final Map<String, String> childAssignedDrivers = {};
    for (final child in parentChildren) {
      final driverId = (child['assignedDriver'] ?? '').toString().trim();
      if (driverId.isEmpty) continue;
      final driverName = (child['assignedDriverName'] ?? '').toString().trim();
      childAssignedDrivers[driverId] = driverName.isEmpty ? driverId : driverName;
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _firestore
          .collection('requests')
          .where('parentId', isEqualTo: _currentUser.uid)
          .where('status', isEqualTo: 'approved')
          .snapshots(),
      builder: (context, requestsSnap) {
        final assignedDrivers = Map<String, String>.from(childAssignedDrivers);
        final approvedRequests = requestsSnap.data?.docs ?? const [];
        for (final req in approvedRequests) {
          final requestData = req.data();
          final driverId = (requestData['driverId'] ?? '').toString().trim();
          if (driverId.isEmpty) continue;
          assignedDrivers.putIfAbsent(driverId, () => driverId);
        }

        final hasSelectedDriver = _selectedReviewDriverId != null &&
            assignedDrivers.containsKey(_selectedReviewDriverId);
        final effectiveDriverId = hasSelectedDriver
            ? _selectedReviewDriverId
            : (assignedDrivers.isNotEmpty ? assignedDrivers.keys.first : null);

        if (!hasSelectedDriver && effectiveDriverId != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() => _selectedReviewDriverId = effectiveDriverId);
          });
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: ReviewService.watchParentReviews(_currentUser.uid),
          builder: (context, snapshot) {
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

            bool sameDay(DateTime a, DateTime b) =>
                a.year == b.year && a.month == b.month && a.day == b.day;

            final filteredReviewDocs = reviewDocs.where((doc) {
              final review = doc.data();
              final driverId = (review['driverId'] ?? '').toString().trim();
              final driverLabel =
                  assignedDrivers[driverId] ?? 'Driver ($driverId)';
              final rating = ((review['rating'] as num?)?.toInt() ?? 0).clamp(0, 5);
              final sentiment =
                  (review['sentiment'] ?? 'neutral').toString().toLowerCase().trim();
              final createdAt = (review['createdAt'] as Timestamp?)?.toDate();

              final driverMatches = _reviewDriverQuery.trim().isEmpty ||
                  driverLabel
                      .toLowerCase()
                      .contains(_reviewDriverQuery.trim().toLowerCase());
              final ratingMatches = _reviewRatingFilter == 'all' ||
                  rating.toString() == _reviewRatingFilter;
              final sentimentMatches = _reviewSentimentFilter == 'all' ||
                  sentiment == _reviewSentimentFilter;
              final dateMatches = _reviewDateFilter == null ||
                  (createdAt != null && sameDay(createdAt, _reviewDateFilter!));

              return driverMatches &&
                  ratingMatches &&
                  sentimentMatches &&
                  dateMatches;
            }).toList();

            return ListView(
              padding: AppTheme.contentPadding(context),
              children: [
                _premiumCard(
                  margin: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Submit Review',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 14),
                      if (assignedDrivers.isEmpty)
                        const Text(
                          'No assigned driver found for review yet.',
                          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                        )
                      else ...[
                        DropdownButtonFormField<String>(
                          value: effectiveDriverId,
                          decoration: const InputDecoration(labelText: 'Driver'),
                          items: assignedDrivers.entries
                              .map(
                                (e) => DropdownMenuItem<String>(
                                  value: e.key,
                                  child: Text(e.value),
                                ),
                              )
                              .toList(),
                          onChanged: _submittingReview
                              ? null
                              : (value) {
                                  setState(() => _selectedReviewDriverId = value);
                                },
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Rating',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: List.generate(5, (index) {
                            final star = index + 1;
                            final selected = star <= _reviewRating;
                            return IconButton(
                              onPressed: _submittingReview
                                  ? null
                                  : () => setState(() => _reviewRating = star),
                              icon: Icon(
                                selected ? Icons.star_rounded : Icons.star_border_rounded,
                                color: selected ? Colors.amber : AppTheme.textSecondary,
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _reviewCommentController,
                          enabled: !_submittingReview,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Comment',
                            hintText: 'Write your feedback',
                          ),
                        ),
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: _submittingReview
                                ? null
                                : () async {
                                    if (_submittingReview) return;
                                    final driverId = effectiveDriverId;
                                    final comment = _reviewCommentController.text.trim();
                                    final hasValidRating =
                                        _reviewRating >= 1 && _reviewRating <= 5;
                                    if (driverId == null || driverId.isEmpty) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Please select a driver.'),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                      return;
                                    }
                                    if (!hasValidRating || comment.isEmpty) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Please provide rating and comment'),
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                      return;
                                    }

                                    setState(() => _submittingReview = true);
                                    try {
                                      final sentiment =
                                          await _fetchSentimentFromApi(comment);
                                      print("FINAL SENTIMENT: $sentiment");
                                      await ReviewService.createReview(
                                        parentId: _currentUser.uid,
                                        driverId: driverId,
                                        rating: _reviewRating,
                                        comment: comment,
                                        sentiment: sentiment.trim().toLowerCase(),
                                      );
                                      if (!mounted) return;
                                      _reviewCommentController.clear();
                                      setState(() => _reviewRating = 5);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Review submitted successfully.'),
                                          backgroundColor: AppTheme.success,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    } catch (e) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('Failed to submit review: $e'),
                                          backgroundColor: AppTheme.error,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                    } finally {
                                      if (mounted) {
                                        setState(() => _submittingReview = false);
                                      }
                                    }
                                  },
                            icon: _submittingReview
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.send_rounded),
                            label: Text(_submittingReview ? 'Submitting...' : 'Submit'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _premiumCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'My Reviews',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          SizedBox(
                            width: 220,
                            child: TextFormField(
                              key: ValueKey('review-driver-$_reviewDriverQuery'),
                              initialValue: _reviewDriverQuery,
                              onChanged: (value) =>
                                  setState(() => _reviewDriverQuery = value),
                              decoration: const InputDecoration(
                                labelText: 'Search Driver Name',
                                prefixIcon: Icon(Icons.person_search_rounded),
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 150,
                            child: DropdownButtonFormField<String>(
                              value: _reviewRatingFilter,
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
                                setState(() => _reviewRatingFilter = value);
                              },
                              decoration: const InputDecoration(
                                labelText: 'Rating',
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 150,
                            child: DropdownButtonFormField<String>(
                              value: _reviewSentimentFilter,
                              isDense: true,
                              items: const [
                                DropdownMenuItem(value: 'all', child: Text('All')),
                                DropdownMenuItem(value: 'positive', child: Text('Positive')),
                                DropdownMenuItem(value: 'neutral', child: Text('Neutral')),
                                DropdownMenuItem(value: 'negative', child: Text('Negative')),
                              ],
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() => _reviewSentimentFilter = value);
                              },
                              decoration: const InputDecoration(
                                labelText: 'Sentiment',
                              ),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: _pickReviewDateFilter,
                            icon: const Icon(Icons.date_range_rounded),
                            label: Text(
                              _reviewDateFilter == null
                                  ? 'Filter Date'
                                  : '${_reviewDateFilter!.day.toString().padLeft(2, '0')}/${_reviewDateFilter!.month.toString().padLeft(2, '0')}/${_reviewDateFilter!.year}',
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _resetReviewFilters,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Clear Filters'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (reviewDocs.isEmpty)
                        const Text(
                          'No reviews submitted yet.',
                          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                        )
                      else if (filteredReviewDocs.isEmpty)
                        const Text(
                          'No reviews found for the selected filters.',
                          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                        )
                      else
                        ...filteredReviewDocs.map((doc) {
                          final review = doc.data();
                          final reviewId = doc.id;
                          final driverId = (review['driverId'] ?? '').toString();
                          final driverLabel =
                              assignedDrivers[driverId] ?? 'Driver ($driverId)';
                          final rating = (review['rating'] as num?)?.toInt() ?? 0;
                          final comment = (review['comment'] ?? '').toString();
                          final sentiment = (review['sentiment'] ?? 'neutral').toString();
                          final status = (review['status'] ?? 'active').toString();
                          final adminResponse =
                              (review['adminResponse'] as Map<String, dynamic>?) ??
                                  const <String, dynamic>{};
                          final adminResponseMessage =
                              (adminResponse['message'] ?? '').toString().trim();
                          final adminResponseStatus =
                              (adminResponse['status'] ?? '').toString().toLowerCase().trim();
                          final createdAt = (review['createdAt'] as Timestamp?)?.toDate();
                          final isEditing = _editingReviewId == reviewId;
                          final isDeleting = _deletingReviewId == reviewId;
                          final dateText = createdAt == null
                              ? 'Just now'
                              : '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}';

                          return Container(
                            margin: const EdgeInsets.only(top: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppTheme.divider),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        driverLabel,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: AppTheme.textPrimary,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      dateText,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppTheme.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Rating: $rating/5 • Sentiment: $sentiment • Status: $status',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  comment.isEmpty ? 'No comment' : comment,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textPrimary,
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
                                        Row(
                                          children: [
                                            const Text(
                                              'Admin Response:',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: AppTheme.textSecondary,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
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
                                Row(
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: (isEditing || isDeleting)
                                          ? null
                                          : () => _openEditReviewDialog(
                                                reviewId: reviewId,
                                                initialRating: rating,
                                                initialComment: comment,
                                              ),
                                      icon: isEditing
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.edit_outlined, size: 18),
                                      label: Text(isEditing ? 'Updating...' : 'Edit'),
                                    ),
                                    const SizedBox(width: 8),
                                    OutlinedButton.icon(
                                      onPressed: (isEditing || isDeleting)
                                          ? null
                                          : () => _softDeleteReviewAsParent(
                                                reviewId: reviewId,
                                              ),
                                      icon: isDeleting
                                          ? const SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.delete_outline, size: 18),
                                      label: Text(isDeleting ? 'Deleting...' : 'Delete'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _circularAvatar({required String imageUrl, required String label, double radius = 40}) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppTheme.primary.withOpacity(0.5),
                AppTheme.accent.withOpacity(0.5),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withOpacity(0.15),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: CircleAvatar(
              radius: radius,
              backgroundColor: AppTheme.subtleSurface,
              backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
              child: imageUrl.isEmpty
                  ? Icon(Icons.person_rounded, size: radius, color: AppTheme.primary.withOpacity(0.5))
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      ],
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

  Map<String, bool> _normalizeWeeklyAvailability(Map<String, dynamic> driverData) {
    final raw = driverData['weeklyAvailability'];
    const weekDays = <MapEntry<String, String>>[
      MapEntry('monday', 'Monday'),
      MapEntry('tuesday', 'Tuesday'),
      MapEntry('wednesday', 'Wednesday'),
      MapEntry('thursday', 'Thursday'),
      MapEntry('friday', 'Friday'),
      MapEntry('saturday', 'Saturday'),
      MapEntry('sunday', 'Sunday'),
    ];
    final normalized = {
      for (final day in weekDays) day.key: false,
    };
    if (raw is Map) {
      for (final day in weekDays) {
        normalized[day.key] = raw[day.key] == true;
      }
    }
    return normalized;
  }

  Widget _weeklyAvailabilitySection(Map<String, dynamic> driverData) {
    const weekDays = <MapEntry<String, String>>[
      MapEntry('monday', 'Monday'),
      MapEntry('tuesday', 'Tuesday'),
      MapEntry('wednesday', 'Wednesday'),
      MapEntry('thursday', 'Thursday'),
      MapEntry('friday', 'Friday'),
      MapEntry('saturday', 'Saturday'),
      MapEntry('sunday', 'Sunday'),
    ];
    final weekly = _normalizeWeeklyAvailability(driverData);
    final unavailable = weekDays.where((d) => weekly[d.key] != true).map((d) => d.value).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context) * 0.8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.calendar_month_rounded, size: 18, color: AppTheme.textSecondary),
              SizedBox(width: 8),
              Text(
                'Weekly availability',
                style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: weekDays.map((day) {
              final isAvailable = weekly[day.key] == true;
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: (isAvailable ? AppTheme.success : AppTheme.error).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '${day.value.substring(0, 3)} ${isAvailable ? 'A' : 'U'}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isAvailable ? AppTheme.success : AppTheme.error,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 6),
          Text(
            unavailable.isEmpty
                ? 'Upcoming unavailable days: None'
                : 'Upcoming unavailable days: ${unavailable.join(', ')}',
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _driverInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppTheme.verticalSpacing(context) * 0.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary))),
        ],
      ),
    );
  }

  Future<Map<String, String>> _fetchDriverNamesByIds(List<String> driverIds) async {
    if (driverIds.isEmpty) return const <String, String>{};

    final normalizedIds = driverIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (normalizedIds.isEmpty) return const <String, String>{};

    const chunkSize = 10;
    final Map<String, String> namesById = {};

    for (var i = 0; i < normalizedIds.length; i += chunkSize) {
      final end = (i + chunkSize < normalizedIds.length)
          ? i + chunkSize
          : normalizedIds.length;
      final chunk = normalizedIds.sublist(i, end);
      final snap = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        final data = doc.data();
        final name = (data['name'] ?? data['fullName'] ?? data['displayName'] ?? '').toString().trim();
        if (name.isNotEmpty) {
          namesById[doc.id] = name;
        }
      }
    }

    return namesById;
  }

  Future<void> _updateAssignedDriver(String driverId, String driverName, String childId) async {
    final parentDoc = await _firestore.collection('users').doc(_currentUser.uid).get();
    final children = List<Map<String, dynamic>>.from(parentDoc.data()?['children'] ?? []);
    final index = children.indexWhere((c) => c['id'] == childId);
    if (index != -1 && (children[index]['assignedDriver'] != driverId)) {
      children[index]['assignedDriver'] = driverId;
      children[index]['assignedDriverName'] = driverName;
      await _firestore.collection('users').doc(_currentUser.uid).set({'children': children}, SetOptions(merge: true));
    }
  }

  Future<void> _updateReviewAsParent({
    required String reviewId,
    required int rating,
    required String comment,
  }) async {
    if (_editingReviewId != null) return;
    setState(() => _editingReviewId = reviewId);
    try {
      final apiSentiment = await _fetchSentimentFromApi(comment);
      await _firestore.collection('reviews').doc(reviewId).set({
        'rating': rating,
        'comment': comment.trim(),
        'sentiment': apiSentiment,
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Review updated successfully.'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update review: $e'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _editingReviewId = null);
      }
    }
  }

  Future<void> _softDeleteReviewAsParent({
    required String reviewId,
  }) async {
    if (_deletingReviewId != null) return;
    setState(() => _deletingReviewId = reviewId);
    try {
      await _firestore.collection('reviews').doc(reviewId).delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Review deleted successfully.'),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete review: $e'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _deletingReviewId = null);
      }
    }
  }

  Future<void> _openEditReviewDialog({
    required String reviewId,
    required int initialRating,
    required String initialComment,
  }) async {
    int dialogRating = initialRating.clamp(1, 5);
    _editReviewCommentController.text = initialComment;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Review'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Rating'),
                  const SizedBox(height: 8),
                  Row(
                    children: List.generate(5, (index) {
                      final star = index + 1;
                      return IconButton(
                        onPressed: () {
                          setDialogState(() => dialogRating = star);
                        },
                        icon: Icon(
                          star <= dialogRating
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color:
                              star <= dialogRating ? Colors.amber : AppTheme.textSecondary,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _editReviewCommentController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Comment',
                      hintText: 'Update your feedback',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;
    final nextComment = _editReviewCommentController.text.trim();
    if (nextComment.isEmpty || dialogRating < 1 || dialogRating > 5) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide rating and comment'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await _updateReviewAsParent(
      reviewId: reviewId,
      rating: dialogRating,
      comment: nextComment,
    );
  }

  Future<String> _fetchSentimentFromApi(String comment) async {
    final endpoint = Uri.parse(ApiConfig.sentimentUrl);
    print('SENTIMENT REQUEST URL: $endpoint');
    try {
      final response = await http
          .post(
            endpoint,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'text': comment}),
          )
          .timeout(const Duration(seconds: 4));
      print('SENTIMENT RESPONSE BODY: ${response.body}');

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final rawSentiment = (data['sentiment'] ?? '').toString().toLowerCase().trim();
        if (rawSentiment == 'positive' ||
            rawSentiment == 'neutral' ||
            rawSentiment == 'negative') {
          return rawSentiment;
        }
        throw Exception('Invalid sentiment payload: ${response.body}');
      }
      throw Exception(
        'Sentiment API failed (${response.statusCode}): ${response.body}',
      );
    } catch (e) {
      print('SENTIMENT API ERROR: $e');
      rethrow;
    }
  }

  Future<_PaymentIntentData> _createPaymentIntent({
    required double fare,
    required String rideId,
  }) async {
    final endpoint = Uri.parse(ApiConfig.createPaymentIntentUrl);
    final response = await http
        .post(
          endpoint,
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'amount': fare,
            'rideId': rideId,
            'parentId': _currentUser.uid,
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'Payment intent failed (${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final clientSecret = (data['client_secret'] ?? '').toString().trim();
    final paymentIntentId = (data['payment_intent_id'] ?? '')
        .toString()
        .trim();
    if (clientSecret.isEmpty) {
      throw Exception('Missing Stripe client secret from backend.');
    }
    if (paymentIntentId.isEmpty) {
      throw Exception('Missing Stripe payment intent id from backend.');
    }
    return _PaymentIntentData(
      clientSecret: clientSecret,
      paymentIntentId: paymentIntentId,
    );
  }

  Future<_PaymentIntentData> _createPaymentIntentWithRetry({
    required double fare,
    required String rideId,
  }) async {
    Exception? lastException;
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        return await _createPaymentIntent(
          fare: fare,
          rideId: rideId,
        );
      } on TimeoutException catch (e) {
        lastException = Exception(
          'Payment intent request timed out (attempt $attempt). ${e.message ?? ''}'.trim(),
        );
      } catch (e) {
        if (attempt == 2) rethrow;
        lastException = Exception('Payment intent request failed (attempt $attempt): $e');
      }
      if (attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    }
    throw lastException ?? Exception('Payment intent request failed.');
  }

  bool _isPaymentCancelled(Object error) {
    if (error is _PaymentCancelledException) return true;
    if (error is StripeException) {
      return error.error.code == FailureCode.Canceled;
    }
    final raw = error.toString();
    return raw.contains('FailureCode.Canceled') ||
        RegExp(r'code:\s*Canceled\b').hasMatch(raw);
  }

  String _friendlyErrorMessage(Object error) {
    if (_isPaymentCancelled(error)) {
      return 'Payment cancelled.';
    }
    if (error is StripeException) {
      final localized = error.error.localizedMessage?.trim();
      if (localized != null && localized.isNotEmpty) {
        return localized;
      }
      final message = error.error.message?.trim();
      if (message != null && message.isNotEmpty) {
        return message;
      }
      return 'Payment failed. Please try again.';
    }
    if (error is StripeConfigException) {
      return error.message;
    }
    if (error is TimeoutException) {
      return error.message ?? 'Payment timed out. Please try again.';
    }
    final raw = error.toString().trim();
    if (raw.startsWith('Exception: ')) {
      final message = raw.substring('Exception: '.length).trim();
      if (message.startsWith('StripeException') ||
          message.contains('FailureCode.')) {
        return 'Payment failed. Please try again.';
      }
      return message;
    }
    if (raw.startsWith('StripeException') || raw.contains('FailureCode.')) {
      return 'Payment failed. Please try again.';
    }
    return raw;
  }

  void _showPaymentOutcomeSnackBar(Object error) {
    if (!mounted) return;
    if (_isPaymentCancelled(error)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment cancelled.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (kDebugMode) {
      debugPrint('Payment error: $error');
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_friendlyErrorMessage(error)),
        backgroundColor: AppTheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _payRideWithStripeWeb({
    required String clientSecret,
  }) async {
    var isCardComplete = false;
    var isSubmitting = false;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Complete Payment'),
              content: SizedBox(
                width: 520,
                child: stripe_web.buildPaymentElement(
                  clientSecret: clientSecret,
                  onChanged: (complete) {
                    setDialogState(() => isCardComplete = complete);
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: (!isCardComplete || isSubmitting)
                      ? null
                      : () async {
                          setDialogState(() => isSubmitting = true);
                          try {
                            await stripe_web
                                .confirmPaymentElement(returnUrl: Uri.base.toString())
                                .timeout(
                                  const Duration(seconds: 60),
                                  onTimeout: () => throw TimeoutException(
                                    'Stripe web payment confirmation timed out. Please try again.',
                                  ),
                                );
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(true);
                            }
                          } catch (e) {
                            _showPaymentOutcomeSnackBar(e);
                            if (dialogContext.mounted) {
                              setDialogState(() => isSubmitting = false);
                            }
                          }
                        },
                  child: Text(isSubmitting ? 'Processing...' : 'Pay'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) {
      throw const _PaymentCancelledException();
    }
  }

  Future<_PaymentIntentData> _payRideWithStripe({
    required double fare,
    required String rideId,
  }) async {
    if (ApiConfig.stripePublishableKey.isEmpty) {
      throw Exception(
        'Stripe publishable key missing. Set STRIPE_PUBLISHABLE_KEY with --dart-define.',
      );
    }

    try {
      final paymentIntentData = await _createPaymentIntentWithRetry(
        fare: fare,
        rideId: rideId,
      );
      final clientSecret = paymentIntentData.clientSecret;
      if (clientSecret.isEmpty) {
        throw Exception('Missing Stripe client secret from backend.');
      }

      if (kIsWeb) {
        await _payRideWithStripeWeb(clientSecret: clientSecret);
        return paymentIntentData;
      }

      if (!_supportsStripePayments) {
        throw Exception('Payments are not supported on this platform.');
      }

      await Stripe.instance
          .initPaymentSheet(
            paymentSheetParameters: SetupPaymentSheetParameters(
              paymentIntentClientSecret: clientSecret,
              merchantDisplayName: 'Transport App',
            ),
          )
          .timeout(
            const Duration(seconds: 25),
            onTimeout: () => throw TimeoutException(
              'Stripe payment sheet initialization timed out. Please try again.',
            ),
          );
      await Stripe.instance.presentPaymentSheet().timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException(
          'Stripe payment confirmation timed out. Please try again.',
        ),
      );
      return paymentIntentData;
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) {
        throw const _PaymentCancelledException();
      }
      rethrow;
    } on TimeoutException catch (e) {
      throw Exception(e.message ?? 'Payment timed out. Please try again.');
    }
  }

  static const List<_NavItem> _navItems = [
    _NavItem('Personal info', Icons.person_rounded),
    _NavItem('Notifications', Icons.notifications_rounded),
    _NavItem('Dashboard', Icons.dashboard_rounded),
    _NavItem('Drivers', Icons.people_rounded),
    _NavItem('Children', Icons.child_care_rounded),
    _NavItem('Payments', Icons.payment_rounded),
    _NavItem('Reviews', Icons.star_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _firestore.collection('users').doc(_currentUser.uid).snapshots(),
      builder: (c, s) {
        if (!s.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        final data = s.data!.data() ?? {};
        final parentName = data['name']?.toString() ?? '';

        final pages = [
          _personalInfo(data),
          _notificationsPage(),
          _dashboard(data),
          _driversPage(data),
          _childrenPage(data),
          _paymentsPage(data),
          _reviewsPage(data),
        ];

        return Scaffold(
          backgroundColor: AppTheme.surface,
          appBar: AppBar(
            title: Text(_navItems[_selectedIndex].label),
            actions: [
              if (_selectedIndex == 2)
                IconButton(
                  icon: const Icon(Icons.notifications_active_outlined),
                  onPressed: () {
                    setState(() => _selectedIndex = 1);
                  },
                ),
            ],
          ),
          drawer: Drawer(
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
                          backgroundColor: Colors.white24,
                          child: Text(parentName.isEmpty ? '?' : parentName[0].toUpperCase(), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: Colors.white)),
                        ),
                        const SizedBox(height: 12),
                        Text(parentName.isEmpty ? 'Parent' : parentName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white)),
                        const SizedBox(height: 4),
                        Text(data['phone']?.toString() ?? '', style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.9))),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.symmetric(vertical: AppTheme.verticalSpacing(context)),
                      children: [
                        ..._navItems.asMap().entries.map((e) {
                          final selected = _selectedIndex == e.key;
                          return _drawerNavTile(
                            icon: e.value.icon,
                            label: e.value.label,
                            selected: selected,
                            onTap: () {
                              setState(() => _selectedIndex = e.key);
                              Navigator.pop(context);
                            },
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
              SafeArea(child: pages[_selectedIndex]),
            ],
          ),
        );
      },
    );
  }

  Widget _emptyPage(String title, IconData icon) {
    return Padding(
      padding: AppTheme.contentPadding(context),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: AppTheme.textSecondary.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

class _NavItem {
  final String label;
  final IconData icon;
  const _NavItem(this.label, this.icon);
}
