import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const String _deviceIdKey = 'device_id';

/// Identificador estable del dispositivo: se genera (uuid v4) la primera vez
/// que hace falta, se persiste en `shared_preferences` y no vuelve a
/// cambiar — aperturas siguientes leen el mismo valor guardado.
///
/// Expuesto como `FutureProvider` en vez de resolverlo de forma síncrona en
/// el arranque: la lectura de `shared_preferences` es async, y así compone
/// igual que el resto de providers async ya existentes (`domainsProvider`,
/// `currentDomainProvider`) sin necesitar un paso de inicialización aparte
/// en `main.dart`. Al no ser `.autoDispose`, Riverpod lo mantiene vivo y
/// cacheado, así que el uuid se genera/lee como mucho una vez por sesión.
final deviceIdProvider = FutureProvider<String>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final existing = prefs.getString(_deviceIdKey);
  if (existing != null) return existing;

  final generated = const Uuid().v4();
  await prefs.setString(_deviceIdKey, generated);
  return generated;
});
