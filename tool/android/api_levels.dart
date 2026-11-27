import 'dart:io';

import 'package:xml/xml.dart';

/// An Android API level such as `33` or `36.1`.
final class ApiLevel implements Comparable<ApiLevel> {
  const ApiLevel(this.major, [this.minor = 0]);

  factory ApiLevel.parse(String value) {
    final parts = value.split('.');
    return ApiLevel(
      int.parse(parts.first),
      parts.length > 1 ? int.parse(parts[1]) : 0,
    );
  }

  final int major;
  final int minor;

  @override
  int compareTo(ApiLevel other) =>
      major != other.major ? major - other.major : minor - other.minor;

  bool operator <=(ApiLevel other) => compareTo(other) <= 0;

  @override
  String toString() => minor == 0 ? '$major' : '$major.$minor';
}

/// When an API element was added and deprecated.
final class ApiHistory {
  const ApiHistory(this.since, this.deprecated);

  final ApiLevel since;
  final ApiLevel? deprecated;

  bool deprecatedAtOrBefore(ApiLevel level) {
    final deprecated = this.deprecated;
    return deprecated != null && deprecated <= level;
  }
}

/// A method entry from `api-versions.xml`, keyed by its JVM signature.
final class MethodHistory {
  const MethodHistory(this.name, this.arity, this.history);

  final String name;
  final int arity;
  final ApiHistory history;
}

/// API levels of every class and member, read from the SDK's
/// `data/api-versions.xml`.
final class ApiLevels {
  ApiLevels._(this._classes, this._fields, this._methods);

  factory ApiLevels.load(File file) {
    final classes = <String, ApiHistory>{};
    final fields = <String, ApiHistory>{};
    final methods = <String, List<MethodHistory>>{};
    final document = XmlDocument.parse(file.readAsStringSync());
    for (final element in document.rootElement.findElements('class')) {
      final className = element.getAttribute('name')!.replaceAll('/', '.');
      final classHistory = _history(element, null);
      classes[className] = classHistory;
      for (final member in element.childElements) {
        final name = member.getAttribute('name');
        if (name == null) continue;
        final history = _history(member, classHistory);
        switch (member.name.local) {
          case 'field':
            fields['$className#$name'] = history;
          case 'method':
            final methodName = name.substring(0, name.indexOf('('));
            final arity = _arity(name);
            methods
                .putIfAbsent('$className#$methodName', () => [])
                .add(MethodHistory(methodName, arity, history));
        }
      }
    }
    return ApiLevels._(classes, fields, methods);
  }

  final Map<String, ApiHistory> _classes;
  final Map<String, ApiHistory> _fields;
  final Map<String, List<MethodHistory>> _methods;

  Iterable<String> get classNames => _classes.keys;

  ApiHistory? classHistory(String binaryName) => _classes[binaryName];

  ApiHistory? fieldHistory(String binaryName, String field) =>
      _fields['$binaryName#$field'];

  /// Every overload of [name] in [binaryName] that takes [arity] arguments.
  List<MethodHistory> overloads(String binaryName, String name, int arity) => [
    for (final method
        in _methods['$binaryName#$name'] ?? const <MethodHistory>[])
      if (method.arity == arity) method,
  ];

  static ApiHistory _history(XmlElement element, ApiHistory? parent) {
    final since = element.getAttribute('since');
    final deprecated = element.getAttribute('deprecated');
    return ApiHistory(
      since != null
          ? ApiLevel.parse(since)
          : parent?.since ?? const ApiLevel(1),
      deprecated != null ? ApiLevel.parse(deprecated) : parent?.deprecated,
    );
  }

  static int _arity(String signature) {
    final params = signature.substring(
      signature.indexOf('(') + 1,
      signature.indexOf(')'),
    );
    var count = 0;
    for (var i = 0; i < params.length; i++) {
      while (params[i] == '[') {
        i++;
      }
      if (params[i] == 'L') i = params.indexOf(';', i);
      count++;
    }
    return count;
  }
}
