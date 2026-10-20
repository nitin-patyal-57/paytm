import 'dart:convert';
import 'dart:typed_data';

import 'ble_constants.dart';

/// Message framing for BLE transport.
///
/// Characteristic values are limited by the negotiated MTU, so logical
/// messages are split into small frames and reassembled on the other side.
///
/// Frame layout (bytes):
///   [0]     tag: 0x01 = FIRST frame, 0x02 = CONTINUATION frame
///   [1..2]  total payload length, big-endian (FIRST frames only)
///   [3..]   payload slice (FIRST frames), [1..] payload slice (CONTINUATION)
class MessageFraming {
  MessageFraming._();

  static const int firstFrameTag = 0x01;
  static const int continuationFrameTag = 0x02;
  static const int headerOverhead = 3;

  /// Maximum payload bytes per frame used unless a smaller MTU is known.
  static const int maxPayloadChunk = FuelPayBle.defaultChunkSize;

  /// Splits [payload] into frames carrying at most [chunkSize] payload bytes.
  static List<Uint8List> encode(Uint8List payload, {int? chunkSize}) {
    final chunk = (chunkSize ?? maxPayloadChunk).clamp(1, maxPayloadChunk * 4);
    if (payload.isEmpty) {
      return [
        Uint8List.fromList([firstFrameTag, 0, 0])
      ];
    }
    final frames = <Uint8List>[];
    for (var offset = 0; offset < payload.length; offset += chunk) {
      final end =
          offset + chunk > payload.length ? payload.length : offset + chunk;
      final slice = payload.sublist(offset, end);
      if (offset == 0) {
        final frame = Uint8List(headerOverhead + slice.length);
        frame[0] = firstFrameTag;
        frame[1] = (payload.length >> 8) & 0xff;
        frame[2] = payload.length & 0xff;
        frame.setRange(headerOverhead, frame.length, slice);
        frames.add(frame);
      } else {
        final frame = Uint8List(1 + slice.length);
        frame[0] = continuationFrameTag;
        frame.setRange(1, frame.length, slice);
        frames.add(frame);
      }
    }
    return frames;
  }

  /// Convenience: UTF-8 encode a JSON string, then frame it.
  static List<Uint8List> encodeString(String message, {int? chunkSize}) =>
      encode(Uint8List.fromList(utf8.encode(message)), chunkSize: chunkSize);
}

/// Reassembles framed payloads.
///
/// Feed every received characteristic value to [add]. It returns the complete
/// payload when the final fragment arrives, otherwise `null`.
/// Partial messages older than [FuelPayBle.fragmentTimeout] are considered
/// stale ([isStale]); call [reset] on disconnect.
class FrameAssembler {
  FrameAssembler();

  Uint8List? _buffer;
  int _expectedLength = -1;
  DateTime _lastFragmentAt = DateTime.now();

  bool get hasPartial => _buffer != null;

  DateTime get lastFragmentAt => _lastFragmentAt;

  bool isStale([DateTime? now]) {
    if (_buffer == null) return false;
    final reference = now ?? DateTime.now();
    return reference.difference(_lastFragmentAt) > FuelPayBle.fragmentTimeout;
  }

  /// Returns the fully reassembled payload, or null if more frames are needed.
  /// Throws [FormatException] on malformed frames; the assembler resets so a
  /// bad frame cannot poison subsequent messages.
  Uint8List? add(List<int> frame, {DateTime? now}) {
    _lastFragmentAt = now ?? DateTime.now();
    if (frame.isEmpty) {
      reset();
      throw const FormatException('Empty BLE frame');
    }
    final tag = frame[0];
    if (tag == MessageFraming.firstFrameTag) {
      if (frame.length < MessageFraming.headerOverhead) {
        reset();
        throw const FormatException('FIRST frame too short');
      }
      final total = (frame[1] << 8) | frame[2];
      if (total > FuelPayBle.maxMessageBytes) {
        reset();
        throw const FormatException('Declared message size out of range');
      }
      _expectedLength = total;
      _buffer =
          Uint8List.fromList(frame.sublist(MessageFraming.headerOverhead));
    } else if (tag == MessageFraming.continuationFrameTag) {
      if (_buffer == null) {
        reset();
        throw const FormatException('CONTINUATION frame without FIRST frame');
      }
      final next = Uint8List(_buffer!.length + frame.length - 1);
      next.setAll(0, _buffer!);
      next.setAll(_buffer!.length, frame.sublist(1));
      _buffer = next;
    } else {
      reset();
      throw FormatException('Unknown frame tag: $tag');
    }

    if (_buffer!.length > _expectedLength) {
      reset();
      throw const FormatException('Received more bytes than declared');
    }
    if (_buffer!.length == _expectedLength) {
      final complete = _buffer!;
      reset();
      return complete;
    }
    return null;
  }

  void reset() {
    _buffer = null;
    _expectedLength = -1;
  }
}
