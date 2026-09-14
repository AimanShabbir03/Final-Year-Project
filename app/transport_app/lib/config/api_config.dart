class ApiConfig {
  ApiConfig._();

  static const String STRIPE_PUBLISHABLE_KEY =
      'pk_test_51TlMHqPM88mauh5Tvwp3bKB73kb2e5LAg6Ke5hRXvKGIwnmnpfLQQKHrbHwEG2Jonq3JsHOSRp1YP1dne0FyuTXK00ybrjUneY';

  static const String baseUrl = String.fromEnvironment(
    'TRANSPORT_API_BASE_URL',
    defaultValue: 'http:// 172.18.48.133:8000',
  );

  static const String stripePublishableKey = String.fromEnvironment(
    'STRIPE_PUBLISHABLE_KEY',
    defaultValue: STRIPE_PUBLISHABLE_KEY,
  );

  static String get sentimentUrl => '$baseUrl/sentiment';
  static String get createPaymentIntentUrl => '$baseUrl/create-payment-intent';
}
