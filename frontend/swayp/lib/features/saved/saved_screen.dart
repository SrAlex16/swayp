import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/models/pending_rating.dart';
import 'saved_provider.dart';

/// Pantalla de Guardados (docs/ARCHITECTURE.md sección 7.3): ratings
/// `interested` que el usuario ha guardado desde el swipe. Tocar una fila
/// permite quitarla del listado cambiando el rating a `rejected` o
/// eliminándolo con el botón de borrar.
class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedAsync = ref.watch(savedProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Guardados')),
      body: savedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            _SavedError(error: error, onRetry: () => ref.invalidate(savedProvider)),
        data: (ratings) {
          if (ratings.isEmpty) {
            return const Center(child: Text('No tienes nada guardado por ahora'));
          }
          return ListView.builder(
            itemCount: ratings.length,
            itemBuilder: (context, index) {
              final rating = ratings[index];
              return ListTile(
                leading: _Thumbnail(imageUrl: rating.imageUrl),
                title: Text(rating.title),
                onTap: () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  builder: (context) => _SavedActionsSheet(rating: rating),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _SavedError extends StatelessWidget {
  const _SavedError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = error is AppException
        ? (error as AppException).message
        : 'No se pudo cargar Guardados.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.imageUrl});

  final String? imageUrl;

  static const double _size = 48;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null) {
      return const SizedBox(
        width: _size,
        height: _size,
        child: Icon(Icons.image_not_supported_outlined),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image_outlined),
      ),
    );
  }
}

/// Acciones simples para un item guardado: rechazarlo o quitarlo del listado.
class _SavedActionsSheet extends ConsumerWidget {
  const _SavedActionsSheet({required this.rating});

  final PendingRating rating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              rating.title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                OutlinedButton(
                  onPressed: () {
                    ref.read(savedProvider.notifier).updateItem(rating.ratingId, 'rejected');
                    Navigator.pop(context);
                  },
                  child: const Text('Rechazar'),
                ),
                FilledButton(
                  onPressed: () {
                    ref.read(savedProvider.notifier).updateItem(rating.ratingId, 'rejected');
                    Navigator.pop(context);
                  },
                  child: const Text('Quitar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
