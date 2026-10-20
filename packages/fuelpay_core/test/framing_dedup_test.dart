import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fuelpay_core/fuelpay_core.dart';

void main() {
  group('MessageFraming / FrameAssembler', () {
    test('single-frame message round trip', () {
      const message = '{"type":"PING"}';
      final frames = MessageFraming.encodeString(message, chunkSize: 180);
      expect(frames.length, 1);
      final assembler = FrameAssembler();
      final payload = assembler.add(frames.first);
      expect(payload, isNotNull);
      expect(utf8.decode(payload!), message);
    });

    test('multi-frame message reassembles in order', () {
      final message = jsonEncode({
        'protocolVersion': 1,
        'type': 'PAYMENT_REQUEST',
        'transactionId': 'FP100001',
        'fuelType': 'PETROL',
        'amount': 500,
        'currency': 'INR',
        'mode': 'DEMO',
        'padding': List.generate(120, (i) => 'item$i').join(','),
      });
      final frames = MessageFraming.encodeString(message, chunkSize: 40);
      expect(frames.length, greaterThan(1));

      final assembler = FrameAssembler();
      Uint8List? result;
      for (final frame in frames) {
        result = assembler.add(frame);
      }
      expect(result, isNotNull);
      expect(utf8.decode(result!), message);
      expect(assembler.hasPartial, isFalse);
    });

    test('utf8 (₹) content survives framing', () {
      const message = '{"label":"₹500 — fuel"}';
      final frames = MessageFraming.encodeString(message, chunkSize: 8);
      expect(frames.length, greaterThan(1));
      final assembler = FrameAssembler();
      Uint8List? complete;
      for (final frame in frames) {
        final out = assembler.add(frame);
        if (out != null) complete = out;
      }
      expect(complete, isNotNull);
      expect(utf8.decode(complete!), message);
    });

    test('continuation without first frame is rejected', () {
      final assembler = FrameAssembler();
      expect(
        () => assembler.add([MessageFraming.continuationFrameTag, 1, 2]),
        throwsFormatException,
      );
      expect(assembler.hasPartial, isFalse);
    });

    test('unknown tag and empty frames are rejected', () {
      expect(() => FrameAssembler().add([]), throwsFormatException);
      expect(() => FrameAssembler().add([0x77, 1, 2]), throwsFormatException);
    });

    test('oversized declared length is rejected', () {
      final frame = [
        MessageFraming.firstFrameTag,
        0xFF,
        0xFF, // 65535 > maxMessageBytes
      ];
      expect(() => FrameAssembler().add(frame), throwsFormatException);
    });

    test('partial messages become stale after the fragment timeout', () {
      final assembler = FrameAssembler();
      final frames = MessageFraming.encodeString('x' * 400, chunkSize: 100);
      final start = DateTime(2026, 1, 1, 12);
      assembler.add(frames.first, now: start);
      expect(assembler.hasPartial, isTrue);
      expect(
        assembler.isStale(start.add(FuelPayBle.fragmentTimeout)),
        isFalse,
      );
      expect(
        assembler.isStale(
            start.add(FuelPayBle.fragmentTimeout + const Duration(seconds: 1))),
        isTrue,
      );
      assembler.reset();
      expect(assembler.hasPartial, isFalse);
    });

    test('receiving extra bytes beyond declared length fails', () {
      final frames = MessageFraming.encodeString('hello', chunkSize: 180);
      final first = List<int>.from(frames.first)..add(0x41); // extra byte
      final assembler = FrameAssembler();
      expect(() => assembler.add(first), throwsFormatException);
    });
  });

  group('MessageDeduplicator', () {
    ProtocolMessage sampleMessage() => PaymentRequestMessage(
          transactionId: 'FP100001',
          fuelType: FuelType.diesel,
          amount: 1000,
        );

    test('first message accepted, identical content rejected', () {
      final dedupe = MessageDeduplicator();
      final a = sampleMessage();
      // Byte-identical retry with a different messageId is still a duplicate
      // because dedupKey ignores messageId.
      final b = ProtocolMessage.decodeString(a.encode());
      expect(dedupe.accept(a), isTrue);
      expect(dedupe.accept(b), isFalse);
      expect(dedupe.isDuplicate(b), isTrue);
    });

    test('different content is not a duplicate', () {
      final dedupe = MessageDeduplicator();
      expect(dedupe.accept(sampleMessage()), isTrue);
      expect(
        dedupe.accept(PaymentRequestMessage(
          transactionId: 'FP100001',
          fuelType: FuelType.diesel,
          amount: 2000, // different amount
        )),
        isTrue,
      );
      expect(
        dedupe.accept(PaymentRequestMessage(
          transactionId: 'FP999999', // different id
          fuelType: FuelType.diesel,
          amount: 1000,
        )),
        isTrue,
      );
    });

    test('entries expire after ttl', () {
      final dedupe = MessageDeduplicator(ttl: const Duration(minutes: 5));
      final msg = sampleMessage();
      final t0 = DateTime(2026, 1, 1, 12);
      expect(dedupe.accept(msg, now: t0), isTrue);
      expect(
        dedupe.accept(
          ProtocolMessage.decodeString(msg.encode()),
          now: t0.add(const Duration(minutes: 4)),
        ),
        isFalse,
      );
      expect(
        dedupe.accept(
          ProtocolMessage.decodeString(msg.encode()),
          now: t0.add(const Duration(minutes: 6)),
        ),
        isTrue,
        reason: 'expired entries are forgotten',
      );
    });

    test('capacity is bounded', () {
      final dedupe = MessageDeduplicator(capacity: 10);
      for (var i = 0; i < 50; i++) {
        dedupe.accept(PaymentRequestMessage(
          transactionId: 'FP10000$i',
          fuelType: FuelType.petrol,
          amount: 500,
        ));
      }
      expect(dedupe.size, 10);
    });
  });
}
