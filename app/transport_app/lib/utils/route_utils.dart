import 'package:geolocator/geolocator.dart';

/// Distance in meters beyond which the driver is considered off-route (deviation).
const double deviationThresholdMeters = 1000.0;

/// Distance in meters below which we consider driver "back on route" (reset deviation alert).
const double backOnRouteThresholdMeters = 500.0;

/// Returns the shortest distance in meters from point (lat, lng) to the line segment
/// from (startLat, startLng) to (endLat, endLng).
double distanceFromPointToSegment({
  required double lat,
  required double lng,
  required double startLat,
  required double startLng,
  required double endLat,
  required double endLng,
}) {
  // Closest point on segment to (lat, lng): project onto line, then clamp to segment.
  final dx = endLng - startLng;
  final dy = endLat - startLat;
  final lengthSq = dx * dx + dy * dy;

  if (lengthSq == 0) {
    return Geolocator.distanceBetween(lat, lng, startLat, startLng);
  }

  // Parameter t: 0 = start, 1 = end. Clamp to [0, 1] for segment.
  var t = ((lng - startLng) * dx + (lat - startLat) * dy) / lengthSq;
  if (t < 0) t = 0;
  if (t > 1) t = 1;

  final closestLng = startLng + t * dx;
  final closestLat = startLat + t * dy;

  return Geolocator.distanceBetween(lat, lng, closestLat, closestLng);
}

/// Returns the shortest distance in meters from point (lat, lng) to the polyline
/// (sequence of segments). [points] is the list of (lat, lng) along the path.
double distanceFromPointToPolyline({
  required double lat,
  required double lng,
  required List<(double lat, double lng)> points,
}) {
  if (points.isEmpty) return double.infinity;
  if (points.length == 1) {
    return Geolocator.distanceBetween(lat, lng, points.first.$1, points.first.$2);
  }
  double minDistance = double.infinity;
  for (int i = 0; i < points.length - 1; i++) {
    final start = points[i];
    final end = points[i + 1];
    final d = distanceFromPointToSegment(
      lat: lat,
      lng: lng,
      startLat: start.$1,
      startLng: start.$2,
      endLat: end.$1,
      endLng: end.$2,
    );
    if (d < minDistance) minDistance = d;
  }
  return minDistance;
}
