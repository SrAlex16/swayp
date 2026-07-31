import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:swayp/core/errors/app_exception.dart';
import 'package:swayp/data/repositories/domain_repository.dart';
import 'package:swayp/data/repositories/profile_repository.dart';
import 'package:swayp/domain/models/domain.dart';
import 'package:swayp/domain/models/explicit_preference.dart';
import 'package:swayp/domain/models/user_profile.dart';
import 'package:swayp/features/profile/profile_provider.dart';

const _games = Domain(code: 'games', displayName: 'Videojuegos');

typedef _UpdateProfileCall = ({int? age, String? gender});
typedef _UpdatePreferencesCall = ({String domainCode, List<ExplicitPreference> preferences});

class _FakeProfileRepository extends ProfileRepository {
  _FakeProfileRepository(
    super.ref, {
    UserProfile? initialProfile,
    List<ExplicitPreference>? initialPreferences,
    this.onUpdateProfile,
    this.updateProfileFailWith,
    this.onUpdatePreferences,
    this.updatePreferencesFailWith,
  }) : _profile = initialProfile ?? const UserProfile(age: null, gender: null),
       _preferences = initialPreferences ?? const [];

  UserProfile _profile;
  final List<ExplicitPreference> _preferences;
  final void Function(_UpdateProfileCall call)? onUpdateProfile;
  final AppException? updateProfileFailWith;
  final void Function(_UpdatePreferencesCall call)? onUpdatePreferences;
  final AppException? updatePreferencesFailWith;

  @override
  Future<UserProfile> getProfile() async => _profile;

  @override
  Future<UserProfile> updateProfile({required int? age, required String? gender}) async {
    onUpdateProfile?.call((age: age, gender: gender));
    if (updateProfileFailWith != null) throw updateProfileFailWith!;
    _profile = UserProfile(age: age, gender: gender);
    return _profile;
  }

  @override
  Future<List<ExplicitPreference>> getPreferences(String domainCode) async => _preferences;

  @override
  Future<List<ExplicitPreference>> updatePreferences(
    String domainCode,
    List<ExplicitPreference> preferences,
  ) async {
    onUpdatePreferences?.call((domainCode: domainCode, preferences: preferences));
    if (updatePreferencesFailWith != null) throw updatePreferencesFailWith!;
    return preferences;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ProfileNotifier', () {
    test('carga el perfil existente', () async {
      final container = ProviderContainer(
        overrides: [
          profileRepositoryProvider.overrideWith(
            (ref) => _FakeProfileRepository(
              ref,
              initialProfile: const UserProfile(age: 28, gender: 'no binario'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final profile = await container.read(profileProvider.future);

      expect(profile.age, 28);
      expect(profile.gender, 'no binario');
    });

    test('save() guarda y actualiza el estado', () async {
      final calls = <_UpdateProfileCall>[];
      final container = ProviderContainer(
        overrides: [
          profileRepositoryProvider.overrideWith(
            (ref) => _FakeProfileRepository(ref, onUpdateProfile: calls.add),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(profileProvider.future);

      final error = await container
          .read(profileProvider.notifier)
          .save(age: 30, gender: 'mujer');

      expect(error, null);
      expect(calls, [(age: 30, gender: 'mujer')]);
      expect(container.read(profileProvider).value?.age, 30);
      expect(container.read(profileProvider).value?.gender, 'mujer');
    });

    test('save() devuelve el AppException si falla y no cambia el estado', () async {
      final container = ProviderContainer(
        overrides: [
          profileRepositoryProvider.overrideWith(
            (ref) => _FakeProfileRepository(
              ref,
              initialProfile: const UserProfile(age: 20, gender: null),
              updateProfileFailWith: const AppException(code: 'NETWORK_ERROR', message: 'Sin conexión'),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(profileProvider.future);

      final error = await container.read(profileProvider.notifier).save(age: 99, gender: null);

      expect(error?.message, 'Sin conexión');
      expect(container.read(profileProvider).value?.age, 20);
    });
  });

  group('PreferencesNotifier', () {
    test('carga las preferencias del dominio activo', () async {
      final container = ProviderContainer(
        overrides: [
          domainsProvider.overrideWith((ref) => Future.value(const [_games])),
          profileRepositoryProvider.overrideWith(
            (ref) => _FakeProfileRepository(
              ref,
              initialPreferences: const [ExplicitPreference(tag: 'RPG', weight: 1)],
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final preferences = await container.read(preferencesProvider.future);

      expect(preferences.map((p) => p.tag), ['RPG']);
    });

    test('addPreference() añade con weight 1.0 y envía la lista completa', () async {
      final calls = <_UpdatePreferencesCall>[];
      final container = ProviderContainer(
        overrides: [
          domainsProvider.overrideWith((ref) => Future.value(const [_games])),
          profileRepositoryProvider.overrideWith(
            (ref) => _FakeProfileRepository(
              ref,
              initialPreferences: const [ExplicitPreference(tag: 'RPG', weight: 1)],
              onUpdatePreferences: calls.add,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(preferencesProvider.future);

      await container.read(preferencesProvider.notifier).addPreference('Terror');

      // ExplicitPreference no sobreescribe == (igual que el resto de modelos
      // de dominio de este proyecto, ver Item/Domain), así que se compara
      // por (tag, weight) en vez de por igualdad de objeto.
      expect(calls.length, 1);
      expect(calls.single.domainCode, 'games');
      expect(
        calls.single.preferences.map((p) => (p.tag, p.weight)),
        [('RPG', 1.0), ('Terror', 1.0)],
      );
      expect(
        container.read(preferencesProvider).value?.map((p) => p.tag),
        ['RPG', 'Terror'],
      );
    });

    test('addPreference() no hace nada si el tag ya existe (sin distinguir mayúsculas)', () async {
      final calls = <_UpdatePreferencesCall>[];
      final container = ProviderContainer(
        overrides: [
          domainsProvider.overrideWith((ref) => Future.value(const [_games])),
          profileRepositoryProvider.overrideWith(
            (ref) => _FakeProfileRepository(
              ref,
              initialPreferences: const [ExplicitPreference(tag: 'RPG', weight: 1)],
              onUpdatePreferences: calls.add,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(preferencesProvider.future);

      final error = await container.read(preferencesProvider.notifier).addPreference('rpg');

      expect(error, null);
      expect(calls, isEmpty);
      expect(container.read(preferencesProvider).value?.map((p) => p.tag), ['RPG']);
    });

    test('removePreference() quita el tag y envía la lista restante', () async {
      final calls = <_UpdatePreferencesCall>[];
      final container = ProviderContainer(
        overrides: [
          domainsProvider.overrideWith((ref) => Future.value(const [_games])),
          profileRepositoryProvider.overrideWith(
            (ref) => _FakeProfileRepository(
              ref,
              initialPreferences: const [
                ExplicitPreference(tag: 'RPG', weight: 1),
                ExplicitPreference(tag: 'Terror', weight: 1),
              ],
              onUpdatePreferences: calls.add,
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(preferencesProvider.future);

      await container.read(preferencesProvider.notifier).removePreference('RPG');

      expect(calls.length, 1);
      expect(calls.single.domainCode, 'games');
      expect(calls.single.preferences.map((p) => (p.tag, p.weight)), [('Terror', 1.0)]);
      expect(container.read(preferencesProvider).value?.map((p) => p.tag), ['Terror']);
    });

    test('si el PUT falla, revierte a la lista anterior', () async {
      final container = ProviderContainer(
        overrides: [
          domainsProvider.overrideWith((ref) => Future.value(const [_games])),
          profileRepositoryProvider.overrideWith(
            (ref) => _FakeProfileRepository(
              ref,
              initialPreferences: const [ExplicitPreference(tag: 'RPG', weight: 1)],
              updatePreferencesFailWith: const AppException(
                code: 'NETWORK_ERROR',
                message: 'Sin conexión',
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(preferencesProvider.future);

      final error = await container
          .read(preferencesProvider.notifier)
          .addPreference('Terror');

      expect(error?.message, 'Sin conexión');
      expect(container.read(preferencesProvider).value?.map((p) => p.tag), ['RPG']);
    });
  });
}
