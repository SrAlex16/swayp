import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/errors/app_exception.dart';
import '../../domain/models/domain.dart';

/// Repositorio de dominios (`GET /api/v1/domains`).
class DomainRepository {
  const DomainRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<Domain>> getDomains() async {
    try {
      final response = await _apiClient.dio.get<List<dynamic>>('/domains');
      final domains = response.data ?? const [];
      return domains.cast<Map<String, dynamic>>().map(Domain.fromJson).toList();
    } on DioException catch (error) {
      throw AppException.fromDioError(error);
    }
  }
}

final domainRepositoryProvider = Provider<DomainRepository>((ref) {
  return DomainRepository(ref.watch(apiClientProvider));
});

/// Lista de dominios habilitados, cargada de `GET /domains`.
final domainsProvider = FutureProvider<List<Domain>>((ref) {
  return ref.watch(domainRepositoryProvider).getDomains();
});
