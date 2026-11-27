import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'beam_frame.dart';
import 'crc32.dart';

enum _Stage {
  magic,
  version,
  nameLength,
  name,
  length,
  payload,
  checksum,
  done,
}

/// Parses one [BeamFrame] transfer from chunks that may split it anywhere.
///
/// [add] throws a [BeamFormatException] as soon as the bytes break the
/// format; [close] throws one if the input ended early.
final class BeamParser {
  BeamParser({this.maxPayloadLength = BeamFrame.maxPayloadLength})
    : assert(maxPayloadLength <= 0xffffffff);

  final int maxPayloadLength;
  final _crc = Crc32();
  var _stage = _Stage.magic;
  var _field = Uint8List(BeamFrame.magic.length);
  var _filled = 0;
  var _name = '';
  Uint8List? _payload;
  var _received = 0;

  /// The file name and length, once they have arrived.
  BeamHeader? get header {
    final payload = _payload;
    return payload == null ? null : BeamHeader(_name, payload.length);
  }

  /// Payload bytes received so far.
  int get received => _received;

  bool get isComplete => _stage == _Stage.done;

  Uint8List get payload {
    if (!isComplete) throw StateError('The transfer is not complete');
    return _payload!;
  }

  void add(List<int> chunk) {
    var offset = 0;
    while (offset < chunk.length) {
      offset += switch (_stage) {
        _Stage.done => throw const BeamFormatException(
          BeamFailure.unexpectedBytes,
        ),
        _Stage.payload => _addPayload(chunk, offset),
        _ => _addField(chunk, offset),
      };
    }
  }

  void close() {
    if (!isComplete) throw const BeamFormatException(BeamFailure.truncated);
  }

  int _addField(List<int> chunk, int offset) {
    final count = min(chunk.length - offset, _field.length - _filled);
    _field.setRange(_filled, _filled + count, chunk, offset);
    _filled += count;
    if (_filled == _field.length) _completeField();
    return count;
  }

  int _addPayload(List<int> chunk, int offset) {
    final payload = _payload!;
    final count = min(chunk.length - offset, payload.length - _received);
    payload.setRange(_received, _received + count, chunk, offset);
    _crc.add(chunk, offset, offset + count);
    _received += count;
    if (_received == payload.length) _expect(_Stage.checksum, 4);
    return count;
  }

  void _expect(_Stage stage, int length) {
    _stage = stage;
    _field = Uint8List(length);
    _filled = 0;
    if (length == 0) _completeField();
  }

  void _completeField() {
    final field = _field;
    final data = ByteData.sublistView(field);
    switch (_stage) {
      case _Stage.magic:
        for (var i = 0; i < field.length; i++) {
          if (field[i] != BeamFrame.magic[i]) _fail(BeamFailure.badMagic);
        }
        _expect(_Stage.version, 1);
      case _Stage.version:
        if (field[0] != BeamFrame.version) {
          _fail(BeamFailure.unsupportedVersion);
        }
        _expect(_Stage.nameLength, 1);
      case _Stage.nameLength:
        _expect(_Stage.name, field[0]);
      case _Stage.name:
        _name = _decodeName(field);
        _expect(_Stage.length, 8);
      case _Stage.length:
        final low = data.getUint32(0, Endian.little);
        final high = data.getUint32(4, Endian.little);
        if (high != 0 || low > maxPayloadLength) _fail(BeamFailure.tooLarge);
        _payload = Uint8List(low);
        _stage = _Stage.payload;
        if (low == 0) _expect(_Stage.checksum, 4);
      case _Stage.checksum:
        if (data.getUint32(0, Endian.little) != _crc.value) {
          _fail(BeamFailure.checksumMismatch);
        }
        _stage = _Stage.done;
      case _Stage.payload || _Stage.done:
        throw StateError('No field is expected in stage $_stage');
    }
  }

  static String _decodeName(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      _fail(BeamFailure.badName);
    }
  }

  static Never _fail(BeamFailure failure) => throw BeamFormatException(failure);
}
