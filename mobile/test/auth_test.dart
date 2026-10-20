import 'dart:convert';
import 'dart:typed_data';

import 'package:aira_mobile/core/network/auth.dart';
import 'package:aira_mobile/data/models/job.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _BrokenStore implements TokenStore {
  @override
  Future<String?> read() async => throw StateError('keystore unavailable');
  @override
  Future<void> write(String token) async {}
  @override
  Future<void> clear() async {}
}

class _MemoryStore implements TokenStore {
  _MemoryStore([this.token]);
  String? token;

  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String value) async => token = value;
  @override
  Future<void> clear() async => token = null;
}

/// A tiny fake server: registration hands out tok1, tok2, ...; the studies route only accepts `valid`.
class _FakeServer implements HttpClientAdapter {
  final String Function() valid;
  final registered = <String>[];
  final seenAuth = <String?>[];
  int _n = 0;

  _FakeServer(this.valid);

  ResponseBody _json(int status, Object body) => ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.path == AuthInterceptor.registerPath) {
      final token = 'tok${++_n}';
      registered.add(token);
      return _json(201, {'user_id': 'u$_n', 'token': token});
    }
    final auth = options.headers['Authorization'] as String?;
    seenAuth.add(auth);
    return auth == 'Bearer ${valid()}'
        ? _json(200, {'ok': true})
        : _json(401, {
            'error': {'code': 'UNAUTHORIZED', 'message': 'no'},
          });
  }

  @override
  void close({bool force = false}) {}
}

Dio _client(_FakeServer server, TokenStore store) {
  final plain = Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = server;
  return Dio(BaseOptions(baseUrl: 'http://test'))
    ..httpClientAdapter = server
    ..interceptors.add(AuthInterceptor(store: store, plain: plain));
}

void main() {
  test(
    'registers on the first request, stores the token and reuses it',
    () async {
      final store = _MemoryStore();
      final server = _FakeServer(() => 'tok1');
      final dio = _client(server, store);

      await dio.get<dynamic>('/api/v1/studies');
      await Future.wait([
        dio.get<dynamic>('/api/v1/studies'),
        dio.get<dynamic>('/api/v1/studies'),
      ]);

      expect(server.registered, ['tok1']);
      expect(store.token, 'tok1');
      expect(server.seenAuth, everyElement('Bearer tok1'));
    },
  );

  test('uses the stored token without registering', () async {
    final server = _FakeServer(() => 'saved');
    await _client(
      server,
      _MemoryStore('saved'),
    ).get<dynamic>('/api/v1/studies');

    expect(server.registered, isEmpty);
  });

  test(
    'a rejected token is replaced and the request is retried once',
    () async {
      final store = _MemoryStore('stale');
      final server = _FakeServer(() => 'tok1');
      final dio = _client(server, store);

      final response = await dio.get<dynamic>('/api/v1/studies');

      expect(response.statusCode, 200);
      expect(server.registered, ['tok1']);
      expect(store.token, 'tok1');
      expect(server.seenAuth, ['Bearer stale', 'Bearer tok1']);
    },
  );

  test('gives up after one retry instead of looping', () async {
    final server = _FakeServer(() => 'never');
    final dio = _client(server, _MemoryStore('stale'));

    await expectLater(
      dio.get<dynamic>('/api/v1/studies'),
      throwsA(
        isA<DioException>().having(
          (e) => e.response?.statusCode,
          'status',
          401,
        ),
      ),
    );
    expect(server.registered, hasLength(1));
    expect(server.seenAuth, hasLength(2));
  });

  test(
    'an unreadable keystore fails the request instead of hanging it',
    () async {
      final server = _FakeServer(() => 'tok1');
      final dio = _client(server, _BrokenStore());

      await expectLater(
        dio.get<dynamic>('/api/v1/studies').timeout(const Duration(seconds: 5)),
        throwsA(isA<DioException>()),
      );
      expect(server.seenAuth, isEmpty);
    },
  );

  test('parses a job in each state', () {
    final running = SegmentationJob.fromJson({
      'job_id': 'j',
      'study_id': 's',
      'status': 'running',
    });
    expect(running.isDone, isFalse);
    expect(running.segmentation, isNull);

    final failed = SegmentationJob.fromJson({
      'job_id': 'j',
      'study_id': 's',
      'status': 'failed',
      'error': {'code': 'MODEL_UNAVAILABLE', 'message': 'Model missing'},
    });
    expect(failed.isDone, isTrue);
    expect(failed.errorMessage, 'Model missing');

    final done = SegmentationJob.fromJson({
      'job_id': 'j',
      'study_id': 's',
      'status': 'completed',
      'segmentation': {
        'resource_id': 'm',
        'label': 'Lesion',
        'volume_ml': 1.5,
        'model_name': 'x',
        'model_note': 'Experimental',
      },
    });
    expect(done.isDone, isTrue);
    expect(done.segmentation?.volumeMl, 1.5);
  });
}
