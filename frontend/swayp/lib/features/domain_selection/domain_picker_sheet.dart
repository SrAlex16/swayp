import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../data/repositories/domain_repository.dart';
import '../../domain/models/domain.dart';
import 'current_domain_provider.dart';

/// Selector de dominio (docs/ARCHITECTURE.md sección 7.1) — NO es una
/// pantalla de ruta propia, es el contenido de un `showModalBottomSheet`
/// abierto desde el menú de Descubrir ("Cambiar de obras"). Tocar un
/// dominio lo hace activo, lo persiste y cierra la hoja.
class DomainPickerSheet extends ConsumerWidget {
  const DomainPickerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final domainsAsync = ref.watch(domainsProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Elige un dominio', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            domainsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, stackTrace) => _DomainPickerError(
                error: error,
                onRetry: () => ref.invalidate(domainsProvider),
              ),
              data: (domains) => _DomainList(domains: domains),
            ),
          ],
        ),
      ),
    );
  }
}

class _DomainPickerError extends StatelessWidget {
  const _DomainPickerError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = error is AppException
        ? (error as AppException).message
        : 'No se pudieron cargar los dominios.';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}

class _DomainList extends ConsumerWidget {
  const _DomainList({required this.domains});

  final List<Domain> domains;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final domain in domains)
          ListTile(
            title: Text(domain.displayName),
            onTap: () {
              ref.read(currentDomainProvider.notifier).changeDomain(domain);
              Navigator.pop(context);
            },
          ),
      ],
    );
  }
}
