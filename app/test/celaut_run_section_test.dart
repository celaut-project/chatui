import 'dart:async';
import 'dart:typed_data';

import 'package:argus_wallet/bridge/api/celaut.dart';
import 'package:argus_wallet/bridge/api/celaut_catalog.dart';
import 'package:argus_wallet/bridge/api/celaut_env.dart';
import 'package:argus_wallet/bridge/api/celaut_package.dart';
import 'package:argus_wallet/bridge/api/celaut_service.dart';
import 'package:argus_wallet/celaut/env_store.dart';
import 'package:argus_wallet/celaut/launcher.dart';
import 'package:argus_wallet/celaut/package_channel.dart';
import 'package:argus_wallet/celaut/package_library.dart';
import 'package:argus_wallet/celaut/payers.dart';
import 'package:argus_wallet/celaut/service_strings.dart';
import 'package:argus_wallet/celaut/service_transfer.dart';
import 'package:argus_wallet/l10n/l10n.dart';
import 'package:argus_wallet/theme/argus_theme.dart';
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
  Future<bool> unlock(BuildContext context, PayerWallet wallet) async {
    if (unlocks) open = true;
    return unlocks;
  }
}

/// The service files loaded into the app, in memory.
class _Lib {
  final calls = <String>[];
  var stored = <LibraryPackageView>[];
  Object? importError;

  /// The service that an imported file holds.
  String imports = _best;

  LibraryPackageView view({String? id, String name = 'echo', bool present = true}) =>
      LibraryPackageView(
        serviceId: id ?? _best,
        name: name,
        path: '/data/packages/library/${id ?? _best}.bee',
        bytes: BigInt.from(4096),
        importedAt: 1,
        nodoExport: true,
        present: present,
      );

  PackageLibrary get library => PackageLibrary(
    importPackage: (path, name, dir) async {
      calls.add('import $path $name');
      if (importError != null) throw importError!;
      final v = view(id: imports, name: name.replaceAll('.celaut.bee', ''));
      stored = [...stored.where((p) => p.serviceId != v.serviceId), v];
      return v;
    },
    list: () => stored,
    remove: (id) async {
      calls.add('remove $id');
      stored = [for (final p in stored) if (p.serviceId != id) p];
    },
    privateDir: () async => '/data',
  );
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
  List<EnvChoice>? envChosen;
  Object? skillsError;
  var skills = <SkillView>[_sat, _summary];

  Future<void> open(
    WidgetTester tester, {
    FullWallets? wallets,
    QuoteView? preview,
    List<SkillServiceView>? services,
    ServiceTransfer? transfer,
    PackageChannel? packages,
    _Lib? lib,
    ThemeData? theme,
    bool askEnvironment = false,
    Future<List<DeclaredVariableView>> Function(String, NodeAddress)? declaration,
    EnvStore? envStore,
  }) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
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
              launch: ({required serviceIdHex, initialMu, environment}) async {
                launched.add('$serviceIdHex $initialMu');
                if (launchError != null) throw launchError!;
                if (askEnvironment) {
                  final quotes = QuotesView(quotes: [_quote()], failures: const []);
                  final chosen = await environment!(quotes);
                  if (chosen == null) throw const LaunchCancelled();
                  envChosen = chosen;
                }
                return outcome();
              },
              declaration: declaration,
              envStore: envStore,
              openTunnel: (id, slot) async {
                tunnels.add((id, slot));
                return 4321;
              },
              chatBuilder: (id, port) => Scaffold(body: Text('chat $id $port')),
              openDeposit: () => deposits++,
              transfer: transfer,
              packages: packages,
              library: (lib ?? _Lib()).library,
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
    envChosen = null;
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
    await tester.tap(find.byKey(const Key('run-confirm-ok')));
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

  testWidgets('every skill of the catalog is listed, not only the first ones', (tester) async {
    skills = [
      for (var i = 0; i < 9; i++) SkillView(boxId: 'skill-$i', name: 'Skill $i', prose: '', tags: const []),
    ];
    await open(tester);
    for (var i = 0; i < 9; i++) {
      expect(find.byKey(Key('run-skill-skill-$i')), findsOneWidget);
    }
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

  testWidgets('Run asks first, with the best node and its start cost', (tester) async {
    await open(tester, preview: _quote());
    await tester.tap(find.byKey(const Key('run-skill-skill-sat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skill-sheet-run')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('run-confirm')), findsOneWidget);
    expect(find.text(appL10n.celautRunConfirmTitle('Boolean SAT Solver')), findsOneWidget);
    expect(find.text(appL10n.celautRunConfirmBody), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('run-confirm-quote'))).data,
      appL10n.celautRunPreview('127.0.0.1:18460', '1,000,000 MU'),
    );
    expect(launched, isEmpty, reason: 'nothing starts before the user confirms');
    await tester.tap(find.byKey(const Key('run-confirm-ok')));
    await tester.pumpAndSettle();
    expect(launched, ['$_best 1000000']);
  });

  testWidgets('Cancel in the confirmation starts nothing', (tester) async {
    await open(tester, preview: _quote());
    await tester.tap(find.byKey(const Key('run-skill-skill-sat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skill-sheet-run')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('run-confirm-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('run-confirm')), findsNothing);
    expect(launched, isEmpty);
    expect(find.byKey(const Key('run-progress')), findsNothing);
  });

  testWidgets('with no price yet, the confirmation says so and Run still asks the nodes', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('run-skill-skill-sat')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skill-sheet-run')));
    await tester.pumpAndSettle();
    expect(find.text(appL10n.celautRunConfirmNoQuote), findsOneWidget);
    await tester.tap(find.byKey(const Key('run-confirm-ok')));
    await tester.pumpAndSettle();
    expect(launched, hasLength(1));
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

  group('the service files that the user loaded', () {
    late _Packages packages;
    late _Lib lib;

    setUp(() {
      packages = _Packages();
      lib = _Lib();
    });

    testWidgets('with none loaded, the section says how to load one', (tester) async {
      await open(tester, packages: packages, lib: lib);
      expect(find.byKey(const Key('pkg-empty')), findsOneWidget);
      expect(find.text(appL10n.celautPkgEmpty), findsOneWidget);
      expect(find.byKey(const Key('pkg-import')), findsOneWidget);
    });

    testWidgets('a file is picked, loaded into the app and listed', (tester) async {
      packages.picked = const PickedPackage(path: '/cache/picked.bee', bytes: 10, name: 'echo.celaut.bee');
      await open(tester, packages: packages, lib: lib);
      await tester.tap(find.byKey(const Key('pkg-import')));
      await tester.pumpAndSettle();
      expect(lib.calls, ['import /cache/picked.bee echo.celaut.bee']);
      expect(find.text(appL10n.celautPkgLoaded('echo')), findsOneWidget);
      expect(find.byKey(Key('pkg-$_best')), findsOneWidget);
      expect(find.text('echo'), findsOneWidget);
      expect(find.byKey(const Key('pkg-empty')), findsNothing);
      // Nothing was sent or launched: loading a file only keeps it.
      expect(launched, isEmpty);
    });

    testWidgets('closing the picker loads nothing', (tester) async {
      await open(tester, packages: packages, lib: lib);
      await tester.tap(find.byKey(const Key('pkg-import')));
      await tester.pumpAndSettle();
      expect(packages.picks, 1);
      expect(lib.calls, isEmpty);
      expect(find.byKey(const Key('pkg-empty')), findsOneWidget);
    });

    testWidgets('a file that is not a service package is refused with the reason', (tester) async {
      packages.picked = const PickedPackage(path: '/cache/junk.bee', bytes: 10, name: 'junk.bee');
      lib.importError = const CelautError(
        kind: CelautErrorKind.invalidInput,
        message: 'the file does not say which service it is',
      );
      await open(tester, packages: packages, lib: lib);
      await tester.tap(find.byKey(const Key('pkg-import')));
      await tester.pumpAndSettle();
      expect(
        find.text(appL10n.celautPkgBadFile('the file does not say which service it is')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('pkg-empty')), findsOneWidget);
    });

    testWidgets('Run launches the loaded service by its id', (tester) async {
      lib.stored = [lib.view()];
      await open(tester, packages: packages, lib: lib);
      await tester.tap(find.byKey(Key('pkg-run-$_best')));
      await tester.pumpAndSettle();
      expect(find.text(appL10n.celautRunConfirmTitle('echo')), findsOneWidget);
      await tester.tap(find.byKey(const Key('run-confirm-ok')));
      await tester.pumpAndSettle();
      expect(launched, ['$_best ${ServiceStrings.initialDefault}']);
      expect(changed, greaterThan(0));
    });

    testWidgets('with the theme of the app, a loaded service and the confirmation lay out', (tester) async {
      lib.stored = [lib.view(name: 'echo')];
      await open(tester, packages: packages, lib: lib, theme: argusTheme(watchful: false), preview: _quote());
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byKey(Key('pkg-run-$_best'))).width, lessThan(300));
      await tester.tap(find.byKey(Key('pkg-run-$_best')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('run-confirm')), findsOneWidget);
      await tester.tap(find.byKey(const Key('run-confirm-ok')));
      await tester.pumpAndSettle();
      expect(launched, hasLength(1));
    });

    testWidgets('a service whose file is gone cannot run and says so', (tester) async {
      lib.stored = [lib.view(present: false)];
      await open(tester, packages: packages, lib: lib);
      expect(find.text(appL10n.celautPkgMissing), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.byKey(Key('pkg-run-$_best'))).onPressed, isNull);
      expect(launched, isEmpty);
    });

    testWidgets('Remove asks first, then deletes it; Cancel keeps it', (tester) async {
      lib.stored = [lib.view(name: 'echo')];
      await open(tester, packages: packages, lib: lib);
      await tester.tap(find.byKey(Key('pkg-remove-$_best')));
      await tester.pumpAndSettle();
      expect(find.text(appL10n.celautPkgRemoveBody('echo')), findsOneWidget);
      await tester.tap(find.byKey(const Key('pkg-remove-cancel')));
      await tester.pumpAndSettle();
      expect(lib.calls, isEmpty);
      expect(find.byKey(Key('pkg-$_best')), findsOneWidget);

      await tester.tap(find.byKey(Key('pkg-remove-$_best')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pkg-remove-confirm')));
      await tester.pumpAndSettle();
      expect(lib.calls, ['remove $_best']);
      expect(find.byKey(Key('pkg-$_best')), findsNothing);
      expect(find.byKey(const Key('pkg-empty')), findsOneWidget);
    });

    testWidgets('the loaded services are shown by name with their size and a short id', (tester) async {
      lib.stored = [lib.view(name: 'echo'), lib.view(id: _other, name: 'translate')];
      await open(tester, packages: packages, lib: lib);
      expect(find.text('echo'), findsOneWidget);
      expect(find.text('translate'), findsOneWidget);
      expect(find.textContaining('4.0 KiB · ${_best.substring(0, 8)}'), findsOneWidget);
    });
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
      expect(find.byKey(const Key('run-confirm')), findsNothing, reason: 'it does not ask a second time');
      expect(packages.picks, 0);
    });

    testWidgets('no node has it: a .celaut.bee file is picked, loaded into the app and sent', (tester) async {
      launchError = missingOn(holder: false);
      packages.picked = const PickedPackage(path: '/cache/picked.bee', bytes: 10, name: 'echo.celaut.bee');
      final lib = _Lib();
      await open(tester, transfer: transfer(), packages: packages, lib: lib);
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
      // The file is loaded into the library first, and the service is sent from there.
      expect(lib.calls, ['import /cache/picked.bee echo.celaut.bee']);
      expect(transfers, ['send q.example /data/packages/library/$_best.bee']);
      expect(launched, hasLength(2));
      // And it stays in the app, listed with the services of the user.
      expect(find.byKey(Key('pkg-$_best')), findsOneWidget);
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

    testWidgets('a file of another service is loaded but not sent, and the reason is shown', (tester) async {
      launchError = missingOn(holder: false);
      packages.picked = const PickedPackage(path: '/cache/other.bee', bytes: 10, name: 'other');
      final lib = _Lib()..imports = _other;
      await open(tester, transfer: transfer(), packages: packages, lib: lib);
      await run(tester);
      await tester.tap(find.byKey(const Key('launch-send-service')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('send-confirm-ok')));
      await tester.pumpAndSettle();
      expect(find.text(appL10n.celautSendOtherService), findsOneWidget);
      expect(transfers, isEmpty);
      expect(find.byKey(Key('pkg-$_other')), findsOneWidget, reason: 'it stays in the library');
    });

    testWidgets('a service that the user loaded is sent from the library, with no file to pick', (tester) async {
      launchError = missingOn();
      final lib = _Lib()..stored = [_Lib().view()];
      await open(tester, transfer: transfer(), packages: packages, lib: lib);
      await run(tester);
      expect(find.text(appL10n.celautSendFromLibrary('q.example:9')), findsOneWidget);
      expect(find.text(appL10n.celautSendNoHolder), findsNothing);
      await tester.tap(find.byKey(const Key('launch-send-service')));
      await tester.pumpAndSettle();
      launchError = null;
      await tester.tap(find.byKey(const Key('send-confirm-ok')));
      await tester.pumpAndSettle();
      expect(packages.picks, 0);
      expect(transfers, ['send q.example /data/packages/library/$_best.bee'], reason: 'no fetch from a node');
      expect(launched, hasLength(2));
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

  group('environment variables', () {
    final store = EnvStore(
      names: () => [EnvNameView(name: 'OPENAI_KEY', changedAt: 1)],
      get: (n) => 'secret',
      set: (n, v) {},
      delete: (n) {},
    );
    const declared = [
      DeclaredVariableView(name: 'API_KEY', tags: ['text'], prose: 'The key of the API'),
      DeclaredVariableView(name: 'MODE', tags: [], prose: ''),
    ];

    testWidgets('a service that declares nothing starts with no question', (tester) async {
      await open(tester, askEnvironment: true, declaration: (id, node) async => const [], envStore: store);
      await run(tester);
      expect(find.byKey(const Key('env-step')), findsNothing);
      expect(envChosen, isEmpty);
      expect(launched, hasLength(1));
    });

    testWidgets('the declared variables are asked one by one and go to the start', (tester) async {
      final asked = <(String, int)>[];
      await open(
        tester,
        askEnvironment: true,
        declaration: (id, node) async {
          asked.add((id, node.port));
          return declared;
        },
        envStore: store,
      );
      await run(tester);
      // The declaration is read from the node of the best quote.
      expect(asked, [(_best, 18460)]);
      expect(find.text('Variable 1 of 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('env-ask-pick')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('env-pick-OPENAI_KEY')));
      await tester.pumpAndSettle();
      expect(find.text('Variable 2 of 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('env-ask-skip')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('env-run')));
      await tester.pumpAndSettle();
      expect(envChosen!.map((c) => (c.name, c.container, c.text)), [('API_KEY', 'OPENAI_KEY', null)]);
      expect(find.byKey(const Key('env-step')), findsNothing);
    });

    testWidgets('cancelling the question cancels the launch without a failure sheet', (tester) async {
      await open(tester, askEnvironment: true, declaration: (id, node) async => declared, envStore: store);
      await run(tester);
      await tester.tap(find.byKey(const Key('env-cancel')));
      await tester.pumpAndSettle();
      expect(envChosen, isNull);
      expect(changed, 0);
      expect(find.byKey(const Key('env-step')), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    /// Run, and stop at the dialog: the progress bar of the section animates for as long as
    /// it is open, so the test cannot wait for it to settle.
    Future<void> runUntilDialog(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('run-skill-skill-sat')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('skill-sheet-run')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('run-confirm-ok')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('a declaration that cannot be read offers to run with no variables', (tester) async {
      Future<List<DeclaredVariableView>> broken(String id, NodeAddress node) async =>
          throw const CelautError(kind: CelautErrorKind.protocol, message: 'too large');
      await open(tester, askEnvironment: true, declaration: broken, envStore: store);
      await runUntilDialog(tester);
      expect(find.byKey(const Key('env-unreadable')), findsOneWidget);
      await tester.tap(find.byKey(const Key('env-run-without')));
      await tester.pumpAndSettle();
      expect(envChosen, isEmpty);
      expect(changed, 1);
    });

    testWidgets('a declaration that cannot be read can be cancelled', (tester) async {
      Future<List<DeclaredVariableView>> broken(String id, NodeAddress node) async =>
          throw const CelautError(kind: CelautErrorKind.protocol, message: 'too large');
      await open(tester, askEnvironment: true, declaration: broken, envStore: store);
      await runUntilDialog(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(envChosen, isNull);
      expect(changed, 0);
    });
  });
}
