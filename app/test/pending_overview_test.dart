import 'dart:convert';

import 'package:argus_wallet/bridge/frb_generated.dart';
import 'package:argus_wallet/services/pending_balance.dart';
import 'package:argus_wallet/services/privacy_service.dart';
import 'package:argus_wallet/services/public_wallet_sync.dart';
import 'package:argus_wallet/services/wallet_database_service.dart';
import 'package:argus_wallet/services/wallet_service.dart';
import 'package:argus_wallet/ui/home/overview_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/home_finders.dart';
import 'support/home_harness.dart';

// What the mempool does to a balance shows wherever the balance does: on
// the overview's total and rows, and under the wallet page's balance. The line splits the figure above it, so
// its confirmed side is that figure less what is pending.

const erg = 1000000000;
const lockedZero = '9lockedWalletIndexZeroxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';

/// A node whose answers carry the mempool split `get_balance` and the sync
/// reads return.
class PendingApi extends HomeApi {
  /// Per address, for `get_balance`.
  final summaries = <String, PendingBalance>{};

  /// For the unlocked wallet's sync read.
  PendingBalance? walletSummary;

  @override
  Future<String> crateApiGetBalance({
    required String address,
    String? nodeUrl,
  }) async {
    final raw =
        jsonDecode(
              await super.crateApiGetBalance(address: address, nodeUrl: nodeUrl),
            )
            as Map<String, dynamic>;
    final split = summaries[address];
    return jsonEncode({...raw, 'summary': ?split?.toJson()});
  }

  @override
  Future<String> crateApiGetSyncInputs({
    required List<String> addresses,
    String? nodeUrl,
  }) async {
    final raw =
        jsonDecode(
              await super.crateApiGetSyncInputs(
                addresses: addresses,
                nodeUrl: nodeUrl,
              ),
            )
            as Map<String, dynamic>;
    return jsonEncode({...raw, 'summary': ?walletSummary?.toJson()});
  }
}

void main() {
  final api = PendingApi();
  setUpAll(() => RustLib.initMock(api: api));
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await privacyService.load();
    // Snapshot figures stay as saved: no public refresh in these tests.
    publicWalletSync.setForeground(false);
    api.balances.clear();
    api.summaries.clear();
    api.walletSummary = null;
  });
  tearDown(() async {
    publicWalletSync.setForeground(true);
    if (walletService.isUnlocked) await walletService.lock();
  });

  test('rows and the total split what is pending against their figures', () {
    final live = WalletInfo(
      walletId: 'live',
      name: 'Live',
      createdAt: DateTime(2026),
      address0: 'z',
    );
    final locked = WalletInfo(
      walletId: 'locked',
      name: 'Locked',
      createdAt: DateTime(2026),
      address0: 'y',
    );
    final rows = buildOverviewEntries(
      wallets: [live, locked],
      lastKnown: {
        'locked': LastKnownBalance(
          balanceNano: 5 * erg,
          age: const Duration(minutes: 3),
        ),
      },
      lastPending: {
        'locked': const PendingBalance(
          confirmedNano: 4 * erg,
          pendingInNano: erg,
          transactions: 1,
        ),
      },
      unlockedWalletId: 'live',
      // 10 ERG, 2.5 of it arriving.
      active: const ActiveWalletFigures(
        walletId: 'live',
        balanceNano: 10 * erg,
        syncing: false,
        tokens: [],
        holdings: [],
        pending: PendingBalance(
          confirmedNano: 7500000000,
          pendingInNano: 2500000000,
          transactions: 1,
        ),
      ),
    );
    final byId = {for (final r in rows) r.ref.id: r};

    // The unlocked wallet's headline: 10 ERG, 2.5 of it pending.
    final active = byId['live']!;
    expect(active.balanceNano, 10 * erg);
    expect(active.pending!.pendingDeltaNano, 2500000000);
    expect(active.pending!.confirmedNano, 7500000000);
    expect(active.pending!.netNano, active.balanceNano);
    expect(
      pendingBalanceText(active.pending),
      '+2.5 ERG pending · 7.5 confirmed',
    );

    // A locked wallet's split is read back from its snapshot and shown
    // against the figure saved with it.
    final lockedRow = byId['locked']!;
    expect(lockedRow.balanceNano, 5 * erg);
    expect(lockedRow.pending!.confirmedNano, 4 * erg);
    expect(lockedRow.pending!.netNano, 5 * erg);

    // The total: every row's movement, against the sum of the rows.
    final totals = overviewTotals(rows);
    expect(totals.total.totalNano, (10 + 5) * erg);
    expect(totals.pending!.pendingDeltaNano, 2500000000 + erg);
    expect(totals.pending!.netNano, totals.total.totalNano);
    expect(totals.pending!.transactions, 2);
  });

  test('a total with no split anywhere has no pending line', () {
    final rows = buildOverviewEntries(
      wallets: [
        WalletInfo(
          walletId: 'old',
          name: 'Old',
          createdAt: DateTime(2026),
          address0: 'x',
        ),
      ],
      lastKnown: {
        'old': const LastKnownBalance(balanceNano: erg, age: Duration.zero),
      },
      unlockedWalletId: null,
    );
    expect(rows.single.pending, isNull);
    expect(overviewTotals(rows).pending, isNull);
  });

  testWidgets(
    'the overview shows pending on a locked row and the total',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      FakeKeystore(wallets: ['pend-locked']).install(tester);
      await tester.runAsync(() async {
        await saveWallet('pend-locked', name: 'Savings', address0: lockedZero);
        await WalletDatabaseService.savePublicSnapshot('pend-locked', {
          'wallet_id': 'pend-locked',
          'primary_address': lockedZero,
          'balance_nano_erg': 4 * erg,
          'pending': const PendingBalance(
            confirmedNano: 5 * erg,
            pendingOutNano: erg,
            transactions: 1,
          ).toJson(),
          'tokens': [],
          'public_only': true,
          'last_sync_timestamp': DateTime.now().millisecondsSinceEpoch,
        }, () => true);
      });
      await pumpHome(tester);

      final locked = find.byKey(const ValueKey('overview-row-seed-pend-locked'));
      expect(
        find.descendant(
          of: locked,
          matching: textPlain('−1 ERG pending · 5 confirmed'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('overview-total-pending')),
          matching: textPlain('−1 ERG pending · 5 confirmed'),
        ),
        findsOneWidget,
      );

      // Hidden balances say something is pending, not how much.
      await tester.runAsync(() => privacyService.setHideBalances(true));
      addTearDown(() => privacyService.setHideBalances(false));
      await tester.pumpAndSettle();
      expect(textPlain('•••• ERG pending'), findsNWidgets(2));
      expect(textPlainContaining('confirmed'), findsNothing);
      await disposeHome(tester);
    },
  );

  testWidgets('an unlocked wallet page shows pending under its balance', (
    tester,
  ) async {
    final keystore = FakeKeystore(wallets: ['pend-live'])
      ..biometricResult = 'wrap-key';
    keystore.install(tester);
    await tester.runAsync(
      () => saveWallet('pend-live', name: 'Daily', address0: 'addr0'),
    );
    api.balances['addr0'] = {'balance_nano_erg': 10 * erg, 'tokens': []};
    api.walletSummary = const PendingBalance(
      confirmedNano: 12 * erg,
      pendingOutNano: 2 * erg,
      transactions: 1,
    );
    await pumpHome(tester);
    await tester.tap(find.byKey(const ValueKey('overview-row-seed-pend-live')));
    await tester.pumpAndSettle();
    expect(walletService.isUnlocked, isTrue);
    expect(plainOf(tester, find.byKey(const Key('wallet-balance'))), '10 ERG');
    expect(
      find.descendant(
        of: find.byKey(const Key('wallet-balance-pending')),
        matching: textPlain('−2 ERG pending · 12 confirmed'),
      ),
      findsOneWidget,
    );
    await disposeHome(tester);
  });
}
