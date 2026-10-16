import 'package:argus_wallet/bridge/frb_generated.dart';
import 'package:argus_wallet/services/public_wallet_sync.dart';
import 'package:argus_wallet/services/single_wallet.dart';
import 'package:argus_wallet/services/wallet_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/home_harness.dart';

// The app holds one Ergo wallet and no watched wallets (docs/celaut/ui.md,
// section 1). At each start, the migration removes what an earlier version
// left beyond that.

void main() {
  final api = HomeApi();
  setUpAll(() => RustLib.initMock(api: api));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    publicWalletSync.setForeground(false);
  });
  tearDown(() => publicWalletSync.setForeground(true));

  group('the migration', () {
    Never noDelete(String id) => fail('no wallet is deleted, but $id was');

    test('the watched wallets and the default payer are removed; the rest stays', () async {
      SharedPreferences.setMockInitialValues({
        'argus_watch_only_addresses': '["9watched"]',
        'argus_watch_only_accounts_v1': '[]',
        'celaut_default_payer_v1': 'w1',
        'argus_token_descriptors_v1_watched:address:9watched': '{}',
        'argus_token_descriptors_v1_watched:account:xpub': '{}',
        'argus_token_descriptors_v1_w1': '{}',
        'argus_address_labels': '[]',
      });
      await enforceSingleWallet(walletIds: () async => ['w1'], deleteWallet: noDelete);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), {'argus_token_descriptors_v1_w1', 'argus_address_labels'});
    });

    test('the first wallet stays; every other wallet is deleted', () async {
      final deleted = <String>[];
      await enforceSingleWallet(
        walletIds: () async => ['first', 'second', 'third'],
        deleteWallet: (id) async => deleted.add(id),
      );
      expect(deleted, ['second', 'third']);
    });

    test('one wallet, or none: nothing is deleted', () async {
      await enforceSingleWallet(walletIds: () async => ['only'], deleteWallet: noDelete);
      await enforceSingleWallet(walletIds: () async => const [], deleteWallet: noDelete);
    });

    testWidgets('the user order of the wallets decides which one stays', (tester) async {
      FakeKeystore(wallets: ['w-a', 'w-b', 'w-c']).install(tester);
      final deleted = <String>[];
      await tester.runAsync(() async {
        await saveWallet('w-a', name: 'A');
        await saveWallet('w-b', name: 'B');
        await saveWallet('w-c', name: 'C');
        await walletService.setWalletOrder(['w-b', 'w-c', 'w-a']);
        await enforceSingleWallet(deleteWallet: (id) async => deleted.add(id));
      });
      expect(deleted, ['w-c', 'w-a']);
    });
  });

  group('the home screen', () {
    testWidgets('runs the migration before it reads the wallets', (tester) async {
      final keystore = FakeKeystore(wallets: ['w-keep', 'w-gone']);
      keystore.install(tester);
      await tester.runAsync(() async {
        await saveWallet('w-keep', name: 'Keep');
        await saveWallet('w-gone', name: 'Gone');
      });
      var runs = 0;
      await pumpHome(
        tester,
        enforceSingleWallet: () async {
          runs++;
          keystore.wallets = ['w-keep'];
        },
      );
      expect(runs, 1);
      expect(find.byKey(const ValueKey('overview-row-seed-w-keep')), findsOneWidget);
      expect(find.byKey(const ValueKey('overview-row-seed-w-gone')), findsNothing);
      await disposeHome(tester);
    });

    testWidgets('the Wallet line of the compute home opens the wallet', (tester) async {
      FakeKeystore(wallets: ['w-only']).install(tester);
      await tester.runAsync(() => saveWallet('w-only', name: 'Only'));
      await pumpHome(tester, computeHome: true);
      await tester.tap(find.byKey(const Key('compute-home-wallets')));
      await tester.pumpAndSettle();
      // The page of the wallet, behind its gate: no wallets list in between.
      expect(find.byKey(const Key('gate-unlock')), findsOneWidget);
      expect(find.byKey(const Key('overview-list')), findsNothing);
      await disposeHome(tester);
    });

    testWidgets('with no wallet, the Wallet line offers to create or restore one', (tester) async {
      FakeKeystore(wallets: const []).install(tester);
      await pumpHome(tester, computeHome: true);
      await tester.tap(find.byKey(const Key('compute-home-wallets')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('overview-create')), findsOneWidget);
      expect(find.byKey(const Key('overview-restore')), findsOneWidget);
      await disposeHome(tester);
    });
  });
}
