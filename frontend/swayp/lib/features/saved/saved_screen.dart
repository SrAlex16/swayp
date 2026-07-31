import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/models/pending_rating.dart';
import 'saved_provider.dart';
import 'saved_view_preferences.dart';

/// Pantalla de Guardados (docs/ARCHITECTURE.md sección 7.3): ratings
/// `interested` que el usuario ha guardado desde el swipe. Ya no hay ningún
/// flujo de confirmación — cada fila se puede quitar directamente (swipe o
/// icono de papelera) o rechazar, sin pasos intermedios.
class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final savedAsync = ref.watch(savedProvider);
    final sortOrder = ref.watch(savedSortOrderProvider);
    final lastSeenAt = ref.watch(lastSeenSavedAtProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Guardados'),
        actions: [
          PopupMenuButton<SavedSortOrder>(
            tooltip: 'Ordenar',
            icon: const Icon(Icons.sort),
            initialValue: sortOrder,
            onSelected: (order) =>
                ref.read(savedSortOrderProvider.notifier).setSortOrder(order),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: SavedSortOrder.recent,
                child: Text('Más reciente primero'),
              ),
              PopupMenuItem(
                value: SavedSortOrder.alphabetical,
                child: Text('Alfabético'),
              ),
            ],
          ),
        ],
      ),
      body: savedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            _SavedError(error: error, onRetry: () => ref.invalidate(savedProvider)),
        data: (ratings) {
          if (ratings.isEmpty) {
            return const Center(child: Text('No tienes nada guardado por ahora'));
          }
          final sorted = sortSavedRatings(ratings, sortOrder);
          return ListView.builder(
            itemCount: sorted.length,
            itemBuilder: (context, index) {
              final rating = sorted[index];
              return Dismissible(
                key: ValueKey(rating.ratingId),
                direction: DismissDirection.endToStart,
                background: const _DismissBackground(),
                onDismissed: (_) => ref.read(savedProvider.notifier).remove(rating.ratingId),
                child: ListTile(
                  leading: _Thumbnail(imageUrl: rating.imageUrl),
                  title: Text(rating.title),
                  trailing: isRatingNew(rating, lastSeenAt) ? const _NewBadge() : null,
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    builder: (context) => _SavedActionsSheet(rating: rating),
                  ),
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

/// Fondo rojo con icono de papelera tras la fila al arrastrarla (swipe-to-
/// delete de [Dismissible]) — misma acción que el botón "Eliminar" del
/// bottom sheet, solo que sin abrirlo.
class _DismissBackground extends StatelessWidget {
  const _DismissBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.errorContainer,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.onErrorContainer),
    );
  }
}

/// Punto sutil que marca una fila como recién guardada desde la última
/// visita a Guardados (docs/ARCHITECTURE.md sección 7.3).
class _NewBadge extends StatelessWidget {
  const _NewBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
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

/// Acciones sobre un item guardado: rechazarlo (sigue siendo un rating,
/// solo cambia a `rejected`) o eliminarlo directamente (mismo efecto que el
/// swipe-to-delete de la fila). Sin ningún paso de confirmación intermedio.
class _SavedActionsSheet extends ConsumerWidget {
  const _SavedActionsSheet({required this.rating});

  final PendingRating rating;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: Text(
              rating.title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ),
          ListTile(
            leading: const Icon(Icons.thumb_down_outlined),
            title: const Text('Rechazar'),
            onTap: () {
              ref.read(savedProvider.notifier).updateItem(rating.ratingId, 'rejected');
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Eliminar'),
            onTap: () {
              ref.read(savedProvider.notifier).remove(rating.ratingId);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }
}
