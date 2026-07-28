import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/profile/profile_screen.dart';
import '../../features/recommendations/recommendations_screen.dart';
import '../../features/saved/saved_provider.dart';
import '../../features/saved/saved_screen.dart';

/// Shell de navegación principal (docs/ARCHITECTURE.md sección 7): barra de
/// navegación inferior con 3 pestañas. Descubrir y Guardados tienen
/// contenido real; Perfil sigue siendo un placeholder hasta un bloque
/// futuro. `IndexedStack` mantiene el estado de cada pestaña al cambiar
/// entre ellas — por eso Guardados no se reconstruye solo por hacerse
/// visible (ver invalidación de seguridad en [_AppShellState._onDestinationSelected]).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _selectedIndex = 0;

  static const List<Widget> _screens = [
    RecommendationsScreen(),
    SavedScreen(),
    ProfileScreen(),
  ];

  void _onDestinationSelected(int index) {
    if (index == 1) {
      // Guardados también se invalida tras un swipe "interested" con éxito
      // (deck_provider.dart), pero como vive en un IndexedStack y no se
      // reconstruye solo por hacerse visible, esto es una red de
      // seguridad extra al entrar en la pestaña.
      ref.invalidate(savedProvider);
    }
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Descubrir',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_outline),
            selectedIcon: Icon(Icons.bookmark),
            label: 'Guardados',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Perfil',
          ),
        ],
      ),
    );
  }
}
