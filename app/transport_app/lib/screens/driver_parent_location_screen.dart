import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../theme/app_theme.dart';
import '../services/directions_service.dart';

class DriverParentLocationScreen extends StatefulWidget {
  final String childName;
  final double parentLatitude;
  final double parentLongitude;
  final double schoolLatitude;
  final double schoolLongitude;

  const DriverParentLocationScreen({
    super.key,
    required this.childName,
    required this.parentLatitude,
    required this.parentLongitude,
    required this.schoolLatitude,
    required this.schoolLongitude,
  });

  @override
  State<DriverParentLocationScreen> createState() =>
      _DriverParentLocationScreenState();
}

class _DriverParentLocationScreenState extends State<DriverParentLocationScreen> {
  GoogleMapController? _mapController;
  LatLng? _driverPosition;
  Timer? _refreshTimer;
  StreamSubscription<Position>? _positionSub;
  List<LatLng>? _routePoints;

  LatLng get _parentPosition =>
      LatLng(widget.parentLatitude, widget.parentLongitude);
  LatLng get _schoolPosition =>
      LatLng(widget.schoolLatitude, widget.schoolLongitude);

  @override
  void initState() {
    super.initState();
    _startDriverPositionUpdates();
    // Refresh the road route periodically
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _loadRoadRoute();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _positionSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _startDriverPositionUpdates() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    // Get an initial position quickly
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (mounted) {
        setState(() {
          _driverPosition = LatLng(pos.latitude, pos.longitude);
        });
        _loadRoadRoute();
        _fitBounds();
      }
    } catch (e) {
      // Ignore initial fetch errors
    }

    // Subscribe to stream for continuous tracking
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      if (!mounted) return;
      setState(() {
        _driverPosition = LatLng(position.latitude, position.longitude);
      });
      _fitBounds();
    });
  }

  Future<void> _loadRoadRoute() async {
    final driverPosition = _driverPosition;
    if (driverPosition == null) return;
    final points = await getRoadRoutePoints(
      originLat: driverPosition.latitude,
      originLng: driverPosition.longitude,
      destLat: _parentPosition.latitude,
      destLng: _parentPosition.longitude,
    );
    if (!mounted) return;
    setState(() {
      _routePoints = points;
    });
    // Optional: avoid re-fitting bounds constantly if user is interacting with map
  }

  void _fitBounds() {
    if (_mapController == null || _driverPosition == null) return;
    final points = <LatLng>[
      _driverPosition!,
      _parentPosition,
      _schoolPosition,
      ...?_routePoints,
    ];
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final point in points.skip(1)) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        80,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('parent'),
        position: _parentPosition,
        infoWindow: InfoWindow(title: '${widget.childName} parent'),
        icon: kIsWeb ? BitmapDescriptor.defaultMarker : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
      Marker(
        markerId: const MarkerId('school'),
        position: _schoolPosition,
        infoWindow: const InfoWindow(title: 'School'),
        icon: kIsWeb ? BitmapDescriptor.defaultMarker : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
      if (_driverPosition != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: _driverPosition!,
          infoWindow: const InfoWindow(title: 'Your live location'),
          icon: kIsWeb ? BitmapDescriptor.defaultMarker : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        ),
    };

    final polylines = <Polyline>{
      if (_driverPosition != null && _routePoints != null && _routePoints!.isNotEmpty)
        Polyline(
          polylineId: const PolylineId('driver_to_parent'),
          points: _routePoints!,
          color: AppTheme.primary,
          width: 5,
        ),
    };

    final initialCenter = _driverPosition ?? _parentPosition;

    return Scaffold(
      appBar: AppBar(title: const Text('Parent & Driver Live Map')),
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: initialCenter, zoom: 14),
              markers: markers,
              polylines: polylines,
              myLocationEnabled: !kIsWeb,
              myLocationButtonEnabled: !kIsWeb,
              onMapCreated: (controller) {
                _mapController = controller;
                _fitBounds();
              },
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Text(
                'Driver location updates in real-time.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
