import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:swayp/data/repositories/domain_repository.dart';
import 'package:swayp/data/repositories/profile_repository.dart';
import 'package:swayp/data/repositories/ratings_repository.dart';
import 'package:swayp/domain/models/domain.dart';
import 'package:swayp/domain/models/explicit_preference.dart';
import 'package:swayp/domain/models/user_profile.dart';
import 'package:swayp/features/profile/profile_screen.dart';

const _games = Domain(code: 'games', displayName: 'Videojuegos');

typedef _UpdateProfileCall = ({int? age, String? gender});

class _FakeProfileRepository extends ProfileRepository {
  _FakeProfileRepository(super.ref, {this.onUpdateProfile});

  final void Function(_UpdateProfileCall call)? onUpdateProfile;

  @override
  Future<UserProfile> getProfile() async => const UserProfile(age: null, gender: null);

  @override
  Future<UserProfile> updateProfile({required int? age, required String? gender}) async {
    onUpdateProfile?.call((age: age, gender: gender));
    return UserProfile(age: age, gender: gender);
  }

  @override
  Future<List<ExplicitPreference>> getPreferences(String domainCode) async => const [];

  @override
  Future<List<ExplicitPreference>> updatePreferences(
    String domainCode,
    List<ExplicitPreference> preferences,
  ) async => preferences;
}

class _FakeRatingsRepository extends RatingsRepository {
  _FakeRatingsRepository(super.ref, {this.onReset});

  final VoidCallback? onReset;

  @override
  Future<int> resetRatings(String domainCode) async {
    onReset?.call();
    return 7;
  }
}

Future<void> _pumpProfileScreen(
  WidgetTester tester, {
  void Function(_UpdateProfileCall call)? onUpdateProfile,
  VoidCallback? onReset,
}) async {
  SharedPreferences.setMockInitialValues({});

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        domainsProvider.overrideWith((ref) => Future.value(const [_games])),
        profileRepositoryProvider.overrideWith(
          (ref) => _FakeProfileRepository(ref, onUpdateProfile: onUpdateProfile),
        ),
        ratingsRepositoryProvider.overrideWith(
          (ref) => _FakeRatingsRepository(ref, onReset: onReset),
        ),
      ],
      child: const MaterialApp(home: ProfileScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('validateAge', () {
    test('acepta el rango 1-120', () {
      expect(validateAge('1'), null);
      expect(validateAge('120'), null);
      expect(validateAge('30'), null);
    });

    test('vacío es válido (la edad es opcional)', () {
      expect(validateAge(''), null);
      expect(validateAge(null), null);
    });

    test('rechaza valores fuera de 1-120', () {
      expect(validateAge('0'), isNotNull);
      expect(validateAge('121'), isNotNull);
      expect(validateAge('-5'), isNotNull);
    });

    test('rechaza texto no numérico', () {
      expect(validateAge('treinta'), isNotNull);
    });
  });

  testWidgets(
    'el formulario de edad rechaza valores fuera de rango sin enviar nada al backend',
    (tester) async {
      final calls = <_UpdateProfileCall>[];
      await _pumpProfileScreen(tester, onUpdateProfile: calls.add);

      await tester.enterText(find.widgetWithText(TextFormField, 'Edad'), '999');
      await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
      await tester.pumpAndSettle();

      expect(find.text('La edad debe estar entre 1 y 120'), findsOneWidget);
      expect(calls, isEmpty);
    },
  );

  testWidgets('el formulario de edad guarda un valor válido', (tester) async {
    final calls = <_UpdateProfileCall>[];
    await _pumpProfileScreen(tester, onUpdateProfile: calls.add);

    await tester.enterText(find.widgetWithText(TextFormField, 'Edad'), '30');
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();

    expect(calls, [(age: 30, gender: null)]);
    expect(find.text('Perfil guardado'), findsOneWidget);
  });

  testWidgets('el diálogo de reset no borra nada con un solo tap (requiere confirmar)', (
    tester,
  ) async {
    var resetCalls = 0;
    await _pumpProfileScreen(tester, onReset: () => resetCalls++);

    // El botón vive al final de un ListView largo: hay que hacerlo visible
    // antes de poder tocarlo, ya que los slivers solo construyen lo que
    // entra (o está cerca de) el viewport.
    await tester.scrollUntilVisible(
      find.widgetWithText(OutlinedButton, 'Reiniciar recomendaciones de Videojuegos'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Reiniciar recomendaciones de Videojuegos'));
    await tester.pumpAndSettle();

    // El diálogo se abre, pero todavía no se ha borrado nada.
    expect(find.text('¿Reiniciar recomendaciones?'), findsOneWidget);
    expect(resetCalls, 0);

    // Cancelar tampoco borra nada.
    await tester.tap(find.widgetWithText(TextButton, 'Cancelar'));
    await tester.pumpAndSettle();

    expect(find.text('¿Reiniciar recomendaciones?'), findsNothing);
    expect(resetCalls, 0);
  });

  testWidgets('confirmar el diálogo de reset sí borra y muestra el deleted_count', (
    tester,
  ) async {
    var resetCalls = 0;
    await _pumpProfileScreen(tester, onReset: () => resetCalls++);

    // El botón vive al final de un ListView largo: hay que hacerlo visible
    // antes de poder tocarlo, ya que los slivers solo construyen lo que
    // entra (o está cerca de) el viewport.
    await tester.scrollUntilVisible(
      find.widgetWithText(OutlinedButton, 'Reiniciar recomendaciones de Videojuegos'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, 'Reiniciar recomendaciones de Videojuegos'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Reiniciar'));
    await tester.pumpAndSettle();

    expect(resetCalls, 1);
    expect(find.text('Se han borrado 7 valoraciones'), findsOneWidget);
  });
}
