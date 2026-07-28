import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _themeModeKey = 'theme_mode';

String _encode(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'system',
  ThemeMode.light => 'light',
  ThemeMode.dark => 'dark',
};

ThemeMode _decode(String? value) => switch (value) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

/// Override manual del tema, sobre el `ThemeMode.system` implícito de
/// `main.dart`: persistido en `shared_preferences` como
/// 'system'/'light'/'dark' (cualquier otro valor, incluido ausente, cae a
/// 'system').
///
/// `Notifier` síncrono, no `AsyncNotifier`: `MaterialApp.router` necesita
/// un `ThemeMode` directo en `themeMode`, no un `AsyncValue` que desenvolver
/// en cada sitio que lo consuma. `build()` devuelve `ThemeMode.system` de
/// inmediato (mismo valor que ya se usaba antes de esto) y dispara la
/// lectura real de `shared_preferences` en segundo plano, corrigiendo el
/// estado en cuanto resuelve — como mucho un frame con el valor por
/// defecto antes de la lectura real, nunca una pantalla en blanco.
class AppThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _loadPersisted();
    return ThemeMode.system;
  }

  Future<void> _loadPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    if (!ref.mounted) return;
    state = _decode(prefs.getString(_themeModeKey));
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, _encode(mode));
  }
}

final themeModeProvider = NotifierProvider<AppThemeModeNotifier, ThemeMode>(
  AppThemeModeNotifier.new,
);
