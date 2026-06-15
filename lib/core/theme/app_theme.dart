// In Flutter 3.44 the compiler needs this import for
// CupertinoPageTransitionsBuilder (moved out of the Material library),
// while the analyzer still thinks Material provides it — keep the import
// and silence the false-positive lint.
// ignore: unused_import, unnecessary_import
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // iOS 26 "Liquid Glass" palette. Names kept from the previous themes so
  // existing call sites don't need to change.
  static const Color wine = Color(0xFF0B0D12);       // ink: headers, primary text
  static const Color deepMauve = Color(0xFF0A84FF);  // tint: primary accent, active elements
  static const Color midMauve = Color(0x9E3C3C43);   // secondary label (62%)
  static const Color softMauve = Color(0x613C3C43);  // tertiary label (38%)
  static const Color paleMauve = Color(0x296E7A96);  // soft fills, ring tracks (16%)

  // Neutrals
  static const Color pageBg = Color(0xFFF3F4F8);     // base background
  static const Color cardBg = Color(0xFFFFFFFF);     // solid white surfaces

  // Semantic accents (iOS system colors)
  static const Color gold = Color(0xFFFF9F0A);       // systemOrange — caution/warning
  static const Color success = Color(0xFF30D158);    // mint — "good"
  static const Color danger = Color(0xFFFF453A);     // systemRed — destructive

  // Extra Liquid Glass tints
  static const Color tintDeep = Color(0xFF0066DD);   // deep blue for links/values
  static const Color ice = Color(0xFF64D2FF);        // ice blue highlight

  // Hairlines and borders
  static const Color separator = Color(0x243C3C43);  // hairline (14%)
  static const Color border = Color(0xFFD1D1D6);     // stronger outline
}

class AppTheme {
  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: AppColors.wine,
      displayColor: AppColors.wine,
    );

    return base.copyWith(
      scaffoldBackgroundColor: AppColors.pageBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.deepMauve,
        primary: AppColors.deepMauve,
        secondary: AppColors.midMauve,
        surface: AppColors.cardBg,
        onPrimary: Colors.white,
        onSurface: AppColors.wine,
        error: AppColors.danger,
        brightness: Brightness.light,
      ),
      // Smooth, modern screen transitions on every platform.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.pageBg,
        foregroundColor: AppColors.wine,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true, // iOS-style centered titles
        titleTextStyle: GoogleFonts.inter(
          color: AppColors.wine,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: const IconThemeData(color: AppColors.deepMauve),
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.separator, width: 0.5),
        ),
        margin: EdgeInsets.zero,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.cardBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        titleTextStyle: GoogleFonts.inter(
          color: AppColors.wine,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: GoogleFonts.inter(
          color: AppColors.midMauve,
          fontSize: 14,
          height: 1.4,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.cardBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        showDragHandle: false,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.wine,
        contentTextStyle: GoogleFonts.inter(color: Colors.white, fontSize: 13.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.deepMauve,
      ),
      // iOS 26 buttons: tinted capsules.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.deepMauve,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.paleMauve,
          disabledForegroundColor: AppColors.softMauve,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: const StadiumBorder(),
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.deepMauve,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: const StadiumBorder(),
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      // iOS "gray" secondary button: soft fill, blue label, no hard border.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.deepMauve,
          backgroundColor: AppColors.cardBg,
          side: const BorderSide(color: AppColors.border, width: 0.8),
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: const StadiumBorder(),
          textStyle: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.deepMauve,
          textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
      // iOS-style text fields: borderless soft-gray fills.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.paleMauve,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: AppColors.deepMauve, width: 1.4),
        ),
        labelStyle: const TextStyle(color: AppColors.midMauve),
        hintStyle: const TextStyle(color: AppColors.softMauve),
        prefixIconColor: AppColors.midMauve,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.cardBg,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.paleMauve,
        height: 68,
        elevation: 0,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.deepMauve
                : AppColors.softMauve,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => GoogleFonts.inter(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? AppColors.deepMauve
                : AppColors.softMauve,
          ),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.cardBg,
        selectedItemColor: AppColors.deepMauve,
        unselectedItemColor: AppColors.softMauve,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        unselectedLabelStyle: TextStyle(fontSize: 10),
      ),
      textTheme: textTheme,
      dividerColor: AppColors.separator,
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: AppColors.paleMauve,
        labelStyle: const TextStyle(color: AppColors.wine, fontSize: 12),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}
