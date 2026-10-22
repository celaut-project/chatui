import 'package:flutter/material.dart';

import '../celaut/celaut_strings.dart';
import '../celaut/compute_home_flag.dart';
import '../celaut/deposit_strings.dart';
import '../celaut/network_strings.dart';
import '../celaut/service_strings.dart';
import '../l10n/l10n.dart';
import '../services/contacts_service.dart';
import '../services/network_controller.dart';
import '../services/wallet_service.dart';
import '../theme/argus_theme.dart';
import '../theme/theme_controller.dart';
import 'celaut/network_screen.dart';
import 'celaut/node_connect_screen.dart';
import 'celaut/deposit_screen.dart';
import 'celaut/env_variables_screen.dart';
import 'celaut/known_nodes_screen.dart';
import 'celaut/service_screen.dart';
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
/// The app holds one wallet. Creating and restoring it live on the overview;
/// renaming and removing it live in its own settings.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.walletId,
    this.embedded = false,
    this.onWalletChanged,
    this.onWalletRemoved,
  });

  /// The seed wallet whose page hosts these settings.
  final String? walletId;

  /// Hosted as a wallet page's tab: no app bar of its own.
  final bool embedded;

  /// The wallet was renamed or its pinned address changed.
  final VoidCallback? onWalletChanged;

  /// The wallet was removed; carries its id.
  final ValueChanged<String>? onWalletRemoved;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<List<WalletInfo>> _walletsFuture = walletService.listWallets();

  /// Only the page of the wallet has the wallet; the settings of the overview
  /// have none.
  String? get _walletId => widget.walletId;

  Future<void> _open(Widget page) async {
    await Navigator.push(context, fadeRoute(page));
    if (!mounted) return;
    // setState takes a callback that returns nothing: an arrow here would return the
    // Future of the list, which setState refuses.
    setState(() {
      _walletsFuture = walletService.listWallets();
    });
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
              return ListView(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
                children: [
                  const UpdateNotice(),
                  if (current != null) ...[
                    _walletHeader(context, current),
                    const SizedBox(height: 24),
                    _seedGroup(current),
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
                        key: const Key('settings-tor'),
                        icon: Icons.shield_outlined,
                        title: NetworkStrings.rowTitle,
                        subtitle: NetworkStrings.rowSubtitle,
                        onTap: () => _open(const NetworkScreen()),
                      ),
                      SettingsRow(
                        icon: Icons.play_circle_outline,
                        title: ServiceStrings.rowTitle,
                        subtitle: ServiceStrings.rowSubtitle,
                        onTap: () => _open(const ServiceScreen()),
                      ),
                      SettingsRow(
                        key: const Key('settings-nodes'),
                        icon: Icons.hub_outlined,
                        title: context.l10n.celautNodesTitle,
                        subtitle: context.l10n.celautNodesRowSubtitle,
                        onTap: () => _open(const KnownNodesScreen()),
                      ),
                      SettingsRow(
                        key: const Key('settings-env'),
                        icon: Icons.key_outlined,
                        title: context.l10n.celautEnvTitle,
                        subtitle: context.l10n.celautEnvRowSubtitle,
                        onTap: () => _open(const EnvVariablesScreen()),
                      ),
                      SettingsRow(
                        icon: Icons.account_balance_wallet_outlined,
                        title: DepositStrings.rowTitle,
                        subtitle: DepositStrings.rowSubtitle,
                        onTap: () => _open(const DepositScreen()),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: computeHomeFlag,
                        builder: (context, on, _) => SettingsRow(
                          icon: Icons.memory_outlined,
                          title: context.l10n.celautComputeHomeRowTitle,
                          subtitle: context.l10n.celautComputeHomeRowSubtitle,
                          trailing: Switch(
                            key: const Key('settings-compute-home'),
                            value: on,
                            onChanged: computeHomeFlag.set,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SettingsGroup(
                    title: context.l10n.aboutTitle,
                    children: [
                      SettingsRow(
                        key: const Key('settings-about'),
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
        ],
      ),
    );
  }

  Widget _walletHeader(BuildContext context, WalletInfo current) {
    final unlocked = walletService.isUnlocked && walletService.activeWalletId == current.walletId;
    final t = context.l10n;
    return _header(
      context,
      icon: Icons.account_balance_wallet_outlined,
      name: current.name,
      detail: unlocked ? t.settingsUnlocked : t.settingsLocked,
    );
  }
}
