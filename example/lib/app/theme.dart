import 'package:material_ui/material_ui.dart';

abstract final class RadarColors {
  static const background = Color(0xff060b0a);
  static const surface = Color(0xff0e1614);
  static const grid = Color(0xff1d3b33);
  static const sweep = Color(0xff35f0a8);
  static const text = Color(0xffe3f2ec);
  static const muted = Color(0xff7d9990);
  static const warm = Color(0xffff7a45);
  static const cold = Color(0xff4aa8ff);
  static const chromaKey = Color(0xff00b140);
}

abstract final class RadarTheme {
  static const monospace = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: ['Menlo', 'Courier New'],
    fontSize: 13,
    height: 1.45,
  );

  static ThemeData get dark {
    final scheme = ColorScheme.fromSeed(
      seedColor: RadarColors.sweep,
      brightness: Brightness.dark,
      surface: RadarColors.surface,
      primary: RadarColors.sweep,
    );
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: RadarColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: RadarColors.background,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: RadarColors.surface,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: RadarColors.surface,
        showDragHandle: true,
      ),
      cardTheme: CardThemeData(
        color: RadarColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
