import 'dart:io';
import 'package:dio/dio.dart';
import 'constants.dart';
import 'storage.dart';

class ApiResponse {
  final bool ok;
  final dynamic data;
  final String? error;
  final int statusCode;

  ApiResponse({
    required this.ok,
    this.data,
    this.error,
    required this.statusCode,
  });
}

class ApiClient {
  static Dio? _dio;
  static String? _baseUrl;
  static String? _sessionCookie;

  static void clearSession() {
    _sessionCookie = null;
  }

  static Future<Dio> get dio async {
    final currentUrl = await SecureKeyStorage.getServerUrl();
    if (_dio == null || _baseUrl != currentUrl) {
      _baseUrl = currentUrl.endsWith('/') ? currentUrl.substring(0, currentUrl.length - 1) : currentUrl;
      _dio = Dio(BaseOptions(
        baseUrl: '$_baseUrl/api.php',
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          AppConstants.headerRequestedWith: AppConstants.headerRequestedWithValue,
          'Accept': 'application/json',
        },
      ));

      _dio!.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) async {
          final rememberToken = await SecureKeyStorage.loadRememberToken();
          final csrfToken = await SecureKeyStorage.loadCsrfToken();

          if (rememberToken != null && rememberToken.isNotEmpty) {
            options.headers[AppConstants.headerRememberToken] = rememberToken;
          }
          if (csrfToken != null && csrfToken.isNotEmpty) {
            options.headers[AppConstants.headerCsrfToken] = csrfToken;
          }
          if (_sessionCookie != null && _sessionCookie!.isNotEmpty) {
            options.headers['Cookie'] = _sessionCookie;
          }
          return handler.next(options);
        },
        onResponse: (response, handler) async {
          // 1. Absorb session cookie (PHPSESSID) for PHP challenge handshake
          final cookies = response.headers['set-cookie'];
          if (cookies != null && cookies.isNotEmpty) {
            for (final c in cookies) {
              if (c.contains('PHPSESSID=')) {
                final match = RegExp(r'PHPSESSID=([^;]+)').firstMatch(c);
                if (match != null) {
                  _sessionCookie = 'PHPSESSID=${match.group(1)}';
                }
              }
            }
          }

          // 2. Absorb token rotations
          final newRemember = response.headers.value(AppConstants.headerNewRememberToken);
          final newCsrf = response.headers.value(AppConstants.headerNewCsrfToken);

          if (newRemember != null && newRemember.isNotEmpty) {
            await SecureKeyStorage.saveRememberToken(newRemember);
          }
          if (newCsrf != null && newCsrf.isNotEmpty) {
            await SecureKeyStorage.saveCsrfToken(newCsrf);
          }
          return handler.next(response);
        },
      ));
    }
    return _dio!;
  }

  static Future<ApiResponse> get(String action, [Map<String, dynamic>? queryParams]) async {
    try {
      final client = await dio;
      final qp = {'action': action, ...(queryParams ?? {})};
      final res = await client.get('', queryParameters: qp);

      if (res.data is Map && res.data['error'] != null) {
        return ApiResponse(
          ok: false,
          error: res.data['error'].toString(),
          data: res.data,
          statusCode: res.statusCode ?? 400,
        );
      }
      return ApiResponse(ok: true, data: res.data, statusCode: res.statusCode ?? 200);
    } on DioException catch (e) {
      final err = e.response?.data is Map ? e.response?.data['error'] : e.message;
      return ApiResponse(
        ok: false,
        error: err?.toString() ?? 'Network error',
        statusCode: e.response?.statusCode ?? 500,
      );
    } catch (e) {
      return ApiResponse(ok: false, error: e.toString(), statusCode: 500);
    }
  }

  static Future<ApiResponse> post(String action, Map<String, dynamic> body) async {
    try {
      final client = await dio;
      final res = await client.post('', queryParameters: {'action': action}, data: body);

      if (res.data is Map && res.data['error'] != null) {
        return ApiResponse(
          ok: false,
          error: res.data['error'].toString(),
          data: res.data,
          statusCode: res.statusCode ?? 400,
        );
      }
      return ApiResponse(ok: true, data: res.data, statusCode: res.statusCode ?? 200);
    } on DioException catch (e) {
      final err = e.response?.data is Map ? e.response?.data['error'] : e.message;
      return ApiResponse(
        ok: false,
        error: err?.toString() ?? 'Network error',
        statusCode: e.response?.statusCode ?? 500,
      );
    } catch (e) {
      return ApiResponse(ok: false, error: e.toString(), statusCode: 500);
    }
  }

  static Future<ApiResponse> postMultipart(
    String action,
    FormData formData, {
    void Function(int sent, int total)? onProgress,
  }) async {
    try {
      final client = await dio;
      final res = await client.post(
        '',
        queryParameters: {'action': action},
        data: formData,
        onSendProgress: onProgress,
      );

      if (res.data is Map && res.data['error'] != null) {
        return ApiResponse(
          ok: false,
          error: res.data['error'].toString(),
          data: res.data,
          statusCode: res.statusCode ?? 400,
        );
      }
      return ApiResponse(ok: true, data: res.data, statusCode: res.statusCode ?? 200);
    } on DioException catch (e) {
      final err = e.response?.data is Map ? e.response?.data['error'] : e.message;
      return ApiResponse(
        ok: false,
        error: err?.toString() ?? 'Upload failed',
        statusCode: e.response?.statusCode ?? 500,
      );
    } catch (e) {
      return ApiResponse(ok: false, error: e.toString(), statusCode: 500);
    }
  }
}
