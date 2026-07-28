import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/device/device_id_provider.dart';
import '../../core/errors/app_exception.dart';
import '../../domain/models/item.dart';

/// Estado de un job de recomendaciones (`GET /jobs/<id>`,
/// src/api/routes/jobs_routes.py). `status` es "pending" | "running" |
/// "done" | "error" (src/services/job_service.py).
class JobStatus {
  const JobStatus({required this.status, this.result, this.errorMessage});

  final String status;
  final List<Item>? result;
  final String? errorMessage;

  bool get isDone => status == 'done';
  bool get isError => status == 'error';

  factory JobStatus.fromJson(Map<String, dynamic> json) {
    final rawResult = json['result'] as List<dynamic>?;
    return JobStatus(
      status: json['status'] as String,
      result: rawResult?.cast<Map<String, dynamic>>().map(Item.fromJson).toList(),
      errorMessage: json['error_message'] as String?,
    );
  }
}

/// Repositorio del motor de recomendaciones vía jobs asíncronos
/// (docs/ARCHITECTURE.md sección 3.5).
class RecommendationsRepository {
  const RecommendationsRepository(this._ref);

  final Ref _ref;

  /// `POST /domains/<domain_code>/recommendations/jobs` — devuelve el
  /// `job_id`, sin esperar a que termine.
  Future<String> requestRecommendationJob(String domainCode) async {
    final apiClient = _ref.read(apiClientProvider);
    final deviceId = await _ref.read(deviceIdProvider.future);

    try {
      final response = await apiClient.dio.post<Map<String, dynamic>>(
        '/domains/$domainCode/recommendations/jobs',
        data: {'device_id': deviceId},
      );
      return response.data!['job_id'] as String;
    } on DioException catch (error) {
      throw AppException.fromDioError(error);
    }
  }

  /// `GET /jobs/<job_id>` — una sola consulta. El polling en sí (repetir
  /// esta llamada hasta que termine) vive en `deck_provider.dart`, no aquí.
  Future<JobStatus> pollJob(String jobId) async {
    final apiClient = _ref.read(apiClientProvider);

    try {
      final response = await apiClient.dio.get<Map<String, dynamic>>('/jobs/$jobId');
      return JobStatus.fromJson(response.data!);
    } on DioException catch (error) {
      throw AppException.fromDioError(error);
    }
  }
}

final recommendationsRepositoryProvider = Provider<RecommendationsRepository>(
  (ref) => RecommendationsRepository(ref),
);
