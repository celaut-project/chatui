import 'package:argus_wallet/bridge/frb_generated.dart';
import 'package:argus_wallet/theme/argus_theme.dart';
import 'package:argus_wallet/ui/create_wallet_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MnemonicApi extends RustLibApi {
  @override
  Future<String> crateApiGenerateMnemonic({required int strength}) async =>
      List.filled(15, 'abandon').join(' ');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => RustLib.initMock(api: _MnemonicApi()));

  Future<void> toConfirmStep(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: argusTheme(watchful: true),
      home: const CreateWalletScreen(),
    ));
    await tester.tap(find.text('Generate recovery phrase'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I wrote these down'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm the phrase'), findsOneWidget);
  }

  testWidgets('skipping the check after the warning creates the wallet', (tester) async {
    await toConfirmStep(tester);
    await tester.tap(find.byKey(const Key('create-skip-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Skip the check?'), findsOneWidget);

    // There is no PIN step any more: the wallet is made at once (the phone unlock guards it).
    await tester.tap(find.widgetWithText(FilledButton, 'Skip'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Skip the check?'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('cancelling the warning stays on the check', (tester) async {
    await toConfirmStep(tester);
    await tester.tap(find.byKey(const Key('create-skip-confirm')));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm the phrase'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
