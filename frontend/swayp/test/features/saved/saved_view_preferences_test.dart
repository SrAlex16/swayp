import 'package:flutter_test/flutter_test.dart';

import 'package:swayp/domain/models/pending_rating.dart';
import 'package:swayp/features/saved/saved_view_preferences.dart';

const _olderRating = PendingRating(
  ratingId: 1,
  itemId: 10,
  title: 'Zootopia',
  imageUrl: null,
  externalUrl: null,
  status: 'interested',
  createdAt: '2026-07-27 10:00:00',
);
const _newerRating = PendingRating(
  ratingId: 2,
  itemId: 20,
  title: 'Avengers',
  imageUrl: null,
  externalUrl: null,
  status: 'interested',
  createdAt: '2026-07-29 10:00:00',
);

void main() {
  group('isRatingNew', () {
    test('es nuevo si createdAt es posterior al umbral', () {
      final lastSeenAt = DateTime.parse('2026-07-28 00:00:00');

      expect(isRatingNew(_newerRating, lastSeenAt), true);
    });

    test('no es nuevo si createdAt es anterior al umbral', () {
      final lastSeenAt = DateTime.parse('2026-07-28 00:00:00');

      expect(isRatingNew(_olderRating, lastSeenAt), false);
    });

    test('no es nuevo si createdAt es exactamente el umbral', () {
      final lastSeenAt = DateTime.parse('2026-07-27 10:00:00');

      expect(isRatingNew(_olderRating, lastSeenAt), false);
    });

    test('sin umbral (primera vez que se abre Guardados), nada es nuevo', () {
      expect(isRatingNew(_newerRating, null), false);
    });
  });

  group('sortSavedRatings', () {
    test('recent ordena por createdAt descendente', () {
      final sorted = sortSavedRatings([_olderRating, _newerRating], SavedSortOrder.recent);

      expect(sorted.map((r) => r.ratingId), [2, 1]);
    });

    test('alphabetical ordena por título ascendente, sin distinguir mayúsculas', () {
      final sorted = sortSavedRatings(
        [_olderRating, _newerRating],
        SavedSortOrder.alphabetical,
      );

      expect(sorted.map((r) => r.ratingId), [2, 1]); // Avengers antes que Zootopia
    });

    test('no muta la lista de entrada', () {
      final input = [_olderRating, _newerRating];
      sortSavedRatings(input, SavedSortOrder.alphabetical);

      expect(input.map((r) => r.ratingId), [1, 2]);
    });
  });
}
