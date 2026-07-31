import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/device/device_id_provider.dart';
import '../../core/errors/app_exception.dart';
import '../../domain/models/explicit_preference.dart';
import '../../domain/models/user_profile.dart';

/// Repositorio de perfil de usuario y preferencias explícitas
/// (`/users/profile`, `/users/domains/<code>/preferences`,
/// src/api/routes/profile_routes.py).
class ProfileRepository {
  const ProfileRepository(this._ref);

  final Ref _ref;

  Future<UserProfile> getProfile() async {
    final apiClient = _ref.read(apiClientProvider);
    final deviceId = await _ref.read(deviceIdProvider.future);

    try {
      final response = await apiClient.dio.get<Map<String, dynamic>>(
        '/users/profile',
        queryParameters: {'device_id': deviceId},
      );
      return UserProfile.fromJson(response.data!);
    } on DioException catch (error) {
      throw AppException.fromDioError(error);
    }
  }

  /// El backend valida `age` en 1-120 (src/api/routes/profile_routes.py) y
  /// devuelve `400` si no lo cumple — la UI debería validarlo antes de
  /// llegar aquí (ver `validateAge` en `profile_screen.dart`), pero esto no
  /// duplica esa validación: se limita a propagar el error si aun así llega
  /// un valor fuera de rango.
  Future<UserProfile> updateProfile({required int? age, required String? gender}) async {
    final apiClient = _ref.read(apiClientProvider);
    final deviceId = await _ref.read(deviceIdProvider.future);

    try {
      final response = await apiClient.dio.put<Map<String, dynamic>>(
        '/users/profile',
        data: {'device_id': deviceId, 'age': age, 'gender': gender},
      );
      return UserProfile.fromJson(response.data!);
    } on DioException catch (error) {
      throw AppException.fromDioError(error);
    }
  }

  Future<List<ExplicitPreference>> getPreferences(String domainCode) async {
    final apiClient = _ref.read(apiClientProvider);
    final deviceId = await _ref.read(deviceIdProvider.future);

    try {
      final response = await apiClient.dio.get<List<dynamic>>(
        '/users/domains/$domainCode/preferences',
        queryParameters: {'device_id': deviceId},
      );
      final items = response.data ?? const [];
      return items.cast<Map<String, dynamic>>().map(ExplicitPreference.fromJson).toList();
    } on DioException catch (error) {
      throw AppException.fromDioError(error);
    }
  }

  /// El `PUT` reemplaza la lista completa (no la fusiona) — hay que enviar
  /// siempre todas las preferencias que deban quedar, no solo la nueva.
  Future<List<ExplicitPreference>> updatePreferences(
    String domainCode,
    List<ExplicitPreference> preferences,
  ) async {
    final apiClient = _ref.read(apiClientProvider);
    final deviceId = await _ref.read(deviceIdProvider.future);

    try {
      final response = await apiClient.dio.put<List<dynamic>>(
        '/users/domains/$domainCode/preferences',
        data: {
          'device_id': deviceId,
          'preferences': preferences.map((preference) => preference.toJson()).toList(),
        },
      );
      final items = response.data ?? const [];
      return items.cast<Map<String, dynamic>>().map(ExplicitPreference.fromJson).toList();
    } on DioException catch (error) {
      throw AppException.fromDioError(error);
    }
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => ProfileRepository(ref));
