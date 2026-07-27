import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/seed_repository.dart';
import '../../domain/models/item.dart';
import '../domain_selection/current_domain_provider.dart';

const int _seedCount = 10;

/// Mazo de ítems de Descubrir para el dominio activo (docs/ARCHITECTURE.md
/// sección 7.1). Se recarga automáticamente cuando cambia
/// [currentDomainProvider]. Deliberadamente NO es un `FutureProvider` puro:
/// el swipe (siguiente bloque) necesita poder quitar cartas del mazo sin
/// volver a pedir el seed, así que el estado vive en un `AsyncNotifier`
/// mutable — la carga inicial es async, pero el mazo en sí es mutable
/// después.
///
/// Nota: por ahora hay un único mazo activo (el del dominio actual), no uno
/// por dominio en caché simultáneamente (lo que docs/ARCHITECTURE.md sección
/// 4.3 describe como providers `family`, para no perder progreso al
/// alternar de dominio) — cambiar de dominio siempre vuelve a pedir el
/// seed. Se puede convertir a `family` más adelante si hace falta.
class DeckNotifier extends AsyncNotifier<List<Item>> {
  @override
  Future<List<Item>> build() async {
    final domain = await ref.watch(currentDomainProvider.future);
    if (domain == null) return const [];

    return ref.read(seedRepositoryProvider).getSeed(domain.code, count: _seedCount);
  }
}

final deckProvider = AsyncNotifierProvider<DeckNotifier, List<Item>>(DeckNotifier.new);
