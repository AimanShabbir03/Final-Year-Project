/// Google Maps API key for Directions API (road-following routes).
/// 1) Set via: flutter run --dart-define=GOOGLE_MAPS_API_KEY=your_key
/// 2) Or set [kGoogleMapsApiKeyFallback] below for development (do not commit real keys).
/// Ensure "Directions API" is enabled in Google Cloud Console for this key.
const String kGoogleMapsApiKeyFallback = 'AIzaSyBvU-ElXDdS-uvpZiU3hl_CnWvNxHyeBzE';

String get googleMapsApiKey {
  const fromEnv = String.fromEnvironment('GOOGLE_MAPS_API_KEY', defaultValue: '');
  if (fromEnv.isNotEmpty) return fromEnv;
  return kGoogleMapsApiKeyFallback;
}
