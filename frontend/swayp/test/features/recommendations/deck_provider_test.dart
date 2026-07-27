import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:swayp/core/errors/app_exception.dart';
import 'package:swayp/data/repositories/domain_repository.dart';
import 'package:swayp/data/repositories/ratings_repository.dart';
import 'package:swayp/data/repositories/seed_repository.dart';
import 'package:swayp/domain/models/domain.dart';
import 'package:swayp/domain/models/item.dart';
import 'package:swayp/features/recommendations/deck_provider.dart';

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

class _FakeRatingsRepository extends RatingsRepository {
  _FakeRatingsRepository(super.ref, {this.onSubmit, this.failWith});

  final void Function(_SubmittedRating rating)? onSubmit;
  final AppException? failWith;

  @override
  Future<void> submitRating({
    required String domainCode,
    required int itemId,
    required String status,
  }) async {
    onSubmit?.call((domainCode: domainCode, itemId: itemId, status: status));
    if (failWith != null) throw failWith!;
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
}
