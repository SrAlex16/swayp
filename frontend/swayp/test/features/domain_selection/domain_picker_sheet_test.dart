import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:swayp/core/errors/app_exception.dart';
import 'package:swayp/data/repositories/domain_repository.dart';
import 'package:swayp/domain/models/domain.dart';
import 'package:swayp/features/domain_selection/current_domain_provider.dart';
import 'package:swayp/features/domain_selection/domain_picker_sheet.dart';

const _games = Domain(code: 'games', displayName: 'Videojuegos');
const _movies = Domain(code: 'movies', displayName: 'Películas');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('estado loading muestra un indicador de progreso', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [domainsProvider.overrideWith((ref) => Completer<List<Domain>>().future)],
        child: const MaterialApp(home: Scaffold(body: DomainPickerSheet())),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('estado error muestra el mensaje y un botón de reintentar', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          domainsProvider.overrideWith(
            (ref) => Future<List<Domain>>.error(
              const AppException(code: 'NETWORK_ERROR', message: 'No hay conexión'),
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: DomainPickerSheet())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No hay conexión'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Reintentar'), findsOneWidget);
  });

  testWidgets('estado data muestra un ítem de lista por dominio con su display_name', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          domainsProvider.overrideWith((ref) => Future.value(const [_games, _movies])),
        ],
        child: const MaterialApp(home: Scaffold(body: DomainPickerSheet())),
      ),
    );
    await tester.pump();

    expect(find.text('Videojuegos'), findsOneWidget);
    expect(find.text('Películas'), findsOneWidget);
  });

  testWidgets('tocar un dominio actualiza el dominio actual, lo persiste y cierra la hoja', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        domainsProvider.overrideWith((ref) => Future.value(const [_games, _movies])),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (context) => const DomainPickerSheet(),
                  ),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Elige un dominio'), findsOneWidget);

    await tester.tap(find.text('Películas'));
    await tester.pumpAndSettle();

    // La hoja se cerró.
    expect(find.text('Elige un dominio'), findsNothing);

    final currentDomain = await container.read(currentDomainProvider.future);
    expect(currentDomain?.code, 'movies');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('current_domain_code'), 'movies');
  });
}
