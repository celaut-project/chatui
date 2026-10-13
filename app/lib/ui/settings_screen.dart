import 'package:flutter/material.dart';
import 'cold_signing_screen.dart';

import '../celaut/celaut_strings.dart';
import '../celaut/deposit_strings.dart';
import '../celaut/service_strings.dart';
import '../format.dart';
import '../l10n/l10n.dart';
import '../services/address_label_service.dart';
import '../services/contacts_service.dart';
import '../services/network_controller.dart';
import '../services/wallet_service.dart';
import '../services/watch_account_service.dart';
import '../services/watch_only_service.dart';
import '../theme/argus_theme.dart';
import '../theme/theme_controller.dart';
import 'celaut/node_connect_screen.dart';
import 'celaut/deposit_screen.dart';
import 'celaut/service_screen.dart';
import 'home/overview_model.dart';
import 'home/watched_actions.dart';
import 'settings/about_page.dart';
import 'settings/address_book_page.dart';
import 'settings/display_settings_page.dart';
import 'settings/network_settings_page.dart';
import 'settings/preview_settings_page.dart';
import 'settings/security_settings_page.dart';
import 'settings/settings_shared.dart';
import 'settings/update_notice.dart';
import 'settings/wallet_settings_page.dart';
import 'widgets/soft_card.dart';

/// Settings hub: the open wallet on top, then short groups whose rows open
/// their own page. Per-wallet and app-wide scopes are labelled.
///
/// Wallets themselves — switching, creating, restoring, watching — live on
/// the overview. Renaming and removing a wallet live in its own settings.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.walletId,
    this.watched,
    this.embedded = false,
    this.onShowAllWallets,
    this.onWalletChanged,
    this.onWalletRemoved,
  });

  /// The seed wallet whose page hosts these settings.
  final String? walletId;

  /// The watched address or account whose page hosts these settings.
  final WalletRef? watched;

  /// Hosted as a wallet page's tab: no app bar of its own.
  final bool embedded;

  /// Back to the overview, from the header.
  final VoidCallback? onShowAllWallets;

  /// The wallet was renamed or its pinned address changed.
  final VoidCallback? onWalletChanged;

  /// The wallet was removed, or stopped being watched; carries its id.
  final ValueChanged<String>? onWalletRemoved;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<List<WalletInfo>> _walletsFuture = walletService.listWallets();

  /// Only a seed wallet's page has a seed wallet; the overview's settings
  /// and a watched wallet's page have none.
  String? get _walletId => widget.watched != null ? null : widget.walletId;

  Future<void> _open(Widget page) async {
    await Navigator.push(context, fadeRoute(page));
    if (mounted) setState(() => _walletsFuture = walletService.listWallets());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.embedded ? null : AppBar(title: Text(context.l10n.commonSettings)),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          themeController,
          networkController,
          walletService.unlocked,
          watchOnlyService,
          watchAccountService,
          addressLabelService,
          contactsService,
        ]),
        builder: (context, _) {
          return FutureBuilder<List<WalletInfo>>(
            future: _walletsFuture,
            builder: (context, snapshot) {
              final wallets = snapshot.data ?? const <WalletInfo>[];
              WalletInfo? current;
              for (final w in wallets) {
                if (w.walletId == _walletId) current = w;
              }
              final watched = widget.watched;
              return ListView(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
                children: [
                  const UpdateNotice(),
                  if (current != null) ...[
                    _walletHeader(context, current, wallets.length),
                    const SizedBox(height: 24),
                    _seedGroup(current),
                  ] else if (watched != null) ...[
                    _watchedHeader(context, watched),
                    const SizedBox(height: 24),
                    _watchedGroup(watched),
                  ],
                  _appGroup(includeSecurity: current == null),
                  SettingsGroup(
                    title: CelautStrings.developerGroup,
                    scope: CelautStrings.developerScope,
                    children: [
                      SettingsRow(
                        icon: Icons.dns_outlined,
                        title: CelautStrings.nodeRowTitle,
                        subtitle: CelautStrings.nodeRowSubtitle,
                        onTap: () => _open(const NodeConnectScreen()),
                      ),
                      SettingsRow(
                        icon: Icons.play_circle_outline,
                        title: ServiceStrings.rowTitle,
                        subtitle: ServiceStrings.rowSubtitle,
                        onTap: () => _open(const ServiceScreen()),
                      ),
                      SettingsRow(
                        icon: Icons.account_balance_wallet_outlined,
                        title: DepositStrings.rowTitle,
                        subtitle: DepositStrings.rowSubtitle,
                        onTap: () => _open(const DepositScreen()),
                      ),
                    ],
                  ),
                  SettingsGroup(
                    title: context.l10n.aboutTitle,
                    children: [
                      SettingsRow(
                        icon: Icons.info_outline,
                        title: context.l10n.settingsAboutRowTitle,
                        subtitle: context.l10n.settingsAboutRowSubtitle,
                        onTap: () => _open(const AboutPage()),
                      ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _seedGroup(WalletInfo current) {
    final t = context.l10n;
    return SettingsGroup(
      title: t.commonThisWallet,
      // The header above names the wallet; a long name as the scope tag
      // would run off the label row.
      scope: t.settingsSeedWalletScope,
      children: [
        SettingsRow(
          icon: Icons.account_balance_wallet_outlined,
          title: t.settingsWalletRowTitle,
          subtitle: t.settingsWalletRowSubtitle,
          onTap: () => _open(
            WalletSettingsPage(
              walletId: current.walletId,
              walletName: current.name,
              onChanged: widget.onWalletChanged,
              onRemoved: widget.onWalletRemoved,
            ),
          ),
        ),
        SettingsRow(
          icon: Icons.lock_outline,
          title: t.securityTitle,
          subtitle: t.settingsSecurityWalletSubtitle,
          onTap: () => _open(SecuritySettingsPage(walletId: current.walletId)),
        ),
      ],
    );
  }

  Widget _appGroup({required bool includeSecurity}) {
    final t = context.l10n;
    return SettingsGroup(
      title: t.settingsAppGroup,
      scope: t.settingsScopeAppWide,
      children: [
        if (includeSecurity)
          SettingsRow(
            icon: Icons.lock_outline,
            title: t.securityTitle,
            subtitle: t.settingsSecurityAppSubtitle,
            onTap: () => _open(const SecuritySettingsPage()),
          ),
        SettingsRow(
          icon: Icons.qr_code_scanner,
          title: t.settingsOfflineSigningTitle,
          subtitle: t.settingsOfflineSigningSubtitle,
          onTap: () => openColdSigner(context),
        ),
        SettingsRow(
          icon: Icons.image_outlined,
          title: t.settingsRemotePreviewsTitle,
          subtitle: t.settingsRemotePreviewsSubtitle,
          onTap: () => _open(const PreviewSettingsPage()),
        ),
        SettingsRow(
          icon: Icons.hub_outlined,
          title: t.networkTitle,
          subtitle: networkController.statusLabel,
          onTap: () => _open(const NetworkSettingsPage()),
        ),
        SettingsRow(
          icon: Icons.palette_outlined,
          title: t.displayTitle,
          subtitle: '${_appearanceName()} · ${networkController.fiatCode.toUpperCase()}',
          onTap: () => _open(const DisplaySettingsPage()),
        ),
        SettingsRow(
          icon: Icons.contacts_outlined,
          title: t.addressBookTitle,
          subtitle: t.settingsContactsCount(contactsService.contacts.length),
          onTap: () => _open(const AddressBookPage()),
        ),
      ],
    );
  }

  static String _appearanceName() => switch (themeController.mode) {
        ArgusThemeMode.system => '${themeController.darkPalette.name} / ${themeController.lightPalette.name}',
        ArgusThemeMode.dark => themeController.darkPalette.name,
        ArgusThemeMode.light => themeController.lightPalette.name,
      };

  Widget _header(BuildContext context, {required IconData icon, required String name, required String detail}) {
    final colors = ArgusColors.of(context);
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accentOf(context).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: accentTextOf(context)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: headingFont, fontWeight: FontWeight.w700, fontSize: 19),
                ),
                const SizedBox(height: 2),
                Text(detail, style: TextStyle(fontSize: 12.5, color: colors.muted)),
              ],
            ),
          ),
          if (widget.onShowAllWallets != null)
            TextButton(
              onPressed: widget.onShowAllWallets,
              child: Text(context.l10n.settingsAllWallets),
            ),
        ],
      ),
    );
  }

  Widget _walletHeader(BuildContext context, WalletInfo current, int count) {
    final unlocked = walletService.isUnlocked && walletService.activeWalletId == current.walletId;
    final t = context.l10n;
    return _header(
      context,
      icon: Icons.account_balance_wallet_outlined,
      name: current.name,
      detail: [
        unlocked ? t.settingsUnlocked : t.settingsLocked,
        t.settingsWalletsOnDevice(count),
      ].join(' · '),
    );
  }

  // ── Watched wallets ────────────────────────────────────────────────────

  WatchAccount? _account(WalletRef ref) {
    for (final a in watchAccountService.accounts) {
      if (a.key == ref.id) return a;
    }
    return null;
  }

  String _watchedName(WalletRef ref) => ref.kind == WalletKind.watchedAccount
      ? (_account(ref)?.label ?? context.l10n.commonWatchedAccount)
      : (addressLabelService.labelFor(ref.id) ?? context.l10n.commonWatchedAddress);

  Widget _watchedHeader(BuildContext context, WalletRef ref) {
    return _header(
      context,
      icon: Icons.visibility_outlined,
      name: _watchedName(ref),
      detail: ref.kind == WalletKind.watchedAccount
          ? context.l10n.settingsWatchOnlyAccountDetail(shorten(ref.id, head: 8, tail: 6))
          : context.l10n.settingsWatchOnlyAddressDetail(shorten(ref.id, head: 6, tail: 6)),
    );
  }

  Widget _watchedGroup(WalletRef ref) {
    final account = ref.kind == WalletKind.watchedAccount;
    final t = context.l10n;
    return SettingsGroup(
      title: account ? t.settingsThisAccount : t.settingsThisAddress,
      scope: t.settingsWatchOnlyScope,
      children: [
        SettingsRow(
          icon: Icons.edit_outlined,
          title: t.commonName,
          subtitle: _watchedName(ref),
          onTap: () => _renameWatched(ref),
        ),
        SettingsRow(
          icon: Icons.visibility_off_outlined,
          title: t.commonStopWatching,
          subtitle: t.settingsStopWatchingSubtitle,
          danger: true,
          onTap: () => _unwatch(ref),
        ),
      ],
    );
  }

  // The same flows as the watched wallet's ⋮ menu and its overview row's
  // swipe (home/watched_actions.dart).
  Future<void> _renameWatched(WalletRef ref) async {
    if (await renameWatched(context, ref)) widget.onWalletChanged?.call();
  }

  Future<void> _unwatch(WalletRef ref) async {
    if (await stopWatching(context, ref)) widget.onWalletRemoved?.call(ref.id);
  }
}
