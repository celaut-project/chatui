import 'package:argus_wallet/services/wallet_service.dart';
import 'package:argus_wallet/ui/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('com.argus.wallet/secure_storage');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  void listWallets(WidgetTester tester, List<String> ids) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _channel,
      (call) async => call.method == 'listWalletIds' ? ids : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null),
    );
  }

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: home));
    await tester.pumpAndSettle();
  }

  testWidgets('without a wallet the hub is app-wide only', (tester) async {
    listWallets(tester, const []);
    await pump(tester, const SettingsScreen());
    for (final text in ['Security', 'Network', 'Display', 'Address book', 'About Celaut']) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    // The wallet is created and restored on the overview; there is no
    // wallet list here, no offline signing and no default payer.
    for (final text in ['Manage', 'Watch-only', 'THIS WALLET', 'No wallet selected', 'Offline signing']) {
      expect(find.text(text), findsNothing, reason: text);
    }
  });

  testWidgets("a seed wallet's hub leads to its own settings", (tester) async {
    listWallets(tester, const ['hub-wallet']);
    await tester.runAsync(
      () => walletService.saveWalletInfo('hub-wallet', name: 'Savings', createdAt: DateTime(2026)),
    );
    await pump(tester, const SettingsScreen(walletId: 'hub-wallet'));
    expect(find.text('THIS WALLET'), findsOneWidget);
    expect(find.text('Name, addresses and backup'), findsOneWidget);
    expect(find.text('Security'), findsOneWidget);
    expect(find.text('Savings'), findsWidgets);
    // One wallet: no way to all wallets, no count of wallets.
    expect(find.text('All wallets'), findsNothing);
    expect(find.textContaining('on this device'), findsNothing);
  });
}
