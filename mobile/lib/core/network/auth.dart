import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the API bearer token lives on the device.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

/// Keystore/Keychain-backed storage: the token is the only credential for the user's studies.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'aira_api_token';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// Sends `Authorization: Bearer <token>` on every request.
///
/// The app has no login: the first request registers an anonymous user and keeps the returned token.
/// If the server rejects the token (401, e.g. its database was reset) the app registers again and
/// retries that request once.
class AuthInterceptor extends QueuedInterceptor {
  AuthInterceptor({required this.store, required this.plain});

  static const registerPath = '/api/v1/users/anonymous';

  final TokenStore store;

  /// A Dio without this interceptor, for registering and for the retry. Retrying through the
  /// intercepted Dio would wait on this interceptor's own error queue and deadlock.
  final Dio plain;

  String? _token;

  Future<String> _register() async {
    final response = await plain.post<Map<String, dynamic>>(registerPath);
    final token = response.data?['token'] as String?;
    if (token == null) {
      throw DioException(requestOptions: response.requestOptions, message: 'Registration returned no token.');
    }
    _token = token;
    await store.write(token);
    return token;
  }

  Future<String> _ensureToken() async => _token ??= await store.read() ?? await _register();

  @override
  Future<void> onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.path == registerPath) return handler.next(options);
    try {
      options.headers['Authorization'] = 'Bearer ${await _ensureToken()}';
      handler.next(options);
    } on DioException catch (e) {
      handler.reject(e);
    } catch (e) {
      // e.g. the keystore cannot be read: fail the request instead of leaving it waiting forever.
      handler.reject(DioException(requestOptions: options, error: e, message: 'Unable to read the saved login.'));
    }
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode != 401 || err.requestOptions.path == registerPath) return handler.next(err);
    try {
      _token = null;
      await store.clear();
      final token = await _register();
      final retry = err.requestOptions..headers['Authorization'] = 'Bearer $token';
      handler.resolve(await plain.fetch<dynamic>(retry));
    } on DioException catch (e) {
      handler.next(e);
    } catch (_) {
      handler.next(err);
    }
  }
}
