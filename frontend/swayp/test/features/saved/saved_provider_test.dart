import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:swayp/core/errors/app_exception.dart';
import 'package:swayp/data/repositories/domain_repository.dart';
import 'package:swayp/data/repositories/pending_confirmation_repository.dart';
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

typedef _ConfirmCall = ({String domainCode, int ratingId, String status});

class _FakePendingConfirmationRepository extends PendingConfirmationRepository {
  _FakePendingConfirmationRepository(super.ref, this._pending, {this.onConfirm, this.failWith});

  final List<PendingRating> _pending;
  final void Function(_ConfirmCall call)? onConfirm;
  final AppException? failWith;

  @override
  Future<List<PendingRating>> getPending(String domainCode) async => _pending;

  @override
  Future<void> confirm(String domainCode, int ratingId, String status) async {
    onConfirm?.call((domainCode: domainCode, ratingId: ratingId, status: status));
    if (failWith != null) throw failWith!;
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
        pendingConfirmationRepositoryProvider.overrideWith(
          (ref) => _FakePendingConfirmationRepository(ref, [_rating1, _rating2]),
        ),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(savedProvider.future);

    expect(result.map((rating) => rating.ratingId), [1, 2]);
  });

  test('confirmItem quita el item de la lista tras éxito', () async {
    final calls = <_ConfirmCall>[];
    final container = ProviderContainer(
      overrides: [
        domainsProvider.overrideWith((ref) => Future.value(const [_games])),
        pendingConfirmationRepositoryProvider.overrideWith(
          (ref) => _FakePendingConfirmationRepository(
            ref,
            [_rating1, _rating2],
            onConfirm: calls.add,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(savedProvider.future);

    await container.read(savedProvider.notifier).confirmItem(1, 'known_liked');

    expect(calls, [(domainCode: 'games', ratingId: 1, status: 'known_liked')]);
    expect(container.read(savedProvider).value?.map((rating) => rating.ratingId), [2]);
  });

  test('un fallo al confirmar no quita el item (permite reintentar)', () async {
    final container = ProviderContainer(
      overrides: [
        domainsProvider.overrideWith((ref) => Future.value(const [_games])),
        pendingConfirmationRepositoryProvider.overrideWith(
          (ref) => _FakePendingConfirmationRepository(
            ref,
            [_rating1, _rating2],
            failWith: const AppException(code: 'NETWORK_ERROR', message: 'Sin conexión'),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(savedProvider.future);

    // No debe lanzar ni tumbar el test.
    await container.read(savedProvider.notifier).confirmItem(1, 'known_liked');

    expect(container.read(savedProvider).value?.map((rating) => rating.ratingId), [1, 2]);
  });
}
