import 'dart:html' as html;

/// Request browser notification permission without showing a notification.
Future<void> requestNotificationPermission() async {
  if (!html.Notification.supported) return;

  final permission = html.Notification.permission;
  if (permission == 'default') {
    await html.Notification.requestPermission();
  }
}

/// Show a ride notification only if permission is already granted.
void showRideNotification(String title, String body) {
  if (!html.Notification.supported) return;

  final permission = html.Notification.permission;
  if (permission != 'granted') return;

  html.Notification(title, body: body);
}

