import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:swayp/core/errors/app_exception.dart';
import 'package:swayp/data/repositories/domain_repository.dart';
import 'package:swayp/data/repositories/pending_confirmation_repository.dart';
import 'package:swayp/data/repositories/ratings_repository.dart';
import 'package:swayp/data/repositories/seed_repository.dart';
import 'package:swayp/domain/models/domain.dart';
import 'package:swayp/domain/models/item.dart';
import 'package:swayp/domain/models/pending_rating.dart';
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

class _FakePendingConfirmationRepository extends PendingConfirmationRepository {
  _FakePendingConfirmationRepository(super.ref);

  int callCount = 0;

  @override
  Future<List<PendingRating>> getPending(String domainCode) async {
    callCount++;
    return const [];
  }

  @override
  Future<void> confirm(String domainCode, int ratingId, String status) async {}
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
        pendingConfirmationRepositoryProvider.overrideWith(
          (ref) => _FakePendingConfirmationRepository(ref),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(deckProvider.future);
    await container.read(savedProvider.future);

    final fakePending =
        container.read(pendingConfirmationRepositoryProvider)
            as _FakePendingConfirmationRepository;
    expect(fakePending.callCount, 1);

    container.read(deckProvider.notifier).swipe(_item1, 'interested');
    // Deja correr el submit en segundo plano, cuya finalización con éxito
    // es lo que dispara la invalidación de saved_provider.
    await Future<void>.delayed(Duration.zero);

    await container.read(savedProvider.future);
    expect(fakePending.callCount, 2);
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

  test(
    'con el toggle "ya lo conozco" activo, el swipe manda known_liked/known_disliked '
    'y el toggle se resetea después',
    () async {
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
      container.read(alreadyKnownToggleProvider.notifier).toggle();
      expect(container.read(alreadyKnownToggleProvider), true);

      container.read(deckProvider.notifier).swipe(_item1, 'interested', alreadyKnown: true);
      await Future<void>.delayed(Duration.zero);

      expect(submitted, [(domainCode: 'games', itemId: 1, status: 'known_liked')]);
      // El toggle se resetea tras el swipe, no se queda pegado para la
      // siguiente carta.
      expect(container.read(alreadyKnownToggleProvider), false);

      container.read(deckProvider.notifier).swipe(_item2, 'rejected');
      await Future<void>.delayed(Duration.zero);

      expect(submitted.last, (domainCode: 'games', itemId: 2, status: 'rejected'));
    },
  );
}
