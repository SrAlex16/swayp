import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/device/device_id_provider.dart';
import '../../core/errors/app_exception.dart';

/// Repositorio de la blacklist dura (`POST /domains/<domain_code>/blacklist`,
/// docs/ARCHITECTURE.md sección 3.3) — exclusión permanente y explícita de
/// un ítem, distinta de `ratings.status='rejected'` (que sí es señal de
/// entrenamiento). No genera ningún rating.
class BlacklistRepository {
  const BlacklistRepository(this._ref);

  final Ref _ref;

  Future<void> addToBlacklist({required String domainCode, required int itemId}) async {
    final apiClient = _ref.read(apiClientProvider);
    final deviceId = await _ref.read(deviceIdProvider.future);

    try {
      await apiClient.dio.post<Map<String, dynamic>>(
        '/domains/$domainCode/blacklist',
        data: {'device_id': deviceId, 'item_id': itemId},
      );
    } on DioException catch (error) {
      throw AppException.fromDioError(error);
    }
  }
}

final blacklistRepositoryProvider = Provider<BlacklistRepository>(
  (ref) => BlacklistRepository(ref),
);
