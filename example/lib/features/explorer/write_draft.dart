import 'dart:convert';

import '../../bluetooth/hex.dart';
import 'value_decoder.dart';

enum WriteFormat { hex, text }

/// What the user typed in the write dialog, and the bytes it stands for.
final class WriteDraft {
  const WriteDraft(this.input, this.format);

  final String input;
  final WriteFormat format;

  /// Null when [input] is not valid hex.
  List<int>? get bytes => switch (format) {
    WriteFormat.hex => parseHex(input),
    WriteFormat.text => utf8.encode(input),
  };

  /// Why the draft cannot be written, or null when it can.
  String? problem(int maximumLength) {
    final bytes = this.bytes;
    if (bytes == null) return 'Use pairs of hex digits, such as 01 FF';
    if (bytes.isEmpty) return 'Enter at least one byte';
    if (bytes.length > maximumLength) {
      return '${bytes.length} bytes is over the limit of $maximumLength';
    }
    return null;
  }

  /// The same bytes typed in [format]. Bytes that are not printable text
  /// cannot be shown as text, so that conversion starts empty.
  WriteDraft convertTo(WriteFormat format) {
    if (format == this.format) return this;
    final bytes = this.bytes ?? const [];
    return switch (format) {
      WriteFormat.hex => WriteDraft(bytes.toHex(), format),
      WriteFormat.text => WriteDraft(_exactText(bytes) ?? '', format),
    };
  }

  static String? _exactText(List<int> bytes) {
    final text = ValueDecoder.printableText(bytes);
    if (text == null || utf8.encode(text).length != bytes.length) return null;
    return text;
  }
}
