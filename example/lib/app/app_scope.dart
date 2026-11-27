import 'package:flutter/widgets.dart';

import '../bluetooth/scanner.dart';

/// App-wide objects that live as long as the app.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.scanner, required super.child});

  final Scanner scanner;

  static AppScope of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!;

  @override
  bool updateShouldNotify(AppScope oldWidget) => scanner != oldWidget.scanner;
}
