import 'package:argus_wallet/bridge/api/celaut.dart';
import 'package:argus_wallet/bridge/api/celaut_home.dart';
import 'package:argus_wallet/bridge/api/celaut_service.dart';
import 'package:argus_wallet/bridge/frb_generated.dart';
import 'package:argus_wallet/format.dart';
import 'package:argus_wallet/l10n/l10n.dart';
import 'package:argus_wallet/ui/celaut/known_nodes_screen.dart';
import 'package:argus_wallet/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _a = 'aa' * 32;
final _b = 'bb' * 32;

/// The node list as the database keeps it: a removed node keeps its record and its
/// deposits, and comes back with them.
class _Db implements KnownNodes {
  final records = <String, ({List<String> addresses, int deposited, bool listed})>{
    'aa' * 32: (addresses: ['a.example:1'], deposited: 10000000, listed: true),
  };
  final byAddress = {'a.example:1': 'aa' * 32, 'b.example:2': 'bb' * 32};
  final errors = <CelautError>[];
  final adds = <String>[];

  KnownNodeView _view(String peer) => KnownNodeView(
    peerId: peer,
    addresses: records[peer]!.addresses,
    depositedNanoErg: BigInt.from(records[peer]!.deposited),
  );

  @override
  List<KnownNodeView> list() => [
    for (final e in records.entries)
      if (e.value.listed) _view(e.key),
  ];

  @override
  Future<KnownNodeView> add(NodeAddress node) async {
    final address = '${node.host}:${node.port}';
    adds.add(address);
    if (errors.isNotEmpty) throw errors.removeAt(0);
    final peer = byAddress[address]!;
    final old = records[peer];
    records[peer] = (
      addresses: old?.addresses ?? [address],
      deposited: old?.deposited ?? 0,
      listed: true,
    );
    return _view(peer);
  }

  @override
  void remove(String peerId) {
    final old = records[peerId]!;
    records[peerId] = (addresses: old.addresses, deposited: old.deposited, listed: false);
  }
}

class _Api extends RustLibApi {
  @override
  List<KnownNodeView> crateApiCelautHomeCelautKnownNodes() => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => RustLib.initMock(api: _Api()));

  Future<_Db> pump(
    WidgetTester tester, {
    List<String>? made,
    List<String?>? scans,
    bool camera = false,
  }) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = _Db();
    await tester.pumpWidget(
      MaterialApp(
        home: KnownNodesScreen(
          nodes: db,
          newClient: (node) async {
            made?.add('${node.host}:${node.port}');
            return NewClientView(peerId: _b, earlierClients: 1);
          },
          // The QR codes that the scanner reads, in order; null is "back". With
          // `camera`, the app's scanner opens (the test has no camera).
          scan: camera ? null : (_) async => scans!.removeAt(0),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return db;
  }

  testWidgets('add a node by its address and remove it; its deposits stay', (tester) async {
    final db = await pump(tester);
    expect(find.byKey(Key('nodes-row-$_a')), findsOneWidget);
    expect(find.text(appL10n.celautNodesDeposited(formatErg(10000000))), findsOneWidget);

    await tester.enterText(find.byKey(const Key('nodes-address')), 'b.example:2');
    await tester.tap(find.byKey(const Key('nodes-add')));
    await tester.pumpAndSettle();
    expect(db.adds, ['b.example:2']);
    expect(find.byKey(Key('nodes-row-$_b')), findsOneWidget);
    expect(find.text(appL10n.celautNodesAdded), findsOneWidget);

    await tester.tap(find.byKey(Key('nodes-remove-$_a')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('nodes-row-$_a')), findsNothing);
    expect(find.text(appL10n.celautNodesRemoved), findsOneWidget);
    // The record and its deposits stay in the database.
    expect(db.records[_a]!.deposited, 10000000);

    // Adding it again restores them.
    await tester.enterText(find.byKey(const Key('nodes-address')), 'a.example:1');
    await tester.tap(find.byKey(const Key('nodes-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('nodes-row-$_a')), findsOneWidget);
    expect(find.text(appL10n.celautNodesDeposited(formatErg(10000000))), findsOneWidget);
  });

  testWidgets('a bad address calls nothing', (tester) async {
    final db = await pump(tester);
    await tester.enterText(find.byKey(const Key('nodes-address')), 'no port');
    await tester.tap(find.byKey(const Key('nodes-add')));
    await tester.pumpAndSettle();
    expect(db.adds, isEmpty);
  });

  testWidgets('add a node by a QR code: the same check as a typed address', (tester) async {
    final db = await pump(tester, scans: ['celaut://node?addr=b.example:2', '[::1]:9']);
    await tester.tap(find.byKey(const Key('nodes-scan')));
    await tester.pumpAndSettle();
    expect(db.adds, ['b.example:2']);
    expect(find.byKey(Key('nodes-row-$_b')), findsOneWidget);
    expect(find.text(appL10n.celautNodesAdded), findsOneWidget);
    expect(find.byKey(const Key('nodes-error')), findsNothing);

    // A bare address goes to the node check too; this one does not answer.
    db.errors.add(const CelautError(kind: CelautErrorKind.unreachable, message: 'refused'));
    await tester.tap(find.byKey(const Key('nodes-scan')));
    await tester.pumpAndSettle();
    expect(db.adds, ['b.example:2', '::1:9']);
  });

  testWidgets('a QR code that is not a node address shows the error and stores nothing', (
    tester,
  ) async {
    final db = await pump(
      tester,
      scans: ['ergopay://example.org/pay', 'celaut://node?addr=b.example:0'],
    );
    await tester.enterText(find.byKey(const Key('nodes-address')), 'typed');
    await tester.tap(find.byKey(const Key('nodes-scan')));
    await tester.pumpAndSettle();
    expect(db.adds, isEmpty);
    expect(find.text(appL10n.celautAddressInvalid), findsOneWidget);
    // The typed text stays; the scanned text does not go into the field.
    expect(find.text('typed'), findsOneWidget);

    await tester.tap(find.byKey(const Key('nodes-scan')));
    await tester.pumpAndSettle();
    expect(db.adds, isEmpty);
    expect(find.text(appL10n.celautPortInvalid), findsOneWidget);
    expect(find.byKey(Key('nodes-row-$_b')), findsNothing);
    expect(db.records.keys, [_a]);
  });

  testWidgets('a scanned node that fails the check shows the error of a typed address', (
    tester,
  ) async {
    const refused = CelautError(kind: CelautErrorKind.unreachable, message: 'refused');
    final db = await pump(tester, scans: ['celaut://node?addr=b.example:2']);
    db.errors.add(refused);
    await tester.enterText(find.byKey(const Key('nodes-address')), 'b.example:2');
    await tester.tap(find.byKey(const Key('nodes-add')));
    await tester.pumpAndSettle();
    final typed = tester.widget<Text>(find.byKey(const Key('nodes-error'))).data;

    await tester.enterText(find.byKey(const Key('nodes-address')), '');
    db.errors.add(refused);
    await tester.tap(find.byKey(const Key('nodes-scan')));
    await tester.pumpAndSettle();
    expect(db.adds, ['b.example:2', 'b.example:2']);
    expect(tester.widget<Text>(find.byKey(const Key('nodes-error'))).data, typed);
    expect(find.byKey(Key('nodes-row-$_b')), findsNothing);
    expect(db.records.keys, [_a]);
  });

  testWidgets('back from the scanner changes nothing; the address field still works', (
    tester,
  ) async {
    final db = await pump(tester, scans: [null]);
    await tester.tap(find.byKey(const Key('nodes-scan')));
    await tester.pumpAndSettle();
    expect(db.adds, isEmpty);
    expect(find.byKey(const Key('nodes-error')), findsNothing);

    await tester.enterText(find.byKey(const Key('nodes-address')), 'b.example:2');
    await tester.tap(find.byKey(const Key('nodes-add')));
    await tester.pumpAndSettle();
    expect(db.adds, ['b.example:2']);
    expect(find.byKey(Key('nodes-row-$_b')), findsOneWidget);
  });

  testWidgets('no camera (or no permission): a message, then the address field works', (
    tester,
  ) async {
    // The camera plugin as on a phone where the user refused the camera permission.
    const channel = MethodChannel('plugins.flutter.io/camera');
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'availableCameras') {
        return [
          {'name': '0', 'lensFacing': 'back', 'sensorOrientation': 90},
        ];
      }
      throw PlatformException(code: 'CameraAccessDenied', message: 'denied');
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
    );
    final db = await pump(tester, camera: true);
    // Nothing asks for the camera before the scanner opens.
    expect(calls, isEmpty);
    await tester.tap(find.byKey(const Key('nodes-scan')));
    await tester.pumpAndSettle();
    expect(find.text(appL10n.scanCameraUnavailable), findsOneWidget);
    await tester.tap(find.text(appL10n.scanBack));
    await tester.pumpAndSettle();
    expect(db.adds, isEmpty);

    await tester.enterText(find.byKey(const Key('nodes-address')), 'b.example:2');
    await tester.tap(find.byKey(const Key('nodes-add')));
    await tester.pumpAndSettle();
    expect(db.adds, ['b.example:2']);
  });

  testWidgets('a node that forgot the client: a new client, then the add', (tester) async {
    final made = <String>[];
    final db = await pump(tester, made: made);
    db.errors.add(
      const CelautError(
        kind: CelautErrorKind.clientUnknown,
        message: 'This RPC requires a client_id minted by GenerateClient first.',
      ),
    );
    await tester.enterText(find.byKey(const Key('nodes-address')), 'b.example:2');
    await tester.tap(find.byKey(const Key('nodes-add')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('client-unknown-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('client-unknown-new')));
    await tester.pumpAndSettle();
    expect(made, ['b.example:2']);
    expect(db.adds, ['b.example:2', 'b.example:2']);
    expect(find.byKey(Key('nodes-row-$_b')), findsOneWidget);
  });

  testWidgets('Settings opens the node list and comes back without an error', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('com.argus.wallet/secure_storage');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'listWalletIds' ? <String>[] : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
    );
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-nodes')));
    await tester.pumpAndSettle();
    expect(find.text(appL10n.celautNodesEmpty), findsOneWidget);
    // Back to Settings: `_open` refreshes the wallets with setState. Its callback must
    // not return a Future (that was an assertion error before).
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('settings-nodes')), findsOneWidget);
  });
}
