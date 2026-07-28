import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:swayp/core/theme/theme_mode_provider.dart';

void main() {
  test('sin nada persistido, arranca en ThemeMode.system', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(themeModeProvider), ThemeMode.system);
  });

  test('con un valor persistido, lo recupera tras cargar en segundo plano', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Valor inicial síncrono, antes de que resuelva la lectura real.
    expect(container.read(themeModeProvider), ThemeMode.system);

    await Future<void>.delayed(Duration.zero);

    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test('un valor inválido guardado cae a system', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'algo-raro'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await Future<void>.delayed(Duration.zero);

    expect(container.read(themeModeProvider), ThemeMode.system);
  });

  test('setThemeMode actualiza el estado de inmediato y persiste', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(themeModeProvider.notifier).setThemeMode(ThemeMode.light);

    expect(container.read(themeModeProvider), ThemeMode.light);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('theme_mode'), 'light');
  });

  test('el valor persistido sobrevive a un nuevo container ("reapertura de la app")', () async {
    SharedPreferences.setMockInitialValues({});
    final firstContainer = ProviderContainer();
    await firstContainer
        .read(themeModeProvider.notifier)
        .setThemeMode(ThemeMode.dark);
    firstContainer.dispose();

    final secondContainer = ProviderContainer();
    addTearDown(secondContainer.dispose);
    // Primera lectura: dispara build() (síncrono, ThemeMode.system) y con
    // él _loadPersisted() en segundo plano — hay que esperar a que
    // resuelva antes de comprobar el valor corregido.
    secondContainer.read(themeModeProvider);
    await Future<void>.delayed(Duration.zero);

    expect(secondContainer.read(themeModeProvider), ThemeMode.dark);
  });
}
