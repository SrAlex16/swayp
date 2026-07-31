import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../data/repositories/profile_repository.dart';
import '../../domain/models/explicit_preference.dart';
import '../../domain/models/user_profile.dart';
import '../domain_selection/current_domain_provider.dart';

/// Perfil de usuario (edad/género, docs/ARCHITECTURE.md sección 7.2). No
/// depende del dominio activo, a diferencia de [PreferencesNotifier].
class ProfileNotifier extends AsyncNotifier<UserProfile> {
  @override
  Future<UserProfile> build() => ref.read(profileRepositoryProvider).getProfile();

  /// Guarda edad/género. Devuelve el [AppException] si falló (`null` en
  /// éxito) — la pantalla decide qué mostrar; no hay aquí un canal de error
  /// aparte tipo `swipeErrorProvider` porque este formulario no tiene un
  /// efecto optimista que revertir, solo un guardado explícito.
  Future<AppException?> save({required int? age, required String? gender}) async {
    try {
      final updated = await ref
          .read(profileRepositoryProvider)
          .updateProfile(age: age, gender: gender);
      state = AsyncData(updated);
      return null;
    } on AppException catch (error) {
      developer.log(
        'fallo al guardar el perfil: ${error.code} ${error.message}',
        name: 'swayp.profile',
        level: 1000,
      );
      return error;
    }
  }
}

final profileProvider = AsyncNotifierProvider<ProfileNotifier, UserProfile>(ProfileNotifier.new);

/// Preferencias explícitas del usuario en el dominio activo
/// (docs/ARCHITECTURE.md sección 9). Se recarga automáticamente cuando
/// cambia [currentDomainProvider], igual que `deckProvider`/`savedProvider`.
class PreferencesNotifier extends AsyncNotifier<List<ExplicitPreference>> {
  @override
  Future<List<ExplicitPreference>> build() async {
    final domain = await ref.watch(currentDomainProvider.future);
    if (domain == null) return const [];

    return ref.read(profileRepositoryProvider).getPreferences(domain.code);
  }

  /// Añade [tag] con `weight` fijo a 1.0. No-op (sin llamada de red) si el
  /// tag ya existe — evita un 409/500 innecesario, ya que el backend
  /// almacena `tag` como parte de la clave primaria por dominio y el `PUT`
  /// reemplaza la lista completa, no la fusiona (un duplicado en el mismo
  /// envío rompería el `INSERT`).
  Future<AppException?> addPreference(String tag) {
    final trimmed = tag.trim();
    if (trimmed.isEmpty) return Future.value(null);

    final current = state.value ?? const [];
    final alreadyExists = current.any(
      (preference) => preference.tag.toLowerCase() == trimmed.toLowerCase(),
    );
    if (alreadyExists) return Future.value(null);

    return _replaceAll([...current, ExplicitPreference(tag: trimmed, weight: 1.0)]);
  }

  Future<AppException?> removePreference(String tag) {
    final current = state.value ?? const [];
    return _replaceAll(current.where((preference) => preference.tag != tag).toList());
  }

  /// Optimista: la lista se actualiza de inmediato, el `PUT` (que reemplaza
  /// la lista completa en el backend) va después; si falla, revierte —
  /// mismo patrón que `SavedNotifier.remove()`.
  Future<AppException?> _replaceAll(List<ExplicitPreference> updated) async {
    final domainCode = ref.read(currentDomainProvider).value?.code;
    if (domainCode == null) return null;

    final previous = state.value ?? const [];
    state = AsyncData(updated);

    try {
      final confirmed = await ref
          .read(profileRepositoryProvider)
          .updatePreferences(domainCode, updated);
      state = AsyncData(confirmed);
      return null;
    } on AppException catch (error) {
      developer.log(
        'fallo al guardar preferencias: ${error.code} ${error.message}',
        name: 'swayp.profile',
        level: 1000,
      );
      if (ref.mounted) {
        state = AsyncData(previous);
      }
      return error;
    }
  }
}

final preferencesProvider = AsyncNotifierProvider<PreferencesNotifier, List<ExplicitPreference>>(
  PreferencesNotifier.new,
);
