import 'package:flutter/material.dart';

ThemeData stimaTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: const Color(0xff004532),
        brightness: brightness,
      ).copyWith(
        primary: dark ? const Color(0xff8bd6b6) : const Color(0xff004532),
        onPrimary: dark ? const Color(0xff002116) : Colors.white,
        primaryContainer: dark
            ? const Color(0xff0f7a5d)
            : const Color(0xff065f46),
        onPrimaryContainer: dark
            ? const Color(0xffe3fff1)
            : const Color(0xff8bd6b6),
        secondary: dark ? const Color(0xffc07a71) : const Color(0xff904a45),
        secondaryContainer: dark
            ? const Color(0xff5f302d)
            : const Color(0xfffda49c),
        onSecondaryContainer: dark
            ? const Color(0xfff6d0cc)
            : const Color(0xff783733),
        tertiary: dark ? const Color(0xffe6b44c) : const Color(0xff92400e),
        tertiaryContainer: dark
            ? const Color(0xff3b2d10)
            : const Color(0xfffef3c7),
        onTertiaryContainer: dark
            ? const Color(0xffe6b44c)
            : const Color(0xff92400e),
        surface: dark ? const Color(0xff0b1013) : const Color(0xfff0f4f8),
        surfaceContainerLowest: dark ? const Color(0xff182128) : Colors.white,
        surfaceContainerLow: dark
            ? const Color(0xff121920)
            : const Color(0xffe2e8f0),
        surfaceContainer: dark
            ? const Color(0xff182128)
            : const Color(0xffdbe4ee),
        surfaceContainerHigh: dark
            ? const Color(0xff0f161b)
            : const Color(0xffcbd5e1),
        surfaceContainerHighest: dark
            ? const Color(0xff202830)
            : const Color(0xffb8c9dc),
        onSurface: dark ? const Color(0xffeef2ef) : const Color(0xff0d1c2e),
        onSurfaceVariant: dark
            ? const Color(0xffb5beb8)
            : const Color(0xff3f4944),
        outline: dark ? const Color(0xff7f8a84) : const Color(0xff6f7973),
        outlineVariant: dark
            ? const Color(0xff5b6761)
            : const Color(0xffbec9c2),
        error: dark ? const Color(0xffffb4ab) : const Color(0xffba1a1a),
        errorContainer: dark
            ? const Color(0xff4a1f1c)
            : const Color(0xffffdad6),
        onErrorContainer: dark
            ? const Color(0xffffb4ab)
            : const Color(0xffba1a1a),
      );
  const documentShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(12)),
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: documentShape,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: documentShape,
        // Use the darker existing container for white labels, while text actions
        // use the lighter primary role against dark surfaces.
        backgroundColor: dark ? scheme.primaryContainer : scheme.primary,
        foregroundColor: Colors.white,
        textStyle: base.textTheme.labelLarge?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
  );
}
