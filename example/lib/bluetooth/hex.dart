extension HexBytes on List<int> {
  /// Such as `4C 00 10 05`. With [max], longer values end in an ellipsis.
  String toHex({int? max}) {
    final shown = max == null || length <= max ? this : take(max);
    final hex = shown
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
    return shown.length < length ? '$hex …' : hex;
  }
}

/// Parses hex such as `0a FF 3c` or `0aff3c`; returns null when invalid.
List<int>? parseHex(String text) {
  final digits = text.replaceAll(RegExp(r'[\s:,-]|0x'), '');
  if (digits.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(digits)) {
    return null;
  }
  return [
    for (var i = 0; i < digits.length; i += 2)
      int.parse(digits.substring(i, i + 2), radix: 16),
  ];
}
