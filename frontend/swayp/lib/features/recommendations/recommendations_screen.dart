import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../domain_selection/current_domain_provider.dart';
import '../domain_selection/domain_picker_sheet.dart';

/// Pantalla de Descubrir (docs/ARCHITECTURE.md sección 7.1) — pantalla de
/// arranque de la app. Contenido mínimo por ahora: confirma que el dominio
/// activo carga y se puede cambiar de principio a fin. El swipe real se
/// construye en el siguiente bloque.
class RecommendationsScreen extends ConsumerWidget {
  const RecommendationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentDomainAsync = ref.watch(currentDomainProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(currentDomainAsync.value?.displayName ?? 'Descubrir'),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu),
            tooltip: 'Menú',
            onPressed: () => _openMainMenu(context),
          ),
        ],
      ),
      body: currentDomainAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text(_errorMessage(error))),
        data: (domain) => Center(
          child: Text(
            domain == null
                ? 'No hay dominios disponibles.'
                : 'Swipe de ${domain.displayName} (próximamente)',
          ),
        ),
      ),
    );
  }

  String _errorMessage(Object error) {
    return error is AppException ? error.message : 'No se pudo cargar el dominio activo.';
  }

  Future<void> _openMainMenu(BuildContext context) async {
    final selection = await showModalBottomSheet<_MenuAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => const _MainMenuSheet(),
    );

    if (selection == _MenuAction.changeDomain && context.mounted) {
      showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (context) => const DomainPickerSheet(),
      );
    }
  }
}

enum _MenuAction { changeDomain }

/// Menú de acciones de Descubrir. Por ahora solo tiene "Cambiar de obras";
/// pensado para crecer con más opciones más adelante (docs/ARCHITECTURE.md
/// sección 7.1).
class _MainMenuSheet extends StatelessWidget {
  const _MainMenuSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('Cambiar de obras'),
            onTap: () => Navigator.pop(context, _MenuAction.changeDomain),
          ),
        ],
      ),
    );
  }
}
