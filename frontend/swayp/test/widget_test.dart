import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:swayp/data/repositories/domain_repository.dart';
import 'package:swayp/domain/models/domain.dart';
import 'package:swayp/main.dart';

void main() {
  testWidgets('la app arranca en Descubrir con la barra de navegación de 3 pestañas', (
    WidgetTester tester,
  ) async {
    // domainsProvider se sobreescribe para no depender de una llamada de red
    // real en el test (evita, entre otras cosas, dejar un Timer de
    // conexión de dio pendiente cuando el test termina antes de que
    // resuelva o falle por su cuenta). shared_preferences necesita valores
    // mock: sin ellos, currentDomainProvider se queda colgado intentando
    // hablar con un platform channel que no existe en el entorno de test,
    // y el spinner indeterminado nunca deja asentar pumpAndSettle.
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          domainsProvider.overrideWith(
            (ref) => Future.value(const [Domain(code: 'games', displayName: 'Videojuegos')]),
          ),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Descubrir'), findsWidgets);
    expect(find.text('Guardados'), findsWidgets);
    expect(find.text('Perfil'), findsWidgets);
  });
}
