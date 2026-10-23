import 'package:argus_wallet/bridge/frb_generated.dart';
import 'package:argus_wallet/format.dart';
import 'package:argus_wallet/services/privacy_service.dart';
import 'package:argus_wallet/services/public_wallet_sync.dart';
import 'package:argus_wallet/services/wallet_database_service.dart';
import 'package:argus_wallet/services/wallet_service.dart';
import 'package:argus_wallet/ui/home/overview_model.dart';
import 'package:argus_wallet/ui/settings_screen.dart';
import 'package:argus_wallet/ui/wallets_overview_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/home_finders.dart';
import 'support/home_harness.dart';

// A1: the app opens on an overview of the wallet of the app, with a
// balance that needs no unlock.

const vanity = '9vanityPinnedAddressAtIndex275xxxxxxxxxxxxxxxxxxxxx';
const zero = '9zeroAddressOfThePinnedWalletxxxxxxxxxxxxxxxxxxxxxxx';

Map<String, dynamic> snapshot(String id, int nano, {int ageMinutes = 1}) => {
      'wallet_id': id,
      'primary_address': vanity,
      'frontier_addresses': [zero],
      'balance_nano_erg': nano,
      'tokens': [],
      'address_holdings': [
        {'address': zero, 'index': 0, 'balance_nano_erg': 3000000000, 'tokens': []},
        {'address': vanity, 'balance_nano_erg': nano - 3000000000, 'tokens': []},
      ],
      'public_only': true,
      'public_refreshed_at':
          DateTime.now().subtract(Duration(minutes: ageMinutes)).millisecondsSinceEpoch,
      'last_sync_timestamp':
          DateTime.now().subtract(Duration(minutes: ageMinutes)).millisecondsSinceEpoch,
    };

void main() {
  final api = HomeApi();
  setUpAll(() => RustLib.initMock(api: api));
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await privacyService.load();
    // One scheduler for the whole test run: each launch starts due.
    publicWalletSync.resetSchedule();
    api.balances.clear();
    api.balanceCalls.clear();
  });
  tearDown(() async {
    publicWalletSync.setForeground(true);
    if (walletService.isUnlocked) await walletService.lock();
  });

  Future<void> wallets(
    WidgetTester tester, {
    Map<String, dynamic>? pinnedSnapshot,
  }) async {
    FakeKeystore(wallets: ['ov-pinned']).install(tester);
    await tester.runAsync(() async {
      await saveWallet('ov-pinned', name: 'Vanity', address0: zero, pinnedIndex: 275, pinnedAddress: vanity);
      if (pinnedSnapshot != null) {
        await WalletDatabaseService.savePublicSnapshot('ov-pinned', pinnedSnapshot, () => true);
      }
    });
  }

  testWidgets('the wallet and its balance', (tester) async {
    publicWalletSync.setForeground(false);
    await wallets(tester, pinnedSnapshot: snapshot('ov-pinned', 12000000000));
    await pumpHome(tester);
    expect(walletService.isUnlocked, isFalse);
    // One wallet, with no name.
    expect(find.text('Vanity'), findsNothing);
    expect(find.text('Wallet details'), findsOneWidget);
    expect(plainOf(tester, find.byKey(const Key('overview-total'))), '12 ERG');
    expect(textPlainContaining('not loaded'), findsNothing);
    // One wallet: no way to add another.
    expect(find.byKey(const Key('overview-add-wallet')), findsNothing);
    // What index 0 of the pinned wallet holds is called out under its row.
    final row = find.byKey(const ValueKey('overview-row-seed-ov-pinned'));
    expect(find.descendant(of: row, matching: textPlain('3 ERG on another address')), findsOneWidget);
    // Opened (the fingerprint prompt cancelled), the locked page still shows
    // the wallet as its pinned address, not index 0, and its whole balance.
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('#275'), findsOneWidget);
    expect(find.text(shorten(vanity, head: 8, tail: 6)), findsOneWidget);
    expect(textPlain('12 ERG'), findsOneWidget);
    await disposeHome(tester);
  });

  testWidgets('hidden balances mask the total and every row', (tester) async {
    publicWalletSync.setForeground(false);
    await privacyService.setHideBalances(true);
    addTearDown(() => privacyService.setHideBalances(false));
    await wallets(tester, pinnedSnapshot: snapshot('ov-pinned', 12000000000));
    await pumpHome(tester);
    expect(plainOf(tester, find.byKey(const Key('overview-total'))), '•••••• ERG');
    expect(textPlainContaining(RegExp(r'\b12\b')), findsNothing);
    expect(textPlain('•••• ERG'), findsOneWidget, reason: 'the row of the wallet');
    expect(textPlain('Funds on another address'), findsOneWidget);
    expect(textPlainContaining('3 ERG'), findsNothing);
    await disposeHome(tester);
  });

  testWidgets('no wallet yet: create or restore one, and nothing to watch', (tester) async {
    SharedPreferences.setMockInitialValues({});
    FakeKeystore(wallets: const []).install(tester);
    await pumpHome(tester);
    expect(find.textContaining('No wallet yet'), findsOneWidget);
    for (final key in ['overview-create', 'overview-restore']) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
    for (final key in ['overview-watch-address', 'overview-watch-xpub']) {
      expect(find.byKey(Key(key)), findsNothing, reason: key);
    }
    await disposeHome(tester);
  });

  testWidgets('settings open from the overview, app-wide only', (tester) async {
    publicWalletSync.setForeground(false);
    await wallets(tester);
    await pumpHome(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.text('THIS WALLET'), findsNothing);
    expect(find.text('Network'), findsOneWidget);
    await disposeHome(tester);
  });

  testWidgets('locked wallets refresh from public data at launch, with no unlock', (tester) async {
    // A snapshot older than the five-minute floor, and a node that now
    // reports more on both addresses.
    await wallets(tester, pinnedSnapshot: snapshot('ov-pinned', 12000000000, ageMinutes: 60));
    api.balances[zero] = {'balance_nano_erg': 4000000000, 'tokens': []};
    api.balances[vanity] = {'balance_nano_erg': 9500000000, 'tokens': []};
    await pumpHome(tester);
    expect(walletService.isUnlocked, isFalse);
    expect(api.balanceCalls, containsAll([zero, vanity]));
    final row = find.byKey(const ValueKey('overview-row-seed-ov-pinned'));
    expect(find.descendant(of: row, matching: textPlain('13.5 ERG')), findsOneWidget);
    expect(find.descendant(of: row, matching: textPlain('4 ERG on another address')), findsOneWidget);
    await disposeHome(tester);
  });

  testWidgets('a pinned wallet never synced here is read at index 0 as well', (tester) async {
    await wallets(tester);
    api.balances[zero] = {'balance_nano_erg': 4000000000, 'tokens': []};
    api.balances[vanity] = {'balance_nano_erg': 9500000000, 'tokens': []};
    await pumpHome(tester);
    expect(api.balanceCalls, containsAll([zero, vanity]));
    final known = await tester.runAsync(() => WalletDatabaseService.lastKnownBalance('ov-pinned'));
    expect(known!.balanceNano, 13500000000);
    await disposeHome(tester);
  });

  test('the overview total is the sum of what its rows show', () {
    final rows = [
      OverviewEntry(ref: const WalletRef.seed('a'), name: 'a', state: OverviewRowState.locked, balanceNano: 5),
      OverviewEntry(ref: const WalletRef.seed('b'), name: 'b', state: OverviewRowState.locked),
      OverviewEntry(
        ref: const WalletRef.seed('c'),
        name: 'c',
        state: OverviewRowState.locked,
        balanceNano: 7,
        tokens: const [(id: 't', amount: 1, decimals: 0)],
      ),
    ];
    final totals = overviewTotals(rows);
    expect(totals.total.totalNano, 12);
    expect(totals.total.unknown, 1);
    expect(totals.wallets, 3);
    expect(totals.tokens.single.id, 't');
  });

  test("an unlocked wallet's row carries its live figures", () {
    final w = WalletInfo(walletId: 'live', name: 'Live', createdAt: DateTime(2026), address0: 'z');
    final row = buildOverviewEntries(
      wallets: [w],
      lastKnown: const {},
      unlockedWalletId: 'live',
      active: const ActiveWalletFigures(
        walletId: 'live',
        balanceNano: 10,
        syncing: false,
        tokens: [],
        holdings: [],
      ),
    ).single;
    expect(row.state, OverviewRowState.unlocked);
    expect(row.balanceNano, 10);
  });

  testWidgets('the overview is the only wallet list: no wallet icon, no Manage', (tester) async {
    publicWalletSync.setForeground(false);
    await wallets(tester);
    await pumpHome(tester);
    expect(find.byType(WalletsOverviewScreen), findsOneWidget);
    expect(find.byTooltip('Wallets'), findsNothing);
    expect(find.text('Manage'), findsNothing);
    await disposeHome(tester);
  });
}
