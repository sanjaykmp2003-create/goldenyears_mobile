import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens copied 1:1 from the web console's styles.css (:root variables).
class C {
  static const green = Color(0xFF6FA32B);
  static const greenDk = Color(0xFF5A8722);
  static const greenLt = Color(0xFFE9F2D8);
  static const navy = Color(0xFF004890);
  static const navyDk = Color(0xFF00356B);
  static const navyLt = Color(0xFFDDE8F3);
  static const blue = Color(0xFF0090D8);
  static const blueLt = Color(0xFFD6EEFB);
  static const red = Color(0xFFD81818);
  static const redLt = Color(0xFFFAE0E0);
  static const redDk = Color(0xFFB51414);
  static const amber = Color(0xFFD98A1F);
  static const amberLt = Color(0xFFF7E7CB);
  static const purple = Color(0xFF6B4EA3);
  static const purpleLt = Color(0xFFE7E0F3);
  static const ink = Color(0xFF1B2430);
  static const ink2 = Color(0xFF48566A);
  static const ink3 = Color(0xFF7A8699);
  static const bg = Color(0xFFF4F6F4);
  static const surface = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFF9FAF8);
  static const line = Color(0xFFE3E7E3);
  static const line2 = Color(0xFFEEF1EE);
  static const radius = 14.0;

  static const shadowSm = [
    BoxShadow(color: Color(0x0F102018), blurRadius: 3, offset: Offset(0, 1)),
  ];
}

/// Headings use Newsreader (serif), body uses Inter - same pairing as the web app.
TextStyle serif(double size, {FontWeight w = FontWeight.w600, Color color = C.ink}) =>
    GoogleFonts.newsreader(fontSize: size, fontWeight: w, color: color, letterSpacing: -0.2);

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: C.green,
      primary: C.green,
      onPrimary: Colors.white,
      secondary: C.navy,
      surface: C.surface,
      error: C.red,
    ),
    scaffoldBackgroundColor: C.bg,
  );
  final text = GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: C.ink, displayColor: C.ink);
  return base.copyWith(
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: C.surface,
      foregroundColor: C.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: const Border(bottom: BorderSide(color: C.line)),
      titleTextStyle: serif(19),
    ),
    dividerTheme: const DividerThemeData(color: C.line, space: 1, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      labelStyle: const TextStyle(color: C.ink2, fontSize: 13, fontWeight: FontWeight.w500),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: C.line)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: C.line)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: const BorderSide(color: C.green, width: 1.4)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.green,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.ink2,
        side: const BorderSide(color: C.line),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: C.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: C.greenLt,
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
            fontSize: 11.5,
            fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
            color: s.contains(WidgetState.selected) ? C.greenDk : C.ink3,
          )),
      iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(color: s.contains(WidgetState.selected) ? C.greenDk : C.ink3)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: C.ink,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}
