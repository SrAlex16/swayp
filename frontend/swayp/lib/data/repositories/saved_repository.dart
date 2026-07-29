import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/device/device_id_provider.dart';
import '../../core/errors/app_exception.dart';
import '../../domain/models/pending_rating.dart';

/// Repositorio de la lista de Guardados (docs/ARCHITECTURE.md sección 7.3):
/// `GET /domains/<code>/pending-confirmation` devuelve los ratings `interested`
/// del usuario y `PATCH /domains/<code>/ratings/<rating_id>` permite cambiarlos.
class SavedRepository {
  const SavedRepository(this._ref);

  final Ref _ref;

  Future<List<PendingRating>> getSavedRatings(String domainCode) async {
    final apiClient = _ref.read(apiClientProvider);
    final deviceId = await _ref.read(deviceIdProvider.future);

    try {
      final response = await apiClient.dio.get<List<dynamic>>(
        '/domains/$domainCode/pending-confirmation',
        queryParameters: {'device_id': deviceId},
      );
      final items = response.data ?? const [];
      return items.cast<Map<String, dynamic>>().map(PendingRating.fromJson).toList();
    } on DioException catch (error) {
      throw AppException.fromDioError(error);
    }
  }

  Future<void> updateRatingStatus(String domainCode, int ratingId, String status) async {
    final apiClient = _ref.read(apiClientProvider);
    final deviceId = await _ref.read(deviceIdProvider.future);

    try {
      await apiClient.dio.patch<Map<String, dynamic>>(
        '/domains/$domainCode/ratings/$ratingId',
        data: {'device_id': deviceId, 'status': status},
      );
    } on DioException catch (error) {
      throw AppException.fromDioError(error);
    }
  }
}

final savedRepositoryProvider = Provider<SavedRepository>(
  (ref) => SavedRepository(ref),
);
