import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../utils/route_utils.dart';
import '../theme/app_theme.dart';
import '../services/directions_service.dart';
import '../services/local_notifications.dart';
import '../services/web_notifications.dart';

/// Start/end coordinates for the expected route (school → destination).
class RouteBounds {
  final double startLat;
  final double startLng;
  final double endLat;
  final double endLng;
  const RouteBounds({
    required this.startLat,
    required this.startLng,
    required this.endLat,
    required this.endLng,
  });
}

Future<RouteBounds?> fetchRouteBoundsForChild(
  FirebaseFirestore firestore,
  String parentId,
  String childId,
) async {
  final parentDoc = await firestore.collection('users').doc(parentId).get();
  final parentData = parentDoc.data();
  if (parentData == null) return null;
  final children = parentData['children'] as List<dynamic>? ?? [];
  final list = children.cast<Map<String, dynamic>>().where((c) => c['id'] == childId).toList();
  if (list.isEmpty) return null;
  final child = list.first;
  final routeName = child['route']?.toString();
  if (routeName == null || routeName.isEmpty) return null;

  final routeQuery = await firestore
      .collection('routes')
      .where('name', isEqualTo: routeName)
      .limit(1)
      .get();

  if (routeQuery.docs.isEmpty) return null;
  final routeData = routeQuery.docs.first.data();
  final startLat = (routeData['schoolLatitude'] ?? routeData['schoolLat']) as num?;
  final startLng = (routeData['schoolLongitude'] ?? routeData['schoolLng']) as num?;
  final endLat = (child['parentLatitude'] ?? parentData['latitude']) as num?;
  final endLng = (child['parentLongitude'] ?? parentData['longitude']) as num?;
  if (startLat == null || startLng == null || endLat == null || endLng == null) return null;

  return RouteBounds(
    startLat: startLat.toDouble(),
    startLng: startLng.toDouble(),
    endLat: endLat.toDouble(),
    endLng: endLng.toDouble(),
  );
}

/// Fetches route bounds by route name (e.g. for driver's route).
Future<RouteBounds?> getRouteBoundsByRouteName(
  FirebaseFirestore firestore,
  String routeName,
) async {
  if (routeName.isEmpty) return null;
  final routeQuery = await firestore
      .collection('routes')
      .where('name', isEqualTo: routeName)
      .limit(1)
      .get();
  if (routeQuery.docs.isEmpty) return null;
  final routeData = routeQuery.docs.first.data();
  final startLat = (routeData['schoolLatitude'] ?? routeData['schoolLat']) as num?;
  final startLng = (routeData['schoolLongitude'] ?? routeData['schoolLng']) as num?;
  final endLat = (routeData['destinationLatitude'] ?? routeData['destinationLat']) as num?;
  final endLng = (routeData['destinationLongitude'] ?? routeData['destinationLng']) as num?;
  if (startLat == null || startLng == null || endLat == null || endLng == null) return null;
  return RouteBounds(
    startLat: startLat.toDouble(),
    startLng: startLng.toDouble(),
    endLat: endLat.toDouble(),
    endLng: endLng.toDouble(),
  );
}

class DriverLocationScreen extends StatefulWidget {
  final String childId;
  const DriverLocationScreen({Key? key, required this.childId}) : super(key: key);

  @override
  State<DriverLocationScreen> createState() => _DriverLocationScreenState();
}

class _DriverLocationScreenState extends State<DriverLocationScreen> {
  GoogleMapController? _mapController;
  LatLng? _driverPosition;
  bool _deviationNotified = false;

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: firestore
          .collection('requests')
          .where('childIds', arrayContains: widget.childId)
          .where('status', isEqualTo: 'approved')
          .snapshots(),
      builder: (context, requestSnap) {
        if (!requestSnap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final requests = requestSnap.data!.docs;
        if (requests.isEmpty) {
          return const Scaffold(
            body: Center(child: Text("No driver assigned yet")),
          );
        }
        final requestData = requests.first.data();
        final driverId = requestData['driverId'] as String?;
        final parentId = requestData['parentId'] as String?;
        if (driverId == null || driverId.isEmpty) {
          return const Scaffold(
            body: Center(child: Text("Driver ID not found")),
          );
        }
        if (parentId == null || parentId.isEmpty) {
          return const Scaffold(
            body: Center(child: Text("Parent ID not found")),
          );
        }

        return _TrackingContent(
          driverId: driverId,
          parentId: parentId,
          childId: widget.childId,
          onDeviationNotified: () {
            if (mounted) setState(() => _deviationNotified = true);
          },
          deviationNotified: _deviationNotified,
          onBackOnRoute: () {
            if (mounted) setState(() => _deviationNotified = false);
          },
        );
      },
    );
  }
}

class _TrackingContent extends StatefulWidget {
  final String driverId;
  final String parentId;
  final String childId;
  final VoidCallback onDeviationNotified;
  final bool deviationNotified;
  final VoidCallback onBackOnRoute;

  const _TrackingContent({
    required this.driverId,
    required this.parentId,
    required this.childId,
    required this.onDeviationNotified,
    required this.deviationNotified,
    required this.onBackOnRoute,
  });

  @override
  State<_TrackingContent> createState() => _TrackingContentState();
}

class _TrackingContentState extends State<_TrackingContent> {
  GoogleMapController? _mapController;
  RouteBounds? _routeBounds;
  /// Road-following path (from Directions API). If null, fall back to straight line.
  List<LatLng>? _roadRoutePoints;

  @override
  void initState() {
    super.initState();
    _loadRoute();
  }

  Future<void> _loadRoute() async {
    final bounds = await fetchRouteBoundsForChild(
      FirebaseFirestore.instance,
      widget.parentId,
      widget.childId,
    );
    if (!mounted) return;
    setState(() => _routeBounds = bounds);

    if (bounds != null) {
      final points = await getRoadRoutePoints(
        originLat: bounds.startLat,
        originLng: bounds.startLng,
        destLat: bounds.endLat,
        destLng: bounds.endLng,
      );
      if (mounted) setState(() => _roadRoutePoints = points);
    }
  }

  /// Distance from driver to the actual path (road polyline or straight segment).
  double _distanceToRoute(double lat, double lng) {
    if (_roadRoutePoints != null && _roadRoutePoints!.length >= 2) {
      final points = _roadRoutePoints!
          .map((p) => (p.latitude, p.longitude))
          .toList();
      return distanceFromPointToPolyline(lat: lat, lng: lng, points: points);
    }
    final bounds = _routeBounds;
    if (bounds != null) {
      return distanceFromPointToSegment(
        lat: lat,
        lng: lng,
        startLat: bounds.startLat,
        startLng: bounds.startLng,
        endLat: bounds.endLat,
        endLng: bounds.endLng,
      );
    }
    return double.infinity;
  }

  void _checkDeviation(double lat, double lng) {
    final distanceMeters = _distanceToRoute(lat, lng);

    if (distanceMeters > deviationThresholdMeters && !widget.deviationNotified) {
      _sendDeviationNotification();
      widget.onDeviationNotified();
    } else if (distanceMeters < backOnRouteThresholdMeters && widget.deviationNotified) {
      widget.onBackOnRoute();
    }
  }

  Future<void> _sendDeviationNotification() async {
    // Firestore notifications for route deviations are created from the driver's
    // GPS tracking (see GPSController), to avoid duplicate records. Here we only
    // show a local/web notification for the parent.
    if (kIsWeb) {
      showRideNotification('Route deviation', 'Driver has deviated from the route by more than 1 km.');
    } else {
      LocalNotificationService.showRideNotification(
        'Route deviation',
        'Driver has deviated from the route by more than 1 km.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final firestore = FirebaseFirestore.instance;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: firestore.collection('driverLocations').doc(widget.driverId).snapshots(),
      builder: (context, locationSnap) {
        if (!locationSnap.hasData || !locationSnap.data!.exists) {
          return Scaffold(
            appBar: AppBar(title: const Text("Track Driver")),
            body: const Center(child: Text("Waiting for driver location...")),
          );
        }

        final locData = locationSnap.data!.data();
        if (locData == null) {
          return Scaffold(
            appBar: AppBar(title: const Text("Track Driver")),
            body: const Center(child: Text("No location data available")),
          );
        }

        final lat = (locData['latitude'] ?? 0.0).toDouble();
        final lng = (locData['longitude'] ?? 0.0).toDouble();
        final hasValidPosition = lat != 0.0 && lng != 0.0;
        final driverStatus = (locData['status'] ?? '').toString();
        final isDriverVisible = driverStatus != 'off' && driverStatus.isNotEmpty;
        final isDriverOnRide = driverStatus == 'onRide';

        // Only check deviation when ride has started; only show driver on map when visible.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (isDriverOnRide && hasValidPosition && _routeBounds != null) {
            _checkDeviation(lat, lng);
          }
          if (hasValidPosition && isDriverVisible && _mapController != null) {
            _autoFollowDriver(LatLng(lat, lng));
          }
        });

        // Show driver marker as long as they are not 'off'.
        final LatLng? driverPosition = (hasValidPosition && isDriverVisible) ? LatLng(lat, lng) : null;
        final Marker? driverMarker = driverPosition == null
            ? null
            : Marker(
                markerId: const MarkerId('driver'),
                position: driverPosition,
                icon: kIsWeb ? BitmapDescriptor.defaultMarker : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
              );

        Set<Polyline> polylines = {};
        if (_roadRoutePoints != null && _roadRoutePoints!.length >= 2) {
          polylines.add(
            Polyline(
              polylineId: const PolylineId('route'),
              points: _roadRoutePoints!,
              color: Colors.blue,
              width: 5,
            ),
          );
        }

        Set<Marker> markers = {};
        if (driverMarker != null) markers.add(driverMarker);
        if (_routeBounds != null) {
          markers.add(
            Marker(
              markerId: const MarkerId('start'),
              position: LatLng(_routeBounds!.startLat, _routeBounds!.startLng),
              icon: kIsWeb ? BitmapDescriptor.defaultMarker : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
              infoWindow: const InfoWindow(title: 'School Location'),
            ),
          );
          markers.add(
            Marker(
              markerId: const MarkerId('end'),
              position: LatLng(_routeBounds!.endLat, _routeBounds!.endLng),
              icon: kIsWeb ? BitmapDescriptor.defaultMarker : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
              infoWindow: const InfoWindow(title: 'Parent Location'),
            ),
          );
        }

        LatLng center;
        if (driverPosition != null) {
          center = driverPosition;
        } else if (_roadRoutePoints != null && _roadRoutePoints!.isNotEmpty) {
          final mid = _roadRoutePoints!.length ~/ 2;
          center = _roadRoutePoints![mid];
        } else if (_routeBounds != null) {
          center = LatLng(
            (_routeBounds!.startLat + _routeBounds!.endLat) / 2,
            (_routeBounds!.startLng + _routeBounds!.endLng) / 2,
          );
        } else {
          center = const LatLng(34.168, 73.221);
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text("Track Driver"),
            actions: [
              if (_routeBounds != null)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.rectangle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text("Route", style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          body: Stack(
            children: [
              Positioned.fill(
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: center,
                    zoom: 14,
                  ),
                  markers: markers,
                  polylines: polylines,
                  myLocationEnabled: !kIsWeb,
                  myLocationButtonEnabled: !kIsWeb,
                  onMapCreated: (controller) {
                    _mapController = controller;
                    if (driverPosition != null && (_roadRoutePoints != null || _routeBounds != null)) {
                      _fitBoundsIncludingDriver(driverPosition!);
                    } else if (driverPosition != null) {
                      _mapController!.animateCamera(CameraUpdate.newLatLng(driverPosition!));
                    } else if (_roadRoutePoints != null && _roadRoutePoints!.isNotEmpty) {
                      _fitBoundsFromPoints();
                    } else if (_routeBounds != null) {
                      _fitBounds();
                    }
                  },
                ),
              ),
              if (!isDriverVisible || !hasValidPosition)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 24,
                  child: Center(
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        child: Text(
                          'Driver is currently offline. Tracking will begin once the driver is active.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ),
                )
              else if (!isDriverOnRide)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 24,
                  child: Center(
                    child: Material(
                      elevation: 4,
                      color: AppTheme.primary,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        child: const Text(
                          'Driver is on the way to your location',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  LatLng? _lastCameraPosition;

  void _autoFollowDriver(LatLng currentPos) {
    if (_lastCameraPosition == null) {
      _lastCameraPosition = currentPos;
      _fitBoundsIncludingDriver(currentPos);
      return;
    }

    final dist = Geolocator.distanceBetween(
      _lastCameraPosition!.latitude,
      _lastCameraPosition!.longitude,
      currentPos.latitude,
      currentPos.longitude,
    );

    if (dist > 50) {
      _lastCameraPosition = currentPos;
      _fitBoundsIncludingDriver(currentPos);
    }
  }

  void _fitBounds() {
    final bounds = _routeBounds;
    if (bounds == null || _mapController == null) return;
    final sw = LatLng(
      bounds.startLat < bounds.endLat ? bounds.startLat : bounds.endLat,
      bounds.startLng < bounds.endLng ? bounds.startLng : bounds.endLng,
    );
    final ne = LatLng(
      bounds.startLat > bounds.endLat ? bounds.startLat : bounds.endLat,
      bounds.startLng > bounds.endLng ? bounds.startLng : bounds.endLng,
    );
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: sw, northeast: ne),
      80,
    ));
  }

  void _fitBoundsIncludingDriver(LatLng driverPos) {
    if (_mapController == null) return;
    double minLat = driverPos.latitude, maxLat = driverPos.latitude;
    double minLng = driverPos.longitude, maxLng = driverPos.longitude;
    if (_roadRoutePoints != null) {
      for (final p in _roadRoutePoints!) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
    } else if (_routeBounds != null) {
      final b = _routeBounds!;
      minLat = b.startLat < b.endLat ? b.startLat : b.endLat;
      maxLat = b.startLat > b.endLat ? b.startLat : b.endLat;
      minLng = b.startLng < b.endLng ? b.startLng : b.endLng;
      maxLng = b.startLng > b.endLng ? b.startLng : b.endLng;
    }
    
    // Add driver position to min/max check again just to be safe
    if (driverPos.latitude < minLat) minLat = driverPos.latitude;
    if (driverPos.latitude > maxLat) maxLat = driverPos.latitude;
    if (driverPos.longitude < minLng) minLng = driverPos.longitude;
    if (driverPos.longitude > maxLng) maxLng = driverPos.longitude;

    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)),
      80,
    ));
  }

  void _fitBoundsFromPoints() {
    if (_roadRoutePoints == null || _roadRoutePoints!.isEmpty || _mapController == null) return;
    double minLat = _roadRoutePoints!.first.latitude, maxLat = minLat;
    double minLng = _roadRoutePoints!.first.longitude, maxLng = minLng;
    for (final p in _roadRoutePoints!) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng)),
      80,
    ));
  }
}
