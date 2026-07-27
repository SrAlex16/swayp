import 'package:flutter/material.dart';

/// Color semilla: coral intenso, no el azul por defecto de Material. Un
/// swipe de descubrimiento es una decisión instantánea (sí/no) — el coral
/// transmite esa energía/urgencia mejor que un azul neutro de "app
/// corporativa", y evita que Swayp se confunda visualmente con Material
/// Design sin personalizar.
const Color _seedColor = Color(0xFFFF5A5F);

/// Tema de la app (docs/ARCHITECTURE.md sección 4.2), Material 3 con esquema
/// de color generado desde [_seedColor].
class AppTheme {
  AppTheme._();

  static ThemeData get light =>
      ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: _seedColor));

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: _seedColor, brightness: Brightness.dark),
  );
}
