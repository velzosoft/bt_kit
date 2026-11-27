import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

import 'callback_classes.dart';

/// Builds the `implement` factory added to each callback class.
///
/// The handler types are copied from the listener bindings JNIgen generated
/// for the adapters, so they always match the generated code.
Map<String, String> callbackFacades(
  String generatedBindings,
  List<CallbackClass> classes,
) {
  final unit = parseString(
    content: generatedBindings,
    throwIfDiagnostics: false,
  ).unit;
  final listeners = {
    for (final declaration in unit.declarations.whereType<ClassDeclaration>())
      declaration.namePart.typeName.lexeme: declaration,
  };
  return {
    for (final c in classes)
      c.binaryName: _facade(
        c,
        _handlers(listeners['\$${c.adapterName}\$Listener']!),
      ),
  };
}

final class _Handler {
  _Handler(this.name, this.type, this.arity);

  final String name;
  final String type;
  final int arity;

  String get noop => '(${List.filled(arity, '_').join(', ')}) {}';
}

List<_Handler> _handlers(ClassDeclaration listener) {
  final factory = listener.body.members
      .whereType<ConstructorDeclaration>()
      .single;
  return [
    for (final parameter in factory.parameters.parameters)
      if (parameter.name!.lexeme case final name when !name.endsWith(r'$async'))
        if (_functionType(parameter) case final type?)
          _Handler(name, type.toSource(), type.parameters.parameters.length),
  ];
}

GenericFunctionType? _functionType(FormalParameter parameter) =>
    switch (parameter.type) {
      final GenericFunctionType type => type,
      _ => null,
    };

String _facade(CallbackClass c, List<_Handler> handlers) {
  final adapter = c.adapterName;
  final params = handlers.map((h) => '    ${h.type}? ${h.name},').join('\n');
  final listener = [
    '\$$adapter\$Listener(',
    for (final h in handlers) ...[
      '      ${h.name}: ${h.name} ?? ${h.noop},',
      '      ${h.name}\$async: true,',
    ],
    '    )',
  ].join('\n');
  final implementation = '$adapter\$Listener.implement(\n$listener,\n  )';
  if (c.isService) {
    return '''

  /// Installs Dart handlers for the manifest-declared
  /// `${c.adapterBinaryName}` service.
  ///
  /// Handlers are optional and run asynchronously on the calling isolate.
  /// Events that arrive while no Flutter engine is running are dropped.
  static void implement({
$params
  }) => $adapter.install(
    $implementation,
  );

  /// The service instance the system is running, if any.
  static ${c.dartName}? get running => $adapter.current();
''';
  }
  return '''

  /// Implements [${c.dartName}] with Dart handlers.
  ///
  /// Handlers are optional and run asynchronously on the calling isolate.
  /// They stay alive for as long as Java references the returned object.
  factory ${c.dartName}.implement({
$params
  }) => $adapter(
    $implementation,
  );
''';
}
