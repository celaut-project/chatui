import 'dart:typed_data';

import 'package:argus_wallet/bridge/api/celaut_receipts.dart';
import 'package:argus_wallet/bridge/api/celaut_service.dart';
import 'package:argus_wallet/ui/celaut/instance_actions.dart';
import 'package:argus_wallet/l10n/l10n.dart';
import 'package:argus_wallet/theme/argus_theme.dart';
import 'package:argus_wallet/ui/celaut/instance_info_screen.dart';
import 'package:argus_wallet/ui/celaut/instance_receipts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _instance = InstanceListView(
  instanceId: 'i1-receipts',
  peerId: 'aa' * 32,
  address: 'node.example:53460',
  serviceId: 'ef' * 32,
  slots: Uint16List.fromList([8080]),
  chatSlots: Uint16List.fromList([8080]),
  webSlots: Uint16List(0),
  startedAt: 1,
  startChargeMu: '1000',
  name: 'Echo',
  alias: '',
  refundMu: '',
);

ReceiptsView _view({
  StartReceiptState start = StartReceiptState.valid,
  int checkpoints = 3,
  int streams = 1,
  int closed = 1,
  int cancelled = 0,
  List<ReceiptFaultView> faults = const [],
}) =>
    ReceiptsView(
      start: start,
      checkpoints: BigInt.from(checkpoints),
      streams: BigInt.from(streams),
      closed: BigInt.from(closed),
      cancelled: BigInt.from(cancelled),
      faults: faults,
    );

Future<void> _pump(
  WidgetTester tester,
  ReceiptsView? view, {
  Future<bool> Function(String)? export,
}) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: InstanceInfoScreen(
      instance: _instance,
      state: InstanceState.running,
      loadReceipts: (_) => view,
      exportReceipts: export ?? (_) async => true,
    ),
  ));
  await tester.pumpAndSettle();
}

String _text(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

void main() {
  testWidgets('good receipts: start ✓, the checkpoints, the close, no fault', (tester) async {
    await _pump(tester, _view());
    expect(find.byKey(const Key('info-receipts')), findsOneWidget);
    expect(_text(tester, 'info-receipts-start'), '✓');
    expect(_text(tester, 'info-receipts-checkpoints'), '3');
    expect(_text(tester, 'info-receipts-close'), '✓');
    expect(find.byKey(const Key('info-receipts-fault-0')), findsNothing);
  });

  testWidgets('a cancelled tunnel has no close, and it is not shown as a fault', (tester) async {
    await _pump(tester, _view(closed: 0, cancelled: 1));
    final l = appL10n;
    expect(_text(tester, 'info-receipts-close'), l.chatsReceiptsCancelled);
    expect(find.byKey(const Key('info-receipts-fault-0')), findsNothing);
  });

  testWidgets('a mismatch and a bad start are in red', (tester) async {
    await _pump(
      tester,
      _view(
        start: StartReceiptState.invalid,
        faults: const [
          ReceiptFaultView(kind: ReceiptFaultKind.envs, detail: ''),
          ReceiptFaultView(kind: ReceiptFaultKind.received, detail: ''),
        ],
      ),
    );
    final l = appL10n;
    final red = rustFor(tester.element(find.byKey(const Key('info-receipts'))));
    final start = tester.widget<Text>(find.byKey(const Key('info-receipts-start')));
    expect(start.data, '✗');
    expect(start.style?.color, red);
    final fault = tester.widget<Text>(find.byKey(const Key('info-receipts-fault-1')));
    expect(fault.data, l.chatsReceiptsFaultReceived);
    expect(fault.data, "Node signed data that doesn't match what this phone received");
    expect(fault.style?.color, red);
    expect(_text(tester, 'info-receipts-fault-0'), l.chatsReceiptsFaultEnvs);
  });

  testWidgets('export shares the file, and says so when there is nothing', (tester) async {
    final asked = <String>[];
    await _pump(tester, _view(), export: (id) async {
      asked.add(id);
      return false;
    });
    await tester.ensureVisible(find.byKey(const Key('info-receipts-export')));
    await tester.tap(find.byKey(const Key('info-receipts-export')));
    await tester.pump();
    expect(asked, ['i1-receipts']);
    expect(find.text(appL10n.chatsReceiptsExportNone), findsOneWidget);
  });

  testWidgets('no section when the app cannot read the receipts', (tester) async {
    await _pump(tester, null);
    expect(find.byKey(const Key('info-receipts')), findsNothing);
    expect(find.byKey(const Key('info-stop')), findsOneWidget);
  });

  test('the close of several tunnels has a count for each state', () {
    final l = appL10n;
    expect(receiptsCloseText(l, _view(streams: 0, closed: 0)), l.chatsReceiptsNoTunnel);
    expect(receiptsCloseText(l, _view(streams: 1, closed: 0)), l.chatsReceiptsOpen);
    expect(
      receiptsCloseText(l, _view(streams: 4, closed: 2, cancelled: 1)),
      '✓ 2 · ${l.chatsReceiptsCancelled} 1 · ${l.chatsReceiptsOpen} 1',
    );
  });
}
