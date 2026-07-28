import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:swayp/features/recommendations/batch_strategy.dart';

void main() {
  group('decideBatchSource (función pura)', () {
    test('con menos de 5 swipes, usa seed', () {
      expect(decideBatchSource(swipeCount: 0, batchCount: 1), BatchSource.seed);
      expect(decideBatchSource(swipeCount: 4, batchCount: 2), BatchSource.seed);
    });

    test('con 5 o más swipes, usa el motor', () {
      expect(decideBatchSource(swipeCount: 5, batchCount: 1), BatchSource.engine);
      expect(decideBatchSource(swipeCount: 100, batchCount: 2), BatchSource.engine);
    });

    test('cada 3er lote usa seed sin importar el umbral', () {
      expect(decideBatchSource(swipeCount: 100, batchCount: 3), BatchSource.seed);
      expect(decideBatchSource(swipeCount: 100, batchCount: 6), BatchSource.seed);
      expect(decideBatchSource(swipeCount: 100, batchCount: 9), BatchSource.seed);
      // Los que no son múltiplos de 3 siguen la regla normal del umbral.
      expect(decideBatchSource(swipeCount: 100, batchCount: 4), BatchSource.engine);
      expect(decideBatchSource(swipeCount: 100, batchCount: 5), BatchSource.engine);
    });

    test('umbral e intervalo de diversidad son configurables', () {
      expect(decideBatchSource(swipeCount: 2, batchCount: 1, threshold: 2), BatchSource.engine);
      expect(
        decideBatchSource(swipeCount: 100, batchCount: 2, diversityInterval: 2),
        BatchSource.seed,
      );
    });
  });

  group('BatchStrategyStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('incrementSwipeCount incrementa y persiste por dominio', () async {
      const store = BatchStrategyStore();

      await store.incrementSwipeCount('games');
      await store.incrementSwipeCount('games');
      await store.incrementSwipeCount('movies');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('swipe_count_games'), 2);
      expect(prefs.getInt('swipe_count_movies'), 1);
    });

    test('nextBatchSource combina los contadores persistidos con la regla pura', () async {
      const store = BatchStrategyStore();

      // Lote 1: sin swipes todavía -> seed.
      expect(await store.nextBatchSource('games'), BatchSource.seed);
      // Lote 2: sigue sin swipes -> seed.
      expect(await store.nextBatchSource('games'), BatchSource.seed);

      for (var i = 0; i < 10; i++) {
        await store.incrementSwipeCount('games');
      }

      // Lote 3 (múltiplo de 3): seed por diversidad, aunque ya haya swipes de sobra.
      expect(await store.nextBatchSource('games'), BatchSource.seed);
      // Lote 4: ya no es múltiplo de 3 y hay swipes de sobra -> motor.
      expect(await store.nextBatchSource('games'), BatchSource.engine);
    });

    test('los contadores son independientes por dominio', () async {
      const store = BatchStrategyStore();

      for (var i = 0; i < 10; i++) {
        await store.incrementSwipeCount('games');
      }

      // "movies" no tiene swipes propios todavía, aunque "games" sí -> seed.
      expect(await store.nextBatchSource('movies'), BatchSource.seed);
    });
  });
}
