import 'package:bt_radar/features/explorer/write_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bytes', () {
    test('parses hex with separators', () {
      expect(const WriteDraft('01 ff:3C', WriteFormat.hex).bytes, [
        0x01,
        0xff,
        0x3c,
      ]);
      expect(const WriteDraft('0x0102', WriteFormat.hex).bytes, [1, 2]);
    });

    test('is null for invalid hex', () {
      expect(const WriteDraft('0', WriteFormat.hex).bytes, isNull);
      expect(const WriteDraft('zz', WriteFormat.hex).bytes, isNull);
    });

    test('encodes text as UTF-8', () {
      expect(const WriteDraft('hé', WriteFormat.text).bytes, [
        0x68,
        0xc3,
        0xa9,
      ]);
    });
  });

  group('problem', () {
    test('accepts a value within the limit', () {
      expect(const WriteDraft('01 02', WriteFormat.hex).problem(2), isNull);
    });

    test('explains invalid hex', () {
      expect(
        const WriteDraft('abc', WriteFormat.hex).problem(20),
        'Use pairs of hex digits, such as 01 FF',
      );
    });

    test('needs at least one byte', () {
      expect(
        const WriteDraft('', WriteFormat.text).problem(20),
        'Enter at least one byte',
      );
    });

    test('enforces the maximum write length', () {
      expect(
        const WriteDraft('hello', WriteFormat.text).problem(4),
        '5 bytes is over the limit of 4',
      );
    });
  });

  group('convertTo', () {
    test('text to hex', () {
      final draft = const WriteDraft('Hi', WriteFormat.text);
      expect(draft.convertTo(WriteFormat.hex).input, '48 69');
    });

    test('hex to text when printable', () {
      final draft = const WriteDraft('48 69', WriteFormat.hex);
      expect(draft.convertTo(WriteFormat.text).input, 'Hi');
    });

    test('hex to text starts empty when not printable', () {
      final draft = const WriteDraft('48 00', WriteFormat.hex);
      expect(draft.convertTo(WriteFormat.text).input, '');
      expect(
        const WriteDraft(
          '01',
          WriteFormat.hex,
        ).convertTo(WriteFormat.text).input,
        '',
      );
    });

    test('keeps the draft in the same format', () {
      const draft = WriteDraft('zz', WriteFormat.hex);
      expect(draft.convertTo(WriteFormat.hex), same(draft));
    });
  });
}
