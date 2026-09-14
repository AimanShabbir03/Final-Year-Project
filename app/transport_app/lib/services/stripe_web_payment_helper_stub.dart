import 'package:flutter/widgets.dart';

Widget buildPaymentElement({
  required String clientSecret,
  required ValueChanged<bool> onChanged,
}) {
  return const SizedBox.shrink();
}

Future<void> confirmPaymentElement({
  required String returnUrl,
}) async {
  throw UnsupportedError('Stripe web payment is not available on this platform.');
}
