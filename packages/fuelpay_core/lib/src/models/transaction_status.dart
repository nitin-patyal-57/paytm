/// Transaction lifecycle states — wire values match the backend API exactly.
enum TransactionStatus {
  created('CREATED'),
  requestSent('REQUEST_SENT'),
  requestReceived('REQUEST_RECEIVED'),
  accepted('ACCEPTED'),
  qrReady('QR_READY'),
  paymentPending('PAYMENT_PENDING'),
  paymentSuccess('PAYMENT_SUCCESS'),
  paymentFailed('PAYMENT_FAILED'),
  cancelled('CANCELLED'),
  expired('EXPIRED');

  const TransactionStatus(this.wireName);

  final String wireName;

  static TransactionStatus fromWire(String value) {
    for (final status in TransactionStatus.values) {
      if (status.wireName == value) return status;
    }
    throw ArgumentError('Unknown transaction status: $value');
  }

  static TransactionStatus? tryFromWire(String? value) {
    for (final status in TransactionStatus.values) {
      if (status.wireName == value) return status;
    }
    return null;
  }

  /// Terminal states never change again.
  bool get isTerminal =>
      this == paymentSuccess ||
      this == paymentFailed ||
      this == cancelled ||
      this == expired;

  /// Payment outcome states — only the backend demo payment service may set them.
  bool get isPaymentOutcome => this == paymentSuccess || this == paymentFailed;

  /// Short human label for chips and cards.
  String get label {
    switch (this) {
      case TransactionStatus.created:
        return 'Created';
      case TransactionStatus.requestSent:
        return 'Sent';
      case TransactionStatus.requestReceived:
        return 'Received';
      case TransactionStatus.accepted:
        return 'Accepted';
      case TransactionStatus.qrReady:
        return 'QR Ready';
      case TransactionStatus.paymentPending:
        return 'Awaiting Payment';
      case TransactionStatus.paymentSuccess:
        return 'Paid (Demo)';
      case TransactionStatus.paymentFailed:
        return 'Failed';
      case TransactionStatus.cancelled:
        return 'Cancelled';
      case TransactionStatus.expired:
        return 'Expired';
    }
  }
}
