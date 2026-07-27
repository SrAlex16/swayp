import 'package:dio/dio.dart';

/// Excepción de dominio de la app, mapeada desde el formato de error
/// estandarizado que devuelve el backend (docs/ARCHITECTURE.md sección 3.4):
/// `{"error": {"code", "message", "request_id"}}`.
///
/// El `code` es lo que decide la UI (mensaje/acción de retry, etc. — ver
/// sección 4.5), no el `message`, que es para logging/depuración.
class AppException implements Exception {
  const AppException({required this.code, required this.message, this.requestId});

  final String code;
  final String message;
  final String? requestId;

  /// Parsea un [DioException]. Si la respuesta del backend viene en el
  /// formato estandarizado, extrae `code`/`message`/`request_id` de ahí.
  /// Si no (ej. sin conexión, timeout, respuesta que no llegó a generar el
  /// backend), cae a un `code` genérico según el tipo de fallo de dio.
  factory AppException.fromDioError(DioException error) {
    final data = error.response?.data;
    if (data is Map<String, dynamic> && data['error'] is Map<String, dynamic>) {
      final errorBody = data['error'] as Map<String, dynamic>;
      return AppException(
        code: errorBody['code'] as String? ?? 'UNKNOWN_ERROR',
        message: errorBody['message'] as String? ?? 'Error desconocido',
        requestId: errorBody['request_id'] as String?,
      );
    }

    return AppException(
      code: _fallbackCode(error),
      message: error.message ?? 'No se pudo conectar con el servidor',
      requestId: error.requestOptions.extra['request_id'] as String?,
    );
  }

  static String _fallbackCode(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'TIMEOUT';
      case DioExceptionType.connectionError:
        return 'CONNECTION_ERROR';
      case DioExceptionType.cancel:
        return 'CANCELLED';
      default:
        return 'NETWORK_ERROR';
    }
  }

  @override
  String toString() => 'AppException(code: $code, message: $message, requestId: $requestId)';
}
