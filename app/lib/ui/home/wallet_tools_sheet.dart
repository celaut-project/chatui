import 'package:flutter/material.dart';

import '../../theme/argus_theme.dart';
import 'home_models.dart';
import 'home_style.dart';
import 'home_widgets.dart';
import '../../l10n/l10n.dart';

/// Mark, name and one line for each tool behind More. The lines are short
/// forms of the Discover explainers, which stay the full account.
({IconData icon, String title, String blurb}) walletToolLook(WalletTool tool) => switch (tool) {
      WalletTool.tokens => (
          icon: Icons.token_outlined,
          title: appL10n.commonTokens,
          blurb: appL10n.homeToolTokensBlurb,
        ),
      WalletTool.utxos => (
          icon: Icons.grid_view_outlined,
          title: appL10n.homeUtxoManagement,
          blurb: appL10n.homeToolUtxosBlurb,
        ),
      WalletTool.addresses => (
          icon: Icons.account_tree_outlined,
          title: appL10n.commonAddresses,
          blurb: appL10n.homeToolAddressesBlurb,
        ),
      WalletTool.lock => (
          icon: Icons.lock_outline,
          title: appL10n.homeToolLock,
          blurb: appL10n.homeToolLockBlurb,
        ),
    };

/// A flat sheet for the home screens: the same rows, rules and labels as
/// the page beneath, on the palette's surface, under a quiet handle.
Future<T?> showHomeSheet<T>(BuildContext context, {required Widget Function(BuildContext) builder}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Theme.of(context).colorScheme.surface,
    // Tall at large text sizes: it may fill the screen, but not run under
    // the status bar.
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(homeRadius))),
    builder: builder,
  );
}

/// A sheet's handle and its label line ("MORE · MAIN WALLET").
class HomeSheetHeader extends StatelessWidget {
  const HomeSheetHeader({super.key, required this.title, this.subject});

  final String title;

  /// Read after the title in the same capitals, e.g. the wallet's name.
  final String? subject;

  @override
  Widget build(BuildContext context) {
    final t = HomeText.of(context);
    return Column(
      children: [
        Container(
          width: 32,
          height: 4,
          margin: const EdgeInsets.only(top: 10, bottom: 8),
          decoration: BoxDecoration(color: t.muted.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: homeGutter),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Semantics(
                header: true,
                child: Text.rich(
                  TextSpan(
                    text: title.toUpperCase(),
                    children: [if (subject != null) TextSpan(text: '   ·   ${subject!.toUpperCase()}')],
                  ),
                  style: t.label,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Opens More and returns the tool picked, or null if dismissed.
Future<WalletTool?> showWalletToolsSheet(
  BuildContext context, {
  required List<WalletToolEntry> tools,
}) {
  return showHomeSheet<WalletTool>(
    context,
    builder: (ctx) => WalletToolsSheet(
      tools: tools,
      onSelect: (tool) => Navigator.pop(ctx, tool),
    ),
  );
}

/// The More sheet: the wallet's own tools that don't earn a place in the
/// action row. Protocols live in the Discover tab; this is only what acts
/// on the wallet itself, with Lock set apart under a rule.
class WalletToolsSheet extends StatelessWidget {
  const WalletToolsSheet({super.key, required this.tools, required this.onSelect});

  final List<WalletToolEntry> tools;
  final ValueChanged<WalletTool> onSelect;

  @override
  Widget build(BuildContext context) {
    final main = tools.where((t) => t.tool != WalletTool.lock).toList();
    final lock = tools.where((t) => t.tool == WalletTool.lock).toList();
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HomeSheetHeader(title: context.l10n.homeActionMore),
            for (final entry in main) _row(context, entry),
            if (lock.isNotEmpty) ...[
              const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: HomeRule()),
              for (final entry in lock) _row(context, entry, chevron: false),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, WalletToolEntry entry, {bool chevron = true}) {
    final t = HomeText.of(context);
    final look = walletToolLook(entry.tool);
    final status = entry.status;
    final warn = rustFor(context);
    return HomeRow(
      inkKey: Key('wallet-tool-${entry.tool.name}'),
      onTap: () => onSelect(entry.tool),
      semanticLabel: [look.title, ?status, look.blurb].join(', '),
      leading: HomeDisc(child: Icon(look.icon, size: 18, color: t.ink)),
      title: Text.rich(
        TextSpan(
          text: look.title,
          children: [
            if (status != null)
              TextSpan(
                text: '   $status',
                style: t.secondary.copyWith(
                  color: entry.warn ? warn : ArgusColors.of(context).accentText,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
        style: t.primary,
      ),
      subtitle: TextSpan(text: look.blurb),
      trailing: chevron ? Icon(Icons.chevron_right, size: 18, color: t.muted) : null,
    );
  }
}

/// What the welcome offers when the app has no wallet.
enum AddWalletChoice {
  create('overview-create'),
  restore('overview-restore');

  const AddWalletChoice(this.keyName);

  final String keyName;
}
