import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

/// Adds a single `implement` factory to every generated protocol and returns
/// the updated bindings together with the protocols it covered.
///
/// FFIgen offers several ways to implement a protocol through its
/// `$Builder` class. Layer 1 exposes one: listener semantics, which are safe
/// whichever thread the system calls the delegate on.
({String source, List<String> protocols}) addDelegateFacades(String source) {
  final unit = parseString(content: source, throwIfDiagnostics: false).unit;
  final builders = {
    for (final declaration in unit.declarations.whereType<ClassDeclaration>())
      declaration.namePart.typeName.lexeme: declaration,
  };
  final insertions = <(int, String)>[];
  for (final type in unit.declarations.whereType<ExtensionTypeDeclaration>()) {
    final protocol = type.namePart.typeName.lexeme;
    final builder = builders['$protocol\$Builder'];
    final listener = builder?.body.members
        .whereType<MethodDeclaration>()
        .where((m) => m.name.lexeme == 'implementAsListener')
        .firstOrNull;
    if (listener == null) continue;
    final body = type.body as BlockClassBody;
    insertions.add((
      body.rightBracket.offset,
      _facade(protocol, listener.parameters!.parameters),
    ));
  }
  insertions.sort((a, b) => b.$1.compareTo(a.$1));
  var result = source;
  for (final (offset, text) in insertions) {
    result = result.replaceRange(offset, offset, text);
  }
  return (
    source: result,
    protocols: [
      for (final (_, text) in insertions)
        RegExp(r'static (\w+) implement\(').firstMatch(text)!.group(1)!,
    ],
  );
}

String _facade(String protocol, List<FormalParameter> parameters) {
  final handlers = parameters
      .where((p) => !p.name!.lexeme.startsWith(r'$'))
      .toList();
  final params = handlers.map((p) => '    ${p.toSource()},').join('\n');
  final args = handlers
      .map((p) => '    ${p.name!.lexeme}: ${p.name!.lexeme},')
      .join('\n');
  return '''

  /// Implements [$protocol] with Dart handlers.
  ///
  /// Handlers run asynchronously on this isolate, whichever thread the
  /// system calls them on. Delegate properties are weak: keep the returned
  /// object referenced for as long as it is in use.
  static $protocol implement({
$params
  }) => $protocol\$Builder.implementAsListener(
$args
  );
''';
}
