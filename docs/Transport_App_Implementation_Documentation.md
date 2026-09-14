# Transport App – Implementation Documentation

This document describes how the transport app implements: (1) adding schools and locations in the admin web, (2) sending notifications to parents when a ride starts or ends, and (3) route deviation detection and alerts.

---

## 1. Adding Schools and Locations in the Admin Web

### 1.1 Overview

Schools and route locations are managed in the **admin web** (React app under `admin/admin-web`). Schools are added via a map-based modal; routes are added by choosing a school (origin) and a destination, both with coordinates. Data is stored in **Firebase Firestore**.

### 1.2 Adding Schools

**Where it lives:**  
`admin/admin-web/src/components/AddSchoolMapModal.js` and `admin/admin-web/src/pages/AdminDashboard.js`.

**Flow:**

1. **Opening the modal**  
   In `AdminDashboard.js`, state `addSchoolMapOpen` controls the “Add School” modal. A button (e.g. in the Schools section) calls `setAddSchoolMapOpen(true)` (around line 1320). The modal is rendered with `AddSchoolMapModal` and `onSelectSchool` set to `addSchoolFromMap`.

2. **Map and search**  
   `AddSchoolMapModal`:
   - Uses **Google Maps JavaScript API**: a map is created in a `ref` with default center (e.g. Abbottabad `34.1688, 73.2215`) or the browser’s current position via `navigator.geolocation.getCurrentPosition`.
   - Draws a **10 km radius circle** (`SEARCH_RADIUS_M = 10000`) for context.
   - Has a search box. On “Search”, it uses **Google Places API (PlacesService.textSearch)** with the search query, current map center, and radius. Results are shown as a list with name, address, and coordinates.

3. **Selecting a place**  
   User picks a result. That place’s `name`, `lat`, `lng`, and optional `address` are stored in `selectedPlace`. “Add School” calls `onSelectSchool(selectedPlace)`.

4. **Saving to Firestore**  
   In `AdminDashboard.js`, `addSchoolFromMap(school)` (around lines 290–306):
   - Calls `addDoc(collection(db, "schools"), { name, latitude, longitude, ...(address && { address }) })`.
   - Shows success/error toast and closes the modal.

**Summary:** Schools are added by searching Places on the map, selecting a result, and saving one document per school in the `schools` collection with name, latitude, longitude, and optional address.

### 1.3 Adding Routes (and Destination “Locations”)

**Where it lives:**  
`admin/admin-web/src/components/AddRouteModal.js`, `admin/admin-web/src/components/PlaceSearchModal.js`, and `AdminDashboard.js`.

**Flow:**

1. **Opening the modal**  
   “Add Route” sets `addRouteModalOpen` to true (around line 1261). `AddRouteModal` receives `schools` (from Firestore `schools` collection) and `onAddRoute` = `addRouteFromModal`.

2. **Choosing school (origin)**  
   Schools that have `latitude` and `longitude` are listed in a dropdown. User selects one; that school’s `id`, `name`, `latitude`, `longitude` are kept as `selectedSchool`.

3. **Choosing destination**  
   “Select destination” opens `PlaceSearchModal`. It uses the same pattern as the school modal: Google Map, optional geolocation, **PlacesService.textSearch** with a 10 km radius. User searches, selects a place, and that place (name, lat, lng, address) is set as `destination`.

4. **Saving the route**  
   When both school and destination are set, user submits. `AddRouteModal`’s `handleSubmit` calls `onAddRoute` with:
   - `schoolName`, `schoolLatitude`, `schoolLongitude`, `schoolId`
   - `destinationName`, `destinationLatitude`, `destinationLongitude`, `destinationAddress`

   In `AdminDashboard.js`, `addRouteFromModal(routeData)` (around lines 252–284):
   - Builds `name` as `"${schoolName} → ${destinationName}"`.
   - Calls `addDoc(collection(db, "routes"), { name, schoolName, schoolLatitude, schoolLongitude, schoolId?, destinationName, destinationLatitude, destinationLongitude, destinationAddress? })`.

**Summary:** Routes are “school → destination” with coordinates and optional address. Destination “locations” are not a separate collection; they are stored as fields on each route document.

### 1.4 Data Model (Firestore)

- **`schools`**  
  - `name`, `latitude`, `longitude`, optional `address`.

- **`routes`**  
  - `name` (e.g. `"School A → Area X"`),  
  - `schoolName`, `schoolLatitude`, `schoolLongitude`, optional `schoolId`,  
  - `destinationName`, `destinationLatitude`, `destinationLongitude`, optional `destinationAddress`.

Admin listens to `schools` and `routes` with `onSnapshot` so the UI updates in real time.

---

## 2. Sending Notifications to the Parent (Ride Start / Ride End)

### 2.1 Overview

When the **driver** marks a child as “ride started” or “ride ended” in the Flutter app, a **notification document** is written to Firestore. The **parent** app listens to that collection and shows a local (mobile) or web notification.

### 2.2 Driver Side: Creating the Notification

**Where it lives:**  
`app/transport_app/lib/screens/driver_dashboard.dart`.

**Flow:**

1. **Assigned children**  
   The driver sees a list of assigned children (from Firestore `requests` where `driverId == currentUser.uid` and `status == 'approved'`). For each child, the driver has a “Start ride” / “Stop ride” button.

2. **Button action**  
   On tap (around lines 482–513):
   - Toggle state: `newRideOn = !isChildOnRide` (start vs stop).
   - Call `_sendRideNotificationToParent(type: newRideOn ? 'ride_started' : 'ride_ended', parentId, childName)`.
   - Update local set `_childrenOnRide` (add or remove child).
   - If any child is on ride: get parent IDs, route name, route bounds, then start or update GPS tracking and set `rideStatus` in Firestore. If no child on ride: stop tracking and clear ride status.

3. **Writing the notification**  
   `_sendRideNotificationToParent` (around lines 356–375):
   - Reads driver name from `users/<driverId>`.
   - Builds `message`: `"Ride started for <childName>."` or `"Ride finished for <childName>."`.
   - Calls `_firestore.collection('notifications').add({ parentId, type: 'ride_started'|'ride_ended', driverId, driverName, childName, message, timestamp, read: false })`.

**Summary:** Each “Start ride” / “Stop ride” creates one document in the `notifications` collection with `parentId`, `type`, and message.

### 2.3 Parent Side: Receiving and Showing the Notification

**Where it lives:**  
`app/transport_app/lib/screens/parent_dashboard.dart`, `lib/services/local_notifications.dart`, `lib/services/web_notifications_web.dart` (and stub for non-web).

**Flow:**

1. **Listener setup**  
   In `ParentDashboard.initState`, `_listenForRideNotifications()` is called. It subscribes to:
   - `_firestore.collection('notifications').where('parentId', isEqualTo: _currentUser.uid).snapshots()`.

2. **On new notification**  
   For each `docChange` with `type == added`:
   - Skip if the doc ID was already in `_shownNotificationIds` (avoid duplicates).
   - Add doc ID to `_shownNotificationIds`.
   - Read `type`, `message`, `childName`.
   - Set title: `'Route deviation'` if `type == 'route_deviation'`, else `'Ride started'` or `'Ride finished'` for `ride_started` / `ride_ended`.
   - Body is `message` (or child-aware message).

3. **Showing the notification**  
   - **Web:** `showRideNotification(title, body)` in `web_notifications_web.dart` uses `html.Notification(title, body)` (after permission is requested on dashboard load).
   - **Mobile:** `LocalNotificationService.showRideNotification(title, body)` in `local_notifications.dart` uses `FlutterLocalNotificationsPlugin` with channel `rides_channel`.

**Summary:** Parent gets ride start/end (and deviation) by real-time Firestore listener plus platform-specific notification API.

---

## 3. Route Deviation

### 3.1 Overview

**Route deviation** means the driver is too far from the expected route. When that happens, the app writes a `route_deviation` notification for the parent. Deviation is implemented in two places: **background/ongoing tracking** in `GPSController` (driver app) and **live map** in `DriverLocationScreen` (parent app). Both use the same thresholds and similar logic.

### 3.2 Thresholds and Geometry

**Where it lives:**  
`app/transport_app/lib/utils/route_utils.dart`.

- **`deviationThresholdMeters = 1000`** – if the driver’s distance to the route is ≥ 1 km, it counts as “deviated” and a notification is sent (once per “deviation episode”).
- **`backOnRouteThresholdMeters = 500`** – when the driver comes back within 500 m of the route, the state resets so that a future deviation can trigger again.

**Distance calculations:**

- **Segment:** `distanceFromPointToSegment(lat, lng, startLat, startLng, endLat, endLng)`  
  Shortest distance from the driver point to the line segment (school → destination). Implemented by projecting the point onto the line and clamping to the segment, then using `Geolocator.distanceBetween`.

- **Polyline:** `distanceFromPointToPolyline(lat, lng, points)`  
  Shortest distance from the driver to any segment of the polyline (used when a road route is available).

**Summary:** Deviation = distance to route ≥ 1000 m; “back on route” = distance < 500 m.

### 3.3 Route Bounds and Road Route

**Where it lives:**  
`app/transport_app/lib/screens/driver_location_screen.dart`, `app/transport_app/lib/services/directions_service.dart`.

- **Route bounds** come from Firestore. For a given route name, `getRouteBoundsByRouteName` queries `routes` where `name == routeName` and reads `schoolLatitude/Longitude` and `destinationLatitude/Longitude` (with fallback field names). These define the straight-line segment.

- **Road route (optional):** `getRoadRoutePoints(originLat, originLng, destLat, destLng)` in `directions_service.dart` calls the **Google Directions API** (driving), decodes the overview polyline, and returns a list of `LatLng`. This is used on the parent’s map and for more accurate deviation when available.

**Summary:** Deviation can be computed against a straight segment (school→destination) or against the driving polyline when the Directions API is used.

### 3.4 Driver App: Background Deviation (GPSController)

**Where it lives:**  
`app/transport_app/lib/screens/gps_controller.dart`.

**Flow:**

1. **When tracking starts with a ride**  
   When the driver has at least one child “on ride”, the dashboard calls `GPSController.startTracking(uid, routeBounds: driverBounds, parentIds: parentIds)`. `driverBounds` come from `getRouteBoundsByRouteName(_firestore, routeName)` (driver’s assigned route). `GPSController` stores `_routeBounds`, `_parentIds`, sets `_rideInProgress = true`, and resets `_deviationNotified`.

2. **On each location update**  
   `Geolocator.getPositionStream` (distanceFilter: 5 m) triggers `_updateLocation(driverId, position)`:
   - Writes position to `driverLocations/<driverId>` (latitude, longitude, timestamp, status: `'onRide'`).
   - If `_rideInProgress`, bounds exist, and parent list is non-empty:
     - Computes `distanceMeters = distanceFromPointToSegment(position, bounds)`.
     - If `distanceMeters >= deviationThresholdMeters` and not yet `_deviationNotified`: set `_deviationNotified = true` and for each `parentId` in `_parentIds` add a document to `notifications`: `{ parentId, type: 'route_deviation', message: 'Driver has deviated from the route by more than 1 km.', timestamp, read: false }`.
     - If `distanceMeters < backOnRouteThresholdMeters` and `_deviationNotified`: set `_deviationNotified = false`.

**Summary:** In the driver app, deviation is checked on the GPS stream using the straight segment only, and all parents of children on that ride get one Firestore notification per deviation event; the parent app then shows it like ride start/end.

### 3.5 Parent App: Deviation on the Map (DriverLocationScreen)

**Where it lives:**  
`app/transport_app/lib/screens/driver_location_screen.dart`.

**Flow:**

1. **Loading route**  
   `_TrackingContent` gets route bounds via `fetchRouteBoundsForChild(firestore, parentId, childId)` (from assigned request/route). If bounds exist, it also loads `_roadRoutePoints` via `getRoadRoutePoints` (Directions API).

2. **Distance to route**  
   `_distanceToRoute(lat, lng)`:
   - If `_roadRoutePoints` is available, uses `distanceFromPointToPolyline(lat, lng, points)`.
   - Else uses `distanceFromPointToSegment` with route bounds.

3. **When driver location updates**  
   Parent listens to `driverLocations/<driverId>` in a `StreamBuilder`. In `addPostFrameCallback`, when the driver is on ride and has valid position, it calls `_checkDeviation(lat, lng)`:
   - If `distance >= deviationThresholdMeters` and not yet `deviationNotified`: call `_sendDeviationNotification()` and `onDeviationNotified()`.
   - If `distance < backOnRouteThresholdMeters` and already `deviationNotified`: call `onBackOnRoute()`.

4. **Sending the notification**  
   `_sendDeviationNotification()` adds to Firestore `notifications` (same structure as in GPSController) and then shows the notification locally (web: `showRideNotification`; mobile: `LocalNotificationService.showRideNotification`).

**Summary:** On the parent’s tracking screen, deviation is checked using the road polyline when available, and both a Firestore document and an immediate local notification are sent. The same `notifications` collection and listener in `ParentDashboard` also show this as “Route deviation” for the parent.

---

## 4. End-to-End Summary

| Feature | Where | How |
|--------|--------|-----|
| **Add schools** | Admin web | AddSchoolMapModal: Google Maps + Places text search → pick place → `addDoc(schools, { name, latitude, longitude, address? })`. |
| **Add routes/locations** | Admin web | AddRouteModal: select school from list, pick destination via PlaceSearchModal (Places API) → `addDoc(routes, { name, school*, destination* })`. |
| **Ride start/end notification** | Driver app → Parent | Driver taps Start/Stop ride → `notifications.add({ parentId, type: ride_started/ride_ended, ... })` → Parent’s snapshot listener → Web Notification or FlutterLocalNotificationsPlugin. |
| **Route deviation** | Driver + Parent apps | Driver: GPSController checks distance to segment on position stream, writes `notifications` with `type: 'route_deviation'`. Parent: DriverLocationScreen checks distance to polyline/segment on map, same. Parent dashboard listener shows all three types (ride_started, ride_ended, route_deviation). |

---

## 5. File Reference

| Component | Path |
|-----------|------|
| Admin dashboard (schools, routes, Firestore) | `admin/admin-web/src/pages/AdminDashboard.js` |
| Add school modal (map + Places) | `admin/admin-web/src/components/AddSchoolMapModal.js` |
| Add route modal | `admin/admin-web/src/components/AddRouteModal.js` |
| Place search modal (destination) | `admin/admin-web/src/components/PlaceSearchModal.js` |
| Driver dashboard (start/stop ride, notifications) | `app/transport_app/lib/screens/driver_dashboard.dart` |
| Parent dashboard (notification listener) | `app/transport_app/lib/screens/parent_dashboard.dart` |
| GPS tracking & deviation (driver) | `app/transport_app/lib/screens/gps_controller.dart` |
| Driver location / map & deviation (parent) | `app/transport_app/lib/screens/driver_location_screen.dart` |
| Route geometry (distance to segment/polyline) | `app/transport_app/lib/utils/route_utils.dart` |
| Directions API (road polyline) | `app/transport_app/lib/services/directions_service.dart` |
| Local notifications (Android) | `app/transport_app/lib/services/local_notifications.dart` |
| Web notifications | `app/transport_app/lib/services/web_notifications_web.dart` |
