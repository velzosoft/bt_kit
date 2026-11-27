// ignore_for_file: implementation_imports

import 'package:jnigen/src/elements/elements.dart' as ast;

import 'exposure_rules.dart';

/// A Java class that apps subclass to receive events, such as
/// `BluetoothGattCallback` or `BroadcastReceiver`.
///
/// Dart cannot subclass Java classes, so each one gets a generated Java
/// adapter that forwards its callbacks to a listener interface Dart
/// implements.
final class CallbackClass {
  CallbackClass(this.decl, this.callbacks, {required this.isService});

  static const adapterPackage = 'dev.btkit.adapters';

  final ast.ClassDecl decl;
  final List<ast.Method> callbacks;

  /// Services are created by the system, so their adapter reads a static
  /// listener instead of taking one in its constructor.
  final bool isService;

  String get binaryName => decl.binaryName;

  String get dartName => binaryName.split('.').last;

  String get adapterName => '${dartName.replaceAll(r'$', '')}Adapter';

  String get adapterBinaryName => '$adapterPackage.$adapterName';

  static List<CallbackClass> find(
    ast.Classes classes,
    AndroidExposureRules rules,
  ) => [
    for (final decl in classes.decls.values)
      if (_isSubclassable(decl, rules))
        if (_callbacks(decl, rules) case final callbacks
            when callbacks.isNotEmpty)
          CallbackClass(decl, callbacks, isService: _isService(decl)),
  ]..sort((a, b) => a.binaryName.compareTo(b.binaryName));

  static bool _isSubclassable(ast.ClassDecl decl, AndroidExposureRules rules) =>
      decl.declKind == ast.DeclKind.classKind &&
      decl.modifiers.containsAll(const {'public', 'abstract'}) &&
      rules.classExposure(decl.binaryName) == Exposure.full &&
      decl.methods.any(
        (m) => m.isConstructor && !m.modifiers.contains('private'),
      );

  static List<ast.Method> _callbacks(
    ast.ClassDecl decl,
    AndroidExposureRules rules,
  ) => [
    for (final method in decl.methods)
      if (isCallback(method) &&
          rules.includesMethod(
            decl.binaryName,
            method.name,
            method.params.length,
          ))
        method,
  ];

  /// A public, overridable `void onXxx(...)` method.
  static bool isCallback(ast.Method method) =>
      method.isPublic &&
      !method.isStatic &&
      !method.isFinal &&
      !method.isConstructor &&
      method.returnType.name == 'void' &&
      RegExp('^on[A-Z]').hasMatch(method.name);

  static bool _isService(ast.ClassDecl decl) => switch (decl.superclass) {
    ast.DeclaredType(binaryName: 'android.app.Service') => true,
    _ => false,
  };
}
