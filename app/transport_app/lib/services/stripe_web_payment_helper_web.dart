import 'package:flutter/widgets.dart';
import 'package:flutter_stripe_web/flutter_stripe_web.dart';

Widget buildPaymentElement({
  required String clientSecret,
  required ValueChanged<bool> onChanged,
}) {
  return PaymentElement(
    clientSecret: clientSecret,
    onCardChanged: (details) => onChanged(details?.complete ?? false),
  );
}

Future<void> confirmPaymentElement({
  required String returnUrl,
}) async {
  await WebStripe.instance.confirmPaymentElement(
    ConfirmPaymentElementOptions(
      confirmParams: ConfirmPaymentParams(return_url: returnUrl),
      redirect: PaymentConfirmationRedirect.ifRequired,
    ),
  );
}
