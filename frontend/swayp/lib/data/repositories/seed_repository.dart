import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/device/device_id_provider.dart';
import '../../core/errors/app_exception.dart';
import '../../domain/models/item.dart';

/// Repositorio de la baraja semilla (`GET /domains/<domain_code>/seed`).
class SeedRepository {
  const SeedRepository(this._ref);

  final Ref _ref;

  Future<List<Item>> getSeed(String domainCode, {required int count}) async {
    final apiClient = _ref.read(apiClientProvider);
    final deviceId = await _ref.read(deviceIdProvider.future);

    try {
      final response = await apiClient.dio.get<List<dynamic>>(
        '/domains/$domainCode/seed',
        queryParameters: {'device_id': deviceId, 'count': count},
      );
      final items = response.data ?? const [];
      return items.cast<Map<String, dynamic>>().map(Item.fromJson).toList();
    } on DioException catch (error) {
      throw AppException.fromDioError(error);
    }
  }
}

final seedRepositoryProvider = Provider<SeedRepository>((ref) => SeedRepository(ref));
