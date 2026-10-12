import '../widgets/error_sheet.dart';
import 'package:flutter/material.dart';

import '../../bridge/argus_error.dart';
import '../../l10n/l10n.dart';
import '../../services/privacy_service.dart';
import '../../services/secure_storage.dart';
import '../../services/session_lock.dart';
import '../../services/spend_policy.dart';
import '../../services/wallet_service.dart';
import 'settings_shared.dart';
import '../widgets/entry_dialogs.dart';

/// Auto-lock (app-wide) plus this wallet's PIN and biometric unlock.
class SecuritySettingsPage extends StatefulWidget {
  const SecuritySettingsPage({super.key, this.walletId});
  final String? walletId;

  @override
  State<SecuritySettingsPage> createState() => _SecuritySettingsPageState();
}

class _SecuritySettingsPageState extends State<SecuritySettingsPage> {
  bool _canBiometric = false;
  bool _hasPin = false;
  bool _loadFailed = false;
  bool _busy = false;
  int _graceKey = 0;

  String? get _walletId => widget.walletId ?? walletService.activeWalletId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final hasPin = await SecureStorageService.hasPinWrap(walletId: _walletId);
      final bio = hasPin &&
          await SecureStorageService.hasBiometric() &&
          await SecureStorageService.hasWrapKey(walletId: _walletId);
      if (!mounted) return;
      setState(() {
        _hasPin = hasPin;
        _canBiometric = bio;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadFailed = true);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _disableBiometric() async {
    final t = context.l10n;
    setState(() => _busy = true);
    try {
      await SecureStorageService.deleteWrapKey(walletId: _walletId);
      await _load();
      _snack(t.securityBiometricDisabled);
    } catch (_) {
      _snack(t.securityBiometricDisableFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enableBiometric() async {
    final t = context.l10n;
    final entry = await showDialog<PinEntry>(
      context: context,
      builder: (_) => PinEntryDialog(title: t.pinConfirm),
    );
    if (entry == null) return;
    final entered = entry.pin;
    final pinErr = validatePin(entered);
    if (pinErr != null) {
      _snack(pinErr);
      return;
    }
    try {
      final blocked = await SecureStorageService.pinBlockedMessage();
      if (blocked != null) {
        _snack(blocked);
        return;
      }
    } on SecureStorageException {
      _snack(t.securityPinLockoutCheckFailed);
      return;
    }
    setState(() => _busy = true);
    try {
      final saved = await sessionLock.run(() async {
        final pinWrap = await SecureStorageService.loadPinWrap(walletId: _walletId);
        if (pinWrap == null) return false;
        final wrapKey = await walletService.unwrapKeyWithPin(pinWrap, entered);
        await SecureStorageService.saveWrapKey(wrapKey, walletId: _walletId);
        await SecureStorageService.clearPinGate();
        return true;
      });
      if (!mounted) return;
      if (!saved) {
        _snack(t.securityNoPinWalletFound);
        return;
      }
      setState(() => _canBiometric = true);
      _snack(t.securityBiometricEnabled);
    } on ArgusException catch (e) {
      if (isIncorrectPin(e)) {
        try {
          await SecureStorageService.recordPinFailure();
        } catch (_) {}
        _snack(t.pinIncorrect);
      } else {
        _snack(t.securityBiometricEnableFailed);
      }
    } catch (_) {
      _snack(t.securityBiometricEnableFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePin() async {
    final t = context.l10n;
    final entry = await showDialog<PinEntry>(
      context: context,
      builder: (_) => PinEntryDialog(
        title: t.securityChangePin,
        askCurrent: true,
        pinLabel: t.securityNewPin,
        askConfirm: true,
        confirmLabel: t.securityChange,
      ),
    );
    if (entry == null) return;
    final old = entry.current;
    final next = entry.pin;
    final confirm = entry.confirm;
    final pinErr = validatePin(next);
    if (pinErr != null) {
      _snack(pinErr);
      return;
    }
    if (next != confirm) {
      _snack(t.pinMismatch);
      return;
    }
    setState(() => _busy = true);
    try {
      var changed = false;
      await sessionLock.run(() async {
        final pinWrap = await SecureStorageService.loadPinWrap(walletId: _walletId);
        if (pinWrap == null) {
          _snack(t.securityNoPinWallet);
          return;
        }
        final blocked = await SecureStorageService.pinBlockedMessage();
        if (blocked != null) {
          _snack(blocked);
          return;
        }
        final wrapKey = await walletService.unwrapKeyWithPin(pinWrap, old);
        final newPinWrap = await walletService.wrapKeyWithPin(wrapKey, next);
        await SecureStorageService.savePinWrap(newPinWrap, walletId: _walletId);
        changed = true;
      });
      if (changed) {
        _snack(t.securityPinChanged);
        try {
          await SecureStorageService.clearPinGate();
        } catch (_) {
          _snack(t.securityPinChangedLockoutNotReset);
        }
      }
    } on ArgusException catch (e) {
      if (isIncorrectPin(e)) {
        try {
          await SecureStorageService.recordPinFailure();
        } catch (_) {}
        _snack(t.pinIncorrect);
      } else {
        showErrorSheet(context, code: e.code, message: e.message);
      }
    } catch (_) {
      _snack(t.securityChangePinFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<(int, String)> get _graceOptions {
    final t = context.l10n;
    return [
      (0, t.securityLockImmediately),
      (2, t.securityLockAfterSeconds(2)),
      (30, t.securityLockAfterSeconds(30)),
      (60, t.securityLockAfterMinutes(1)),
      (300, t.securityLockAfterMinutes(5)),
    ];
  }

  Future<void> _pickGrace() async {
    final t = context.l10n;
    final current = sessionLock.grace.inSeconds;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(t.securityLockWhenBackgrounded),
        children: [
          for (final (secs, label) in _graceOptions)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, secs),
              child: Row(
                children: [
                  Expanded(child: Text(label)),
                  if (secs == current) const Icon(Icons.check, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null || picked == current) return;
    try {
      await sessionLock.setGrace(Duration(seconds: picked));
    } catch (_) {
      _snack(t.securityAutoLockUpdateFailed);
    }
    if (mounted) setState(() => _graceKey++);
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = walletService.isUnlocked;
    final t = context.l10n;
    final graceLabel = _graceOptions
        .firstWhere((o) => o.$1 == sessionLock.grace.inSeconds, orElse: () => (0, '${sessionLock.grace.inSeconds}s'))
        .$2;
    return SettingsPage(
      title: t.securityTitle,
      children: [
        SettingsGroup(
          title: t.securityAutoLock,
          scope: t.settingsScopeAppWide,
          children: [
            SettingsRow(
              key: ValueKey(_graceKey),
              icon: Icons.timer_outlined,
              title: t.securityLockWhenBackgrounded,
              subtitle: graceLabel,
              onTap: _pickGrace,
            ),
          ],
        ),
        SettingsGroup(
          title: t.securityUnlockGroup,
          scope: t.commonThisWallet,
          children: [
            if (!unlocked)
              SettingsRow(
                icon: Icons.lock_outline,
                title: t.securityUnlockFirst,
                subtitle: t.securityUnlockFirstSubtitle,
              )
            else if (_loadFailed)
              SettingsRow(
                icon: Icons.refresh,
                title: t.securityRetryUnlockSettings,
                subtitle: t.securityReadSetupFailed,
                onTap: _busy ? null : _load,
              )
            else ...[
              SettingsRow(
                icon: Icons.fingerprint,
                title: t.securityBiometricUnlock,
                subtitle: _canBiometric
                    ? t.securityBiometricOn
                    : (_hasPin ? t.securityOff : t.securitySetPinHint),
                trailing: _hasPin
                    ? Switch(
                        value: _canBiometric,
                        onChanged: _busy ? null : (v) => v ? _enableBiometric() : _disableBiometric(),
                      )
                    : null,
              ),
              if (_hasPin)
                SettingsRow(
                  icon: Icons.lock_reset,
                  title: t.securityChangePin,
                  onTap: _busy ? null : _changePin,
                ),
            ],
          ],
        ),
        SettingsNote(t.securityPinNote),
        ListenableBuilder(
          listenable: privacyService,
          builder: (context, _) => SettingsGroup(
            title: t.securityScreen,
            scope: t.settingsScopeAppWide,
            children: [
              SettingsRow(
                icon: Icons.screenshot_monitor_outlined,
                title: t.securityBlockScreenshots,
                subtitle: privacyService.blockScreenshots
                    ? t.securityScreenshotsBlocked
                    : t.securityScreenshotsAllowed,
                trailing: Switch(
                  value: privacyService.blockScreenshots,
                  onChanged: (v) => privacyService.setBlockScreenshots(v),
                ),
              ),
            ],
          ),
        ),
        SettingsNote(t.securitySeedScreensNote),
        ListenableBuilder(
          listenable: spendPolicy,
          builder: (context, _) => SettingsGroup(
            title: t.securitySpending,
            scope: t.settingsScopeAppWide,
            children: [
              SettingsRow(
                icon: Icons.hourglass_bottom_rounded,
                title: t.securitySpendUnconfirmed,
                subtitle: spendPolicy.spendUnconfirmed
                    ? t.securitySpendUnconfirmedOn
                    : t.securitySpendUnconfirmedOff,
                trailing: Switch(
                  key: const Key('spend-unconfirmed-switch'),
                  value: spendPolicy.spendUnconfirmed,
                  onChanged: (v) async {
                    try {
                      await spendPolicy.setSpendUnconfirmed(v);
                    } catch (_) {
                      _snack(t.securitySpendingSaveFailed);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        SettingsNote(spendUnconfirmedNote),
      ],
    );
  }
}
