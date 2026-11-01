import 'dart:typed_data';

import 'package:argus_wallet/bridge/api/celaut.dart';
import 'package:argus_wallet/bridge/api/celaut_http.dart';
import 'package:argus_wallet/bridge/frb_generated.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fakes the HTTP tunnel calls of the bridge: the Dart side passes its arguments through
/// and gets the types of the answer and of the errors back.
class _HttpApi extends RustLibApi {
  final closed = <BigInt>[];
  ({BigInt handle, String method, String path, List<HttpHeader> headers, List<int> body})? last;

  @override
  Future<BigInt> crateApiCelautHttpCelautHttpOpen({
    required String instanceId,
    required int slot,
  }) async {
    if (instanceId == 'gone') {
      throw CelautError(kind: CelautErrorKind.invalidInput, message: 'This instance is not known.');
    }
    return BigInt.from(7);
  }

  @override
  Future<HttpAnswer> crateApiCelautHttpCelautHttpRequest({
    required BigInt handle,
    required String method,
    required String pathAndQuery,
    required List<HttpHeader> headers,
    required List<int> body,
  }) async {
    if (closed.contains(handle)) {
      throw CelautError(kind: CelautErrorKind.invalidInput, message: 'This HTTP tunnel is closed.');
    }
    last = (handle: handle, method: method, path: pathAndQuery, headers: headers, body: body);
    return HttpAnswer(
      status: 201,
      headers: [HttpHeader(name: 'content-type', value: 'text/plain')],
      body: Uint8List.fromList([104, 105]),
    );
  }

  @override
  void crateApiCelautHttpCelautHttpClose({required BigInt handle}) => closed.add(handle);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final api = _HttpApi();
  setUpAll(() => RustLib.initMock(api: api));

  test('open, request and close pass through the bridge', () async {
    final handle = await celautHttpOpen(instanceId: 'web-1', slot: 80);
    expect(handle, BigInt.from(7));
    final answer = await celautHttpRequest(
      handle: handle,
      method: 'POST',
      pathAndQuery: '/a?b=1',
      headers: [HttpHeader(name: 'accept', value: '*/*')],
      body: [1, 2, 3],
    );
    expect(answer.status, 201);
    expect(answer.headers.single, HttpHeader(name: 'content-type', value: 'text/plain'));
    expect(answer.body, [104, 105]);
    expect(api.last!.method, 'POST');
    expect(api.last!.path, '/a?b=1');
    expect(api.last!.body, [1, 2, 3]);
    celautHttpClose(handle: handle);
    expect(api.closed, [handle]);
  });

  test('errors come as CelautError', () async {
    await expectLater(
      celautHttpOpen(instanceId: 'gone', slot: 80),
      throwsA(isA<CelautError>().having((e) => e.kind, 'kind', CelautErrorKind.invalidInput)),
    );
    await expectLater(
      celautHttpRequest(
        handle: BigInt.from(7),
        method: 'GET',
        pathAndQuery: '/',
        headers: [],
        body: [],
      ),
      throwsA(isA<CelautError>()),
    );
  });
}
