import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:ffigen/ffigen.dart';

/// Why a declaration or member is left out of Layer 1.
enum IosOmission {
  nonBluetooth('non-Bluetooth technology; kept as a type when referenced'),
  systemCreated('allocator of an object only the system creates');

  const IosOmission(this.reason);

  final String reason;
}

typedef IosOmitted = ({
  String declaration,
  String member,
  IosOmission omission,
});

/// The rules that decide what the iOS half of Layer 1 exposes.
///
/// FFIgen already omits every API deprecated at or before the minimum iOS
/// version (`externalVersions`) and generates runtime version checks for
/// newer ones. These rules add scope and the remaining omissions.
final class IosExposureRules {
  IosExposureRules({this.systemCreated = const {}});

  /// Classes whose initializers are all unavailable, such as `CBPeripheral`
  /// or `CBATTRequest`. Found by [findSystemCreated] on a first pass.
  final Set<String> systemCreated;

  /// Frameworks that make up the Bluetooth surface, with their prefixes.
  static const frameworks = {
    'CoreBluetooth': 'CB',
    'AccessorySetupKit': 'AS',
    'ExternalAccessory': 'EA',
  };

  /// Declarations an app must use to drive Bluetooth objects and that
  /// `package:objective_c` does not provide: peripheral identifiers, the run
  /// loop mode L2CAP streams are scheduled in, the notifications that report
  /// ExternalAccessory connections, and the product images of the
  /// AccessorySetupKit picker.
  static const supportDeclarations = {
    'NSUUID',
    'NSRunLoopCommonModes',
    'NSNotificationCenter',
    'NSNotification',
    'UIImage',
  };

  static const _allocators = {'alloc', 'allocWithZone:', 'new'};
  static final _nonBluetooth = RegExp('WiFi');

  final omitted = <IosOmitted>[];
  final included = <String, String>{};

  bool _inScope(String name) =>
      supportDeclarations.contains(name) ||
      (frameworks.values.any(name.startsWith) && !_isNonBluetooth(name));

  bool _isNonBluetooth(String name) {
    if (!frameworks.values.any(name.startsWith)) return false;
    return _nonBluetooth.hasMatch(name);
  }

  List<Visitor> get visitors => [
    Visitor(
      objCInterface: (node) {
        node.isIncluded = _decide(node.originalName, 'interface');
        if (node.isIncluded) _applyToInterface(node);
      },
      objCProtocol: (node) =>
          node.isIncluded = _decide(node.originalName, 'protocol'),
      objCCategory: (node) =>
          node.isIncluded = _inScope(node.interface.originalName),
      enumClass: (node) => node.isIncluded = _decide(node.originalName, 'enum'),
      global: (node) => node.isIncluded = _decide(node.originalName, 'global'),
      unnamedEnumConstant: (node) =>
          node.isIncluded = _decide(node.originalName, 'constant'),
      macroConstant: (node) =>
          node.isIncluded = _decide(node.originalName, 'constant'),
      typealias: (node) {
        if (_decide(node.originalName, 'typealias')) {
          node.isIncluded = TypealiasInclude.always;
        }
      },
    ),
  ];

  bool _decide(String name, String kind) {
    if (_isNonBluetooth(name)) {
      omitted.add((
        declaration: name,
        member: '*',
        omission: IosOmission.nonBluetooth,
      ));
    }
    final include = _inScope(name);
    if (include) included.putIfAbsent(name, () => kind);
    return include;
  }

  void _applyToInterface(ObjCInterface node) {
    if (!systemCreated.contains(node.originalName)) return;
    for (final method in node.methods) {
      if (!_allocators.contains(method.originalName)) continue;
      method.isIncluded = false;
      omitted.add((
        declaration: node.originalName,
        member: method.originalName,
        omission: IosOmission.systemCreated,
      ));
    }
  }
}

/// Finds the generated classes that have no initializer.
///
/// FFIgen drops unavailable initializers after visitors run, so this reads
/// the output of a first pass.
Set<String> findSystemCreated(String bindings) {
  final unit = parseString(content: bindings, throwIfDiagnostics: false).unit;
  final initializers = <String>{};
  final classes = <String>{};
  for (final declaration in unit.declarations) {
    switch (declaration) {
      case ExtensionTypeDeclaration(:final namePart, :final body)
          when body.members.whereType<MethodDeclaration>().any(
            (m) => m.name.lexeme == 'alloc',
          ):
        classes.add(namePart.typeName.lexeme);
      case ExtensionDeclaration(:final onClause?, :final body)
          when body.members.whereType<MethodDeclaration>().any(
            (m) => m.name.lexeme.startsWith('init'),
          ):
        initializers.add(onClause.extendedType.toSource());
      default:
    }
  }
  return classes.difference(initializers);
}
