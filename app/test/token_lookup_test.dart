import 'dart:async';
import 'dart:convert';

import 'package:argus_wallet/bridge/frb_generated.dart';
import 'package:argus_wallet/services/network_controller.dart';
import 'package:argus_wallet/services/token_metadata.dart';
import 'package:argus_wallet/services/wallet_service.dart';
import 'package:argus_wallet/services/wallet_sync_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'wallet_sync_controller_test.dart' show FakeGateway;

const _node = 'https://node.example';
String _id(String seed) => seed * (64 ~/ seed.length);

/// A held token, and a token the wallet's table knows.
final _held = _id('ab');
final _deep = _id('d1');

class LookupApi extends RustLibApi {
  final List<({String id, String provider, bool node})> asked = [];

  /// The request numbered [gateOnCall] (1-based) waits for this.
  Completer<void>? gate;
  int gateOnCall = 1;

  /// The native side runs one metadata job at a time; a second request
  /// while one is in flight fails as "already running". Tracked so a test
  /// can assert the app never asks for two at once.
  int inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<BigInt> crateApiWalletRestore({
    required String encryptedSeedJson,
    String? wrapKey,
  }) async => BigInt.one;

  @override
  Future<void> crateApiWalletLock({required BigInt handleId}) async {}

  int cancels = 0;

  @override
  void crateApiCancelTokenMetadata() => cancels++;

  @override
  Future<String> crateApiInspectTokenMetadata({
    required String tokenId,
    required String providerUrl,
    required bool providerIsNode,
  }) async {
    asked.add((id: tokenId, provider: providerUrl, node: providerIsNode));
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      final waiting = asked.length == gateOnCall ? gate : null;
      if (waiting != null) {
        gate = null;
        await waiting.future;
      }
    } finally {
      inFlight--;
    }
    return jsonEncode({
      'id': tokenId,
      'name': 'Name ${tokenId.substring(0, 2)}',
      'decimals': 2,
      'decimalsEvidence': 'valid',
      'supplyEvidence': 'originalEmission',
      'emissionAmount': 1000,
      'declaredAssetKind': 'none',
      'metadataState': 'complete',
      'mediaState': 'unknown',
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 1000 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: 'condition never became true');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = LookupApi();
  setUpAll(() {
    RustLib.initMock(api: api);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.argus.wallet/secure_storage'),
          (call) async => null,
        );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api.asked.clear();
    api.gate = null;
    api.gateOnCall = 1;
    api.inFlight = 0;
    api.maxInFlight = 0;
    networkController.activeUrl = _node;
  });

  tearDown(() async {
    networkController.activeUrl = null;
    // A test that backgrounds the app must not leave the next one there.
    TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
    if (walletService.isUnlocked) await walletService.lock();
  });

  Future<void> resolveForWallet(WalletService svc, String walletId) =>
      svc.prefetchTokenMeta(
        [_held],
        walletId: walletId,
        servedBy: _node,
        stillCurrent: () => true,
      );

  test('one lookup, best layer first', () async {
    const sigUsd = '03faf2cb329f2e90d6d23b58d91bbb6c046aa143261cc21f52fbe2824bfcbf04';
    final legacyOnly = _id('1e');
    SharedPreferences.setMockInitialValues({
      'argus_token_meta_v2': jsonEncode({
        sigUsd: {'name': 'Old SigUSD', 'decimals': 0},
        legacyOnly: {'name': 'Legacy', 'decimals': 1},
      }),
    });
    final svc = WalletService();
    await svc.loadTokenMeta();
    await svc.restoreWallet('mock', walletId: 'layers');
    await resolveForWallet(svc, 'layers');

    expect(svc.cachedTokenMeta(_held)?.name, 'Name ab',
        reason: "the wallet's own descriptor comes first");
    expect(svc.cachedTokenMeta(sigUsd)?.name, 'SigUSD',
        reason: 'the curated registry outranks a table with no provenance');
    expect(svc.cachedTokenMeta(sigUsd)?.decimals, 2);
    expect(svc.cachedTokenMeta(legacyOnly)?.name, 'Legacy');
    expect(svc.cachedTokenMeta(_id('99')), isNull);
    await svc.lock('layers');
  });

  test('the first balance after an unlock already carries learned names',
      () async {
    final first = WalletService();
    await first.restoreWallet('mock', walletId: 'relaunch');
    await resolveForWallet(first, 'relaunch');
    await first.lock('relaunch');
    api.asked.clear();

    // A relaunch: nothing in memory, and no name pass has run.
    final second = WalletService();
    await second.restoreWallet('mock', walletId: 'relaunch');
    final holdings = await second.hydrateTokens([
      {'id': _held, 'amount': 500},
    ]);
    expect(holdings.single.name, 'Name ab',
        reason: 'names must not wait for a sync to come back');
    expect(holdings.single.decimals, 2);
    expect(holdings.single.amount, 500);
    expect(api.asked, isEmpty, reason: 'and cost no request');
    await second.lock('relaunch');
  });

  test('the first refresh after an unlock publishes names, not ids', () async {
    // beta.1: the table loaded inside the name pass, which waits for the
    // history leg; the first balance republished every holding as an id.
    final first = WalletService();
    await first.restoreWallet('mock', walletId: 'w1');
    await resolveForWallet(first, 'w1');
    await first.lock('w1');

    final second = WalletService();
    await second.restoreWallet('mock', walletId: 'w1');
    final gateway = _RealHydration(second)
      ..balances = {
        'addr0': {
          'balance_nano_erg': 1000,
          'tokens': [
            {'id': _held, 'amount': 500},
          ],
        },
      }
      // The slow leg, held open: no name pass can have run.
      ..historyGate = Completer<void>();
    final controller = WalletSyncController(gateway);
    addTearDown(controller.dispose);
    await controller.hydrateAfterUnlock();
    final refresh = controller.refresh(discover: false);
    await _until(() => controller.tokens.isNotEmpty);

    expect(controller.tokens.single.name, 'Name ab');
    expect(controller.tokens.single.decimals, 2);
    expect(gateway.resolved, isEmpty, reason: 'before any name pass');

    gateway.historyGate!.complete();
    await refresh;
    await second.lock('w1');
  });

  test('a holding published without a record is filled from the lookup',
      () async {
    walletService.rememberTokenMeta(TokenBalance(id: _deep, amount: 0, name: 'Pooled', decimals: 4, decimalsEvidence: DecimalsEvidence.valid));
    final shown = walletService.displayMetadata(
      TokenBalance(id: _deep, amount: 12345),
    );
    expect(shown.name, 'Pooled');
    expect(shown.decimals, 4);
    expect(shown.amount, 12345);

    // Restored from a snapshot: a name, but none of the evidence behind it.
    final restored = TokenBalance(id: _deep, amount: 1, name: 'Snapshot');
    expect(walletService.displayMetadata(restored).name, 'Pooled',
        reason: 'what is known now is the one source');

    final unknown = TokenBalance(id: _id('77'), amount: 1, name: 'Published');
    expect(walletService.displayMetadata(unknown).name, 'Published',
        reason: 'with nothing known, a holding keeps its published name');
  });

  test('a name only an explicit load supplied is never stored', () async {
    await walletService.restoreWallet('mock', walletId: 'stored');
    final loaded = await walletService.loadMetadata(
      TokenBalance(id: _held, amount: 1),
      provider: _node,
      providerIsNode: true,
    );
    expect(loaded.name, 'Name ab');
    expect(tokenLabel(_held), 'Name ab', reason: 'shown for this session');
    expect(storedTokenLabel(_held), 'abababab…',
        reason: 'memory-only by design, so never written into a record');
  });

  group('display helpers', () {
    test('an amount nothing can scale is said to be raw units', () {
      expect(
        tokenAmountText(BigInt.from(349670571986), _id('6d')),
        '349,670,571,986 raw units of 6d6d6d6d…',
      );
      expect(tokenDecimals(_id('6d')), isNull);
    });

    test('a known scale is applied', () {
      walletService.rememberTokenMeta(TokenBalance(id: _deep, amount: 0, name: 'Pooled', decimals: 4, decimalsEvidence: DecimalsEvidence.valid));
      expect(tokenAmountText(BigInt.from(12345678), _deep), '1,234.5678 Pooled');
      expect(tokenDecimals(_deep), 4);
    });

    test('a token issued with no decimals has a known zero', () {
      walletService.rememberTokenMeta(TokenBalance(id: _deep, amount: 0, name: 'Whole', decimalsEvidence: DecimalsEvidence.valid));
      expect(tokenAmountText(BigInt.from(69), _deep), '69 Whole');
    });

    test('a malformed decimals declaration is not trusted', () {
      walletService.rememberTokenMeta(TokenBalance(id: _deep, amount: 0, name: 'Odd', decimalsEvidence: DecimalsEvidence.invalid));
      expect(tokenAmountText(BigInt.from(69), _deep), '69 raw units of Odd');
    });

    test('a holding keeps its published name once caches are cleared', () {
      final held = TokenBalance(
        id: _id('77'),
        amount: 150,
        name: 'Kept',
        decimals: 2,
      );
      expect(tokenAmountText(BigInt.from(150), held.id, held: held), '1.5 Kept');
    });

    test('issuer text is sanitised before it is shown', () {
      walletService.rememberTokenMeta(TokenBalance(id: _deep, amount: 0, name: 'Ev\u202eil\u0001', decimals: 0, decimalsEvidence: DecimalsEvidence.valid));
      expect(tokenLabel(_deep), 'Evil');
    });

    test('exact at any size', () {
      expect(
        formatUnits(BigInt.parse('123456789012345678901234567890'), 9),
        '123,456,789,012,345,678,901.23456789',
      );
    });
  });
}

/// The controller over the real service's hydration, so the test exercises
/// the same table load a relaunch does.
class _RealHydration extends FakeGateway {
  _RealHydration(this.service);
  final WalletService service;

  @override
  Future<List<TokenBalance>> hydrateTokens(dynamic raw) =>
      service.hydrateTokens(raw);
}
