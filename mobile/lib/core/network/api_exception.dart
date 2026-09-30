import 'package:dio/dio.dart';

/// An error with a message that is safe to show to the user.
class ApiException implements Exception {
  const ApiException(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  factory ApiException.fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.connectionError:
        return const ApiException(
          'Unable to reach the processing server. Check your network connection.',
          code: 'NETWORK_ERROR',
        );
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const ApiException(
          'The server took too long to respond. Please try again.',
          code: 'TIMEOUT',
        );
      case DioExceptionType.cancel:
        return const ApiException('The request was cancelled.', code: 'CANCELLED');
      default:
        break;
    }

    final response = error.response;
    final data = response?.data;
    if (data is Map && data['error'] is Map) {
      final body = data['error'] as Map;
      return ApiException(
        body['message'] as String? ?? 'An unexpected error occurred.',
        code: body['code'] as String?,
        statusCode: response?.statusCode,
      );
    }
    return ApiException(
      'An unexpected error occurred. Please try again.',
      code: 'UNKNOWN',
      statusCode: response?.statusCode,
    );
  }

  @override
  String toString() => message;
}
