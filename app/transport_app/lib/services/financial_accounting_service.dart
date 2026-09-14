import 'package:cloud_firestore/cloud_firestore.dart';

class PaymentLedgerResult {
  const PaymentLedgerResult({
    required this.transactionId,
    required this.parentAccountId,
    required this.driverAccountId,
    required this.adminAccountId,
    required this.driverShare,
    required this.adminCommission,
  });

  final String transactionId;
  final String parentAccountId;
  final String driverAccountId;
  final String adminAccountId;
  final double driverShare;
  final double adminCommission;
}

class FinancialAccountingService {
  FinancialAccountingService._();

  static String buildAccountId({
    required String role,
    required String userId,
  }) {
    return '${role}_$userId';
  }

  static double _roundToTwo(double value) {
    return double.parse(value.toStringAsFixed(2));
  }

  static Future<Map<String, double>> _resolveCommissionPercents(
    FirebaseFirestore firestore,
  ) async {
    try {
      final settingsSnap = await firestore
          .collection('system_settings')
          .doc('commission_settings')
          .get();
      final data = settingsSnap.data() ?? const <String, dynamic>{};
      final driverPercent =
          (data['driverSharePercent'] as num?)?.toDouble() ?? 70.0;
      final platformPercent =
          (data['platformSharePercent'] as num?)?.toDouble() ?? 30.0;
      final total = driverPercent + platformPercent;
      if (driverPercent < 0 ||
          driverPercent > 100 ||
          platformPercent < 0 ||
          platformPercent > 100 ||
          (total - 100).abs() > 0.001) {
        return const {
          'driverSharePercent': 70.0,
          'platformSharePercent': 30.0,
        };
      }
      return {
        'driverSharePercent': driverPercent,
        'platformSharePercent': platformPercent,
      };
    } catch (_) {
      return const {
        'driverSharePercent': 70.0,
        'platformSharePercent': 30.0,
      };
    }
  }

  static Future<PaymentLedgerResult> recordSuccessfulPayment({
    required FirebaseFirestore firestore,
    required String paymentId,
    required String stripePaymentIntentId,
    required String rideId,
    required String parentId,
    required String driverId,
    required double amount,
    required String paymentMethod,
    required String paymentStatus,
  }) async {
    final percentages = await _resolveCommissionPercents(firestore);
    final driverSharePercent = percentages['driverSharePercent'] ?? 70.0;
    final platformSharePercent = percentages['platformSharePercent'] ?? 30.0;
    final driverShare = _roundToTwo(amount * (driverSharePercent / 100));
    final adminCommission = _roundToTwo(amount * (platformSharePercent / 100));

    final usersSnap = await firestore
        .collection('users')
        .where('role', whereIn: ['admin', 'superadmin'])
        .get();

    final adminUsers = usersSnap.docs
        .where((doc) =>
            (doc.data()['role'] ?? '').toString().toLowerCase().trim() ==
            'admin')
        .toList();
    final superAdminUsers = usersSnap.docs
        .where((doc) =>
            (doc.data()['role'] ?? '').toString().toLowerCase().trim() ==
            'superadmin')
        .toList();

    final parentAccountId = buildAccountId(role: 'parent', userId: parentId);
    final driverAccountId = buildAccountId(role: 'driver', userId: driverId);

    String adminAccountId;
    if (superAdminUsers.isNotEmpty) {
      adminAccountId = buildAccountId(
        role: 'superadmin',
        userId: superAdminUsers.first.id,
      );
    } else if (adminUsers.isNotEmpty) {
      adminAccountId = buildAccountId(
        role: 'admin',
        userId: adminUsers.first.id,
      );
    } else {
      adminAccountId = buildAccountId(role: 'superadmin', userId: 'platform');
    }

    final batch = firestore.batch();

    final parentAccountRef =
        firestore.collection('financial_accounts').doc(parentAccountId);
    final driverAccountRef =
        firestore.collection('financial_accounts').doc(driverAccountId);
    final existingLedgerSnap = await firestore
        .collection('earnings_ledger')
        .where('rideId', isEqualTo: rideId)
        .limit(1)
        .get();

    batch.set(
      parentAccountRef,
      {
        'accountId': parentAccountId,
        'userId': parentId,
        'role': 'parent',
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'totalPaid': FieldValue.increment(_roundToTwo(amount)),
        'totalTransactions': FieldValue.increment(1),
      },
      SetOptions(merge: true),
    );

    batch.set(
      driverAccountRef,
      {
        'accountId': driverAccountId,
        'userId': driverId,
        'role': 'driver',
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'totalEarnings': FieldValue.increment(driverShare),
        'totalPaidRides': FieldValue.increment(1),
        'totalTransactions': FieldValue.increment(1),
      },
      SetOptions(merge: true),
    );

    for (final adminDoc in adminUsers) {
      final accountId = buildAccountId(role: 'admin', userId: adminDoc.id);
      batch.set(
        firestore.collection('financial_accounts').doc(accountId),
        {
          'accountId': accountId,
          'userId': adminDoc.id,
          'role': 'admin',
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'totalCommission': FieldValue.increment(adminCommission),
          'totalTransactions': FieldValue.increment(1),
        },
        SetOptions(merge: true),
      );
    }

    for (final superAdminDoc in superAdminUsers) {
      final accountId =
          buildAccountId(role: 'superadmin', userId: superAdminDoc.id);
      batch.set(
        firestore.collection('financial_accounts').doc(accountId),
        {
          'accountId': accountId,
          'userId': superAdminDoc.id,
          'role': 'superadmin',
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'totalCommission': FieldValue.increment(adminCommission),
          'totalTransactions': FieldValue.increment(1),
        },
        SetOptions(merge: true),
      );
    }

    if (adminUsers.isEmpty && superAdminUsers.isEmpty) {
      batch.set(
        firestore.collection('financial_accounts').doc(adminAccountId),
        {
          'accountId': adminAccountId,
          'userId': 'platform',
          'role': 'superadmin',
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'totalCommission': FieldValue.increment(adminCommission),
          'totalTransactions': FieldValue.increment(1),
        },
        SetOptions(merge: true),
      );
    }

    final transactionRef = firestore.collection('transactions').doc(paymentId);
    batch.set(
      transactionRef,
      {
        'type': 'ride_payment',
        'transactionId': paymentId,
        'stripePaymentIntentId': stripePaymentIntentId,
        'parentAccountId': parentAccountId,
        'driverAccountId': driverAccountId,
        'adminAccountId': adminAccountId,
        'rideId': rideId,
        'parentId': parentId,
        'driverId': driverId,
        'amount': _roundToTwo(amount),
        'driverShare': driverShare,
        'adminCommission': adminCommission,
        'driverSharePercent': driverSharePercent,
        'platformSharePercent': platformSharePercent,
        'paymentStatus': paymentStatus,
        'paymentMethod': paymentMethod,
        'dateTime': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    if (existingLedgerSnap.docs.isNotEmpty) {
      batch.set(
        existingLedgerSnap.docs.first.reference,
        {
          'paymentId': paymentId,
          'driverId': driverId,
          'driverAmount': driverShare,
          'superAdminAmount': adminCommission,
          'split': '${driverSharePercent.toStringAsFixed(0)}_${platformSharePercent.toStringAsFixed(0)}',
          'transactionId': paymentId,
          'stripePaymentIntentId': stripePaymentIntentId,
          'paymentDateTime': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } else {
      batch.set(
        firestore.collection('earnings_ledger').doc(paymentId),
        {
          'rideId': rideId,
          'paymentId': paymentId,
          'driverId': driverId,
          'driverAmount': driverShare,
          'superAdminAmount': adminCommission,
          'split': '${driverSharePercent.toStringAsFixed(0)}_${platformSharePercent.toStringAsFixed(0)}',
          'transactionId': paymentId,
          'stripePaymentIntentId': stripePaymentIntentId,
          'paymentDateTime': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();

    return PaymentLedgerResult(
      transactionId: paymentId,
      parentAccountId: parentAccountId,
      driverAccountId: driverAccountId,
      adminAccountId: adminAccountId,
      driverShare: driverShare,
      adminCommission: adminCommission,
    );
  }
}
