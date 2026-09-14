import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/directions_service.dart';

class DriverRideMapScreen extends StatefulWidget {
  final String childName;
  final String rideModeLabel;
  final LatLng parentLocation;
  final LatLng schoolLocation;
  final bool isMorningRide;
  final bool liveTrackingMode;

  const DriverRideMapScreen({
    super.key,
    required this.childName,
    required this.rideModeLabel,
    required this.parentLocation,
    required this.schoolLocation,
    required this.isMorningRide,
    required this.liveTrackingMode,
  });

  @override
  State<DriverRideMapScreen> createState() => _DriverRideMapScreenState();
}

class _DriverRideMapScreenState extends State<DriverRideMapScreen> {
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionSub;
  LatLng? _driverPosition;
  List<LatLng>? _roadRoutePoints;

  @override
  void initState() {
    super.initState();
    _loadRoadRoute();
    _startDriverPositionUpdates();
  }
  
  Future<void> _loadRoadRoute() async {
    try {
      final start = widget.isMorningRide ? widget.parentLocation : widget.schoolLocation;
      final end = widget.isMorningRide ? widget.schoolLocation : widget.parentLocation;
      final points = await getRoadRoutePoints(
        originLat: start.latitude,
        originLng: start.longitude,
        destLat: end.latitude,
        destLng: end.longitude,
      );
      if (mounted && points != null) {
        setState(() => _roadRoutePoints = points);
      }
    } catch (e) {
      print("Error loading road route: $e");
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _startDriverPositionUpdates() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
    }

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((position) {
      if (!mounted) return;
      setState(() {
        _driverPosition = LatLng(position.latitude, position.longitude);
      });
      _fitMapBounds();
    });
  }

  void _fitMapBounds() {
    if (_mapController == null) return;
    final points = <LatLng>[
      widget.parentLocation,
      widget.schoolLocation,
      if (_driverPosition != null) _driverPosition!,
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
        90,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('parent'),
        position: widget.parentLocation,
        icon: kIsWeb ? BitmapDescriptor.defaultMarker : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: "Parent's Location"),
      ),
      Marker(
        markerId: const MarkerId('school'),
        position: widget.schoolLocation,
        icon: kIsWeb ? BitmapDescriptor.defaultMarker : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'School'),
      ),
      if (_driverPosition != null)
        Marker(
          markerId: const MarkerId('driver'),
          position: _driverPosition!,
          icon: kIsWeb ? BitmapDescriptor.defaultMarker : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Your Current Location'),
        ),
    };

    final polylines = <Polyline>{
      if (_roadRoutePoints != null && _roadRoutePoints!.isNotEmpty)
        Polyline(
          polylineId: const PolylineId('route'),
          points: _roadRoutePoints!,
          color: Colors.blue,
          width: 5,
        ),
    };

    final initialCenter = LatLng(
      (widget.parentLocation.latitude + widget.schoolLocation.latitude) / 2,
      (widget.parentLocation.longitude + widget.schoolLocation.longitude) / 2,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.rideModeLabel} • ${widget.childName}'),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: initialCenter, zoom: 13),
              markers: markers,
              polylines: polylines,
              myLocationEnabled: !kIsWeb,
              myLocationButtonEnabled: !kIsWeb,
              onMapCreated: (controller) {
                _mapController = controller;
                _fitMapBounds();
              },
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 20,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  widget.liveTrackingMode
                      ? 'Live tracking mode is ON. You must be within 100m of the destination to stop the ride.'
                      : 'Pickup and dropoff locations are marked. Tap Start Ride when you are ready to begin.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
