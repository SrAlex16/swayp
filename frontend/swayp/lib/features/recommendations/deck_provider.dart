import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../data/repositories/ratings_repository.dart';
import '../../data/repositories/seed_repository.dart';
import '../../domain/models/item.dart';
import '../domain_selection/current_domain_provider.dart';

const int _seedCount = 10;

/// Último error al enviar un rating en segundo plano (ver
/// [DeckNotifier.swipe]). Señal de "un solo disparo", no estado persistente:
/// la UI la observa con `ref.listen` para mostrar un SnackBar puntual y la
/// resetea a `null` justo después de mostrarla. Un `NotifierProvider`
/// nullable (no un `StateProvider`, que en Riverpod 3.x queda relegado a
/// `package:flutter_riverpod/legacy.dart`) porque solo hace falta el último
/// error (no un histórico) y así se mantiene la misma familia de API que
/// [CurrentDomainNotifier]/[DeckNotifier] en vez de mezclar dos estilos.
class SwipeErrorNotifier extends Notifier<AppException?> {
  @override
  AppException? build() => null;

  /// Descarta el error actual tras mostrarlo (la UI la llama después del
  /// SnackBar). `state` solo se puede asignar desde dentro de un
  /// `Notifier` — de ahí este método en vez de que la UI toque `.state`
  /// directamente.
  void dismiss() => state = null;
}

final swipeErrorProvider = NotifierProvider<SwipeErrorNotifier, AppException?>(
  SwipeErrorNotifier.new,
);

/// Mazo de ítems de Descubrir para el dominio activo (docs/ARCHITECTURE.md
/// sección 7.1). Se recarga automáticamente cuando cambia
/// [currentDomainProvider]. Deliberadamente NO es un `FutureProvider` puro:
/// el swipe necesita poder quitar cartas del mazo sin volver a pedir el
/// seed, así que el estado vive en un `AsyncNotifier` mutable — la carga
/// inicial es async, pero el mazo en sí es mutable después.
///
/// Nota: por ahora hay un único mazo activo (el del dominio actual), no uno
/// por dominio en caché simultáneamente (lo que docs/ARCHITECTURE.md sección
/// 4.3 describe como providers `family`, para no perder progreso al
/// alternar de dominio) — cambiar de dominio siempre vuelve a pedir el
/// seed. Se puede convertir a `family` más adelante si hace falta.
class DeckNotifier extends AsyncNotifier<List<Item>> {
  @override
  Future<List<Item>> build() async {
    final domain = await ref.watch(currentDomainProvider.future);
    if (domain == null) return const [];

    return ref.read(seedRepositoryProvider).getSeed(domain.code, count: _seedCount);
  }

  /// Valora [item] con [status] ("interested" o "rejected").
  ///
  /// Alcance explícito de este bloque (ver docs/TODO.md): envío optimista
  /// simple. La carta se quita del mazo en memoria al instante; el POST a
  /// `/ratings` va en segundo plano sin bloquear la UI. Si falla, se loguea
  /// y se expone vía [swipeErrorProvider], pero la carta NO se reinserta —
  /// eso (y una cola local persistente con reintento) queda como
  /// refinamiento futuro, no implementado aquí.
  void swipe(Item item, String status) {
    final domainCode = ref.read(currentDomainProvider).value?.code;

    final current = state.value ?? const [];
    final updated = current.where((candidate) => candidate.itemId != item.itemId).toList();
    state = AsyncData(updated);

    if (domainCode != null) {
      unawaited(_submitRating(domainCode, item, status));
    }

    if (updated.isEmpty) {
      ref.invalidateSelf();
    }
  }

  Future<void> _submitRating(String domainCode, Item item, String status) async {
    try {
      await ref.read(ratingsRepositoryProvider).submitRating(
        domainCode: domainCode,
        itemId: item.itemId,
        status: status,
      );
    } on AppException catch (error) {
      developer.log(
        'fallo al enviar rating: ${error.code} ${error.message}',
        name: 'swayp.deck',
        level: 1000,
      );
      ref.read(swipeErrorProvider.notifier).state = error;
    }
  }
}

final deckProvider = AsyncNotifierProvider<DeckNotifier, List<Item>>(DeckNotifier.new);
