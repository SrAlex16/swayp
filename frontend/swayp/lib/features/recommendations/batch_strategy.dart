import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Con menos de [recommendationThreshold] swipes en el dominio, el
/// siguiente lote se pide vía `/seed` en vez del motor de recomendación
/// (no hay señal suficiente todavía para que el motor aporte algo mejor
/// que una muestra aleatoria).
const int recommendationThreshold = 5;

/// Cada [diversityBatchInterval]-ésimo lote se pide vía `/seed` aunque ya
/// se haya cruzado el umbral, para inyectar variedad y no encerrar al
/// usuario en un bucle de recomendaciones cada vez más parecidas entre sí.
const int diversityBatchInterval = 3;

enum BatchSource { seed, engine }

/// Decisión de origen del siguiente lote — función pura y testeable: recibe
/// los contadores ya leídos, no toca `shared_preferences` directamente
/// (eso lo hace [BatchStrategyStore]).
///
/// [batchCount] es el número de lote que se está a punto de pedir, 1-based
/// (el primer lote de un dominio es el 1, no el 0).
BatchSource decideBatchSource({
  required int swipeCount,
  required int batchCount,
  int threshold = recommendationThreshold,
  int diversityInterval = diversityBatchInterval,
}) {
  if (diversityInterval > 0 && batchCount % diversityInterval == 0) {
    return BatchSource.seed;
  }
  if (swipeCount < threshold) {
    return BatchSource.seed;
  }
  return BatchSource.engine;
}

/// Contadores locales por dominio (docs de la sesión: sin endpoint nuevo en
/// el backend para esto, todo vive en `shared_preferences` del cliente).
class BatchStrategyStore {
  const BatchStrategyStore();

  String _swipeCountKey(String domainCode) => 'swipe_count_$domainCode';
  String _batchCountKey(String domainCode) => 'batch_count_$domainCode';

  /// Incrementa el contador de swipes de [domainCode]. Lo llama
  /// `deck_provider.dart` tras cada envío de rating con éxito, sin
  /// distinguir por `status` — es un conteo de actividad, no solo de
  /// "interested".
  Future<void> incrementSwipeCount(String domainCode) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_swipeCountKey(domainCode)) ?? 0;
    await prefs.setInt(_swipeCountKey(domainCode), current + 1);
  }

  /// Decide el origen del siguiente lote para [domainCode] y avanza (y
  /// persiste) el contador de lotes — siempre, sin importar qué origen se
  /// haya elegido, porque "cada 3er lote" cuenta todos los lotes pedidos,
  /// no solo los que fueron al motor.
  Future<BatchSource> nextBatchSource(String domainCode) async {
    final prefs = await SharedPreferences.getInstance();
    final swipeCount = prefs.getInt(_swipeCountKey(domainCode)) ?? 0;
    final batchCount = (prefs.getInt(_batchCountKey(domainCode)) ?? 0) + 1;
    await prefs.setInt(_batchCountKey(domainCode), batchCount);

    return decideBatchSource(swipeCount: swipeCount, batchCount: batchCount);
  }
}

final batchStrategyStoreProvider = Provider<BatchStrategyStore>(
  (ref) => const BatchStrategyStore(),
);
