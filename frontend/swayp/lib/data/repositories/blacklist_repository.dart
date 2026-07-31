import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/device/device_id_provider.dart';
import '../../core/errors/app_exception.dart';

/// Resultado de `POST /domains/<domain_code>/blacklist`
/// (src/api/routes/blacklist_routes.py). `collectionBlacklisted` solo es
/// no-nulo si el ítem tenía una saga asignada y el dominio la soporta (hoy
/// solo "movies", ver docs/ARCHITECTURE.md sección 3.3) — bloquearlo excluye
/// también el resto de ítems de esa saga.
class BlacklistResult {
  const BlacklistResult({required this.itemBlacklisted, required this.collectionBlacklisted});

  final bool itemBlacklisted;
  final String? collectionBlacklisted;

  factory BlacklistResult.fromJson(Map<String, dynamic> json) {
    return BlacklistResult(
      itemBlacklisted: json['item_blacklisted'] as bool? ?? true,
      collectionBlacklisted: json['collection_blacklisted'] as String?,
    );
  }
}

/// Repositorio de la blacklist dura (`POST /domains/<domain_code>/blacklist`,
/// docs/ARCHITECTURE.md sección 3.3) — exclusión permanente y explícita de
/// un ítem, distinta de `ratings.status='rejected'` (que sí es señal de
/// entrenamiento). No genera ningún rating.
class BlacklistRepository {
  const BlacklistRepository(this._ref);

  final Ref _ref;

  Future<BlacklistResult> addToBlacklist({
    required String domainCode,
    required int itemId,
  }) async {
    final apiClient = _ref.read(apiClientProvider);
    final deviceId = await _ref.read(deviceIdProvider.future);

    try {
      final response = await apiClient.dio.post<Map<String, dynamic>>(
        '/domains/$domainCode/blacklist',
        data: {'device_id': deviceId, 'item_id': itemId},
      );
      return BlacklistResult.fromJson(response.data!);
    } on DioException catch (error) {
      throw AppException.fromDioError(error);
    }
  }
}

final blacklistRepositoryProvider = Provider<BlacklistRepository>(
  (ref) => BlacklistRepository(ref),
);
