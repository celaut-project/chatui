import 'dart:typed_data';

import 'package:argus_wallet/bridge/api/celaut.dart';
import 'package:argus_wallet/bridge/api/celaut_home.dart';
import 'package:argus_wallet/bridge/api/celaut_service.dart';
import 'package:argus_wallet/celaut/launcher.dart';
import 'package:flutter_test/flutter_test.dart';

QuoteView _quote(String peer, int port) => QuoteView(
  address: NodeAddress(host: 'node$port.example', port: port),
  peerId: peer,
  costMu: '1000',
  initMaintenanceMu: '1',
  maxMaintenanceMu: '1',
  maintenanceSecondsLoop: 10,
  variance: 0,
  comparedNanoErg: '1',
);

InstanceView _instance(String id) => InstanceView(
  instanceId: id,
  peerId: 'p',
  slots: Uint16List.fromList([8080]),
  chatSlots: Uint16List.fromList([8080]),
  clientBalanceMu: '5',
);

const _service = 'ab';
const _error = CelautError(kind: CelautErrorKind.unreachable, message: 'down');
const _forgot = CelautError(kind: CelautErrorKind.clientUnknown, message: 'forgot');

void main() {
  late List<List<NodeAddress>> asked;
  late List<int> started;
  late QuotesView answer;
  late Map<int, CelautError> failures;

  setUp(() {
    asked = [];
    started = [];
    failures = {};
    answer = QuotesView(quotes: [_quote('a', 1), _quote('b', 2), _quote('c', 3)], failures: const []);
  });

  Future<LaunchOutcome> launch({List<NodeAddress>? nodes, List<KnownNodeView> known = const []}) =>
      launchService(
        serviceIdHex: _service,
        initialMu: '7',
        nodes: nodes,
        knownNodes: () => known,
        quote: ({required nodes, required serviceIdHex, initialMu}) async {
          asked.add(nodes);
          expect(initialMu, '7');
          return answer;
        },
        start: ({required node, required serviceIdHex, initialMu}) async {
          started.add(node.port);
          final failure = failures[node.port];
          if (failure != null) throw failure;
          return _instance('i${node.port}');
        },
      );

  test('the first quote starts, and the others are not tried', () async {
    final outcome = await launch(nodes: [const NodeAddress(host: 'x', port: 1)]);
    expect(started, [1]);
    expect(outcome.quote.peerId, 'a');
    expect(outcome.instance.instanceId, 'i1');
    expect(outcome.skipped, isEmpty);
  });

  test('a node that fails is skipped, in the order of the quotes', () async {
    failures = {1: _error, 2: _error};
    final outcome = await launch(nodes: [const NodeAddress(host: 'x', port: 1)]);
    expect(started, [1, 2, 3]);
    expect(outcome.quote.peerId, 'c');
    expect(outcome.skipped.map((s) => s.quote.peerId), ['a', 'b']);
    expect(outcome.skipped.first.error, _error);
  });

  test('when every node fails, the failure has each reason', () async {
    failures = {1: _error, 2: _forgot, 3: _error};
    await expectLater(
      launch(nodes: [const NodeAddress(host: 'x', port: 1)]),
      throwsA(
        isA<LaunchFailure>()
            .having((f) => f.kind, 'kind', LaunchFailureKind.allFailed)
            .having((f) => f.skipped, 'skipped', hasLength(3))
            .having((f) => f.clientUnknown.single.quote.peerId, 'forgot', 'b'),
      ),
    );
    expect(started, [1, 2, 3]);
  });

  test('no quote is no start', () async {
    answer = QuotesView(
      quotes: const [],
      failures: [
        QuoteFailureView(
          address: const NodeAddress(host: 'x', port: 1),
          kind: CelautErrorKind.timeout,
          message: 't',
        ),
      ],
    );
    await expectLater(
      launch(nodes: [const NodeAddress(host: 'x', port: 1)]),
      throwsA(
        isA<LaunchFailure>()
            .having((f) => f.kind, 'kind', LaunchFailureKind.noQuotes)
            .having((f) => f.quoteFailures, 'quoteFailures', hasLength(1)),
      ),
    );
    expect(started, isEmpty);
  });

  test('with no nodes, the known nodes are asked with their latest address', () async {
    await launch(
      known: [
        KnownNodeView(
          peerId: 'a',
          addresses: ['one.example:10', 'old.example:11'],
          depositedNanoErg: BigInt.zero,
        ),
        KnownNodeView(peerId: 'b', addresses: const [], depositedNanoErg: BigInt.zero),
        KnownNodeView(peerId: 'c', addresses: ['not an address'], depositedNanoErg: BigInt.zero),
        KnownNodeView(peerId: 'd', addresses: ['[::1]:12'], depositedNanoErg: BigInt.zero),
      ],
    );
    expect(asked.single.map((n) => '${n.host}:${n.port}'), ['one.example:10', '::1:12']);
  });

  test('typed nodes are used and the known nodes are not read', () async {
    final typed = [const NodeAddress(host: 'typed.example', port: 5)];
    await launch(nodes: typed);
    expect(asked.single, typed);
  });

  test('no typed and no known node is a failure, and nobody is asked', () async {
    await expectLater(
      launch(),
      throwsA(isA<LaunchFailure>().having((f) => f.kind, 'kind', LaunchFailureKind.noNodes)),
    );
    expect(asked, isEmpty);
  });
}
