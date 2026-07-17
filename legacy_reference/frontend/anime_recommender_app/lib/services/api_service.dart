// lib/services/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart'; // Importar para persistencia

class ApiService {
  // URL del endpoint de Render
  // 💡 ACTUALIZAR ESTA URL si el servicio se ha movido
  static const String baseUrl = 'https://anime-recommender-aykp.onrender.com'; 
  
  // Clave base para SharedPreferences, usando el nombre de usuario para diferenciar
  static const String _storageKeyBase = 'recommendations_data_';

  // --- MÉTODOS DE LA API ---
  
  // Obtener recomendaciones (y guardar caché)
  static Future<Map<String, dynamic>> getRecommendations(String username) async {
    try {
      print('🌐 Conectando con API: $baseUrl/api/recommendations/$username');
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/recommendations/$username'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(
        const Duration(seconds: 300), // TIMEOUT AUMENTADO A 5 MINUTOS (300s)
        onTimeout: () {
          throw const FormatException('Timeout: La solicitud tardó demasiado en responder.');
        },
      );
      print('📦 Response body: ${response.body}');
      print('📡 Response status: ${response.statusCode}');
      
      final data = jsonDecode(response.body);
      print('📦 Parsed: $data');
      
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

        // Solo cacheamos si realmente fue success
        if (data['status'] == 'success') {
          await _saveDataToCache(username, data);
        } else {
          print('⚠️ Respuesta con status=${data['status']}, no se guarda en caché.');
        }
        return data;
      } else {
        throw Exception('Error al obtener recomendaciones. Código: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error API getRecommendations: $e');
      rethrow;
    }
  }

  // ✅ NUEVO: Método para enviar IDs a la Blacklist
  static Future<Map<String, dynamic>> addToBlacklist(List<int> animeIds) async {
      try {
          print('🌐 Enviando ${animeIds.length} IDs a la Blacklist API...');
          
          final response = await http.post(
              Uri.parse('$baseUrl/api/blacklist'), // ✅ Nuevo endpoint
              headers: {'Content-Type': 'application/json'},
              body: json.encode({'anime_ids': animeIds.map((id) => id.toString()).toList()}), // Enviar como string
          ).timeout(const Duration(seconds: 30));
          
          print('📡 Blacklist Response status: ${response.statusCode}');
          
          // --- ✨ SOLUCIÓN AL FORMATEXCEPTION: Verificar el estado antes de decodificar ---
          if (response.statusCode == 200) {
              final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
              return data;
          } else {
              // Para códigos de error (404, 500, etc.)
              try {
                  final errorData = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
                  throw Exception(errorData['error'] ?? 'Error al añadir a la blacklist. Código: ${response.statusCode}');
              } catch (_) {
                  throw Exception('Error al añadir a la blacklist. Código: ${response.statusCode}');
              }
          }
      } catch (e) {
          print('❌ Error API Blacklist: $e');
          rethrow;
      }
  }

  // --- MÉTODOS DE CACHÉ ---
  
  // Guardar los datos en la caché
  static Future<void> _saveDataToCache(String username, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_storageKeyBase$username';
      final jsonString = json.encode(data);
      await prefs.setString(key, jsonString);
      print('✅ Datos de recomendaciones guardados en caché para $username.');
    } catch (e) {
      print('❌ Error al guardar datos en caché: $e');
    }
  }

  // Cargar los datos de la caché
  static Future<Map<String, dynamic>?> loadDataFromCache(String username) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_storageKeyBase$username';
    final jsonString = prefs.getString(key);

    if (jsonString != null) {
      final data = json.decode(jsonString) as Map<String, dynamic>;

      if (data['status'] == 'success') {
        print('💡 Datos de recomendaciones cargados desde caché para $username.');
        return data;
      } else {
        print('⚠️ Datos en caché con status=${data['status']}, se ignoran.');
        return null;
      }
    }
  } catch (e) {
    print('❌ Error al cargar datos desde caché: $e');
  }
  print('❌ No hay datos guardados en caché para $username.');
  return null;
}
  
  // ✅ IMPLEMENTACIÓN DEL MÉTODO FALTANTE clearCache
  // Limpia todos los datos de recomendaciones de la caché, independientemente del usuario.
  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Obtenemos todas las claves y filtramos solo aquellas que almacenan datos de recomendación
      final keysToRemove = prefs.getKeys().where((key) => key.startsWith(_storageKeyBase)).toList();
      
      for (final key in keysToRemove) {
        await prefs.remove(key);
      }
      print('✅ Caché de recomendaciones limpiada. ${keysToRemove.length} entradas eliminadas.');
    } catch (e) {
      print('❌ Error al limpiar la caché de recomendaciones: $e');
      rethrow;
    }
  }
}