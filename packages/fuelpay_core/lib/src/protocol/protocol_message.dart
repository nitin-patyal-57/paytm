import 'dart:convert';
import 'dart:math';

import '../models/fuel_transaction.dart';
import '../models/fuel_type.dart';
import '../models/transaction_status.dart';
import '../validation/amount_validator.dart';
import '../validation/transaction_id.dart';
import 'ble_constants.dart';

/// Wire message types exchanged over the FuelPay BLE characteristics.
enum MessageType {
  hello('HELLO'),
  helloAck('HELLO_ACK'),
  paymentRequest('PAYMENT_REQUEST'),
  requestReceived('REQUEST_RECEIVED'),
  requestDecision('REQUEST_DECISION'),
  paymentStatus('PAYMENT_STATUS'),
  cancelTransaction('CANCEL_TRANSACTION'),
  error('ERROR');

  const MessageType(this.wireName);
  final String wireName;

  static MessageType? tryFromWire(String? value) {
    for (final t in MessageType.values) {
      if (t.wireName == value) return t;
    }
    return null;
  }
}

/// Raised when an incoming Bluetooth payload cannot be trusted or parsed.
class ProtocolException implements Exception {
  ProtocolException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => 'ProtocolException($code): $message';
}

final Random _idRandom = Random.secure();

String _newMessageId() {
  final bytes = List<int>.generate(8, (_) => _idRandom.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Base class for every FuelPay protocol message.
///
/// Decode is strict: unknown types, unsupported protocol versions and
/// malformed fields all raise [ProtocolException] — receivers must never
/// trust a message merely because it arrived over Bluetooth.
abstract class ProtocolMessage {
  ProtocolMessage({String? messageId})
      : messageId = messageId ?? _newMessageId();

  final String messageId;

  /// Protocol version emitted by this build (all messages carry it on the wire).
  int get protocolVersion => FuelPayBle.protocolVersion;

  MessageType get type;
  String? get transactionId => null;

  Map<String, dynamic> toJson();

  String encode() => jsonEncode(toJson());
  List<int> encodeBytes() => utf8.encode(encode());

  /// Identity used for duplicate detection: the message content without the
  /// per-send messageId, so byte-identical retries are recognised as duplicates.
  String get dedupKey {
    final map = Map<String, dynamic>.from(toJson())..remove('messageId');
    return jsonEncode(map);
  }

  // ---------------------------------------------------------------- decode

  static ProtocolMessage decodeString(String source) {
    dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw ProtocolException('INVALID_JSON', 'Payload is not valid JSON');
    }
    if (decoded is! Map) {
      throw ProtocolException('INVALID_SHAPE', 'Payload must be a JSON object');
    }
    final map = Map<String, dynamic>.from(decoded);

    final version = map['protocolVersion'];
    if (version is! int) {
      throw ProtocolException(
          'UNSUPPORTED_VERSION', 'protocolVersion must be an integer');
    }
    if (!FuelPayBle.supportedProtocolVersions.contains(version)) {
      throw ProtocolException(
        'UNSUPPORTED_VERSION',
        'Protocol version $version is not supported by this build '
            '(supported: ${FuelPayBle.supportedProtocolVersions.join(', ')})',
      );
    }

    final type = MessageType.tryFromWire(map['type'] as String?);
    if (type == null) {
      throw ProtocolException(
          'UNKNOWN_TYPE', 'Unknown message type: ${map['type']}');
    }

    final messageId = map['messageId'];
    if (messageId != null && (messageId is! String || messageId.length > 64)) {
      throw ProtocolException('VALIDATION', 'messageId must be a short string');
    }

    switch (type) {
      case MessageType.hello:
        final role = map['role'];
        if (role is! String || role.isEmpty) {
          throw ProtocolException('VALIDATION', 'HELLO requires a role');
        }
        return HelloMessage(messageId: messageId as String?, role: role);
      case MessageType.helloAck:
        final pumpName = map['pumpName'];
        if (pumpName is! String || pumpName.isEmpty) {
          throw ProtocolException(
              'VALIDATION', 'HELLO_ACK requires a pumpName');
        }
        return HelloAckMessage(
          messageId: messageId as String?,
          pumpName: pumpName,
          mode: PaymentMode.fromWire(map['mode'] as String?),
        );
      case MessageType.paymentRequest:
        return PaymentRequestMessage._validate(map, messageId as String?);
      case MessageType.requestReceived:
        final tx = _requireTxId(map);
        final status = map['status'];
        if (status is! String || status.toUpperCase() != 'PENDING') {
          throw ProtocolException(
              'VALIDATION', 'REQUEST_RECEIVED.status must be PENDING');
        }
        return RequestReceivedMessage(
          messageId: messageId as String?,
          transactionId: tx,
          mode: PaymentMode.fromWire(map['mode'] as String?),
        );
      case MessageType.requestDecision:
        final tx = _requireTxId(map);
        final rawDecision = map['decision'];
        if (rawDecision is! String) {
          throw ProtocolException(
              'VALIDATION', 'decision must be ACCEPTED or REJECTED');
        }
        final decision = rawDecision.toUpperCase();
        if (decision != RequestDecisionMessage.accepted &&
            decision != RequestDecisionMessage.rejected) {
          throw ProtocolException(
              'VALIDATION', 'decision must be ACCEPTED or REJECTED');
        }
        final reason = map['reason'];
        if (reason != null && reason is! String) {
          throw ProtocolException('VALIDATION', 'reason must be a string');
        }
        return RequestDecisionMessage(
          messageId: messageId as String?,
          transactionId: tx,
          decision: decision,
          reason: reason as String?,
          mode: PaymentMode.fromWire(map['mode'] as String?),
        );
      case MessageType.paymentStatus:
        final tx = _requireTxId(map);
        final status = _parsePayableStatus(map['status']);
        final timestampRaw = map['timestamp'];
        DateTime? timestamp;
        if (timestampRaw != null) {
          if (timestampRaw is! String) {
            throw ProtocolException(
                'VALIDATION', 'timestamp must be an ISO-8601 string');
          }
          timestamp = DateTime.tryParse(timestampRaw);
          if (timestamp == null) {
            throw ProtocolException('VALIDATION', 'timestamp must be ISO-8601');
          }
        }
        return PaymentStatusMessage(
          messageId: messageId as String?,
          transactionId: tx,
          status: status,
          mode: PaymentMode.fromWire(map['mode'] as String?),
          timestamp: timestamp,
        );
      case MessageType.cancelTransaction:
        final tx = _requireTxId(map);
        final reason = map['reason'];
        if (reason != null && reason is! String) {
          throw ProtocolException('VALIDATION', 'reason must be a string');
        }
        return CancelTransactionMessage(
          messageId: messageId as String?,
          transactionId: tx,
          reason: reason as String?,
        );
      case MessageType.error:
        final code = map['code'];
        final message = map['message'];
        if (code is! String ||
            code.isEmpty ||
            message is! String ||
            message.isEmpty) {
          throw ProtocolException(
              'VALIDATION', 'ERROR requires code and message');
        }
        final tx = map['transactionId'];
        if (tx != null && tx is! String) {
          throw ProtocolException(
              'VALIDATION', 'transactionId must be a string');
        }
        return ProtocolErrorMessage(
          messageId: messageId as String?,
          code: code,
          message: message,
          transactionId: tx as String?,
        );
    }
  }

  static ProtocolMessage decodeBytes(List<int> bytes) {
    if (bytes.length > FuelPayBle.maxMessageBytes) {
      throw ProtocolException('TOO_LARGE', 'Message exceeds maximum size');
    }
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw ProtocolException('INVALID_UTF8', 'Payload is not valid UTF-8');
    }
    return decodeString(text);
  }

  static String _requireTxId(Map<String, dynamic> map) {
    final tx = map['transactionId'];
    if (!TransactionId.isValid(tx)) {
      throw ProtocolException('VALIDATION', 'Invalid or missing transactionId');
    }
    return tx as String;
  }

  /// Accepts canonical state names and the shortened forms from the spec
  /// examples ("SUCCESS" / "FAILED").
  static TransactionStatus _parsePayableStatus(Object? raw) {
    if (raw is! String) {
      throw ProtocolException('VALIDATION', 'status must be a string');
    }
    switch (raw.toUpperCase()) {
      case 'PAYMENT_PENDING':
        return TransactionStatus.paymentPending;
      case 'SUCCESS':
      case 'PAYMENT_SUCCESS':
        return TransactionStatus.paymentSuccess;
      case 'FAILED':
      case 'PAYMENT_FAILED':
        return TransactionStatus.paymentFailed;
      case 'CANCELLED':
        return TransactionStatus.cancelled;
      default:
        throw ProtocolException(
          'VALIDATION',
          'PAYMENT_STATUS.status must be one of PAYMENT_PENDING, SUCCESS, FAILED, CANCELLED',
        );
    }
  }
}

// -------------------------------------------------------------- messages

class HelloMessage extends ProtocolMessage {
  HelloMessage({super.messageId, required this.role});

  /// 'CUSTOMER' — identifies the central to the pump.
  final String role;

  @override
  MessageType get type => MessageType.hello;

  @override
  Map<String, dynamic> toJson() => {
        'protocolVersion': FuelPayBle.protocolVersion,
        'type': type.wireName,
        'messageId': messageId,
        'role': role,
      };
}

class HelloAckMessage extends ProtocolMessage {
  HelloAckMessage(
      {super.messageId, required this.pumpName, this.mode = PaymentMode.demo});

  final String pumpName;
  final PaymentMode mode;

  @override
  MessageType get type => MessageType.helloAck;

  @override
  Map<String, dynamic> toJson() => {
        'protocolVersion': FuelPayBle.protocolVersion,
        'type': type.wireName,
        'messageId': messageId,
        'pumpName': pumpName,
        'mode': mode.wireName,
      };
}

class PaymentRequestMessage extends ProtocolMessage {
  PaymentRequestMessage({
    super.messageId,
    required this.transactionId,
    required this.fuelType,
    required this.amount,
    this.currency = 'INR',
    this.mode = PaymentMode.demo,
  });

  @override
  final String transactionId;
  final FuelType fuelType;

  /// Integer rupees (100..10000).
  final int amount;
  final String currency;
  final PaymentMode mode;

  @override
  MessageType get type => MessageType.paymentRequest;

  factory PaymentRequestMessage._validate(
      Map<String, dynamic> map, String? messageId) {
    final tx = ProtocolMessage._requireTxId(map);
    if (!FuelType.isValid(map['fuelType'] as String?)) {
      throw ProtocolException(
          'VALIDATION', 'fuelType must be PETROL or DIESEL');
    }
    final amount = map['amount'];
    if (amount is! int || !AmountValidator.isValid(amount)) {
      throw ProtocolException(
        'VALIDATION',
        'amount must be an integer between ${AmountValidator.minAmount} '
            'and ${AmountValidator.maxAmount}',
      );
    }
    final currency = map['currency'];
    if (currency != null && currency != 'INR') {
      throw ProtocolException('VALIDATION', 'currency must be INR');
    }
    return PaymentRequestMessage(
      messageId: messageId,
      transactionId: tx,
      fuelType: FuelType.fromWire(map['fuelType'] as String),
      amount: amount,
      currency: 'INR',
      mode: PaymentMode.fromWire(map['mode'] as String?),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'protocolVersion': FuelPayBle.protocolVersion,
        'type': type.wireName,
        'messageId': messageId,
        'transactionId': transactionId,
        'fuelType': fuelType.wireName,
        'amount': amount,
        'currency': currency,
        'mode': mode.wireName,
      };
}

class RequestReceivedMessage extends ProtocolMessage {
  RequestReceivedMessage({
    super.messageId,
    required this.transactionId,
    this.mode = PaymentMode.demo,
  });

  @override
  final String transactionId;
  final PaymentMode mode;

  @override
  MessageType get type => MessageType.requestReceived;

  @override
  Map<String, dynamic> toJson() => {
        'protocolVersion': FuelPayBle.protocolVersion,
        'type': type.wireName,
        'messageId': messageId,
        'transactionId': transactionId,
        'status': 'PENDING',
        'mode': mode.wireName,
      };
}

class RequestDecisionMessage extends ProtocolMessage {
  static const String accepted = 'ACCEPTED';
  static const String rejected = 'REJECTED';

  RequestDecisionMessage({
    super.messageId,
    required this.transactionId,
    required this.decision,
    this.reason,
    this.mode = PaymentMode.demo,
  }) : assert(decision == accepted || decision == rejected);

  @override
  final String transactionId;
  final String decision;
  final String? reason;
  final PaymentMode mode;

  bool get isAccepted => decision == accepted;

  @override
  MessageType get type => MessageType.requestDecision;

  @override
  Map<String, dynamic> toJson() => {
        'protocolVersion': FuelPayBle.protocolVersion,
        'type': type.wireName,
        'messageId': messageId,
        'transactionId': transactionId,
        'decision': decision,
        if (reason != null) 'reason': reason,
        'mode': mode.wireName,
      };
}

class PaymentStatusMessage extends ProtocolMessage {
  PaymentStatusMessage({
    super.messageId,
    required this.transactionId,
    required this.status,
    this.mode = PaymentMode.demo,
    this.timestamp,
  }) : assert(
          status == TransactionStatus.paymentPending ||
              status == TransactionStatus.paymentSuccess ||
              status == TransactionStatus.paymentFailed ||
              status == TransactionStatus.cancelled,
        );

  @override
  final String transactionId;

  /// One of: PAYMENT_PENDING, PAYMENT_SUCCESS, PAYMENT_FAILED, CANCELLED.
  final TransactionStatus status;
  final PaymentMode mode;
  final DateTime? timestamp;

  @override
  MessageType get type => MessageType.paymentStatus;

  factory PaymentStatusMessage.fromTransaction(
    FuelTransaction tx, {
    String? messageId,
  }) {
    assert(
      tx.status == TransactionStatus.paymentPending ||
          tx.status == TransactionStatus.paymentSuccess ||
          tx.status == TransactionStatus.paymentFailed ||
          tx.status == TransactionStatus.cancelled,
      'PAYMENT_STATUS cannot carry ${tx.status.wireName}',
    );
    return PaymentStatusMessage(
      messageId: messageId,
      transactionId: tx.transactionId,
      status: tx.status,
      mode: tx.mode,
      timestamp: tx.updatedAt,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'protocolVersion': FuelPayBle.protocolVersion,
        'type': type.wireName,
        'messageId': messageId,
        'transactionId': transactionId,
        'status': status.wireName,
        'mode': mode.wireName,
        if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
      };
}

class CancelTransactionMessage extends ProtocolMessage {
  CancelTransactionMessage(
      {super.messageId, required this.transactionId, this.reason});

  @override
  final String transactionId;
  final String? reason;

  @override
  MessageType get type => MessageType.cancelTransaction;

  @override
  Map<String, dynamic> toJson() => {
        'protocolVersion': FuelPayBle.protocolVersion,
        'type': type.wireName,
        'messageId': messageId,
        'transactionId': transactionId,
        if (reason != null) 'reason': reason,
      };
}

class ProtocolErrorMessage extends ProtocolMessage {
  ProtocolErrorMessage({
    super.messageId,
    required this.code,
    required this.message,
    this.transactionId,
  });

  final String code;
  final String message;
  @override
  final String? transactionId;

  @override
  MessageType get type => MessageType.error;

  @override
  Map<String, dynamic> toJson() => {
        'protocolVersion': FuelPayBle.protocolVersion,
        'type': type.wireName,
        'messageId': messageId,
        'code': code,
        'message': message,
        if (transactionId != null) 'transactionId': transactionId,
      };
}
