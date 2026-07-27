import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Configuración de rutas de la app (docs/ARCHITECTURE.md sección 4.2).
///
/// Por ahora solo existe la ruta raíz con una pantalla placeholder — las
/// rutas reales (selección de dominio, swipe, guardados, perfil...) se
/// añaden en los siguientes bloques, siguiendo la sección 7.
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const _PlaceholderScreen(),
    ),
  ],
);

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Swayp')));
  }
}
