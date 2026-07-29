import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:swayp/core/errors/app_exception.dart';
import 'package:swayp/data/repositories/blacklist_repository.dart';
import 'package:swayp/data/repositories/domain_repository.dart';
import 'package:swayp/data/repositories/saved_repository.dart';
import 'package:swayp/data/repositories/ratings_repository.dart';
import 'package:swayp/data/repositories/recommendations_repository.dart';
import 'package:swayp/data/repositories/seed_repository.dart';
import 'package:swayp/domain/models/domain.dart';
import 'package:swayp/domain/models/item.dart';
import 'package:swayp/domain/models/pending_rating.dart';
import 'package:swayp/features/recommendations/batch_strategy.dart';
import 'package:swayp/features/recommendations/deck_provider.dart';
import 'package:swayp/features/saved/saved_provider.dart';

const _games = Domain(code: 'games', displayName: 'Videojuegos');
const _item1 = Item(itemId: 1, title: 'Dark Souls', imageUrl: null, externalUrl: null);
const _item2 = Item(itemId: 2, title: 'Cuphead', imageUrl: null, externalUrl: null);
const _item3 = Item(itemId: 3, title: 'Hollow Knight', imageUrl: null, externalUrl: null);

/// Devuelve la siguiente lista de [_responses] en cada llamada (se queda en
/// la última una vez agotadas) — permite simular la recarga tras vaciar el
/// mazo sin necesitar mocks de red reales.
class _FakeSeedRepository extends SeedRepository {
  _FakeSeedRepository(super.ref, this._responses);

  final List<List<Item>> _responses;
  int _callCount = 0;

  @override
  Future<List<Item>> getSeed(String domainCode, {required int count}) async {
    final response = _responses[_callCount.clamp(0, _responses.length - 1)];
    _callCount++;
    return response;
  }
}

typedef _SubmittedRating = ({String domainCode, int itemId, String status});
typedef _DeletedRating = ({String domainCode, int ratingId});

class _FakeRatingsRepository extends RatingsRepository {
  _FakeRatingsRepository(
    super.ref, {
    this.onSubmit,
    this.failWith,
    this.onDelete,
    this.deleteFailWith,
    this.nextRatingId = 100,
  });

  final void Function(_SubmittedRating rating)? onSubmit;
  final AppException? failWith;
  final void Function(_DeletedRating rating)? onDelete;
  final AppException? deleteFailWith;
  int nextRatingId;

  @override
  Future<int> submitRating({
    required String domainCode,
    required int itemId,
    required String status,
  }) async {
    onSubmit?.call((domainCode: domainCode, itemId: itemId, status: status));
    if (failWith != null) throw failWith!;
    return nextRatingId++;
  }

  @override
  Future<void> deleteRating({required String domainCode, required int ratingId}) async {
    onDelete?.call((domainCode: domainCode, ratingId: ratingId));
    if (deleteFailWith != null) throw deleteFailWith!;
  }
}

typedef _BlacklistedItem = ({String domainCode, int itemId});

class _FakeBlacklistRepository extends BlacklistRepository {
  _FakeBlacklistRepository(super.ref, {this.onAdd, this.failWith});

  final void Function(_BlacklistedItem entry)? onAdd;
  final AppException? failWith;

  @override
  Future<void> addToBlacklist({required String domainCode, required int itemId}) async {
    onAdd?.call((domainCode: domainCode, itemId: itemId));
    if (failWith != null) throw failWith!;
  }
}

class _FakeSavedRepository extends SavedRepository {
  _FakeSavedRepository(super.ref);

  int callCount = 0;

  @override
  Future<List<PendingRating>> getSavedRatings(String domainCode) async {
    callCount++;
    return const [];
  }

  @override
  Future<void> updateRatingStatus(String domainCode, int ratingId, String status) async {}
}

/// Fuerza siempre "motor" como origen del siguiente lote, sin depender de
/// los contadores reales de `shared_preferences` — estos tests solo
/// quieren ejercitar el camino de `_loadFromEngine`, no la lógica de
/// batch_strategy.dart (que ya tiene sus propios tests).
class _AlwaysEngineBatchStrategyStore extends BatchStrategyStore {
  const _AlwaysEngineBatchStrategyStore();

  @override
  Future<BatchSource> nextBatchSource(String domainCode) async => BatchSource.engine;

  @override
  Future<void> incrementSwipeCount(String domainCode) async {}
}

/// Devuelve la siguiente entrada de [jobStatuses] en cada `pollJob` (se
/// queda en la última una vez agotadas), simulando el avance de un job
/// real sin llamadas de red.
class _FakeRecommendationsRepository extends RecommendationsRepository {
  _FakeRecommendationsRepository(super.ref, {this.requestFailWith, this.jobStatuses = const []});

  final AppException? requestFailWith;
  final List<JobStatus> jobStatuses;
  int _pollCallCount = 0;

  @override
  Future<String> requestRecommendationJob(String domainCode) async {
    if (requestFailWith != null) throw requestFailWith!;
    return 'job-1';
  }

  @override
  Future<JobStatus> pollJob(String jobId) async {
    final status = jobStatuses[_pollCallCount.clamp(0, jobStatuses.length - 1)];
    _pollCallCount++;
    return status;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('swipe() quita el item de la lista inmediatamente (optimista)', () async {
    final container = ProviderContainer(
      overrides: [
        domainsProvider.overrideWith((ref) => Future.value(const [_games])),
        seedRepositoryProvider.overrideWith(
          (ref) => _FakeSeedRepository(ref, const [
            [_item1, _item2],
          ]),
        ),
        ratingsRepositoryProvider.overrideWith((ref) => _FakeRatingsRepository(ref)),
      ],
    );
    addTearDown(container.dispose);

    final initial = await container.read(deckProvider.future);
    expect(initial.map((item) => item.itemId), [1, 2]);

    container.read(deckProvider.notifier).swipe(_item1, 'interested');

    final afterSwipe = container.read(deckProvider).value;
    expect(afterSwipe?.map((item) => item.itemId), [2]);

    // Deja correr el envío en segundo plano antes de que addTearDown
    // destruya el container — si no, puede seguir en vuelo cuando el
    // container ya no existe.
    await Future<void>.delayed(Duration.zero);
  });

  test('al quedarse sin items, se recarga el mazo automáticamente', () async {
    final container = ProviderContainer(
      overrides: [
        domainsProvider.overrideWith((ref) => Future.value(const [_games])),
        seedRepositoryProvider.overrideWith(
          (ref) => _FakeSeedRepository(ref, const [
            [_item1],
            [_item3],
          ]),
        ),
        ratingsRepositoryProvider.overrideWith((ref) => _FakeRatingsRepository(ref)),
      ],
    );
    addTearDown(container.dispose);

    final initial = await container.read(deckProvider.future);
    expect(initial.map((item) => item.itemId), [1]);

    container.read(deckProvider.notifier).swipe(_item1, 'rejected');

    final reloaded = await container.read(deckProvider.future);
    expect(reloaded.map((item) => item.itemId), [3]);
  });

  test('un fallo al enviar el rating no revienta la app ni reinserta la carta', () async {
    final submitted = <_SubmittedRating>[];
    final container = ProviderContainer(
      overrides: [
        domainsProvider.overrideWith((ref) => Future.value(const [_games])),
        seedRepositoryProvider.overrideWith(
          (ref) => _FakeSeedRepository(ref, const [
            [_item1, _item2],
          ]),
        ),
        ratingsRepositoryProvider.overrideWith(
          (ref) => _FakeRatingsRepository(
            ref,
            onSubmit: submitted.add,
            failWith: const AppException(code: 'NETWORK_ERROR', message: 'Sin conexión'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(deckProvider.future);

    // No debe lanzar ni tumbar el test: swipe() es síncrono y el envío
    // fallido ocurre en segundo plano.
    container.read(deckProvider.notifier).swipe(_item1, 'interested');

    expect(container.read(deckProvider).value?.map((item) => item.itemId), [2]);

    // Deja correr el envío fallido en segundo plano.
    await Future<void>.delayed(Duration.zero);

    expect(submitted, [(domainCode: 'games', itemId: 1, status: 'interested')]);
    expect(container.read(swipeErrorProvider)?.message, 'Sin conexión');
    // La carta sigue fuera del mazo: no se reinserta tras el fallo.
    expect(container.read(deckProvider).value?.map((item) => item.itemId), [2]);
  });

  test('un swipe "interested" con éxito invalida saved_provider', () async {
    final container = ProviderContainer(
      overrides: [
        domainsProvider.overrideWith((ref) => Future.value(const [_games])),
        seedRepositoryProvider.overrideWith(
          (ref) => _FakeSeedRepository(ref, const [
            [_item1, _item2],
          ]),
        ),
        ratingsRepositoryProvider.overrideWith((ref) => _FakeRatingsRepository(ref)),
        savedRepositoryProvider.overrideWith(
          (ref) => _FakeSavedRepository(ref),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(deckProvider.future);
    await container.read(savedProvider.future);

    final fakeSaved =
        container.read(savedRepositoryProvider)
            as _FakeSavedRepository;
    expect(fakeSaved.callCount, 1);

    container.read(deckProvider.notifier).swipe(_item1, 'interested');
    // Deja correr el submit en segundo plano, cuya finalización con éxito
    // es lo que dispara la invalidación de saved_provider.
    await Future<void>.delayed(Duration.zero);

    await container.read(savedProvider.future);
    expect(fakeSaved.callCount, 2);
  });

  test('undo() espera el POST en vuelo, borra el rating y reinserta el item', () async {
    final deletedCalls = <_DeletedRating>[];
    final container = ProviderContainer(
      overrides: [
        domainsProvider.overrideWith((ref) => Future.value(const [_games])),
        seedRepositoryProvider.overrideWith(
          (ref) => _FakeSeedRepository(ref, const [
            [_item1, _item2],
          ]),
        ),
        ratingsRepositoryProvider.overrideWith(
          (ref) => _FakeRatingsRepository(ref, onDelete: deletedCalls.add, nextRatingId: 500),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(deckProvider.future);

    container.read(deckProvider.notifier).swipe(_item1, 'interested');
    expect(container.read(deckProvider).value?.map((item) => item.itemId), [2]);
    expect(container.read(canUndoProvider), true);

    // undo() espera él mismo a que el POST en vuelo termine antes de borrar.
    await container.read(deckProvider.notifier).undo();

    expect(deletedCalls, [(domainCode: 'games', ratingId: 500)]);
    expect(container.read(deckProvider).value?.map((item) => item.itemId), [1, 2]);
    expect(container.read(canUndoProvider), false);
  });

  test('si el DELETE del undo falla, no reinserta la carta y expone el error', () async {
    final container = ProviderContainer(
      overrides: [
        domainsProvider.overrideWith((ref) => Future.value(const [_games])),
        seedRepositoryProvider.overrideWith(
          (ref) => _FakeSeedRepository(ref, const [
            [_item1, _item2],
          ]),
        ),
        ratingsRepositoryProvider.overrideWith(
          (ref) => _FakeRatingsRepository(
            ref,
            deleteFailWith: const AppException(code: 'NETWORK_ERROR', message: 'Sin conexión'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(deckProvider.future);
    container.read(deckProvider.notifier).swipe(_item1, 'interested');

    await container.read(deckProvider.notifier).undo();

    expect(container.read(deckProvider).value?.map((item) => item.itemId), [2]);
    expect(container.read(swipeErrorProvider)?.message, 'Sin conexión');
    expect(container.read(canUndoProvider), false);
  });

  test('el swipe simple envía los estados reales del backend', () async {
    final submitted = <_SubmittedRating>[];
    final container = ProviderContainer(
      overrides: [
        domainsProvider.overrideWith((ref) => Future.value(const [_games])),
        seedRepositoryProvider.overrideWith(
          (ref) => _FakeSeedRepository(ref, const [
            [_item1, _item2],
          ]),
        ),
        ratingsRepositoryProvider.overrideWith(
          (ref) => _FakeRatingsRepository(ref, onSubmit: submitted.add),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(deckProvider.future);
    container.read(swipeModeProvider.notifier).set('skipped');
    expect(container.read(swipeModeProvider), 'skipped');

    container.read(deckProvider.notifier).swipe(_item1, 'skipped');
    await Future<void>.delayed(Duration.zero);

    expect(submitted, [(domainCode: 'games', itemId: 1, status: 'skipped')]);

    container.read(deckProvider.notifier).swipe(_item2, 'rejected');
    await Future<void>.delayed(Duration.zero);

    expect(submitted.last, (domainCode: 'games', itemId: 2, status: 'rejected'));
  });

  test('si el job termina con éxito, usa el resultado del motor (no /seed)', () async {
    final container = ProviderContainer(
      overrides: [
        domainsProvider.overrideWith((ref) => Future.value(const [_games])),
        batchStrategyStoreProvider.overrideWithValue(const _AlwaysEngineBatchStrategyStore()),
        recommendationsRepositoryProvider.overrideWith(
          (ref) => _FakeRecommendationsRepository(
            ref,
            jobStatuses: const [
              JobStatus(status: 'running'),
              JobStatus(status: 'done', result: [_item2]),
            ],
          ),
        ),
        seedRepositoryProvider.overrideWith(
          (ref) => _FakeSeedRepository(ref, const [
            [_item1],
          ]),
        ),
        deckProvider.overrideWith(
          () => DeckNotifier(jobPollInterval: const Duration(milliseconds: 1)),
        ),
      ],
    );
    addTearDown(container.dispose);

    final deck = await container.read(deckProvider.future);

    expect(deck.map((item) => item.itemId), [2]);
  });

  test('si el job da status "error", cae a /seed para ese lote', () async {
    final container = ProviderContainer(
      overrides: [
        domainsProvider.overrideWith((ref) => Future.value(const [_games])),
        batchStrategyStoreProvider.overrideWithValue(const _AlwaysEngineBatchStrategyStore()),
        recommendationsRepositoryProvider.overrideWith(
          (ref) => _FakeRecommendationsRepository(
            ref,
            jobStatuses: const [JobStatus(status: 'error', errorMessage: 'motor caído')],
          ),
        ),
        seedRepositoryProvider.overrideWith(
          (ref) => _FakeSeedRepository(ref, const [
            [_item1, _item2],
          ]),
        ),
        deckProvider.overrideWith(
          () => DeckNotifier(jobPollInterval: const Duration(milliseconds: 1)),
        ),
      ],
    );
    addTearDown(container.dispose);

    final deck = await container.read(deckProvider.future);

    expect(deck.map((item) => item.itemId), [1, 2]);
  });

  test('si el job no termina tras los intentos máximos, cae a /seed', () async {
    final container = ProviderContainer(
      overrides: [
        domainsProvider.overrideWith((ref) => Future.value(const [_games])),
        batchStrategyStoreProvider.overrideWithValue(const _AlwaysEngineBatchStrategyStore()),
        recommendationsRepositoryProvider.overrideWith(
          (ref) => _FakeRecommendationsRepository(
            ref,
            jobStatuses: const [JobStatus(status: 'running')],
          ),
        ),
        seedRepositoryProvider.overrideWith(
          (ref) => _FakeSeedRepository(ref, const [
            [_item3],
          ]),
        ),
        deckProvider.overrideWith(
          () => DeckNotifier(
            jobPollInterval: const Duration(milliseconds: 1),
            jobPollMaxAttempts: 3,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final deck = await container.read(deckProvider.future);

    expect(deck.map((item) => item.itemId), [3]);
  });

  test('si falla la petición del job (POST), cae a /seed', () async {
    final container = ProviderContainer(
      overrides: [
        domainsProvider.overrideWith((ref) => Future.value(const [_games])),
        batchStrategyStoreProvider.overrideWithValue(const _AlwaysEngineBatchStrategyStore()),
        recommendationsRepositoryProvider.overrideWith(
          (ref) => _FakeRecommendationsRepository(
            ref,
            requestFailWith: const AppException(code: 'NETWORK_ERROR', message: 'Sin conexión'),
          ),
        ),
        seedRepositoryProvider.overrideWith(
          (ref) => _FakeSeedRepository(ref, const [
            [_item1],
          ]),
        ),
        deckProvider.overrideWith(
          () => DeckNotifier(jobPollInterval: const Duration(milliseconds: 1)),
        ),
      ],
    );
    addTearDown(container.dispose);

    final deck = await container.read(deckProvider.future);

    expect(deck.map((item) => item.itemId), [1]);
  });

  test('blacklistCurrent() quita el item de la lista y no genera ningún rating', () async {
    final blacklisted = <_BlacklistedItem>[];
    final submittedRatings = <_SubmittedRating>[];
    final container = ProviderContainer(
      overrides: [
        domainsProvider.overrideWith((ref) => Future.value(const [_games])),
        seedRepositoryProvider.overrideWith(
          (ref) => _FakeSeedRepository(ref, const [
            [_item1, _item2],
          ]),
        ),
        ratingsRepositoryProvider.overrideWith(
          (ref) => _FakeRatingsRepository(ref, onSubmit: submittedRatings.add),
        ),
        blacklistRepositoryProvider.overrideWith(
          (ref) => _FakeBlacklistRepository(ref, onAdd: blacklisted.add),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(deckProvider.future);

    container.read(deckProvider.notifier).blacklistCurrent(_item1);

    // Optimista: desaparece del mazo de inmediato.
    expect(container.read(deckProvider).value?.map((item) => item.itemId), [2]);
    // No participa en el undo de un nivel que ya existe.
    expect(container.read(canUndoProvider), false);

    // Deja correr el POST en segundo plano.
    await Future<void>.delayed(Duration.zero);

    expect(blacklisted, [(domainCode: 'games', itemId: 1)]);
    expect(submittedRatings, isEmpty);
  });

  test('un fallo al blacklistear se expone vía swipeErrorProvider (mismo canal)', () async {
    final container = ProviderContainer(
      overrides: [
        domainsProvider.overrideWith((ref) => Future.value(const [_games])),
        seedRepositoryProvider.overrideWith(
          (ref) => _FakeSeedRepository(ref, const [
            [_item1, _item2],
          ]),
        ),
        ratingsRepositoryProvider.overrideWith((ref) => _FakeRatingsRepository(ref)),
        blacklistRepositoryProvider.overrideWith(
          (ref) => _FakeBlacklistRepository(
            ref,
            failWith: const AppException(code: 'NETWORK_ERROR', message: 'Sin conexión'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(deckProvider.future);

    container.read(deckProvider.notifier).blacklistCurrent(_item1);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(swipeErrorProvider)?.message, 'Sin conexión');
    // No se reinserta, igual que un swipe fallido.
    expect(container.read(deckProvider).value?.map((item) => item.itemId), [2]);
  });
}
