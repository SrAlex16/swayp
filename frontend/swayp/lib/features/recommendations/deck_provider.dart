import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../data/repositories/ratings_repository.dart';
import '../../data/repositories/recommendations_repository.dart';
import '../../data/repositories/seed_repository.dart';
import '../../domain/models/item.dart';
import '../domain_selection/current_domain_provider.dart';
import '../saved/saved_provider.dart';
import 'batch_strategy.dart';

const int _seedCount = 10;

// Polling del job de recomendaciones: cada 300ms, máximo 8 intentos (~2.4s
// de espera total). Si se agota sin terminar, o si el job da status
// "error", cae a /seed para ese lote como fallback silencioso. Valores por
// defecto de [DeckNotifier] — inyectables en el constructor para que los
// tests puedan forzar el camino de "se agotan los intentos" sin esperar
// ~2.4s reales de verdad.
const Duration _defaultJobPollInterval = Duration(milliseconds: 300);
const int _defaultJobPollMaxAttempts = 8;

/// Último error al enviar un rating en segundo plano (ver
/// [DeckNotifier.swipe]/[DeckNotifier.undo]). Señal de "un solo disparo",
/// no estado persistente: la UI la observa con `ref.listen` para mostrar
/// un SnackBar puntual y la resetea a `null` justo después de mostrarla.
/// Un `NotifierProvider` nullable (no un `StateProvider`, que en Riverpod
/// 3.x queda relegado a `package:flutter_riverpod/legacy.dart`) porque
/// solo hace falta el último error (no un histórico) y así se mantiene la
/// misma familia de API que [CurrentDomainNotifier]/[DeckNotifier] en vez
/// de mezclar dos estilos.
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

/// Si hay un último swipe que se puede deshacer (docs/ARCHITECTURE.md
/// sección 10, undo de un solo nivel). La UI lo observa para
/// mostrar/ocultar (o deshabilitar) el botón de "volver atrás". Mismo
/// motivo que [swipeErrorProvider] para vivir en un `Notifier` aparte:
/// [DeckNotifier] guarda el resto del estado de "último swipe" en campos
/// privados (no forma parte de `AsyncValue<List<Item>>`), así que necesita
/// un canal aparte y observable para avisar a la UI de si cambió.
class CanUndoNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value; // ignore: use_setters_to_change_properties
}

final canUndoProvider = NotifierProvider<CanUndoNotifier, bool>(CanUndoNotifier.new);

/// Toggle "ya lo conozco" de la carta actual (docs/ARCHITECTURE.md sección
/// 7.1): si está activo, el swipe deja de significar "interés" y pasa a
/// ser una respuesta directa de gusto (`known_liked`/`known_disliked`) en
/// vez de `interested`/`rejected`. [DeckNotifier.swipe] lo resetea a
/// `false` tras cada swipe — así no hace falta duplicar ese reset en cada
/// sitio de la UI que puede disparar un swipe (arrastre y los dos
/// botones).
class AlreadyKnownToggleNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
  void reset() => state = false;
}

final alreadyKnownToggleProvider = NotifierProvider<AlreadyKnownToggleNotifier, bool>(
  AlreadyKnownToggleNotifier.new,
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
  DeckNotifier({
    Duration jobPollInterval = _defaultJobPollInterval,
    int jobPollMaxAttempts = _defaultJobPollMaxAttempts,
  }) : _jobPollInterval = jobPollInterval,
       _jobPollMaxAttempts = jobPollMaxAttempts;

  final Duration _jobPollInterval;
  final int _jobPollMaxAttempts;

  // Bookkeeping del último swipe, para poder deshacerlo (undo de un solo
  // nivel: un swipe o un undo nuevos sustituyen esto, nunca se acumula).
  Item? _lastSwipedItem;
  String? _lastSwipedDomainCode;
  Future<int?>? _lastRatingIdFuture;

  @override
  Future<List<Item>> build() async {
    final domain = await ref.watch(currentDomainProvider.future);
    if (domain == null) return const [];

    final source = await ref.read(batchStrategyStoreProvider).nextBatchSource(domain.code);
    if (source == BatchSource.seed) {
      return ref.read(seedRepositoryProvider).getSeed(domain.code, count: _seedCount);
    }

    return _loadFromEngine(domain.code);
  }

  /// Pide un lote al motor real (`POST recommendations/jobs` + polling a
  /// `GET /jobs/<id>`, docs/ARCHITECTURE.md sección 3.5). Si el job falla,
  /// da error, o no termina dentro de [_jobPollMaxAttempts] intentos, cae a
  /// `/seed` como fallback silencioso — el usuario nunca se queda sin
  /// mazo por un problema del motor.
  Future<List<Item>> _loadFromEngine(String domainCode) async {
    try {
      final jobId = await ref
          .read(recommendationsRepositoryProvider)
          .requestRecommendationJob(domainCode);

      for (var attempt = 0; attempt < _jobPollMaxAttempts; attempt++) {
        await Future<void>.delayed(_jobPollInterval);
        final jobStatus = await ref.read(recommendationsRepositoryProvider).pollJob(jobId);

        if (jobStatus.isDone) {
          return jobStatus.result ?? const [];
        }
        if (jobStatus.isError) {
          developer.log(
            'job de recomendaciones $jobId falló (${jobStatus.errorMessage}), '
            'fallback a /seed para este lote',
            name: 'swayp.deck',
            level: 900,
          );
          return ref.read(seedRepositoryProvider).getSeed(domainCode, count: _seedCount);
        }
        // "pending"/"running": sigue esperando.
      }

      developer.log(
        'job de recomendaciones $jobId no terminó tras $_jobPollMaxAttempts intentos, '
        'fallback a /seed para este lote',
        name: 'swayp.deck',
        level: 900,
      );
      return ref.read(seedRepositoryProvider).getSeed(domainCode, count: _seedCount);
    } on AppException catch (error) {
      developer.log(
        'fallo al pedir/consultar el job de recomendaciones '
        '(${error.code} ${error.message}), fallback a /seed para este lote',
        name: 'swayp.deck',
        level: 900,
      );
      return ref.read(seedRepositoryProvider).getSeed(domainCode, count: _seedCount);
    }
  }

  /// Valora [item]. Sin el toggle "ya lo conozco" activo, [status] debe
  /// ser "interested" (derecha) o "rejected" (izquierda); con
  /// [alreadyKnown] en `true`, se remapea a "known_liked"/"known_disliked"
  /// respectivamente (docs/ARCHITECTURE.md sección 7.1).
  ///
  /// Alcance explícito de este bloque (ver docs/TODO.md): envío optimista
  /// simple. La carta se quita del mazo en memoria al instante; el POST a
  /// `/ratings` va en segundo plano sin bloquear la UI. Si falla, se loguea
  /// y se expone vía [swipeErrorProvider], pero la carta NO se reinserta
  /// automáticamente — para eso está [undo], de un solo nivel.
  void swipe(Item item, String status, {bool alreadyKnown = false}) {
    ref.read(alreadyKnownToggleProvider.notifier).reset();

    final resolvedStatus = alreadyKnown
        ? (status == 'interested' ? 'known_liked' : 'known_disliked')
        : status;

    final domainCode = ref.read(currentDomainProvider).value?.code;

    final current = state.value ?? const [];
    final updated = current.where((candidate) => candidate.itemId != item.itemId).toList();
    state = AsyncData(updated);

    if (domainCode != null) {
      final ratingIdFuture = _submitRating(domainCode, item, resolvedStatus);
      _lastSwipedItem = item;
      _lastSwipedDomainCode = domainCode;
      _lastRatingIdFuture = ratingIdFuture;
      ref.read(canUndoProvider.notifier).set(true);
    }

    if (updated.isEmpty) {
      ref.invalidateSelf();
    }
  }

  /// Deshace el último swipe (docs/ARCHITECTURE.md sección 10, undo de un
  /// solo nivel: no hay "deshacer el deshacer"). Se consume de inmediato
  /// (antes de esperar nada), así un segundo swipe o un segundo undo no
  /// encuentran nada que deshacer hasta que vuelva a haber un swipe nuevo.
  ///
  /// Si el POST de ese swipe seguía en vuelo, espera a que termine. Si
  /// terminó con éxito, borra el rating en el backend
  /// (`DELETE /ratings/<id>`) y solo entonces reinserta la carta al
  /// principio del mazo. Si el POST original ya había fallado (no hay
  /// nada que borrar en el backend), reinserta directamente. Si el
  /// `DELETE` falla, se loguea y se expone vía [swipeErrorProvider] pero
  /// la carta NO se reinserta — más seguro fallar sin reinsertar que
  /// reinsertar sobre un estado del backend inconsistente.
  Future<void> undo() async {
    final item = _lastSwipedItem;
    final domainCode = _lastSwipedDomainCode;
    final ratingIdFuture = _lastRatingIdFuture;
    if (item == null || domainCode == null || ratingIdFuture == null) return;

    _lastSwipedItem = null;
    _lastSwipedDomainCode = null;
    _lastRatingIdFuture = null;
    ref.read(canUndoProvider.notifier).set(false);

    final ratingId = await ratingIdFuture;
    if (!ref.mounted) return;
    if (ratingId == null) {
      // El POST original ya falló (y se reportó entonces): nada que borrar
      // en el backend, así que no hay motivo para no reinsertar la carta.
      _reinsert(item);
      return;
    }

    try {
      await ref.read(ratingsRepositoryProvider).deleteRating(
        domainCode: domainCode,
        ratingId: ratingId,
      );
    } on AppException catch (error) {
      developer.log(
        'fallo al deshacer swipe (rating $ratingId): ${error.code} ${error.message}',
        name: 'swayp.deck',
        level: 1000,
      );
      if (ref.mounted) {
        ref.read(swipeErrorProvider.notifier).state = error;
      }
      return;
    }

    if (ref.mounted) {
      _reinsert(item);
    }
  }

  void _reinsert(Item item) {
    final current = state.value ?? const [];
    state = AsyncData([item, ...current]);
  }

  Future<int?> _submitRating(String domainCode, Item item, String status) async {
    try {
      final ratingId = await ref.read(ratingsRepositoryProvider).submitRating(
        domainCode: domainCode,
        itemId: item.itemId,
        status: status,
      );
      // Cada `await` es un hueco async en el que este notifier puede haberse
      // desechado (ej. el usuario cambió de dominio mientras el envío
      // todavía estaba en vuelo) — `ref.mounted` evita tocar `ref` tras eso,
      // como recomienda Riverpod.
      if (!ref.mounted) return ratingId;

      // Cuenta para batch_strategy.dart (umbral para pasar de /seed al
      // motor), sin distinguir por status: es señal de actividad, no solo
      // de "interested".
      await ref.read(batchStrategyStoreProvider).incrementSwipeCount(domainCode);
      if (!ref.mounted) return ratingId;

      if (status == 'interested') {
        // Guardados (docs/ARCHITECTURE.md sección 7.3) vive de este status;
        // invalida su provider para que se entere sin depender de que su
        // pestaña se reconstruya sola (vive en un IndexedStack, ver
        // app_shell.dart).
        ref.invalidate(savedProvider);
      }
      return ratingId;
    } on AppException catch (error) {
      developer.log(
        'fallo al enviar rating: ${error.code} ${error.message}',
        name: 'swayp.deck',
        level: 1000,
      );
      if (!ref.mounted) return null;
      ref.read(swipeErrorProvider.notifier).state = error;
      return null;
    }
  }
}

final deckProvider = AsyncNotifierProvider<DeckNotifier, List<Item>>(DeckNotifier.new);
