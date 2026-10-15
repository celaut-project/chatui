import 'dart:async';

import 'package:argus_wallet/bridge/api/celaut.dart';
import 'package:argus_wallet/bridge/api/celaut_health.dart';
import 'package:argus_wallet/bridge/api/celaut_home.dart';
import 'package:argus_wallet/bridge/api/celaut_service.dart';
import 'package:argus_wallet/celaut/celaut_strings.dart';
import 'package:argus_wallet/celaut/node_health_format.dart';
import 'package:argus_wallet/celaut/node_health_monitor.dart';
import 'package:argus_wallet/celaut/payers.dart';
import 'package:argus_wallet/celaut/wallet_money.dart';
import 'package:argus_wallet/l10n/l10n.dart';
import 'package:argus_wallet/ui/celaut/compute_home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _a = 'aa' * 32;
final _b = 'bb' * 32;
final _c = 'cc' * 32;
final _d = 'dd' * 32;

int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

NodeHealthView _view(
  String peer,
  NodeAvailability availability, {
  int? latency,
  int lastOk = 0,
  CelautErrorKind? kind,
  String? error,
}) => NodeHealthView(
  peerId: peer,
  address: '$peer.example:1',
  availability: availability,
  latencyMs: latency,
  checkedAt: availability == NodeAvailability.unknown ? 0 : 1,
  lastOkAt: lastOk,
  failures: availability == NodeAvailability.unreachable ? 2 : 0,
  errorKind: kind,
  error: error,
  nextCheckAt: 0,
);

/// A timer factory that the test fires by hand.
class _Timers {
  final created = <({Duration interval, void Function() tick, _FakeTimer timer})>[];

  Timer make(Duration interval, void Function() tick) {
    final timer = _FakeTimer();
    created.add((interval: interval, tick: tick, timer: timer));
    return timer;
  }

  void fire() => created.last.tick();
}

class _FakeTimer implements Timer {
  bool cancelled = false;

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}

void main() {
  group('NodeHealthMonitor', () {
    late _Timers timers;
    late List<bool> checks;
    late Completer<List<NodeHealthView>>? gate;
    late List<NodeHealthView> stored;
    late List<NodeHealthView> answer;
    Object? failWith;

    NodeHealthMonitor make() => NodeHealthMonitor(
      read: () => stored,
      check: (force) async {
        checks.add(force);
        if (gate != null) return gate!.future;
        if (failWith != null) throw failWith!;
        return answer;
      },
      timer: timers.make,
    );

    setUp(() {
      timers = _Timers();
      checks = [];
      gate = null;
      failWith = null;
      stored = [_view(_a, NodeAvailability.unknown)];
      answer = [_view(_a, NodeAvailability.available, latency: 40)];
    });

    test('start reads the stored state at once, then checks the nodes that are due', () async {
      final monitor = make();
      monitor.start();
      expect(monitor.nodes.single.availability, NodeAvailability.unknown);
      expect(monitor.checking, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(checks, [false]);
      expect(monitor.of(_a)!.availability, NodeAvailability.available);
      expect(monitor.of(_b), isNull);
      expect(monitor.checking, isFalse);
      monitor.dispose();
    });

    test('it checks again at each tick, every minute', () async {
      final monitor = make();
      monitor.start();
      await Future<void>.delayed(Duration.zero);
      expect(timers.created.single.interval, const Duration(seconds: 60));
      timers.fire();
      await Future<void>.delayed(Duration.zero);
      timers.fire();
      await Future<void>.delayed(Duration.zero);
      expect(checks, [false, false, false]);
      monitor.dispose();
    });

    test('a check never overlaps another one', () async {
      gate = Completer<List<NodeHealthView>>();
      final monitor = make();
      monitor.start();
      timers.fire();
      await monitor.checkNow();
      expect(checks, [false], reason: 'the tick and checkNow were skipped');
      gate!.complete(answer);
      await Future<void>.delayed(Duration.zero);
      expect(monitor.checking, isFalse);
      gate = null;
      await monitor.checkNow();
      expect(checks, [false, true]);
      monitor.dispose();
    });

    test('checkNow forces the check of every node', () async {
      final monitor = make();
      monitor.start();
      await Future<void>.delayed(Duration.zero);
      await monitor.checkNow();
      expect(checks.last, isTrue);
      monitor.dispose();
    });

    test('an error is kept and does not stop the loop', () async {
      failWith = StateError('the core is not ready');
      final monitor = make();
      monitor.start();
      await Future<void>.delayed(Duration.zero);
      expect(monitor.lastError, isA<StateError>());
      expect(monitor.checking, isFalse);
      expect(monitor.nodes.single.availability, NodeAvailability.unknown);
      failWith = null;
      timers.fire();
      await Future<void>.delayed(Duration.zero);
      expect(monitor.lastError, isNull);
      expect(monitor.of(_a)!.availability, NodeAvailability.available);
      monitor.dispose();
    });

    test('a failure to read the stored state is not an error of the screen', () {
      final monitor = NodeHealthMonitor(
        read: () => throw StateError('no core'),
        check: (_) async => const [],
        timer: timers.make,
      );
      monitor.start();
      expect(monitor.nodes, isEmpty);
      expect(monitor.lastError, isA<StateError>());
      monitor.dispose();
    });

    test('pause cancels the timer and resume starts it again with a check', () async {
      final monitor = make();
      monitor.start();
      await Future<void>.delayed(Duration.zero);
      final first = timers.created.last.timer;
      monitor.pause();
      expect(first.cancelled, isTrue);
      monitor.resume();
      await Future<void>.delayed(Duration.zero);
      expect(timers.created, hasLength(2));
      expect(timers.created.last.timer.cancelled, isFalse);
      expect(checks, [false, false]);
      monitor.dispose();
    });

    test('stop cancels the timer, and start works again later', () async {
      final monitor = make();
      monitor.start();
      await Future<void>.delayed(Duration.zero);
      monitor.stop();
      expect(timers.created.last.timer.cancelled, isTrue);
      monitor.start();
      await Future<void>.delayed(Duration.zero);
      expect(timers.created, hasLength(2));
      monitor.dispose();
    });

    test('start twice makes one timer, and nothing runs after dispose', () async {
      final monitor = make();
      monitor.start();
      monitor.start();
      await Future<void>.delayed(Duration.zero);
      expect(timers.created, hasLength(1));
      monitor.dispose();
      expect(timers.created.single.timer.cancelled, isTrue);
      timers.fire();
      await Future<void>.delayed(Duration.zero);
      expect(checks, [false]);
    });

    test('listeners hear the read, the start of a check and its end', () async {
      final monitor = make();
      var calls = 0;
      monitor.addListener(() => calls++);
      monitor.start();
      await Future<void>.delayed(Duration.zero);
      expect(calls, greaterThanOrEqualTo(3));
      monitor.dispose();
    });
  });

  group('agoText', () {
    final l = appL10n;

    test('seconds, minutes, hours and days', () {
      expect(agoText(l, 0), '0 s');
      expect(agoText(l, 59), '59 s');
      expect(agoText(l, 60), '1 min');
      expect(agoText(l, 3599), '59 min');
      expect(agoText(l, 3600), '1 h');
      expect(agoText(l, 48 * 3600 - 1), '47 h');
      expect(agoText(l, 48 * 3600), '2 d');
      expect(agoText(l, 10 * 86400), '10 d');
    });

    test('a negative time is 0', () {
      expect(agoText(l, -5), '0 s');
    });
  });

  group('the node cards of the home screen', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    ComputeOverviewView overview() => ComputeOverviewView(
      nodesCounted: 4,
      nodesUnreachable: 0,
      cpuCores: const CoresTotalView(total: 1, known: 1, unknownNodes: 0, atLeast: false),
      memBytes: const BytesTotalView(total: 1, known: 1, unknownNodes: 0, atLeast: false),
      diskBytes: const BytesTotalView(total: 1, known: 1, unknownNodes: 0, atLeast: false),
      creditNanoErg: const NanoErgTotalView(total: '1', known: '1', unknownNodes: 0, atLeast: false),
      paidNanoErg: const NanoErgTotalView(total: '1', known: '1', unknownNodes: 0, atLeast: false),
      freeNanoErg: const NanoErgTotalView(total: '1', known: '1', unknownNodes: 0, atLeast: false),
      nodes: [
        for (final p in [_a, _b, _c, _d])
          NodeComputeView(peerId: p, address: '$p.example:1', reachable: true, clientUnknown: false),
      ],
      instances: const [],
    );

    Future<NodeHealthMonitor> pump(
      WidgetTester tester,
      List<NodeHealthView> views, {
      NodeHealthCheck? check,
    }) async {
      tester.view.physicalSize = const Size(390, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final monitor = NodeHealthMonitor(
        read: () => views,
        check: check ?? (force) async => views,
        timer: _Timers().make,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ComputeHomeScreen(
            money: const WalletMoney(
              full: WalletSum(count: 1, unknown: 0, knownNano: 1),
              watched: WalletSum(count: 0, unknown: 0, knownNano: 0),
              gate: FullWalletGate.open,
            ),
            usdPerErg: 2,
            onWallets: () {},
            load: () async => overview(),
            healthMonitor: monitor,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return monitor;
    }

    String line(WidgetTester tester, String peer) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(Key('compute-home-health-$peer')),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data)
        .join(' ');

    testWidgets('each state has its own text', (tester) async {
      final l = appL10n;
      await pump(tester, [
        _view(_a, NodeAvailability.available, latency: 42),
        _view(_b, NodeAvailability.slow, latency: 4200),
        _view(_c, NodeAvailability.unknown),
        _view(
          _d,
          NodeAvailability.unreachable,
          lastOk: _now() - 7200,
          kind: CelautErrorKind.timeout,
          error: 'the node did not answer in time',
        ),
      ]);
      expect(line(tester, _a), l.celautNodeAvailable('42'));
      expect(line(tester, _b), l.celautNodeSlow('4200'));
      expect(line(tester, _c), l.celautNodeUnknownState);
      expect(
        line(tester, _d),
        '${l.celautNodeUnreachable} · ${l.celautNodeLastSeen('2 h')}',
      );
      // The reason, with the text of the node folded below it.
      expect(
        tester.widget<Text>(find.byKey(Key('compute-home-health-reason-$_d'))).data,
        CelautStrings.errorText(CelautErrorKind.timeout),
      );
      expect(
        tester.widget<Text>(find.byKey(Key('compute-home-health-detail-$_d'))).data,
        CelautStrings.detailLabel('the node did not answer in time'),
      );
      // An available node has no reason lines.
      expect(find.byKey(Key('compute-home-health-reason-$_a')), findsNothing);
    });

    testWidgets('a node that never answered says so', (tester) async {
      await pump(tester, [
        _view(_a, NodeAvailability.unreachable, kind: CelautErrorKind.unreachable),
      ]);
      expect(
        line(tester, _a),
        '${appL10n.celautNodeUnreachable} · ${appL10n.celautNodeNeverSeen}',
      );
      expect(find.byKey(Key('compute-home-health-detail-$_a')), findsNothing);
    });

    testWidgets('without a state from the core there is no line', (tester) async {
      await pump(tester, const []);
      expect(find.byKey(Key('compute-home-health-$_a')), findsNothing);
      // The figures of the card are still there.
      expect(find.byKey(Key('compute-home-credit-$_a')), findsOneWidget);
    });

    testWidgets('Check now forces a check and shows that it runs', (tester) async {
      final forced = <bool>[];
      final gate = Completer<List<NodeHealthView>>();
      final views = [_view(_a, NodeAvailability.available, latency: 10)];
      await pump(
        tester,
        views,
        check: (force) {
          forced.add(force);
          return force ? gate.future : Future.value(views);
        },
      );
      expect(find.text(appL10n.celautNodesCheckNow), findsOneWidget);
      await tester.tap(find.byKey(const Key('compute-home-check-nodes')));
      await tester.pump();
      expect(forced.last, isTrue);
      expect(find.text(appL10n.celautNodeChecking), findsWidgets);
      expect(
        tester.widget<TextButton>(find.byKey(const Key('compute-home-check-nodes'))).onPressed,
        isNull,
      );
      gate.complete([_view(_a, NodeAvailability.slow, latency: 9000)]);
      await tester.pumpAndSettle();
      expect(line(tester, _a), appL10n.celautNodeSlow('9000'));
      expect(find.text(appL10n.celautNodesCheckNow), findsOneWidget);
    });

    testWidgets('the overview is not loaded again when the checks give news', (tester) async {
      var loads = 0;
      final views = [_view(_a, NodeAvailability.available, latency: 10)];
      tester.view.physicalSize = const Size(390, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final monitor = NodeHealthMonitor(
        read: () => views,
        check: (force) async => views,
        timer: _Timers().make,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ComputeHomeScreen(
            money: const WalletMoney(
              full: WalletSum(count: 1, unknown: 0, knownNano: 1),
              watched: WalletSum(count: 0, unknown: 0, knownNano: 0),
              gate: FullWalletGate.open,
            ),
            usdPerErg: 2,
            onWallets: () {},
            load: () async {
              loads++;
              return overview();
            },
            healthMonitor: monitor,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await monitor.checkNow();
      await tester.pumpAndSettle();
      expect(loads, 1);
    });

    testWidgets('closing the screen stops the monitor that a test gave', (tester) async {
      final timers = _Timers();
      final monitor = NodeHealthMonitor(
        read: () => const [],
        check: (_) async => const [],
        timer: timers.make,
      );
      tester.view.physicalSize = const Size(390, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: ComputeHomeScreen(
            money: const WalletMoney(
              full: WalletSum(count: 0, unknown: 0, knownNano: 0),
              watched: WalletSum(count: 0, unknown: 0, knownNano: 0),
              gate: FullWalletGate.none,
            ),
            usdPerErg: null,
            onWallets: () {},
            load: () async => overview(),
            healthMonitor: monitor,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(timers.created.single.timer.cancelled, isFalse);
      await tester.pumpWidget(const SizedBox());
      expect(timers.created.single.timer.cancelled, isTrue);
      monitor.dispose();
    });
  });
}
