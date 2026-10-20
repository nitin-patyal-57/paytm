import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fuelpay_core/fuelpay_core.dart';

ProtocolMessage decodeJson(Map<String, dynamic> map) =>
    ProtocolMessage.decodeString(jsonEncode(map));

void main() {
  group('PaymentRequestMessage', () {
    test('encode/decode round trip', () {
      final original = PaymentRequestMessage(
        transactionId: 'FP100001',
        fuelType: FuelType.petrol,
        amount: 500,
      );
      final decoded = ProtocolMessage.decodeString(original.encode());
      expect(decoded, isA<PaymentRequestMessage>());
      final msg = decoded as PaymentRequestMessage;
      expect(msg.transactionId, 'FP100001');
      expect(msg.fuelType, FuelType.petrol);
      expect(msg.amount, 500);
      expect(msg.currency, 'INR');
      expect(msg.mode, PaymentMode.demo);
      expect(msg.protocolVersion, 1);
    });

    test('spec example payload decodes', () {
      final msg = decodeJson({
        'protocolVersion': 1,
        'type': 'PAYMENT_REQUEST',
        'transactionId': 'FP100001',
        'fuelType': 'PETROL',
        'amount': 500,
        'currency': 'INR',
        'mode': 'DEMO',
      });
      expect(msg, isA<PaymentRequestMessage>());
      expect((msg as PaymentRequestMessage).amount, 500);
    });

    test('rejects invalid amounts, fuel types and ids', () {
      Map<String, dynamic> base() => {
            'protocolVersion': 1,
            'type': 'PAYMENT_REQUEST',
            'transactionId': 'FP100001',
            'fuelType': 'PETROL',
            'amount': 500,
            'currency': 'INR',
            'mode': 'DEMO',
          };

      for (final amount in [99, 10001, 0, 500.5, '500', null]) {
        final body = base()..['amount'] = amount;
        expect(
          () => decodeJson(body),
          throwsA(isA<ProtocolException>()
              .having((e) => e.code, 'code', 'VALIDATION')),
          reason: 'amount $amount must be rejected',
        );
      }

      expect(
        () => decodeJson(base()..['fuelType'] = 'KEROSENE'),
        throwsA(isA<ProtocolException>()),
      );
      expect(
        () => decodeJson(base()..['transactionId'] = 'nope'),
        throwsA(isA<ProtocolException>()),
      );
      expect(
        () => decodeJson(base()..['currency'] = 'USD'),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('rejects unsupported protocol versions', () {
      expect(
        () => decodeJson({
          'protocolVersion': 2,
          'type': 'PAYMENT_REQUEST',
          'transactionId': 'FP100001',
          'fuelType': 'PETROL',
          'amount': 500,
        }),
        throwsA(isA<ProtocolException>()
            .having((e) => e.code, 'code', 'UNSUPPORTED_VERSION')),
      );
      expect(
        () => decodeJson({
          'type': 'PAYMENT_REQUEST',
          'transactionId': 'FP100001',
          'fuelType': 'PETROL',
          'amount': 500,
        }),
        throwsA(isA<ProtocolException>()
            .having((e) => e.code, 'code', 'UNSUPPORTED_VERSION')),
      );
    });

    test('rejects unknown message types', () {
      expect(
        () => decodeJson({'protocolVersion': 1, 'type': 'FUTURE_THING'}),
        throwsA(isA<ProtocolException>()
            .having((e) => e.code, 'code', 'UNKNOWN_TYPE')),
      );
    });

    test('rejects invalid JSON and non-object payloads', () {
      expect(
        () => ProtocolMessage.decodeString('{not json'),
        throwsA(isA<ProtocolException>()
            .having((e) => e.code, 'code', 'INVALID_JSON')),
      );
      expect(
        () => ProtocolMessage.decodeString('[1,2,3]'),
        throwsA(isA<ProtocolException>()
            .having((e) => e.code, 'code', 'INVALID_SHAPE')),
      );
      expect(
        () => ProtocolMessage.decodeBytes([0xff, 0xfe, 0x00]),
        throwsA(isA<ProtocolException>()),
      );
    });
  });

  group('ack / decision / status messages', () {
    test('spec REQUEST_RECEIVED example decodes', () {
      final msg = decodeJson({
        'protocolVersion': 1,
        'type': 'REQUEST_RECEIVED',
        'transactionId': 'FP100001',
        'status': 'PENDING',
        'mode': 'DEMO',
      });
      expect(msg, isA<RequestReceivedMessage>());
      expect(msg.transactionId, 'FP100001');
    });

    test('spec PAYMENT_STATUS example decodes (SUCCESS alias)', () {
      final msg = decodeJson({
        'protocolVersion': 1,
        'type': 'PAYMENT_STATUS',
        'transactionId': 'FP100001',
        'status': 'SUCCESS',
        'mode': 'DEMO',
      });
      expect(msg, isA<PaymentStatusMessage>());
      expect((msg as PaymentStatusMessage).status,
          TransactionStatus.paymentSuccess);
    });

    test('payment status round trip keeps canonical status', () {
      final msg = PaymentStatusMessage(
        transactionId: 'FP100001',
        status: TransactionStatus.paymentFailed,
        timestamp: DateTime.utc(2026, 1, 2, 3, 4, 5),
      );
      final decoded =
          ProtocolMessage.decodeString(msg.encode()) as PaymentStatusMessage;
      expect(decoded.status, TransactionStatus.paymentFailed);
      expect(decoded.timestamp, DateTime.utc(2026, 1, 2, 3, 4, 5));
    });

    test('payment status rejects non-payable statuses', () {
      expect(
        () => decodeJson({
          'protocolVersion': 1,
          'type': 'PAYMENT_STATUS',
          'transactionId': 'FP100001',
          'status': 'CREATED',
          'mode': 'DEMO',
        }),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('decision messages carry accepted/rejected', () {
      final accepted = RequestDecisionMessage(
        transactionId: 'FP100001',
        decision: RequestDecisionMessage.accepted,
      );
      final decoded = ProtocolMessage.decodeString(accepted.encode())
          as RequestDecisionMessage;
      expect(decoded.isAccepted, isTrue);

      final rejected = RequestDecisionMessage(
        transactionId: 'FP100001',
        decision: RequestDecisionMessage.rejected,
        reason: 'invalid request',
      );
      final decoded2 = ProtocolMessage.decodeString(rejected.encode())
          as RequestDecisionMessage;
      expect(decoded2.isAccepted, isFalse);
      expect(decoded2.reason, 'invalid request');

      expect(
        () => decodeJson({
          'protocolVersion': 1,
          'type': 'REQUEST_DECISION',
          'transactionId': 'FP100001',
          'decision': 'MAYBE',
        }),
        throwsA(isA<ProtocolException>()),
      );
    });

    test('error and cancel messages round trip', () {
      final err = ProtocolErrorMessage(
        code: 'UNSUPPORTED_VERSION',
        message: 'upgrade required',
        transactionId: 'FP100001',
      );
      final decodedErr = ProtocolMessage.decodeString(err.encode());
      expect(decodedErr, isA<ProtocolErrorMessage>());
      expect((decodedErr as ProtocolErrorMessage).code, 'UNSUPPORTED_VERSION');

      final cancel = CancelTransactionMessage(
        transactionId: 'FP100001',
        reason: 'customer left',
      );
      final decodedCancel = ProtocolMessage.decodeString(cancel.encode());
      expect(decodedCancel, isA<CancelTransactionMessage>());
      expect(decodedCancel.transactionId, 'FP100001');
    });

    test('hello and hello-ack round trip', () {
      final hello = HelloMessage(role: 'CUSTOMER');
      final decoded = ProtocolMessage.decodeString(hello.encode());
      expect(decoded, isA<HelloMessage>());
      expect((decoded as HelloMessage).role, 'CUSTOMER');

      final ack = HelloAckMessage(pumpName: 'FuelPay Pump-1');
      final decodedAck = ProtocolMessage.decodeString(ack.encode());
      expect(decodedAck, isA<HelloAckMessage>());
      expect((decodedAck as HelloAckMessage).pumpName, 'FuelPay Pump-1');
    });
  });
}
