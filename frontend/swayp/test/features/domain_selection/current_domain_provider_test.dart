import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:swayp/data/repositories/domain_repository.dart';
import 'package:swayp/domain/models/domain.dart';
import 'package:swayp/features/domain_selection/current_domain_provider.dart';

const _games = Domain(code: 'games', displayName: 'Videojuegos');
const _movies = Domain(code: 'movies', displayName: 'Películas');

ProviderContainer _buildContainer() {
  return ProviderContainer(
    overrides: [domainsProvider.overrideWith((ref) => Future.value(const [_games, _movies]))],
  );
}

void main() {
  test('sin nada persistido, usa el primer dominio de la lista', () async {
    SharedPreferences.setMockInitialValues({});
    final container = _buildContainer();
    addTearDown(container.dispose);

    final result = await container.read(currentDomainProvider.future);

    expect(result?.code, 'games');
  });

  test('con un código persistido válido, lo resuelve al dominio completo', () async {
    SharedPreferences.setMockInitialValues({'current_domain_code': 'movies'});
    final container = _buildContainer();
    addTearDown(container.dispose);

    final result = await container.read(currentDomainProvider.future);

    expect(result?.code, 'movies');
    expect(result?.displayName, 'Películas');
  });

  test('con un código persistido que ya no existe, cae al primer dominio', () async {
    SharedPreferences.setMockInitialValues({'current_domain_code': 'books'});
    final container = _buildContainer();
    addTearDown(container.dispose);

    final result = await container.read(currentDomainProvider.future);

    expect(result?.code, 'games');
  });

  test('changeDomain actualiza el estado y persiste el código', () async {
    SharedPreferences.setMockInitialValues({});
    final container = _buildContainer();
    addTearDown(container.dispose);

    await container.read(currentDomainProvider.future);
    await container.read(currentDomainProvider.notifier).changeDomain(_movies);

    // changeDomain solo invalida (ver comentario en el propio provider); el
    // rebuild en sí es asíncrono, así que hay que esperar el nuevo `.future`
    // en vez de leer `.value` justo después — igual que ya hace la UI real
    // vía `ref.watch`.
    final updated = await container.read(currentDomainProvider.future);
    expect(updated?.code, 'movies');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('current_domain_code'), 'movies');
  });
}
