/// [text] trimmed, without control characters, and cut on a character
/// boundary to at most [maxBytes] of UTF-8, so that it fits a GATT value.
String shortText(String text, int maxBytes) {
  final kept = StringBuffer();
  var bytes = 0;
  for (final rune in text.trim().runes) {
    if (rune < 0x20 || rune == 0x7f) continue;
    bytes += _utf8Length(rune);
    if (bytes > maxBytes) break;
    kept.writeCharCode(rune);
  }
  return kept.toString().trim();
}

int _utf8Length(int rune) => switch (rune) {
  < 0x80 => 1,
  < 0x800 => 2,
  < 0x10000 => 3,
  _ => 4,
};
