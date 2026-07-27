import 'package:flutter/material.dart';

import '../../features/profile/profile_screen.dart';
import '../../features/recommendations/recommendations_screen.dart';
import '../../features/saved/saved_screen.dart';

/// Shell de navegación principal (docs/ARCHITECTURE.md sección 7): barra de
/// navegación inferior con 3 pestañas. Descubrir es la única con contenido
/// real por ahora; Guardados y Perfil son placeholders hasta bloques
/// futuros. `IndexedStack` mantiene el estado de cada pestaña al cambiar
/// entre ellas.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  static const List<Widget> _screens = [
    RecommendationsScreen(),
    SavedScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) => setState(() => _selectedIndex = index),
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
