import 'package:flutter/material.dart';

import '../../format.dart';
import '../../l10n/l10n.dart';
import '../../services/privacy_service.dart';
import '../../services/wallet_service.dart';
import '../../theme/argus_theme.dart';
import 'settings_shared.dart';
import '../widgets/entry_dialogs.dart';

/// Settings of the wallet: its primary address, change policy, backup, and removing it
/// from this device. The app holds one wallet, so it has no name to show or change.
class WalletSettingsPage extends StatefulWidget {
  const WalletSettingsPage({
    super.key,
    this.walletId,
    this.onChanged,
    this.onRemoved,
  });
  final String? walletId;

  /// The pinned address changed.
  final VoidCallback? onChanged;

  /// The wallet was removed from this device; carries its id. Called even
  /// when this page is already gone: removing the unlocked wallet locks it,
  /// and the lock pops every route above the home screen.
  final ValueChanged<String>? onRemoved;

  @override
  State<WalletSettingsPage> createState() => _WalletSettingsPageState();
}

class _WalletSettingsPageState extends State<WalletSettingsPage> {
  late Future<int> _pinnedIndexFuture;

  String? get _walletId => widget.walletId ?? walletService.activeWalletId;

  @override
  void initState() {
    super.initState();
    _pinnedIndexFuture = walletService.getPinnedAddressIndex(walletId: _walletId);
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _pinnedIndexFuture = walletService.getPinnedAddressIndex(walletId: _walletId);
    });
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _remove() async {
    final id = _walletId;
    if (id == null) return;
    final t = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.walletSettingsRemoveTitle),
        content: Text(t.walletSettingsRemoveBody),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rust, foregroundColor: bone),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.commonRemove),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final onRemoved = widget.onRemoved;
    try {
      await walletService.deleteWallet(id);
    } catch (_) {
      _snack(t.walletSettingsRemoveFailed);
      return;
    }
    onRemoved?.call(id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pinAddressIndex() async {
    final t = context.l10n;
    final entered = await showDialog<String>(
      context: context,
      builder: (_) => TextEntryDialog(
        title: t.walletSettingsPinIndexTitle,
        intro: Text(t.walletSettingsPinIndexIntro),
        introGap: 12,
        label: t.walletSettingsIndexLabel,
        hint: '0',
        helper: '0–${WalletService.maxAddressIndex}',
        keyboardType: TextInputType.number,
        confirmLabel: t.walletSettingsPin,
      ),
    );
    if (entered == null) return;
    final text = entered.trim();
    final index = int.tryParse(text);
    if (index == null || index < 0) {
      _snack(t.walletSettingsInvalidIndex);
      return;
    }
    if (index > WalletService.maxAddressIndex) {
      _snack(t.walletSettingsIndexTooHigh('${WalletService.maxAddressIndex}'));
      return;
    }
    final wid = _walletId;
    if (wid == null) return;
    final addr = await walletService.tryDeriveAddress(index);
    if (!mounted) return;
    if (addr == null) {
      _snack(t.walletSettingsCannotDerive('$index'));
      return;
    }
    await walletService.setPinnedAddressIndex(wid, index, address: addr);
    _refresh();
    widget.onChanged?.call();
    _snack(t.walletSettingsPinnedIndex('$index', shorten(addr, head: 10, tail: 8)));
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = walletService.isUnlocked;
    final t = context.l10n;
    return ListenableBuilder(
      listenable: privacyService,
      builder: (context, _) => SettingsPage(
        title: t.commonWallet,
        children: [
          SettingsGroup(
            title: t.commonAddresses,
            scope: t.commonThisWallet,
            children: [
              FutureBuilder<int>(
                future: _pinnedIndexFuture,
                builder: (context, snapshot) {
                  final pinned = snapshot.data ?? 0;
                  final isPinned = pinned != 0;
                  final outOfRange = pinned > WalletService.maxAddressIndex;
                  return SettingsRow(
                    icon: Icons.push_pin_outlined,
                    danger: outOfRange,
                    title: outOfRange
                        ? t.walletSettingsPinnedOutOfRange('$pinned')
                        : (isPinned ? t.walletSettingsPrimaryPinned('$pinned') : t.walletSettingsPrimaryDefault),
                    subtitle: outOfRange
                        ? t.walletSettingsOutOfRangeHint('${WalletService.maxAddressIndex}')
                        : t.walletSettingsPrimaryHint,
                    trailing: isPinned
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            tooltip: t.walletSettingsUnpin,
                            onPressed: () async {
                              final wid = _walletId;
                              if (wid == null) return;
                              await walletService.setPinnedAddressIndex(wid, 0);
                              _refresh();
                              widget.onChanged?.call();
                            },
                          )
                        : null,
                    onTap: unlocked ? _pinAddressIndex : null,
                  );
                },
              ),
              SettingsRow(
                icon: Icons.shuffle,
                title: t.walletSettingsFreshAddresses,
                subtitle: t.walletSettingsFreshAddressesSubtitle,
                trailing: Switch(
                  value: privacyService.useUnusedChangeAddress(_walletId),
                  onChanged: (v) async {
                    final wid = _walletId;
                    if (wid == null) {
                      _snack(t.walletSettingsUnlockToChange);
                      return;
                    }
                    try {
                      await privacyService.setUnusedChangeAddress(v, walletId: wid);
                    } catch (_) {
                      _snack(t.walletSettingsPrivacySaveFailed);
                    }
                  },
                ),
              ),
            ],
          ),
          SectionLabel(t.walletSettingsBackup),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              t.walletSettingsBackupNote,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 24),
          SettingsGroup(
            title: t.commonRemove,
            scope: t.commonThisWallet,
            children: [
              SettingsRow(
                icon: Icons.delete_outline,
                title: t.walletSettingsRemoveWallet,
                subtitle: t.walletSettingsRemoveWalletSubtitle,
                danger: true,
                onTap: _remove,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
