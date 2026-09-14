import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/route_utils.dart';

/// Route bounds for deviation check (start/end of route).
class DriverRouteBounds {
  final double startLat;
  final double startLng;
  final double endLat;
  final double endLng;
  final List<(double lat, double lng)>? polylinePoints;
  const DriverRouteBounds({
    required this.startLat,
    required this.startLng,
    required this.endLat,
    required this.endLng,
    this.polylinePoints,
  });
}

class GPSController {
  static StreamSubscription<Position>? _positionStream;
  static final _firestore = FirebaseFirestore.instance;
  static DriverRouteBounds? _routeBounds;
  static List<String> _parentIds = [];
  static bool _deviationNotified = false;
  /// True only while driver has an active ride (started and not stopped). Deviation alerts only when true.
  static bool _rideInProgress = false;

  static bool get isTracking => _positionStream != null;

  /// Start GPS tracking. Optionally pass [routeBounds] and [parentIds] for background deviation alerts.
  static Future<void> startTracking(
    String driverId, {
    DriverRouteBounds? routeBounds,
    List<String>? parentIds,
  }) async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        print("Location permission denied");
        return;
      }
    }

    _routeBounds = routeBounds;
    _parentIds = parentIds ?? [];
    _deviationNotified = false;
    _rideInProgress = routeBounds != null && (parentIds?.isNotEmpty ?? false);

    if (_positionStream != null) return;

    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      ),
    ).listen((Position position) async {
      await _updateLocation(driverId, position);
    }, onError: (e) {
      print("GPS stream error: $e");
      Future.delayed(const Duration(seconds: 5), () async {
        final pos = await _getLastKnownPosition();
        if (pos != null) await _updateLocation(driverId, pos);
      });
    });
  }

  /// Update the list of parent IDs to notify when driver deviates (e.g. when more children join the ride).
  static void updateRideParents(List<String> parentIds) {
    _parentIds = List.from(parentIds);
  }

  /// Stop GPS tracking and mark driver as no longer on ride.
  static Future<void> stopTracking() async {
    _rideInProgress = false;
    if (_positionStream != null) {
      await _positionStream!.cancel();
      _positionStream = null;
    }
    _routeBounds = null;
    _parentIds = [];
    _deviationNotified = false;
    // Note: caller should pass driverId to clear status; we don't have it here.
    // So we expose clearRideStatus(driverId) and driver dashboard calls it when stopping.
  }

  /// Call when driver stops ride to set driverLocations status to 'off'.
  static Future<void> clearRideStatus(String driverId) async {
    try {
      await _firestore.collection('driverLocations').doc(driverId).set({
        'status': 'off',
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print("Failed to clear ride status: $e");
    }
  }

  static Future<void> _updateLocation(String driverId, Position position) async {
    try {
      await _firestore.collection('driverLocations').doc(driverId).set({
        'latitude': position.latitude,
        'longitude': position.longitude,
        'timestamp': FieldValue.serverTimestamp(),
        'status': _rideInProgress ? 'onRide' : 'online',
      }, SetOptions(merge: true));

      final bounds = _routeBounds;
      if (_rideInProgress &&
          bounds != null &&
          _parentIds.isNotEmpty &&
          position.latitude != 0 &&
          position.longitude != 0) {
        double distanceMeters;
        if (bounds.polylinePoints != null && bounds.polylinePoints!.isNotEmpty) {
          distanceMeters = distanceFromPointToPolyline(
            lat: position.latitude,
            lng: position.longitude,
            points: bounds.polylinePoints!,
          );
        } else {
          distanceMeters = distanceFromPointToSegment(
            lat: position.latitude,
            lng: position.longitude,
            startLat: bounds.startLat,
            startLng: bounds.startLng,
            endLat: bounds.endLat,
            endLng: bounds.endLng,
          );
        }
        if (distanceMeters > deviationThresholdMeters && !_deviationNotified) {
          _deviationNotified = true;
          for (final parentId in _parentIds) {
            try {
              await _firestore.collection('notifications').add({
                'parentId': parentId,
                'type': 'route_deviation',
                'message':
                    'Driver has deviated from the route by more than 1 km.',
                'timestamp': FieldValue.serverTimestamp(),
                'read': false,
              });
            } catch (e) {
              print("Failed to send deviation notification: $e");
            }
          }
        } else if (distanceMeters < backOnRouteThresholdMeters &&
            _deviationNotified) {
          _deviationNotified = false;
        }
      }
    } catch (e) {
      print("Failed to update location, retrying... $e");
      Future.delayed(
          const Duration(seconds: 3), () => _updateLocation(driverId, position));
    }
  }

  static Future<Position?> _getLastKnownPosition() async {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (e) {
      print("Failed to get last known position: $e");
      return null;
    }
  }
}
