import 'dart:async';
import 'dart:typed_data';

import 'package:argus_wallet/bridge/api/celaut.dart';
import 'package:argus_wallet/bridge/api/celaut_catalog.dart';
import 'package:argus_wallet/bridge/api/celaut_package.dart';
import 'package:argus_wallet/bridge/api/celaut_service.dart';
import 'package:argus_wallet/celaut/launcher.dart';
import 'package:argus_wallet/celaut/package_channel.dart';
import 'package:argus_wallet/celaut/payers.dart';
import 'package:argus_wallet/celaut/service_transfer.dart';
import 'package:argus_wallet/l10n/l10n.dart';
import 'package:argus_wallet/ui/celaut/launch_failure_sheet.dart';
import 'package:argus_wallet/ui/celaut/run_service_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _best = 'aa' * 32;
final _other = 'bb' * 32;

const _sat = SkillView(
  boxId: 'skill-sat',
  name: 'Boolean SAT Solver',
  prose: 'Decides if a formula can be satisfied.',
  tags: ['logic'],
);
const _summary = SkillView(boxId: 'skill-md', name: 'Markdown Summarization', prose: '', tags: []);

List<SkillServiceView> _ranked() => [
  SkillServiceView(serviceId: _best, score: 0.8455, direct: true),
  SkillServiceView(serviceId: _other, score: 0.7, direct: true),
];

QuoteView _quote({String credit = '', String cost = '1000000'}) => QuoteView(
  address: const NodeAddress(host: '127.0.0.1', port: 18460),
  peerId: 'aa' * 32,
  costMu: cost,
  initMaintenanceMu: '1',
  maxMaintenanceMu: '1',
  maintenanceSecondsLoop: 10,
  variance: 0,
  comparedNanoErg: '1',
  clientBalanceMu: credit,
);

InstanceView _instance({List<int> chat = const []}) => InstanceView(
  instanceId: 'inst-1',
  peerId: 'aa' * 32,
  slots: Uint16List.fromList([8080]),
  chatSlots: Uint16List.fromList(chat),
  clientBalanceMu: '5',
);

class _Wallets implements FullWallets {
  _Wallets({this.full = true, this.open = true, this.unlocks = true});

  final bool full;
  bool open;
  final bool unlocks;

  @override
  Future<List<PayerWallet>> payers() async =>
      full ? [PayerWallet(walletId: 'w1', name: 'Main', balanceNano: 1, open: open)] : const [];

  @override
  Future<String?> loadDefault() async => null;

  @override
  Future<bool> unlock(BuildContext context, PayerWallet wallet) async {
    if (unlocks) open = true;
    return unlocks;
  }
}

class _Packages implements PackageChannel {
  bool metered = false;
  PickedPackage? picked;
  int picks = 0;

  @override
  Future<bool> isMetered() async => metered;

  @override
  Future<PickedPackage?> pick() async {
    picks++;
    return picked;
  }
}

void main() {
  late List<String> launched;
  late List<(String, int)> tunnels;
  late int changed;
  late int deposits;
  late LaunchOutcome Function() outcome;
  Object? launchError;
  Object? skillsError;
  var skills = <SkillView>[_sat, _summary];

  Future<void> open(
    WidgetTester tester, {
    FullWallets? wallets,
    QuoteView? preview,
    List<SkillServiceView>? services,
    ServiceTransfer? transfer,
    PackageChannel? packages,
  }) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RunServiceSection(
              wallets: wallets ?? _Wallets(),
              onChanged: () => changed++,
              newClient: (node) async =>
                  NewClientView(peerId: 'aa' * 32, freeCreditMu: '4500000', earlierClients: 1),
              loadSkills: () async {
                if (skillsError != null) throw skillsError!;
                return skills;
              },
              loadServices: (id) async => services ?? _ranked(),
              previewQuote: (id) async => preview,
              launch: ({required serviceIdHex, initialMu}) async {
                launched.add('$serviceIdHex $initialMu');
                if (launchError != null) throw launchError!;
                return outcome();
              },
              openTunnel: (id, slot) async {
                tunnels.add((id, slot));
                return 4321;
              },
              chatBuilder: (id, port) => Scaffold(body: Text('chat $id $port')),
              openDeposit: () => deposits++,
              transfer: transfer,
              packages: packages,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    launched = [];
    tunnels = [];
    changed = 0;
    deposits = 0;
    launchError = null;
    skillsError = null;
    skills = [_sat, _summary];
    outcome = () => LaunchOutcome(quote: _quote(), instance: _instance(), skipped: const []);
  });

  Future<void> run(WidgetTester tester, {String? serviceId}) async {
    await tester.tap(find.byKey(const Key('run-skill-skill-sat')));
    await tester.pumpAndSettle();
    if (serviceId != null) {
      await tester.tap(find.byKey(Key('skill-service-$serviceId')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('skill-sheet-run')));
    await tester.pumpAndSettle();
  }

  testWidgets('it lists the skills and the search narrows them', (tester) async {
    await open(tester);
    expect(find.text('RUN A SERVICE'), findsOneWidget);
    expect(find.text('Boolean SAT Solver'), findsOneWidget);
    expect(find.text('Markdown Summarization'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('run-search')), 'markdown');
    await tester.pump();
    expect(find.text('Boolean SAT Solver'), findsNothing);
    expect(find.text('Markdown Summarization'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('run-search')), 'zzz');
    await tester.pump();
    expect(find.byKey(const Key('run-empty')), findsOneWidget);
  });

  testWidgets('a failure to read the catalog shows a retry that reads it again', (tester) async {
    skillsError = StateError('no bridge');
    await open(tester);
    expect(find.byKey(const Key('run-error')), findsOneWidget);
    skillsError = null;
    await tester.tap(find.byKey(const Key('run-retry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('run-error')), findsNothing);
    expect(find.text('Boolean SAT Solver'), findsOneWidget);
  });

  testWidgets('a skill opens its services, the best first and chosen, with the best node', (tester) async {
    await open(tester, preview: _quote());
    await tester.tap(find.byKey(const Key('run-skill-skill-sat')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skill-sheet')), findsOneWidget);
    expect(find.byKey(const Key('skill-service-best')), findsOneWidget);
    final best = tester.getTopLeft(find.byKey(Key('skill-service-$_best')));
    final other = tester.getTopLeft(find.byKey(Key('skill-service-$_other')));
    expect(best.dy, lessThan(other.dy));
    expect(find.byKey(const Key('skill-service-chosen')), findsOneWidget);
    expect(find.textContaining('127.0.0.1:18460'), findsOneWidget);
    expect(find.textContaining('1,000,000 MU'), findsOneWidget);
  });

  testWidgets('a skill with no service says so, and has no Run button', (tester) async {
    await open(tester, services: const []);
    await tester.tap(find.byKey(const Key('run-skill-skill-sat')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skill-sheet-empty')), findsOneWidget);
    expect(find.byKey(const Key('skill-sheet-run')), findsNothing);
  });

  testWidgets('Run starts the best service with the default balance', (tester) async {
    await open(tester);
    await run(tester);
    expect(launched, ['$_best 1000000']);
  });

  testWidgets('Run starts the service that the user chose', (tester) async {
    await open(tester);
    await run(tester, serviceId: _other);
    expect(launched, ['$_other 1000000']);
  });

  testWidgets('a service with a chat slot opens the conversation', (tester) async {
    outcome = () => LaunchOutcome(quote: _quote(), instance: _instance(chat: [8080, 9090]), skipped: const []);
    await open(tester);
    await run(tester);
    expect(tunnels, [('inst-1', 8080)]);
    expect(find.text('chat inst-1 4321'), findsOneWidget);
    expect(changed, greaterThan(0));
  });

  testWidgets('a service with no chat slot stays on the home with a message and a reload', (tester) async {
    await open(tester);
    await run(tester);
    expect(tunnels, isEmpty);
    expect(find.textContaining('chat inst-1'), findsNothing);
    expect(find.textContaining('Started on 127.0.0.1:18460'), findsOneWidget);
    expect(find.textContaining('1,000,000 MU'), findsOneWidget);
    expect(changed, 1);
  });

  testWidgets('with no full wallet the sheet says so and Run is off', (tester) async {
    await open(tester, wallets: _Wallets(full: false));
    await tester.tap(find.byKey(const Key('run-skill-skill-sat')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skill-sheet-no-wallet')), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('skill-sheet-run'))).onPressed, isNull);
  });

  testWidgets('a locked wallet that is not opened stops the launch', (tester) async {
    await open(tester, wallets: _Wallets(open: false, unlocks: false));
    await run(tester);
    expect(launched, isEmpty);
    expect(find.text(appL10n.celautOpenFullWalletNeeded), findsOneWidget);
  });

  testWidgets('a locked wallet that is opened lets the launch go on', (tester) async {
    await open(tester, wallets: _Wallets(open: false));
    await run(tester);
    expect(launched, hasLength(1));
  });

  testWidgets('when no node starts it, a sheet says why for each node, with the text under Details', (tester) async {
    launchError = LaunchFailure(
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
          _quote(),
          const CelautError(kind: CelautErrorKind.nodeClosed, message: 'This node is not accepting new work.'),
        ),
      ],
      leftOut: const [LeftOutNode(address: 'd.example:4', peerId: 'd', kind: CelautErrorKind.timeout)],
    );
    await open(tester);
    await run(tester);
    expect(find.byKey(const Key('launch-failure')), findsOneWidget);
    expect(find.text(appL10n.celautRunFailedAll), findsOneWidget);
    expect(find.text('q.example:9'), findsOneWidget);
    expect(find.text(appL10n.celautErrorServiceMissing), findsOneWidget);
    expect(find.text('127.0.0.1:18460'), findsOneWidget);
    expect(find.text(appL10n.celautErrorNodeClosed), findsOneWidget);
    expect(find.text(appL10n.celautRunLeftOut), findsOneWidget);
    expect(find.text(appL10n.celautErrorTimeout), findsOneWidget);
    // The text of the node is folded.
    expect(find.text('This node is not accepting new work.'), findsNothing);
    await tester.tap(find.byKey(const Key('launch-details-127.0.0.1:18460')));
    await tester.pumpAndSettle();
    expect(find.text('This node is not accepting new work.'), findsOneWidget);
    expect(find.byKey(const Key('launch-failure-deposit')), findsNothing);
    await tester.tap(find.byKey(const Key('launch-failure-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('launch-failure')), findsNothing);
  });

  testWidgets('a credit problem shows the numbers and a button to the deposit screen', (tester) async {
    launchError = LaunchFailure(
      LaunchFailureKind.allFailed,
      skipped: [
        LaunchSkip(
          _quote(credit: '2500', cost: '1000000'),
          const CelautError(kind: CelautErrorKind.insufficientCredit, message: 'credit 2500 MU, price 1000000 MU'),
        ),
      ],
    );
    await open(tester);
    await run(tester);
    expect(find.text(appL10n.celautRunNeedsCredit('2,500 MU', '1,000,000 MU')), findsOneWidget);
    await tester.tap(find.byKey(const Key('launch-failure-deposit')));
    await tester.pumpAndSettle();
    expect(deposits, 1);
    expect(find.byKey(const Key('launch-failure')), findsNothing);
  });

  testWidgets('a node that forgot the client id gives the choice, never a new client by itself', (tester) async {
    launchError = LaunchFailure(
      LaunchFailureKind.allFailed,
      skipped: [
        LaunchSkip(
          _quote(),
          const CelautError(kind: CelautErrorKind.clientUnknown, message: 'forgot'),
        ),
      ],
    );
    await open(tester);
    await run(tester);
    await tester.tap(find.byKey(const Key('launch-failure-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('client-unknown-dialog')), findsOneWidget);
  });

  group('a service that a node does not have', () {
    late List<String> transfers;
    late _Packages packages;
    late TransferView progress;
    Object? sendError;
    Completer<void>? hold;

    ServiceTransfer transfer() => ServiceTransfer(
      fetch: (source, id, dir) async {
        transfers.add('fetch ${source.host}');
        return PackageView(
          path: '/data/packages/$id.bee',
          bytes: BigInt.from(10),
          serviceId: id,
          hasService: true,
          nodoExport: false,
        );
      },
      inspect: (path) async => PackageView(
        path: path,
        bytes: BigInt.from(10),
        serviceId: _best,
        hasService: true,
        nodoExport: true,
      ),
      send: (node, id, initialMu, path) async {
        transfers.add('send ${node.host} $path');
        await hold?.future;
        if (sendError != null) throw sendError!;
        return _quote();
      },
      progress: () => progress,
      cancel: () => transfers.add('cancel'),
      privateDir: () async => '/data',
    );

    LaunchFailure missingOn({bool holder = true}) => LaunchFailure(
      LaunchFailureKind.noQuotes,
      quoteFailures: [
        QuoteFailureView(
          address: const NodeAddress(host: 'q.example', port: 9),
          kind: CelautErrorKind.serviceMissing,
          message: 'This node does not have the service',
        ),
        if (holder)
          QuoteFailureView(
            address: const NodeAddress(host: 'h.example', port: 7),
            kind: CelautErrorKind.noRoom,
            message: 'This node cannot run the service right now',
          ),
      ],
    );

    setUp(() {
      transfers = [];
      packages = _Packages();
      progress = TransferView(stage: TransferStage.idle, bytes: BigInt.zero);
      sendError = null;
      hold = null;
    });

    testWidgets('it is sent from a node that has it, then the launch runs again', (tester) async {
      launchError = missingOn();
      packages.metered = true;
      await open(tester, transfer: transfer(), packages: packages);
      await run(tester);
      expect(find.byKey(const Key('launch-missing')), findsOneWidget);
      expect(find.text(appL10n.celautSendFromNode('h.example:7', 'q.example:9')), findsOneWidget);
      await tester.tap(find.byKey(const Key('launch-send-service')));
      await tester.pumpAndSettle();
      // On mobile data the confirmation warns.
      expect(find.byKey(const Key('send-confirm')), findsOneWidget);
      expect(find.byKey(const Key('send-metered')), findsOneWidget);
      launchError = null;
      await tester.tap(find.byKey(const Key('send-confirm-ok')));
      await tester.pumpAndSettle();
      expect(transfers, ['fetch h.example', 'send q.example /data/packages/$_best.bee']);
      expect(find.text(appL10n.celautSendDone), findsOneWidget);
      expect(launched, hasLength(2), reason: 'the launch runs again');
      expect(packages.picks, 0);
    });

    testWidgets('no node has it: a .celaut.bee file is picked and sent', (tester) async {
      launchError = missingOn(holder: false);
      packages.picked = const PickedPackage(path: '/cache/picked.bee', bytes: 10, name: 'echo.celaut.bee');
      await open(tester, transfer: transfer(), packages: packages);
      await run(tester);
      expect(find.text(appL10n.celautSendNoHolder), findsOneWidget);
      expect(find.text(appL10n.celautSendFromFile('q.example:9')), findsOneWidget);
      await tester.tap(find.byKey(const Key('launch-send-service')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('send-metered')), findsNothing);
      launchError = null;
      await tester.tap(find.byKey(const Key('send-confirm-ok')));
      await tester.pumpAndSettle();
      expect(packages.picks, 1);
      expect(transfers, ['send q.example /cache/picked.bee']);
      expect(launched, hasLength(2));
    });

    testWidgets('a cancelled confirmation or pick sends nothing', (tester) async {
      launchError = missingOn(holder: false);
      await open(tester, transfer: transfer(), packages: packages);
      await run(tester);
      await tester.tap(find.byKey(const Key('launch-send-service')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('send-confirm-cancel')));
      await tester.pumpAndSettle();
      expect(packages.picks, 0);

      await run(tester);
      await tester.tap(find.byKey(const Key('launch-send-service')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('send-confirm-ok')));
      await tester.pumpAndSettle();
      expect(packages.picks, 1, reason: 'the user closed the picker');
      expect(transfers, isEmpty);
      expect(launched, hasLength(2), reason: 'two launches, no third one');
    });

    testWidgets('a failed transfer says why, and the launch does not run again', (tester) async {
      launchError = missingOn();
      sendError = const CelautError(kind: CelautErrorKind.transferFailed, message: 'the file is cut');
      await open(tester, transfer: transfer(), packages: packages);
      await run(tester);
      await tester.tap(find.byKey(const Key('launch-send-service')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('send-confirm-ok')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('send-failed')), findsOneWidget);
      expect(find.text(appL10n.celautErrorTransferFailed), findsOneWidget);
      expect(find.text('the file is cut'), findsOneWidget);
      expect(launched, hasLength(1));
    });

    testWidgets('the node can store it and refuse the quote: its reason is shown', (tester) async {
      launchError = missingOn();
      sendError = const CelautError(kind: CelautErrorKind.unsupportedArchitecture, message: 'riscv64');
      await open(tester, transfer: transfer(), packages: packages);
      await run(tester);
      await tester.tap(find.byKey(const Key('launch-send-service')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('send-confirm-ok')));
      await tester.pumpAndSettle();
      expect(find.text(appL10n.celautErrorUnsupportedArchitecture), findsOneWidget);
    });

    testWidgets('a file of another service is refused with its reason', (tester) async {
      launchError = missingOn(holder: false);
      packages.picked = const PickedPackage(path: '/cache/other.bee', bytes: 10, name: 'other');
      final other = ServiceTransfer(
        inspect: (path) async => PackageView(
          path: path,
          bytes: BigInt.from(10),
          serviceId: _other,
          hasService: true,
          nodoExport: true,
        ),
        send: (node, id, initialMu, path) async => throw StateError('must not send'),
        progress: () => progress,
        cancel: () {},
      );
      await open(tester, transfer: other, packages: packages);
      await run(tester);
      await tester.tap(find.byKey(const Key('launch-send-service')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('send-confirm-ok')));
      await tester.pumpAndSettle();
      expect(find.text(appL10n.celautSendOtherService), findsOneWidget);
    });

    testWidgets('the progress shows the bytes and the percent, and Cancel stops the transfer', (tester) async {
      launchError = missingOn();
      hold = Completer<void>();
      progress = TransferView(
        stage: TransferStage.sending,
        bytes: BigInt.from(512 * 1024),
        total: BigInt.from(1024 * 1024),
      );
      await open(tester, transfer: transfer(), packages: packages);
      await run(tester);
      await tester.tap(find.byKey(const Key('launch-send-service')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('send-confirm-ok')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const Key('send-progress')), findsOneWidget);
      expect(find.text(appL10n.celautSendSending), findsOneWidget);
      expect(find.textContaining('50%'), findsOneWidget);
      await tester.tap(find.byKey(const Key('send-cancel')));
      await tester.pump();
      expect(transfers.last, 'cancel');
      sendError = const CelautError(kind: CelautErrorKind.transferFailed, message: 'the transfer was cancelled');
      hold!.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('send-progress')), findsNothing);
      expect(find.byKey(const Key('send-failed')), findsOneWidget);
    });
  });

  testWidgets('the failure sheet says that there is no node when the list is empty', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LaunchFailureSheet(failure: LaunchFailure(LaunchFailureKind.noNodes))),
      ),
    );
    expect(find.text(appL10n.celautRunFailedNoNodes), findsOneWidget);
    expect(find.byKey(const Key('launch-failure-deposit')), findsNothing);
  });

  testWidgets('a Celaut error of the quotes is a message, not a crash', (tester) async {
    launchError = const CelautError(kind: CelautErrorKind.unreachable, message: 'x');
    await open(tester);
    await run(tester);
    expect(find.text(appL10n.celautErrorUnreachable), findsOneWidget);
    expect(find.byKey(const Key('run-progress')), findsNothing);
  });
}
