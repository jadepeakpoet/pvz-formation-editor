import 'dart:io';
import 'package:flutter/material.dart';

/// Windows uses an explicit CJK UI font instead of platform fallback at tiny sizes.
ThemeData buildAppTheme({
  bool useMaterial3 = true,
  ColorScheme? colorScheme,
  Color? scaffoldBackgroundColor,
  InputDecorationTheme? inputDecorationTheme,
}) {
  final windows = Platform.isWindows;
  final theme = ThemeData(
    useMaterial3: useMaterial3,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: scaffoldBackgroundColor,
    inputDecorationTheme: inputDecorationTheme,
    fontFamily: windows ? 'Microsoft YaHei UI' : null,
    fontFamilyFallback: windows ? const ['Microsoft YaHei', 'Segoe UI'] : null,
  );
  if (!windows) return theme;
  return theme.copyWith(
    textTheme: _readableText(theme.textTheme),
    primaryTextTheme: _readableText(theme.primaryTextTheme),
  );
}

TextTheme _readableText(TextTheme text) => text.copyWith(
      bodyLarge: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
      bodyMedium: text.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
      bodySmall: text.bodySmall?.copyWith(fontWeight: FontWeight.w500),
      labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      labelMedium: text.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      labelSmall: text.labelSmall?.copyWith(fontWeight: FontWeight.w600),
    );
