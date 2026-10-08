import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'colors.dart';

/// Neo-Brutalist Material 3 teması — Syne display, night zemin.
abstract final class AppTheme {
  static ThemeData get dark {
    final textTheme = GoogleFonts.syneTextTheme(
      ThemeData.dark().textTheme,
    ).apply(
      bodyColor: NoolColors.white,
      displayColor: NoolColors.white,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: NoolColors.night,
      colorScheme: const ColorScheme.dark(
        surface: NoolColors.night,
        primary: NoolColors.acid,
        onPrimary: NoolColors.ink,
        secondary: NoolColors.tangerine,
        onSecondary: NoolColors.ink,
        tertiary: NoolColors.lavender,
        onSurface: NoolColors.white,
        outline: NoolColors.ink,
      ),
      textTheme: textTheme.copyWith(
        displayLarge: textTheme.displayLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -1.5,
          color: NoolColors.white,
        ),
        displayMedium: textTheme.displayMedium?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: -1.2,
          color: NoolColors.white,
        ),
        displaySmall: textTheme.displaySmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          color: NoolColors.white,
        ),
        headlineLarge: textTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: NoolColors.white,
        ),
        headlineMedium: textTheme.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: NoolColors.white,
        ),
        titleLarge: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: NoolColors.white,
        ),
        bodyLarge: textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w500,
          color: NoolColors.white,
        ),
        bodyMedium: textTheme.bodyMedium?.copyWith(
          color: NoolColors.lavender,
        ),
        labelLarge: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: NoolColors.ink,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: NoolColors.acid,
          foregroundColor: NoolColors.ink,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: const BorderSide(color: NoolColors.ink, width: 3.5),
          ),
          textStyle: GoogleFonts.syne(
            fontWeight: FontWeight.w800,
            fontSize: 16,
            letterSpacing: 0.3,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: NoolColors.white,
          backgroundColor: NoolColors.night,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          side: const BorderSide(color: NoolColors.ink, width: 3.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          textStyle: GoogleFonts.syne(
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: NoolColors.night,
        foregroundColor: NoolColors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.syne(
          fontWeight: FontWeight.w800,
          fontSize: 22,
          color: NoolColors.white,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: NoolColors.acid,
        contentTextStyle: GoogleFonts.syne(
          color: NoolColors.ink,
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(2),
          side: const BorderSide(color: NoolColors.ink, width: 3),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}

/// Neo-Brutalist buton gölgesi — blur yok, sert offset.
class BrutalShadow extends StatelessWidget {
  const BrutalShadow({
    super.key,
    required this.child,
    this.offset = const Offset(4, 4),
    this.color = NoolColors.ink,
  });

  final Widget child;
  final Offset offset;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: color,
            offset: offset,
            blurRadius: 0,
            spreadRadius: 0,
          ),
        ],
      ),
      child: child,
    );
  }
}
