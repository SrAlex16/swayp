import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../data/repositories/saved_repository.dart';
import '../../domain/models/pending_rating.dart';
import '../domain_selection/current_domain_provider.dart';

/// Bandeja de Guardados (docs/ARCHITECTURE.md sección 7.3): ratings
/// `interested` que el usuario ha guardado desde el swipe. Se recarga
/// automáticamente cuando cambia [currentDomainProvider].
class SavedNotifier extends AsyncNotifier<List<PendingRating>> {
  @override
  Future<List<PendingRating>> build() async {
    final domain = await ref.watch(currentDomainProvider.future);
    if (domain == null) return const [];

    return ref.read(savedRepositoryProvider).getSavedRatings(domain.code);
  }

  /// Actualiza [ratingId] al estado indicado. En la experiencia actual de
  /// Guardados, el usuario puede quitar un item convirtiéndolo en `rejected`
  /// o borrándolo.
  Future<void> updateItem(int ratingId, String status) async {
    final domainCode = ref.read(currentDomainProvider).value?.code;
    if (domainCode == null) return;

    try {
      await ref.read(savedRepositoryProvider).updateRatingStatus(domainCode, ratingId, status);
    } on AppException catch (error) {
      developer.log(
        'fallo al actualizar rating $ratingId: ${error.code} ${error.message}',
        name: 'swayp.saved',
        level: 1000,
      );
      return;
    }

    final current = state.value ?? const [];
    state = AsyncData(current.where((rating) => rating.ratingId != ratingId).toList());
  }
}

final savedProvider = AsyncNotifierProvider<SavedNotifier, List<PendingRating>>(
  SavedNotifier.new,
);
