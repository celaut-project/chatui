import 'dart:typed_data';

import 'package:argus_wallet/bridge/api/celaut.dart';
import 'package:argus_wallet/bridge/api/celaut_health.dart';
import 'package:argus_wallet/bridge/api/celaut_home.dart';
import 'package:argus_wallet/bridge/api/celaut_service.dart';
import 'package:argus_wallet/celaut/launch_problems.dart';
import 'package:argus_wallet/celaut/launcher.dart';
import 'package:flutter_test/flutter_test.dart';

QuoteView _quote(String peer, int port, {String credit = '', String cost = '1000'}) => QuoteView(
  address: NodeAddress(host: 'node$port.example', port: port),
  peerId: peer,
  costMu: cost,
  initMaintenanceMu: '1',
  maxMaintenanceMu: '1',
  maintenanceSecondsLoop: 10,
  variance: 0,
  comparedNanoErg: '1',
  clientBalanceMu: credit,
);

NodeHealthView _health(
  int port, {
  NodeAvailability availability = NodeAvailability.unreachable,
  int failures = 2,
  CelautErrorKind? kind = CelautErrorKind.timeout,
  String? text = 'the node did not answer in time',
}) => NodeHealthView(
  peerId: 'peer$port',
  address: 'node$port.example:$port',
  availability: availability,
  failures: failures,
  errorKind: kind,
  error: text,
  checkedAt: 100,
  lastOkAt: 0,
  nextCheckAt: 200,
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
  late List<NodeHealthView> healthRecords;

  setUp(() {
    asked = [];
    started = [];
    failures = {};
    healthRecords = [];
    answer = QuotesView(quotes: [_quote('a', 1), _quote('b', 2), _quote('c', 3)], failures: const []);
  });

  Future<LaunchOutcome> launch({List<NodeAddress>? nodes, List<KnownNodeView> known = const []}) =>
      launchService(
        serviceIdHex: _service,
        initialMu: '7',
        nodes: nodes,
        knownNodes: () => known,
        health: () => healthRecords,
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

  group('credit pre-check', () {
    test('a node where the credit is less than the price is not asked to start', () async {
      answer = QuotesView(
        quotes: [_quote('a', 1, credit: '500', cost: '1000'), _quote('b', 2, credit: '5000', cost: '1000')],
        failures: const [],
      );
      final outcome = await launch(nodes: [const NodeAddress(host: 'x', port: 1)]);
      expect(started, [2], reason: 'the node with too little credit gets no call');
      expect(outcome.skipped.single.isCreditProblem, isTrue);
      expect(outcome.skipped.single.error.kind, CelautErrorKind.insufficientCredit);
      expect(outcome.skipped.single.quote.clientBalanceMu, '500');
    });

    test('an unknown balance, or one equal to the price, does not stop the start', () async {
      answer = QuotesView(
        quotes: [_quote('a', 1, credit: '', cost: '1000'), _quote('b', 2, credit: '1000', cost: '1000')],
        failures: const [],
      );
      final outcome = await launch(nodes: [const NodeAddress(host: 'x', port: 1)]);
      expect(started, [1]);
      expect(outcome.skipped, isEmpty);
    });

    test('when every node has too little credit the failure says it for each node', () async {
      answer = QuotesView(
        quotes: [_quote('a', 1, credit: '1', cost: '1000'), _quote('b', 2, credit: '2', cost: '900')],
        failures: const [],
      );
      await expectLater(
        launch(nodes: [const NodeAddress(host: 'x', port: 1)]),
        throwsA(
          isA<LaunchFailure>()
              .having((f) => f.kind, 'kind', LaunchFailureKind.allFailed)
              .having((f) => f.skipped.every((s) => s.isCreditProblem), 'credit', isTrue),
        ),
      );
      expect(started, isEmpty);
    });
  });

  group('node health', () {
    final nodes = [
      const NodeAddress(host: 'node1.example', port: 1),
      const NodeAddress(host: 'node2.example', port: 2),
    ];

    test('a node that failed two checks in a row is left out of the quotes', () async {
      healthRecords = [_health(1)];
      final outcome = await launch(nodes: nodes);
      expect(asked.single.map((n) => n.port), [2]);
      expect(outcome.leftOut.single.address, 'node1.example:1');
      expect(outcome.leftOut.single.kind, CelautErrorKind.timeout);
      expect(outcome.leftOut.single.message, 'the node did not answer in time');
    });

    test('one failed check, a slow node, or an available node is asked', () async {
      healthRecords = [
        _health(1, failures: 1),
        _health(2, availability: NodeAvailability.slow, failures: 0),
      ];
      final outcome = await launch(nodes: nodes);
      expect(asked.single.map((n) => n.port), [1, 2]);
      expect(outcome.leftOut, isEmpty);
    });

    test('if every node would be left out, all of them are asked', () async {
      healthRecords = [_health(1), _health(2)];
      final outcome = await launch(nodes: nodes);
      expect(asked.single.map((n) => n.port), [1, 2]);
      expect(outcome.leftOut, isEmpty);
    });

    test('the nodes that were left out are in the failure', () async {
      healthRecords = [_health(1)];
      answer = const QuotesView(quotes: [], failures: []);
      await expectLater(
        launch(nodes: nodes),
        throwsA(
          isA<LaunchFailure>()
              .having((f) => f.kind, 'kind', LaunchFailureKind.noQuotes)
              .having((f) => f.leftOut.single.address, 'left out', 'node1.example:1'),
        ),
      );
    });

    test('a node with no health record is asked', () async {
      healthRecords = [_health(9)];
      await launch(nodes: nodes);
      expect(asked.single, hasLength(2));
    });
  });

  group('problems of a failure', () {
    test('the action of each reason', () {
      const retry = [
        CelautErrorKind.nodeClosed,
        CelautErrorKind.noRoom,
        CelautErrorKind.rateLimited,
        CelautErrorKind.recursionLimit,
        CelautErrorKind.launchFailed,
        CelautErrorKind.unreachable,
        CelautErrorKind.timeout,
      ];
      const other = [
        CelautErrorKind.serviceMissing,
        CelautErrorKind.policyRefused,
        CelautErrorKind.unsupportedArchitecture,
        CelautErrorKind.identityMismatch,
      ];
      for (final k in retry) {
        expect(actionFor(k), ProblemAction.retryLater, reason: '$k');
      }
      for (final k in other) {
        expect(actionFor(k), ProblemAction.chooseOtherNode, reason: '$k');
      }
      expect(actionFor(CelautErrorKind.insufficientCredit), ProblemAction.addDeposit);
      expect(actionFor(CelautErrorKind.clientUnknown), ProblemAction.askClientChoice);
      expect(actionFor(CelautErrorKind.storage), ProblemAction.none);
    });

    test('a failure gives one problem for each node, with the numbers and the texts', () {
      final failure = LaunchFailure(
        LaunchFailureKind.allFailed,
        quoteFailures: [
          QuoteFailureView(
            address: const NodeAddress(host: 'q.example', port: 9),
            kind: CelautErrorKind.serviceMissing,
            message: 'This node does not have the service ab',
          ),
        ],
        skipped: [
          LaunchSkip(
            _quote('a', 1, credit: '10', cost: '1000'),
            const CelautError(kind: CelautErrorKind.insufficientCredit, message: 'credit 10 MU, price 1000 MU'),
          ),
          LaunchSkip(
            _quote('b', 2),
            const CelautError(kind: CelautErrorKind.nodeClosed, message: 'closed until 09:00'),
          ),
        ],
        leftOut: const [
          LeftOutNode(address: 'd.example:4', peerId: 'd', kind: CelautErrorKind.timeout, message: 'slow'),
          LeftOutNode(address: 'e.example:5', peerId: 'e'),
        ],
      );
      final problems = problemsOf(failure);
      expect(problems.map((p) => p.address), [
        'q.example:9',
        'node1.example:1',
        'node2.example:2',
        'd.example:4',
        'e.example:5',
      ]);
      expect(problems[0].action, ProblemAction.chooseOtherNode);
      expect(problems[0].message, 'This node does not have the service ab');
      expect(problems[1].action, ProblemAction.addDeposit);
      expect((problems[1].creditMu, problems[1].costMu), ('10', '1000'));
      expect(problems[1].message, isEmpty);
      expect(problems[2].action, ProblemAction.retryLater);
      expect(problems[2].message, 'closed until 09:00');
      expect(problems[3].leftOut, isTrue);
      expect(problems[4].kind, CelautErrorKind.unreachable, reason: 'no reason in the record');
    });
  });
}
