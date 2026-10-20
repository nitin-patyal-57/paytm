import 'fuel_type.dart';
import 'transaction_status.dart';

/// Payment execution mode. Only [PaymentMode.demo] is implemented today.
enum PaymentMode {
  demo('DEMO'),
  production('PRODUCTION');

  const PaymentMode(this.wireName);
  final String wireName;

  static PaymentMode fromWire(String? value) =>
      value?.toUpperCase() == PaymentMode.production.wireName
          ? PaymentMode.production
          : PaymentMode.demo;
}

/// Immutable transaction snapshot shared by both apps and the backend.
class FuelTransaction {
  const FuelTransaction({
    required this.transactionId,
    required this.fuelType,
    required this.amount,
    required this.currency,
    required this.status,
    required this.mode,
    this.paymentProvider,
    this.statusReason,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
  });

  final String transactionId;
  final FuelType fuelType;

  /// Integer rupees.
  final int amount;
  final String currency;
  final TransactionStatus status;
  final PaymentMode mode;
  final String? paymentProvider;
  final String? statusReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? completedAt;

  bool get isDemo => mode == PaymentMode.demo;

  /// Creates a fresh transaction in the CREATED state.
  factory FuelTransaction.create({
    required String transactionId,
    required FuelType fuelType,
    required int amount,
    PaymentMode mode = PaymentMode.demo,
    DateTime? now,
  }) {
    final ts = now ?? DateTime.now();
    return FuelTransaction(
      transactionId: transactionId,
      fuelType: fuelType,
      amount: amount,
      currency: 'INR',
      status: TransactionStatus.created,
      mode: mode,
      paymentProvider: mode == PaymentMode.demo ? 'DEMO' : null,
      createdAt: ts,
      updatedAt: ts,
    );
  }

  FuelTransaction copyWith({
    TransactionStatus? status,
    String? paymentProvider,
    String? statusReason,
    DateTime? updatedAt,
    DateTime? completedAt,
  }) {
    return FuelTransaction(
      transactionId: transactionId,
      fuelType: fuelType,
      amount: amount,
      currency: currency,
      status: status ?? this.status,
      mode: mode,
      paymentProvider: paymentProvider ?? this.paymentProvider,
      statusReason: statusReason ?? this.statusReason,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'transactionId': transactionId,
        'fuelType': fuelType.wireName,
        'amount': amount,
        'currency': currency,
        'status': status.wireName,
        'mode': mode.wireName,
        if (paymentProvider != null) 'paymentProvider': paymentProvider,
        if (statusReason != null) 'statusReason': statusReason,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
      };

  factory FuelTransaction.fromJson(Map<String, dynamic> json) {
    return FuelTransaction(
      transactionId: json['transactionId'] as String,
      fuelType: FuelType.fromWire(json['fuelType'] as String?),
      amount: (json['amount'] as num).toInt(),
      currency: json['currency'] as String? ?? 'INR',
      status: TransactionStatus.fromWire(json['status'] as String),
      mode: PaymentMode.fromWire(json['mode'] as String?),
      paymentProvider: json['paymentProvider'] as String?,
      statusReason: json['statusReason'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      completedAt: json['completedAt'] == null
          ? null
          : DateTime.parse(json['completedAt'] as String),
    );
  }

  /// Rejects mismatched identity when a peer message refers to a transaction.
  /// Prevents amount/type tampering and transaction-ID confusion.
  bool matchesIdentity(FuelTransaction other) =>
      transactionId == other.transactionId &&
      amount == other.amount &&
      fuelType == other.fuelType &&
      currency == other.currency;

  /// Minimal, non-sensitive transaction reference for the customer QR code.
  /// Contains no credentials, secrets or personal data.
  Map<String, dynamic> toQrPayload() => <String, dynamic>{
        'v': 1,
        'kind': 'fuelpay-transaction',
        'mode': mode.wireName,
        'tx': transactionId,
        'fuel': fuelType.wireName,
        'amt': amount,
        'cur': currency,
      };

  @override
  String toString() =>
      'FuelTransaction($transactionId, ${fuelType.wireName}, ₹$amount, ${status.wireName}, ${mode.wireName})';
}
