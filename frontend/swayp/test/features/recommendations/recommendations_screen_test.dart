import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:swayp/core/errors/app_exception.dart';
import 'package:swayp/data/repositories/domain_repository.dart';
import 'package:swayp/domain/models/domain.dart';
import 'package:swayp/domain/models/item.dart';
import 'package:swayp/features/recommendations/deck_provider.dart';
import 'package:swayp/features/recommendations/recommendations_screen.dart';

const _games = Domain(code: 'games', displayName: 'Videojuegos');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('estado loading muestra un indicador de progreso', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          domainsProvider.overrideWith((ref) => Future.value(const [_games])),
          deckProvider.overrideWithBuild((ref, notifier) => Completer<List<Item>>().future),
        ],
        child: const MaterialApp(home: RecommendationsScreen()),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('estado error muestra el mensaje y un botón de reintentar', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          domainsProvider.overrideWith((ref) => Future.value(const [_games])),
          deckProvider.overrideWithBuild(
            (ref, notifier) => Future<List<Item>>.error(
              const AppException(code: 'NETWORK_ERROR', message: 'No hay conexión'),
            ),
          ),
        ],
        child: const MaterialApp(home: RecommendationsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No hay conexión'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Reintentar'), findsOneWidget);
  });

  testWidgets('estado data con lista vacía muestra el mensaje de mazo agotado', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          domainsProvider.overrideWith((ref) => Future.value(const [_games])),
          deckProvider.overrideWithBuild((ref, notifier) => Future.value(const <Item>[])),
        ],
        child: const MaterialApp(home: RecommendationsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No hay más obras por ahora en este dominio'), findsOneWidget);
  });

  testWidgets('estado data con ítems muestra solo la carta superior', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          domainsProvider.overrideWith((ref) => Future.value(const [_games])),
          deckProvider.overrideWithBuild(
            (ref, notifier) => Future.value(const [
              Item(itemId: 1, title: 'Dark Souls', imageUrl: null, externalUrl: null),
              Item(itemId: 2, title: 'Cuphead', imageUrl: null, externalUrl: null),
            ]),
          ),
        ],
        child: const MaterialApp(home: RecommendationsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dark Souls'), findsOneWidget);
    expect(find.text('Cuphead'), findsNothing);
  });
}
