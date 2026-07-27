import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/repositories/domain_repository.dart';
import '../../domain/models/domain.dart';

const String _currentDomainCodeKey = 'current_domain_code';

/// Dominio activo de la app (docs/ARCHITECTURE.md sección 7.1): persistido
/// en `shared_preferences` entre aperturas. Si no hay nada guardado
/// (primera apertura), se usa el primero que devuelva `GET /domains`.
class CurrentDomainNotifier extends AsyncNotifier<Domain?> {
  @override
  Future<Domain?> build() async {
    final domains = await ref.watch(domainsProvider.future);
    if (domains.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final storedCode = prefs.getString(_currentDomainCodeKey);

    if (storedCode != null) {
      for (final domain in domains) {
        if (domain.code == storedCode) return domain;
      }
    }

    return domains.first;
  }

  /// Cambia el dominio activo y lo persiste para la próxima apertura.
  ///
  /// Persiste primero y solo entonces invalida [build] (en vez de asignar
  /// `state` a mano aquí) para que [build] siga siendo la única fuente de
  /// verdad del estado: un provider no puede leer su propio `.future` (Riverpod
  /// lo trata como auto-dependencia y lo prohíbe), así que no hay forma de
  /// esperar aquí mismo al rebuild — quien necesite el valor ya asentado lo
  /// lee/observa desde fuera, como ya hace la UI vía `ref.watch`. Esto
  /// también evita una condición de carrera si `changeDomain` se llama
  /// mientras el build inicial todavía está resolviendo: como solo [build]
  /// asigna `state`, el resultado final siempre es consistente aunque haya
  /// un build de por medio a medio terminar.
  Future<void> changeDomain(Domain domain) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentDomainCodeKey, domain.code);
    ref.invalidateSelf();
  }
}

final currentDomainProvider = AsyncNotifierProvider<CurrentDomainNotifier, Domain?>(
  CurrentDomainNotifier.new,
);
