import 'package:material_ui/material_ui.dart';

/// A small Dart syntax highlighter for the code sheet.
abstract final class DartHighlighter {
  static const _comment = Color(0xff6a8a80);
  static const _string = Color(0xffa5e07a);
  static const _keyword = Color(0xffff8fb1);
  static const _type = Color(0xff7cc7ff);
  static const _number = Color(0xffffc66d);
  static const _call = Color(0xfff2e6a0);

  static final _token = RegExp(
    r'(?<comment>//[^\n]*)'
    r"|(?<string>'(?:[^'\\\n]|\\.)*'|"
    r'"(?:[^"\\\n]|\\.)*")'
    r'|(?<keyword>\b(?:abstract|async|await|break|case|class|const|continue|'
    r'default|else|extends|final|for|if|implements|import|in|is|late|new|'
    r'null|on|return|show|static|switch|this|throw|true|false|try|catch|var|'
    r'void|when|while|yield)\b)'
    r'|(?<type>\b[A-Z][A-Za-z0-9_$]*\b)'
    r'|(?<number>\b(?:0x[0-9a-fA-F]+|\d+(?:\.\d+)?)\b)'
    r'|(?<call>\b[a-z_$][A-Za-z0-9_$]*(?=\())',
  );

  static TextSpan highlight(String code, TextStyle base) {
    final spans = <TextSpan>[];
    var position = 0;
    for (final match in _token.allMatches(code)) {
      if (match.start > position) {
        spans.add(TextSpan(text: code.substring(position, match.start)));
      }
      spans.add(TextSpan(text: match[0], style: _styleOf(match)));
      position = match.end;
    }
    if (position < code.length) {
      spans.add(TextSpan(text: code.substring(position)));
    }
    return TextSpan(style: base, children: spans);
  }

  static TextStyle? _styleOf(RegExpMatch match) {
    Color? color;
    var italic = false;
    if (match.namedGroup('comment') != null) {
      color = _comment;
      italic = true;
    } else if (match.namedGroup('string') != null) {
      color = _string;
    } else if (match.namedGroup('keyword') != null) {
      color = _keyword;
    } else if (match.namedGroup('type') != null) {
      color = _type;
    } else if (match.namedGroup('number') != null) {
      color = _number;
    } else if (match.namedGroup('call') != null) {
      color = _call;
    }
    return TextStyle(color: color, fontStyle: italic ? FontStyle.italic : null);
  }
}
