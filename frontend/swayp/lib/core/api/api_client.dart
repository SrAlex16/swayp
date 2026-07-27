import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// URL base del backend. Se puede sobreescribir al compilar/ejecutar con
/// `--dart-define=API_BASE_URL=http://tu-host:5000/api/v1`.
///
/// Default elegido: `http://10.0.2.2:5000/api/v1`, pensado para el emulador
/// de Android (el target más probable en este entorno). `10.0.2.2` es la
/// dirección especial que, dentro del emulador, apunta al `localhost` de la
/// máquina host — `localhost` a secas dentro del emulador se refiere al
/// propio emulador, no al host donde corre Flask. Para iOS Simulator,
/// desktop o web sí hace falta pasar `--dart-define=API_BASE_URL=http://localhost:5000/api/v1`
/// explícitamente, porque en esos targets `localhost` sí es el host real
/// (no se puede detectar la plataforma en tiempo de compilación con
/// `String.fromEnvironment`, así que queda documentado aquí en vez de
/// resuelto automáticamente).
const String _defaultBaseUrl = 'http://10.0.2.2:5000/api/v1';

const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: _defaultBaseUrl,
);

/// Interceptor que genera un `request_id` (uuid v4) por request, lo manda en
/// el header `X-Request-Id` (ver docs/ARCHITECTURE.md sección 3.6, mismo
/// contrato que ya usa el backend) y loguea método/ruta/status/duración.
///
/// Se usa `dart:developer.log` en vez de añadir el paquete `logging`: ya
/// viene con el SDK de Dart, soporta campos estructurados (`name`, `level`,
/// `error`) y se integra con DevTools, sin sumar una dependencia más al
/// pubspec solo para esto.
class _RequestLoggingInterceptor extends Interceptor {
  static const _uuid = Uuid();

  static const _levelError = 1000;
  static const _levelInfo = 800;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra['request_id'] = _uuid.v4();
    options.extra['start_time'] = DateTime.now();
    options.headers['X-Request-Id'] = options.extra['request_id'];
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _log(response.requestOptions, statusCode: response.statusCode);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _log(err.requestOptions, statusCode: err.response?.statusCode, error: err);
    handler.next(err);
  }

  void _log(RequestOptions options, {int? statusCode, Object? error}) {
    final startTime = options.extra['start_time'] as DateTime?;
    final durationMs = startTime == null
        ? null
        : DateTime.now().difference(startTime).inMilliseconds;
    final requestId = options.extra['request_id'] as String?;

    developer.log(
      '${options.method} ${options.path} -> ${statusCode ?? 'ERROR'} '
      '(${durationMs ?? '?'}ms) request_id=$requestId',
      name: 'swayp.api',
      level: error != null ? _levelError : _levelInfo,
      error: error,
    );
  }
}

/// Wrapper de [Dio] configurado con la baseUrl y el interceptor de logging
/// de la app. Pensado para usarse a través de [apiClientProvider], no
/// instanciado directamente en widgets/repositorios.
class ApiClient {
  ApiClient({Dio? dio}) : dio = dio ?? _buildDio();

  final Dio dio;

  static Dio _buildDio() {
    final instance = Dio(
      BaseOptions(
        baseUrl: apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );
    instance.interceptors.add(_RequestLoggingInterceptor());
    return instance;
  }
}

/// Instancia única de [ApiClient] compartida por toda la app.
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
