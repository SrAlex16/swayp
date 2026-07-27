import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/models/item.dart';
import '../domain_selection/current_domain_provider.dart';
import '../domain_selection/domain_picker_sheet.dart';
import 'deck_provider.dart';

/// Pantalla de Descubrir (docs/ARCHITECTURE.md sección 7.1) — pantalla de
/// arranque de la app. Muestra la carta superior del mazo del dominio
/// activo, con swipe real (gesto de arrastre + botones ✕/✓).
class RecommendationsScreen extends ConsumerWidget {
  const RecommendationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentDomainAsync = ref.watch(currentDomainProvider);
    final deckAsync = ref.watch(deckProvider);

    ref.listen<AppException?>(swipeErrorProvider, (previous, next) {
      if (next == null) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next.message)));
      ref.read(swipeErrorProvider.notifier).dismiss();
    });

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
      body: deckAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            _DeckError(error: error, onRetry: () => ref.invalidate(deckProvider)),
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('No hay más obras por ahora en este dominio'));
          }
          final topItem = items.first;
          void swipe(String status) => ref.read(deckProvider.notifier).swipe(topItem, status);

          return Column(
            children: [
              Expanded(
                child: _SwipeableCard(
                  key: ValueKey(topItem.itemId),
                  item: topItem,
                  onSwiped: swipe,
                ),
              ),
              _ActionButtonsRow(
                onReject: () => swipe('rejected'),
                onAccept: () => swipe('interested'),
              ),
            ],
          );
        },
      ),
    );
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

class _DeckError extends StatelessWidget {
  const _DeckError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = error is AppException
        ? (error as AppException).message
        : 'No se pudo cargar el mazo.';

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

/// Carta superior de la pila con gesto de arrastre horizontal
/// (docs/ARCHITECTURE.md sección 7.1): rotación/fade sutiles mientras se
/// arrastra; al superar el umbral de distancia dispara `onSwiped` con
/// "interested" (derecha) o "rejected" (izquierda) y suelta el arrastre. Si
/// no llega al umbral, la carta vuelve al centro.
class _SwipeableCard extends StatefulWidget {
  const _SwipeableCard({required super.key, required this.item, required this.onSwiped});

  final Item item;
  final ValueChanged<String> onSwiped;

  @override
  State<_SwipeableCard> createState() => _SwipeableCardState();
}

class _SwipeableCardState extends State<_SwipeableCard> {
  static const double _swipeThreshold = 120;

  Offset _dragOffset = Offset.zero;

  void _handlePanUpdate(DragUpdateDetails details) {
    setState(() => _dragOffset += details.delta);
  }

  void _handlePanEnd(DragEndDetails details) {
    if (_dragOffset.dx.abs() > _swipeThreshold) {
      widget.onSwiped(_dragOffset.dx > 0 ? 'interested' : 'rejected');
      return;
    }
    setState(() => _dragOffset = Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    final angle = _dragOffset.dx / 800;
    final opacity = (1 - (_dragOffset.dx.abs() / 400)).clamp(0.4, 1.0);

    return GestureDetector(
      onPanUpdate: _handlePanUpdate,
      onPanEnd: _handlePanEnd,
      child: Transform.translate(
        offset: _dragOffset,
        child: Transform.rotate(
          angle: angle,
          child: Opacity(opacity: opacity, child: _TopCard(item: widget.item)),
        ),
      ),
    );
  }
}

/// Contenido visual de la carta: imagen a pantalla casi completa con
/// overlay inferior mostrando el título (docs/ARCHITECTURE.md sección 7.1).
class _TopCard extends StatelessWidget {
  const _TopCard({required this.item});

  final Item item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _CardImage(imageUrl: item.imageUrl),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75)],
                  ),
                ),
                child: Text(
                  item.title,
                  style: Theme.of(
                    context,
                  ).textTheme.headlineSmall?.copyWith(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardImage extends StatelessWidget {
  const _CardImage({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null) {
      return const ColoredBox(
        color: Colors.black12,
        child: Center(child: Icon(Icons.image_not_supported_outlined, size: 48)),
      );
    }

    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => const ColoredBox(
        color: Colors.black12,
        child: Center(child: Icon(Icons.broken_image_outlined, size: 48)),
      ),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const Center(child: CircularProgressIndicator());
      },
    );
  }
}

/// Botones espejo del gesto de swipe (docs/ARCHITECTURE.md sección 7.1).
class _ActionButtonsRow extends StatelessWidget {
  const _ActionButtonsRow({required this.onReject, required this.onAccept});

  final VoidCallback onReject;
  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ActionButton(icon: Icons.close, color: Colors.red, onPressed: onReject),
          const SizedBox(width: 32),
          _ActionButton(icon: Icons.favorite, color: Colors.green, onPressed: onAccept),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.color, required this.onPressed});

  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: null,
      backgroundColor: Theme.of(context).colorScheme.surface,
      foregroundColor: color,
      onPressed: onPressed,
      child: Icon(icon),
    );
  }
}
