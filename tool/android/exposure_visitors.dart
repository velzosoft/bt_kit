import 'package:jnigen/jnigen.dart';

import 'exposure_rules.dart';

/// A member left out of the bindings, for the inventory.
typedef OmittedMember = ({String className, String member, Omission omission});

/// Applies [AndroidExposureRules] through JNIgen's visitor API.
///
/// JNIgen's visitors expose names but not signatures. The first visitor
/// records each method's arity from its parameters; the second applies the
/// rules once every arity is known.
final class ExposureVisitors {
  ExposureVisitors(
    this.rules, {
    required this.finalClasses,
    required this.forwardedCallbacks,
  });

  final AndroidExposureRules rules;
  final Set<String> finalClasses;

  /// `binaryName#name/arity` of every callback an adapter forwards.
  final Set<String> forwardedCallbacks;

  final omitted = <OmittedMember>[];
  final typeOnlyClasses = <String>{};
  final _methods = <_MethodRef>[];

  List<Visitor> get visitors => [_ArityCollector(_methods), _RuleApplier(this)];

  void _applyToMethods() {
    for (final ref in _methods) {
      if (!rules.isInScope(ref.className)) continue;
      final name = ref.method.originalName;
      final omission = rules.methodOmission(
        ref.className,
        name,
        ref.arity,
        isFinalClass: finalClasses.contains(ref.className),
        isForwardedCallback: forwardedCallbacks.contains(
          '${ref.className}#$name/${ref.arity}',
        ),
      );
      if (omission == null) continue;
      ref.method.isIncluded = false;
      omitted.add((
        className: ref.className,
        member: '$name/${ref.arity}',
        omission: omission,
      ));
    }
  }
}

final class _MethodRef {
  _MethodRef(this.className, this.method);

  final String className;
  final Method method;
  int arity = 0;
}

final class _ArityCollector extends Visitor {
  _ArityCollector(this._methods) : super.base();

  final List<_MethodRef> _methods;
  var _className = '';

  @override
  void visitClass(ClassDecl c) => _className = c.binaryName;

  @override
  void visitMethod(Method method) =>
      _methods.add(_MethodRef(_className, method));

  @override
  void visitParam(Param parameter) => _methods.last.arity++;
}

final class _RuleApplier extends Visitor {
  _RuleApplier(this._owner) : super.base();

  final ExposureVisitors _owner;
  var _methodsApplied = false;
  var _className = '';

  @override
  void visitClass(ClassDecl c) {
    if (!_methodsApplied) {
      _methodsApplied = true;
      _owner._applyToMethods();
    }
    _className = c.binaryName;
    if (!_owner.rules.isInScope(_className)) return;
    if (_owner.rules.classExposure(_className) == Exposure.typeOnly) {
      c.isIncluded = false;
      _owner.typeOnlyClasses.add(_className);
    }
  }

  @override
  void visitField(Field field) {
    if (!_owner.rules.isInScope(_className)) return;
    final omission = _owner.rules.fieldOmission(_className, field.originalName);
    if (omission == null) return;
    field.isIncluded = false;
    _owner.omitted.add((
      className: _className,
      member: field.originalName,
      omission: omission,
    ));
  }
}
