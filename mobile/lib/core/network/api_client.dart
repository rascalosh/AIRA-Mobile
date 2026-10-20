import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import 'api_exception.dart';
import 'auth.dart';

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

BaseOptions _baseOptions() => BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: AppConfig.connectTimeout,
      receiveTimeout: AppConfig.receiveTimeout,
      sendTimeout: AppConfig.sendTimeout,
      responseType: ResponseType.json,
    );

final dioProvider = Provider<Dio>((ref) {
  final plain = Dio(_baseOptions());
  final dio = Dio(_baseOptions())
    ..interceptors.add(AuthInterceptor(store: ref.watch(tokenStoreProvider), plain: plain));
  ref.onDispose(() {
    dio.close();
    plain.close();
  });
  return dio;
});

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref.watch(dioProvider)));

/// Thin wrapper over Dio that converts transport errors into [ApiException].
class ApiClient {
  ApiClient(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>> getJson(String path) =>
      _json(() => _dio.get<Map<String, dynamic>>(path));

  Future<List<dynamic>> getList(String path) async {
    try {
      final response = await _dio.get<List<dynamic>>(path);
      return response.data ?? const [];
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Map<String, dynamic>> postJson(String path, {Object? data}) =>
      _json(() => _dio.post<Map<String, dynamic>>(path, data: data));

  Future<Map<String, dynamic>> postMultipart(
    String path,
    FormData data, {
    void Function(int sent, int total)? onSendProgress,
    CancelToken? cancelToken,
  }) =>
      _json(
        () => _dio.post<Map<String, dynamic>>(
          path,
          data: data,
          onSendProgress: onSendProgress,
          cancelToken: cancelToken,
        ),
      );

  Future<Uint8List> getBytes(String path) async {
    try {
      final response = await _dio.get<List<int>>(path, options: Options(responseType: ResponseType.bytes));
      final data = response.data;
      if (data == null) {
        throw const ApiException('The server returned an invalid response.', code: 'INVALID_RESPONSE');
      }
      return Uint8List.fromList(data);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<void> delete(String path) async {
    try {
      await _dio.delete<void>(path);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }

  Future<Map<String, dynamic>> _json(
    Future<Response<Map<String, dynamic>>> Function() request,
  ) async {
    try {
      final response = await request();
      final data = response.data;
      if (data == null) {
        throw const ApiException('The server returned an invalid response.', code: 'INVALID_RESPONSE');
      }
      return data;
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
