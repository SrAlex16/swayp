import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:swayp/core/errors/app_exception.dart';
import 'package:swayp/data/repositories/domain_repository.dart';
import 'package:swayp/data/repositories/saved_repository.dart';
import 'package:swayp/domain/models/domain.dart';
import 'package:swayp/domain/models/pending_rating.dart';
import 'package:swayp/features/saved/saved_provider.dart';

const _games = Domain(code: 'games', displayName: 'Videojuegos');

const _rating1 = PendingRating(
  ratingId: 1,
  itemId: 10,
  title: 'Dark Souls',
  imageUrl: null,
  externalUrl: null,
  status: 'interested',
  createdAt: '2026-07-27 10:00:00',
);
const _rating2 = PendingRating(
  ratingId: 2,
  itemId: 20,
  title: 'Cuphead',
  imageUrl: null,
  externalUrl: null,
  status: 'interested',
  createdAt: '2026-07-27 10:05:00',
);

typedef _UpdateStatusCall = ({String domainCode, int ratingId, String status});
typedef _RemoveCall = ({String domainCode, int ratingId});

class _FakeSavedRepository extends SavedRepository {
  _FakeSavedRepository(
    super.ref,
    this._pending, {
    this.onUpdateStatus,
    this.updateStatusFailWith,
    this.onRemove,
    this.removeFailWith,
  });

  final List<PendingRating> _pending;
  final void Function(_UpdateStatusCall call)? onUpdateStatus;
  final AppException? updateStatusFailWith;
  final void Function(_RemoveCall call)? onRemove;
  final AppException? removeFailWith;

  @override
  Future<List<PendingRating>> getSavedRatings(String domainCode) async => _pending;

  @override
  Future<void> updateRatingStatus(String domainCode, int ratingId, String status) async {
    onUpdateStatus?.call((domainCode: domainCode, ratingId: ratingId, status: status));
    if (updateStatusFailWith != null) throw updateStatusFailWith!;
  }

  @override
  Future<void> removeFromSaved(String domainCode, int ratingId) async {
    onRemove?.call((domainCode: domainCode, ratingId: ratingId));
    if (removeFailWith != null) throw removeFailWith!;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('carga la lista de pendientes de confirmar', () async {
    final container = ProviderContainer(
      overrides: [
        domainsProvider.overrideWith((ref) => Future.value(const [_games])),
        savedRepositoryProvider.overrideWith(
          (ref) => _FakeSavedRepository(ref, [_rating1, _rating2]),
        ),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(savedProvider.future);

    expect(result.map((rating) => rating.ratingId), [1, 2]);
  });

  test('updateItem quita el item de la lista tras éxito', () async {
    final calls = <_UpdateStatusCall>[];
    final container = ProviderContainer(
      overrides: [
        domainsProvider.overrideWith((ref) => Future.value(const [_games])),
        savedRepositoryProvider.overrideWith(
          (ref) => _FakeSavedRepository(
            ref,
            [_rating1, _rating2],
            onUpdateStatus: calls.add,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(savedProvider.future);

    await container.read(savedProvider.notifier).updateItem(1, 'rejected');

    expect(calls, [(domainCode: 'games', ratingId: 1, status: 'rejected')]);
    expect(container.read(savedProvider).value?.map((rating) => rating.ratingId), [2]);
  });

  test('un fallo al actualizar no quita el item (permite reintentar)', () async {
    final container = ProviderContainer(
      overrides: [
        domainsProvider.overrideWith((ref) => Future.value(const [_games])),
        savedRepositoryProvider.overrideWith(
          (ref) => _FakeSavedRepository(
            ref,
            [_rating1, _rating2],
            updateStatusFailWith: const AppException(code: 'NETWORK_ERROR', message: 'Sin conexión'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(savedProvider.future);

    // No debe lanzar ni tumbar el test.
    await container.read(savedProvider.notifier).updateItem(1, 'rejected');

    expect(container.read(savedProvider).value?.map((rating) => rating.ratingId), [1, 2]);
  });

  test('remove() quita el item de la lista de inmediato y llama al DELETE', () async {
    final calls = <_RemoveCall>[];
    final container = ProviderContainer(
      overrides: [
        domainsProvider.overrideWith((ref) => Future.value(const [_games])),
        savedRepositoryProvider.overrideWith(
          (ref) => _FakeSavedRepository(ref, [_rating1, _rating2], onRemove: calls.add),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(savedProvider.future);

    final future = container.read(savedProvider.notifier).remove(1);

    // Optimista: desaparece antes de que el DELETE en segundo plano termine.
    expect(container.read(savedProvider).value?.map((rating) => rating.ratingId), [2]);

    await future;

    expect(calls, [(domainCode: 'games', ratingId: 1)]);
    expect(container.read(savedProvider).value?.map((rating) => rating.ratingId), [2]);
  });

  test('remove() revierte a la lista anterior si el DELETE falla', () async {
    final container = ProviderContainer(
      overrides: [
        domainsProvider.overrideWith((ref) => Future.value(const [_games])),
        savedRepositoryProvider.overrideWith(
          (ref) => _FakeSavedRepository(
            ref,
            [_rating1, _rating2],
            removeFailWith: const AppException(code: 'NETWORK_ERROR', message: 'Sin conexión'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(savedProvider.future);

    await container.read(savedProvider.notifier).remove(1);

    // A diferencia de un swipe fallido, aquí sí se reinserta: la lista
    // completa vuelve a como estaba antes del intento de borrado.
    expect(container.read(savedProvider).value?.map((rating) => rating.ratingId), [1, 2]);
  });
}
