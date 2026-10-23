import 'widgets/error_sheet.dart';
import 'package:flutter/material.dart';

import '../bridge/argus_error.dart';
import '../l10n/l10n.dart';
import '../services/privacy_service.dart';
import '../services/secure_storage.dart';
import '../services/wallet_service.dart';
import '../theme/argus_theme.dart';
import 'create_wallet_screen.dart';
import 'pin_fields.dart';
import 'wallet_dialogs.dart';

class RestoreWalletScreen extends StatefulWidget {
  const RestoreWalletScreen({super.key});

  @override
  State<RestoreWalletScreen> createState() => _RestoreWalletScreenState();
}

class _RestoreWalletScreenState extends State<RestoreWalletScreen> {
  final _phraseCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _pinConfirmCtrl = TextEditingController();
  bool _busy = false;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    armSecureFlag(context);
  }

  @override
  void dispose() {
    privacyService.applyScreenshotPolicy();
    _phraseCtrl.clear();
    _passCtrl.clear();
    _pinCtrl.clear();
    _pinConfirmCtrl.clear();
    _phraseCtrl.dispose();
    _passCtrl.dispose();
    _pinCtrl.dispose();
    _pinConfirmCtrl.dispose();
    super.dispose();
  }

  void _toPin() {
    final words = mnemonicWords(_phraseCtrl.text);
    if (words.isEmpty) {
      _snack(context.l10n.restoreEnterPhrase);
      return;
    }
    if (!isValidMnemonicWordCount(words.length)) {
      _snack(context.l10n.restoreWordCount);
      return;
    }
    setState(() => _step = 1);
  }

  Future<String?> _restore() async {
    final words = mnemonicWords(_phraseCtrl.text);
    final phrase = words.join(' ');
    if (phrase.isEmpty) {
      _snack(context.l10n.restoreEnterPhrase);
      return null;
    }
    final pinErr = pinError(_pinCtrl.text, _pinConfirmCtrl.text);
    if (pinErr != null) {
      _snack(pinErr);
      return null;
    }
    setState(() => _busy = true);
    try {
      final walletId = await walletService.provisionWallet(
        phrase: phrase,
        passphrase: _passCtrl.text,
        pin: _pinCtrl.text,
        // One wallet: the app shows no name, and the core keeps its default.
        name: '',
      );
      if (!mounted) return null;
      await offerBiometricUnlock(context, walletId: walletId, pin: _pinCtrl.text);
      if (!mounted) return null;
      Navigator.pop(context, walletId);
    } on ArgusException catch (e) {
      showErrorSheet(context, code: e.code, message: e.message);
    } on SecureStorageException catch (e) {
      showErrorSheet(context, message: e.message);
    } catch (e) {
      showErrorSheet(context, title: context.l10n.restoreFailedTitle, message: '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    return null;
  }

  void _snack(String msg) {
    if (mounted) showErrorSheet(context, message: msg);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_step > 0) setState(() => _step -= 1);
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.restoreTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_step > 0) {
              setState(() => _step -= 1);
            } else {
              Navigator.pop(context);
            }
          },
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
                20, 8, 20, 32 + MediaQuery.paddingOf(context).bottom),
        children: [
          StepDots(total: 2, index: _step),
          const SizedBox(height: 24),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _step == 0 ? _phraseStep() : _pinStep(),
          ),
        ],
      ),
    ),
    );
  }

  Widget _phraseStep() {
    return Column(
      key: const ValueKey(0),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.l10n.createPhraseLabel, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
            context.l10n.restoreIntro),
        const SizedBox(height: 20),
        TextField(
          controller: _phraseCtrl,
          decoration: InputDecoration(
            labelText: context.l10n.createPhraseLabel,
            hintText: context.l10n.restorePhraseHint,
          ),
          minLines: 4,
          maxLines: 6,
          enableSuggestions: false,
          autocorrect: false,
          enableIMEPersonalizedLearning: false,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passCtrl,
          decoration: InputDecoration(
            labelText: context.l10n.restorePassphraseLabel,
          ),
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          enableIMEPersonalizedLearning: false,
        ),
        const SizedBox(height: 20),
        FilledButton(onPressed: _toPin, child: Text(context.l10n.createContinue)),
      ],
    );
  }

  Widget _pinStep() {
    return Column(
      key: const ValueKey(1),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.l10n.createSetPin, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(context.l10n.createPinBody),
        const SizedBox(height: 20),
        PinFields(pin: _pinCtrl, confirm: _pinConfirmCtrl),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _restore,
          child: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.l10n.restoreButton),
        ),
      ],
    );
  }
}
