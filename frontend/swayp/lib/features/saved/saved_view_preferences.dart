import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/pending_rating.dart';

const String _lastSeenSavedAtKey = 'saved_last_seen_at';
const String _sortOrderKey = 'saved_sort_order';

/// Orden de la lista de Guardados (docs/ARCHITECTURE.md sección 7.3):
/// alfabético por título, o más reciente primero por fecha de guardado.
enum SavedSortOrder { recent, alphabetical }

String _encodeSortOrder(SavedSortOrder order) => switch (order) {
  SavedSortOrder.recent => 'recent',
  SavedSortOrder.alphabetical => 'alphabetical',
};

SavedSortOrder _decodeSortOrder(String? value) => switch (value) {
  'alphabetical' => SavedSortOrder.alphabetical,
  _ => SavedSortOrder.recent,
};

/// Preferencia de orden de Guardados, persistida en `shared_preferences`
/// entre sesiones — mismo patrón que `theme_mode_provider.dart`: `build()`
/// devuelve el valor por defecto de inmediato y corrige el estado en cuanto
/// resuelve la lectura real en segundo plano.
class SavedSortOrderNotifier extends Notifier<SavedSortOrder> {
  @override
  SavedSortOrder build() {
    _loadPersisted();
    return SavedSortOrder.recent;
  }

  Future<void> _loadPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    if (!ref.mounted) return;
    state = _decodeSortOrder(prefs.getString(_sortOrderKey));
  }

  Future<void> setSortOrder(SavedSortOrder order) async {
    state = order;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sortOrderKey, _encodeSortOrder(order));
  }
}

final savedSortOrderProvider = NotifierProvider<SavedSortOrderNotifier, SavedSortOrder>(
  SavedSortOrderNotifier.new,
);

/// Umbral de "nuevo" en Guardados (docs/ARCHITECTURE.md sección 7.3): un
/// [PendingRating] es nuevo si se guardó después de la última vez que el
/// usuario abrió la pantalla. `null` mientras no se ha entrado nunca todavía
/// (nada que comparar: ver [isRatingNew], que trata `null` como "nada es
/// nuevo" para no bombardear de marcas la primera visita).
class LastSeenSavedAtNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  /// Se llama al ENTRAR en la pantalla de Guardados (no al salir): fija
  /// `state` al timestamp que había persistido de la visita anterior —el
  /// umbral que se usa para marcar "nuevo" durante ESTA visita— y solo
  /// entonces persiste [now] para la próxima vez. Si `state` se actualizara
  /// ya con el valor nuevo, la marca de "nuevo" desaparecería al instante en
  /// vez de aguantar toda la visita, tal como se pidió.
  Future<void> enterScreen(DateTime now) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_lastSeenSavedAtKey);
    if (ref.mounted) {
      state = stored != null ? DateTime.tryParse(stored) : null;
    }
    await prefs.setString(_lastSeenSavedAtKey, now.toIso8601String());
  }
}

final lastSeenSavedAtProvider = NotifierProvider<LastSeenSavedAtNotifier, DateTime?>(
  LastSeenSavedAtNotifier.new,
);

/// Si [rating] cuenta como "nuevo" frente al umbral [lastSeenAt] — función
/// pura y testeable, sin tocar Riverpod ni `shared_preferences` (eso lo
/// hacen los notifiers de arriba).
bool isRatingNew(PendingRating rating, DateTime? lastSeenAt) {
  if (lastSeenAt == null) return false;
  final createdAt = DateTime.tryParse(rating.createdAt);
  if (createdAt == null) return false;
  return createdAt.isAfter(lastSeenAt);
}

/// Ordena [ratings] según [order] — función pura y testeable. No muta la
/// lista de entrada.
List<PendingRating> sortSavedRatings(List<PendingRating> ratings, SavedSortOrder order) {
  final sorted = List<PendingRating>.of(ratings);
  switch (order) {
    case SavedSortOrder.alphabetical:
      sorted.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    case SavedSortOrder.recent:
      sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
  return sorted;
}
