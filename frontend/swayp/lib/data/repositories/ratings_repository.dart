import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/device/device_id_provider.dart';
import '../../core/errors/app_exception.dart';

/// Repositorio de ratings (`POST /domains/<domain_code>/ratings`).
class RatingsRepository {
  const RatingsRepository(this._ref);

  final Ref _ref;

  /// Devuelve el `id` del rating creado (o del ya existente, en el caso
  /// idempotente de reintento con el mismo status) — lo necesita
  /// [DeckNotifier.undo] para poder borrarlo si hace falta deshacer el
  /// swipe (docs/ARCHITECTURE.md sección 10).
  Future<int> submitRating({
    required String domainCode,
    required int itemId,
    required String status,
  }) async {
    final apiClient = _ref.read(apiClientProvider);
    final deviceId = await _ref.read(deviceIdProvider.future);

    try {
      final response = await apiClient.dio.post<Map<String, dynamic>>(
        '/domains/$domainCode/ratings',
        data: {'device_id': deviceId, 'item_id': itemId, 'status': status},
      );
      return response.data!['id'] as int;
    } on DioException catch (error) {
      throw AppException.fromDioError(error);
    }
  }

  /// `DELETE /domains/<domain_code>/ratings/<rating_id>` (undo del swipe,
  /// docs/ARCHITECTURE.md sección 10).
  Future<void> deleteRating({required String domainCode, required int ratingId}) async {
    final apiClient = _ref.read(apiClientProvider);
    final deviceId = await _ref.read(deviceIdProvider.future);

    try {
      await apiClient.dio.delete<void>(
        '/domains/$domainCode/ratings/$ratingId',
        queryParameters: {'device_id': deviceId},
      );
    } on DioException catch (error) {
      throw AppException.fromDioError(error);
    }
  }
}

final ratingsRepositoryProvider = Provider<RatingsRepository>((ref) => RatingsRepository(ref));
