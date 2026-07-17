// lib/services/blacklist_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class BlacklistService {
  static const String baseUrl = 'https://anime-recommender-aykp.onrender.com';

  /// Obtener la lista completa de IDs en blacklist
  static Future<List<int>> getBlacklist() async {
    try {
      print('🌐 Obteniendo blacklist desde API...');
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/blacklist'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));
      
      print('📡 Blacklist GET status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        
        if (data['status'] == 'success') {
          final List<dynamic> blacklist = data['blacklist'] as List<dynamic>? ?? [];
          final result = blacklist.map((id) => int.parse(id.toString())).toList();
          print('✅ Blacklist obtenida: ${result.length} IDs');
          return result;
        } else {
          throw Exception(data['message'] ?? 'Error al obtener blacklist');
        }
      } else {
        throw Exception('Error HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error obteniendo blacklist: $e');
      return [];
    }
  }

  /// Añadir IDs a la blacklist
  static Future<void> addToBlacklist(List<int> animeIds) async {
    try {
      print('🌐 Añadiendo ${animeIds.length} IDs a blacklist...');
      
      final response = await http.post(
        Uri.parse('$baseUrl/api/blacklist'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'anime_ids': animeIds.map((id) => id.toString()).toList(),
        }),
      ).timeout(const Duration(seconds: 30));
      
      print('📡 Blacklist POST status: ${response.statusCode}');
      
      if (response.statusCode != 200) {
        final errorData = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        throw Exception(errorData['message'] ?? 'Error al añadir a blacklist');
      }
      
      print('✅ IDs añadidos a blacklist exitosamente');
    } catch (e) {
      print('❌ Error añadiendo a blacklist: $e');
      rethrow;
    }
  }

  /// Eliminar IDs de la blacklist
  static Future<void> removeFromBlacklist(List<int> animeIds) async {
    try {
      print('🌐 Eliminando ${animeIds.length} IDs de blacklist...');
      
      final response = await http.delete(
        Uri.parse('$baseUrl/api/blacklist'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'anime_ids': animeIds.map((id) => id.toString()).toList(),
        }),
      ).timeout(const Duration(seconds: 30));
      
      print('📡 Blacklist DELETE status: ${response.statusCode}');
      
      if (response.statusCode != 200) {
        final errorData = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
        throw Exception(errorData['message'] ?? 'Error al eliminar de blacklist');
      }
      
      print('✅ IDs eliminados de blacklist exitosamente');
    } catch (e) {
      print('❌ Error eliminando de blacklist: $e');
      rethrow;
    }
  }
}