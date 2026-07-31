import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../core/theme/theme_mode_provider.dart';
import '../../domain/models/item.dart';
import '../domain_selection/current_domain_provider.dart';
import '../domain_selection/domain_picker_sheet.dart';
import 'deck_provider.dart';

/// Pantalla de Descubrir (docs/ARCHITECTURE.md sección 7.1) — pantalla de
/// arranque de la app. Muestra la carta superior del mazo del dominio
/// activo, con swipe real (gesto de arrastre + botones ✕/✓), undo de un
/// solo nivel (sección 10) y un botón dedicado para omitir sin ningún flujo
/// de confirmación adicional.
class RecommendationsScreen extends ConsumerWidget {
  const RecommendationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentDomainAsync = ref.watch(currentDomainProvider);
    final deckAsync = ref.watch(deckProvider);
    final canUndo = ref.watch(canUndoProvider);

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
          void swipe(String status) {
            ref.read(deckProvider.notifier).swipe(topItem, status);
          }

          Future<void> blacklist() async {
            final result = await ref.read(deckProvider.notifier).blacklistCurrent(topItem);
            if (!context.mounted) return;
            final collectionName = result?.collectionBlacklisted;
            final message = collectionName != null
                ? "No se te volverán a recomendar películas de '$collectionName'"
                : 'No se te volverá a mostrar';
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
          }

          return Column(
            children: [
              Expanded(
                child: _SwipeableCard(
                  key: ValueKey(topItem.itemId),
                  item: topItem,
                  onSwiped: swipe,
                  onBlacklist: blacklist,
                ),
              ),
              _ActionButtonsRow(
                onReject: () => swipe('rejected'),
                onAccept: () => swipe('interested'),
                onSkip: () => ref.read(deckProvider.notifier).skip(topItem),
                canUndo: canUndo,
                onUndo: () => ref.read(deckProvider.notifier).undo(),
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

    if (!context.mounted) return;

    switch (selection) {
      case _MenuAction.changeDomain:
        showModalBottomSheet(
          context: context,
          showDragHandle: true,
          builder: (context) => const DomainPickerSheet(),
        );
      case _MenuAction.theme:
        showModalBottomSheet(
          context: context,
          showDragHandle: true,
          builder: (context) => const _ThemeModeSheet(),
        );
      case null:
        break;
    }
  }
}

enum _MenuAction { changeDomain, theme }

/// Menú de acciones de Descubrir (docs/ARCHITECTURE.md sección 7.1),
/// pensado para crecer con más opciones más adelante.
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
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('Tema'),
            onTap: () => Navigator.pop(context, _MenuAction.theme),
          ),
        ],
      ),
    );
  }
}

/// Selector manual de tema (Sistema/Claro/Oscuro), sobre el
/// `ThemeMode.system` por defecto — hoja aparte abierta desde el menú
/// principal.
class _ThemeModeSheet extends ConsumerWidget {
  const _ThemeModeSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = ref.watch(themeModeProvider);

    return SafeArea(
      child: RadioGroup<ThemeMode>(
        groupValue: currentMode,
        onChanged: (value) {
          if (value == null) return;
          ref.read(themeModeProvider.notifier).setThemeMode(value);
          Navigator.pop(context);
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in ThemeMode.values)
              RadioListTile<ThemeMode>(title: Text(_themeModeLabel(mode)), value: mode),
          ],
        ),
      ),
    );
  }

  String _themeModeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'Sistema',
    ThemeMode.light => 'Claro',
    ThemeMode.dark => 'Oscuro',
  };
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
/// no llega al umbral, la carta vuelve al centro. [onSwiped] manda el
/// estado real `interested`/`rejected` al backend; omitir vive aparte, en
/// el botón dedicado de [_ActionButtonsRow].
class _SwipeableCard extends StatefulWidget {
  const _SwipeableCard({
    required super.key,
    required this.item,
    required this.onSwiped,
    required this.onBlacklist,
  });

  final Item item;
  final ValueChanged<String> onSwiped;
  final VoidCallback onBlacklist;

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
          child: Opacity(
            opacity: opacity,
            child: Stack(
              children: [
                _TopCard(item: widget.item),
                Positioned(top: 24, left: 24, child: _BlacklistButton(onTap: widget.onBlacklist)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bloqueo permanente del ítem actual (docs/ARCHITECTURE.md sección 3.3):
/// visualmente distinto de los botones ✕/✓/omitir — icono de "bloquear",
/// para que no se confunda con una opción reversible.
class _BlacklistButton extends StatelessWidget {
  const _BlacklistButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: IconButton(
        icon: const Icon(Icons.block, color: Colors.white),
        tooltip: 'No volver a mostrar',
        onPressed: onTap,
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

/// Botones espejo del gesto de swipe (docs/ARCHITECTURE.md sección 7.1),
/// más el de "volver atrás" (sección 10) entre medio — deshabilitado si no
/// hay nada que deshacer.
class _ActionButtonsRow extends StatelessWidget {
  const _ActionButtonsRow({
    required this.onReject,
    required this.onAccept,
    required this.onSkip,
    required this.canUndo,
    required this.onUndo,
  });

  final VoidCallback onReject;
  final VoidCallback onAccept;
  final VoidCallback onSkip;
  final bool canUndo;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ActionButton(icon: Icons.close, color: Colors.red, onPressed: onReject),
          const SizedBox(width: 24),
          _ActionButton(
            icon: Icons.undo,
            color: Colors.grey.shade700,
            onPressed: canUndo ? onUndo : null,
          ),
          const SizedBox(width: 24),
          _ActionButton(icon: Icons.favorite, color: Colors.green, onPressed: onAccept),
          const SizedBox(width: 24),
          _ActionButton(icon: Icons.skip_next, color: Colors.orange, onPressed: onSkip),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.color, required this.onPressed});

  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: null,
      backgroundColor: Theme.of(context).colorScheme.surface,
      foregroundColor: onPressed == null ? Theme.of(context).disabledColor : color,
      onPressed: onPressed,
      child: Icon(icon),
    );
  }
}
