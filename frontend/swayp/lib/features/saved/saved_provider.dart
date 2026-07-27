import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../data/repositories/pending_confirmation_repository.dart';
import '../../domain/models/pending_rating.dart';
import '../domain_selection/current_domain_provider.dart';

/// Bandeja de Guardados (docs/ARCHITECTURE.md sección 8.3): ratings
/// `interested` pendientes de confirmar para el dominio activo. Mismo
/// patrón que `deck_provider.dart` — `AsyncNotifier` mutable en vez de un
/// `FutureProvider` puro, porque `confirmItem` necesita poder quitar un
/// item de la lista sin recargar toda la bandeja. Se recarga
/// automáticamente cuando cambia [currentDomainProvider].
class SavedNotifier extends AsyncNotifier<List<PendingRating>> {
  @override
  Future<List<PendingRating>> build() async {
    final domain = await ref.watch(currentDomainProvider.future);
    if (domain == null) return const [];

    return ref.read(pendingConfirmationRepositoryProvider).getPending(domain.code);
  }

  /// Confirma [ratingId] con [status] ("known_liked" o "known_disliked").
  ///
  /// A diferencia del swipe (que quita la carta al instante y envía en
  /// segundo plano), aquí se espera la respuesta del backend antes de
  /// quitar el item: confirmar "¿te gustó?" no es una acción desechable
  /// como el swipe inicial, así que si falla el item se queda en la lista
  /// tal cual — el usuario puede simplemente volver a tocarlo y
  /// reintentarlo, sin necesitar una cola local aparte.
  Future<void> confirmItem(int ratingId, String status) async {
    final domainCode = ref.read(currentDomainProvider).value?.code;
    if (domainCode == null) return;

    try {
      await ref
          .read(pendingConfirmationRepositoryProvider)
          .confirm(domainCode, ratingId, status);
    } on AppException catch (error) {
      developer.log(
        'fallo al confirmar rating $ratingId: ${error.code} ${error.message}',
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
