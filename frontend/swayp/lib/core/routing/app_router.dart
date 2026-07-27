import 'package:go_router/go_router.dart';

import 'app_shell.dart';

/// Configuración de rutas de la app (docs/ARCHITECTURE.md sección 4.2).
///
/// '/' carga el shell de navegación principal (barra inferior de 3
/// pestañas, sección 7) directamente en Descubrir — no hay pantalla de
/// selección de dominio como ruta propia; el selector vive dentro de una
/// hoja inferior abierta desde el menú de Descubrir (sección 7.1).
final GoRouter appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (context, state) => const AppShell()),
  ],
);
