import 'dart:io';
import 'dart:typed_data';

import 'package:argus_wallet/bridge/api/celaut.dart';
import 'package:argus_wallet/bridge/api/celaut_service.dart';
import 'package:argus_wallet/bridge/frb_generated.dart';
import 'package:argus_wallet/celaut/service_strings.dart';
import 'package:argus_wallet/celaut/tunnel_http.dart';
import 'package:argus_wallet/ui/celaut/service_screen.dart';
import 'package:argus_wallet/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _service = '9b0e4e45d3b078451984895891402a24b24a7f4112522592d7b3e2326aecb4c4';
final _cheap = 'aa' * 32;
final _dear = 'bb' * 32;

QuoteView _quote(String peer, int port, String cost, String? compared) => QuoteView(
      address: NodeAddress(host: '127.0.0.1', port: port),
      peerId: peer,
      costMu: cost,
      initMaintenanceMu: '11990',
      maxMaintenanceMu: '11990',
      maintenanceSecondsLoop: 10,
      variance: 0,
      comparedNanoErg: compared,
    );

class ServiceApi extends RustLibApi {
  final quoteCalls = <({List<NodeAddress> nodes, String service, String? initial})>[];
  final startCalls = <({NodeAddress node, String service, String? initial})>[];
  final stops = <String>[];
  int tunnelPort = 0;
  Object? quoteAnswer;

  @override
  Future<QuotesView> crateApiCelautServiceCelautQuoteService({
    required List<NodeAddress> nodes,
    required String serviceIdHex,
    String? initialMu,
  }) async {
    quoteCalls.add((nodes: nodes, service: serviceIdHex, initial: initialMu));
    final a = quoteAnswer;
    if (a is CelautError) throw a;
    return a! as QuotesView;
  }

  @override
  Future<InstanceView> crateApiCelautServiceCelautStartService({
    required NodeAddress node,
    required String serviceIdHex,
    String? initialMu,
  }) async {
    startCalls.add((node: node, service: serviceIdHex, initial: initialMu));
    return InstanceView(
      instanceId: 'inst-1',
      peerId: _cheap,
      slots: Uint16List.fromList([3030]),
      clientBalanceMu: '3500000',
    );
  }

  @override
  Future<int> crateApiCelautServiceCelautOpenTunnel({
    required String instanceId,
    required int slot,
  }) async =>
      tunnelPort;

  @override
  Future<InstanceStatusView> crateApiCelautServiceCelautInstanceStatus({
    required String instanceId,
  }) async =>
      InstanceStatusView(
        instanceBalanceMu: '976400',
        streamsOpened: BigInt.one,
        lastTunnelError: null,
      );

  @override
  Future<StopView> crateApiCelautServiceCelautStopService({required String instanceId}) async {
    stops.add(instanceId);
    return StopView(refundMu: '976399', clientBalanceMu: '4476399');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final api = ServiceApi();
  setUpAll(() => RustLib.initMock(api: api));
  setUp(() {
    api.quoteCalls.clear();
    api.startCalls.clear();
    api.stops.clear();
    api.quoteAnswer = QuotesView(
      quotes: [_quote(_cheap, 18460, '1000000', '5316400'), _quote(_dear, 18461, '9000000', null)],
      failures: [
        QuoteFailureView(
          address: const NodeAddress(host: 'down.example', port: 9000),
          kind: CelautErrorKind.unreachable,
          message: 'connection refused',
        ),
      ],
    );
  });

  Future<void> pump(WidgetTester tester, {TunnelHttp? http}) async {
    tester.view.physicalSize = const Size(390, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: ServiceScreen(http: http)));
  }

  Future<void> fill(WidgetTester tester, {String nodes = '127.0.0.1:18460\n127.0.0.1:18461'}) async {
    await tester.enterText(find.byKey(const Key('service-nodes')), nodes);
    await tester.enterText(find.byKey(const Key('service-id')), _service.toUpperCase());
  }

  testWidgets('quotes every node, best first, and shows the failures', (tester) async {
    await pump(tester);
    await fill(tester, nodes: '127.0.0.1:18460\n\n[::1]:18461\ndown.example:9000');
    await tester.tap(find.byKey(const Key('service-quote')));
    await tester.pumpAndSettle();

    final call = api.quoteCalls.single;
    expect(call.nodes.map((n) => '${n.host}:${n.port}'),
        ['127.0.0.1:18460', '::1:18461', 'down.example:9000']);
    expect(call.service, _service);
    expect(call.initial, ServiceStrings.initialDefault);
    final cheap = tester.getTopLeft(find.byKey(Key('service-quote-$_cheap')));
    final dear = tester.getTopLeft(find.byKey(Key('service-quote-$_dear')));
    expect(cheap.dy, lessThan(dear.dy));
    expect(find.text(ServiceStrings.cost('1000000')), findsOneWidget);
    expect(find.text(ServiceStrings.compared('5316400')), findsOneWidget);
    expect(find.text(ServiceStrings.compared(null)), findsOneWidget);
    expect(find.text(ServiceStrings.failuresTitle.toUpperCase()), findsOneWidget);
    expect(find.text('Detail: connection refused'), findsOneWidget);
  });

  testWidgets('bad input is shown at the fields and no node is called', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('service-quote')));
    await tester.pumpAndSettle();
    expect(find.text(ServiceStrings.nodesEmpty), findsOneWidget);
    expect(find.text(ServiceStrings.serviceInvalid), findsOneWidget);

    await tester.enterText(find.byKey(const Key('service-nodes')), 'node.example');
    await tester.enterText(find.byKey(const Key('service-id')), _service);
    await tester.enterText(find.byKey(const Key('service-initial')), '1.5');
    await tester.tap(find.byKey(const Key('service-quote')));
    await tester.pumpAndSettle();
    expect(find.text(ServiceStrings.nodeInvalid('node.example')), findsOneWidget);
    expect(find.text(ServiceStrings.initialInvalid), findsOneWidget);
    expect(api.quoteCalls, isEmpty);
  });

  testWidgets('an empty start balance asks for the default of the node', (tester) async {
    await pump(tester);
    await fill(tester);
    await tester.enterText(find.byKey(const Key('service-initial')), '');
    await tester.tap(find.byKey(const Key('service-quote')));
    await tester.pumpAndSettle();
    expect(api.quoteCalls.single.initial, isNull);
  });

  testWidgets('start, call through the local port, and stop', (tester) async {
    // The local port of the tunnel: here a local HTTP server that counts connections.
    final connections = <int>{};
    final server = (await tester.runAsync(
      () => HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    ))!;
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      connections.add(request.connectionInfo!.remotePort);
      request.response.write('bold-pasteur');
      await request.response.close();
    });
    api.tunnelPort = server.port;
    // testWidgets answers every HttpClient with 400: this one must reach the socket.
    final saved = HttpOverrides.current;
    HttpOverrides.global = null;
    final http = TunnelHttp();
    HttpOverrides.global = saved;
    addTearDown(http.close);

    await pump(tester, http: http);
    await fill(tester);
    await tester.tap(find.byKey(const Key('service-quote')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key('service-start-$_cheap')));
    await tester.pumpAndSettle();

    final start = api.startCalls.single;
    expect(start.node, const NodeAddress(host: '127.0.0.1', port: 18460));
    expect(start.service, _service);
    expect(start.initial, ServiceStrings.initialDefault);
    expect(find.byKey(const Key('service-instance')), findsOneWidget);
    expect(find.text(ServiceStrings.clientBalance('3500000')), findsOneWidget);
    // One instance at a time: the start buttons are off.
    expect(
      tester.widget<OutlinedButton>(find.byKey(Key('service-start-$_dear'))).onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('service-open-3030')));
    await tester.pumpAndSettle();
    expect(find.text(ServiceStrings.localPort(server.port)), findsOneWidget);

    for (var i = 0; i < 2; i++) {
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('service-call-3030')));
        // Let the real socket answer.
        for (var j = 0; j < 50 && find.byKey(const Key('service-answer')).evaluate().isEmpty; j++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await tester.pump();
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
    }
    expect(find.text('HTTP 200\nbold-pasteur'), findsOneWidget);
    expect(connections, hasLength(1), reason: 'the calls must share one connection');
    expect(find.text(ServiceStrings.instanceBalance('976400')), findsOneWidget);
    expect(find.text(ServiceStrings.streams(BigInt.one)), findsOneWidget);

    await tester.tap(find.byKey(const Key('service-stop')));
    await tester.pumpAndSettle();
    expect(api.stops, ['inst-1']);
    expect(find.text(ServiceStrings.stopped('976399', '4476399')), findsOneWidget);
    expect(find.byKey(const Key('service-instance')), findsNothing);
  });

  testWidgets('an error of the call is shown in plain English', (tester) async {
    api.quoteAnswer = CelautError(kind: CelautErrorKind.invalidInput, message: 'bad id');
    await pump(tester);
    await fill(tester);
    await tester.tap(find.byKey(const Key('service-quote')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('service-error')), findsOneWidget);
    expect(find.text('Detail: bad id'), findsOneWidget);
  });

  testWidgets('Settings has a Developer row that opens the screen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('com.argus.wallet/secure_storage');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'listWalletIds' ? <String>[] : null,
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text(ServiceStrings.rowTitle));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('service-quote')), findsOneWidget);
  });
}
