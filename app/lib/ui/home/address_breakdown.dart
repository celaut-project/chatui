import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../format.dart';
import '../../l10n/l10n.dart';
import '../../services/address_holdings.dart';
import '../../theme/argus_theme.dart';
import 'home_format.dart';
import 'home_style.dart';
import 'home_widgets.dart';
import 'wallet_tools_sheet.dart';

/// Holdings in the order the breakdown lists them: the address the wallet
/// is shown as first, then every other funded address by index. Empty
/// addresses are counted, not listed, unless [listEmpty]: a wallet can
/// know dozens.
({List<AddressHolding> listed, int emptyOthers}) breakdownRows(
  List<AddressHolding> holdings, {
  required String? identity,
  bool listEmpty = false,
}) {
  final listed = <AddressHolding>[];
  final empty = <AddressHolding>[];
  AddressHolding? shownAs;
  for (final h in holdings) {
    if (h.address == identity) {
      shownAs = h;
    } else if (h.holdsFunds) {
      listed.add(h);
    } else {
      empty.add(h);
    }
  }
  int byIndex(AddressHolding a, AddressHolding b) {
    final ia = a.index, ib = b.index;
    if (ia == null && ib == null) return a.address.compareTo(b.address);
    if (ia == null) return 1;
    if (ib == null) return -1;
    return ia.compareTo(ib);
  }

  listed.sort(byIndex);
  if (!listEmpty) return (listed: [?shownAs, ...listed], emptyOthers: empty.length);
  return (listed: [?shownAs, ...listed, ...empty..sort(byIndex)], emptyOthers: 0);
}

/// Per-address split of a wallet's balance: index, address, ERG, tokens,
/// with the address the wallet is shown as marked. From More it lists the
/// empty addresses as well, so any address can be labelled; [labels] tells
/// the sheet when a label changes.
Future<void> showAddressBreakdownSheet(
  BuildContext context, {
  required String walletName,
  required List<AddressHolding> holdings,
  required String? identity,
  required bool hidden,
  bool listEmpty = false,
  String? Function(String address)? labelFor,
  ValueChanged<String>? onLabel,
  Listenable? labels,
}) {
  Widget sheet() => AddressBreakdownSheet(
        walletName: walletName,
        holdings: holdings,
        identity: identity,
        hidden: hidden,
        listEmpty: listEmpty,
        labelFor: labelFor,
        onLabel: onLabel,
      );
  return showHomeSheet<void>(
    context,
    // A label given from the sheet shows at once.
    builder: (ctx) => labels == null ? sheet() : ListenableBuilder(listenable: labels, builder: (_, _) => sheet()),
  );
}

class AddressBreakdownSheet extends StatelessWidget {
  const AddressBreakdownSheet({
    super.key,
    required this.walletName,
    required this.holdings,
    required this.identity,
    required this.hidden,
    this.listEmpty = false,
    this.labelFor,
    this.onLabel,
  });

  final String walletName;
  final List<AddressHolding> holdings;
  final String? identity;
  final bool hidden;
  final bool listEmpty;

  /// The user's own name for an address, shown under it.
  final String? Function(String address)? labelFor;

  /// Tapping an address names it.
  final ValueChanged<String>? onLabel;

  @override
  Widget build(BuildContext context) {
    final t = HomeText.of(context);
    final rows = breakdownRows(holdings, identity: identity, listEmpty: listEmpty);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 1,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.only(bottom: 16 + MediaQuery.paddingOf(context).bottom),
        children: [
          HomeSheetHeader(title: context.l10n.commonAddresses, subject: walletName),
          Padding(
            padding: const EdgeInsets.fromLTRB(homeGutter, 0, homeGutter, 8),
            child: Text(
              context.l10n.homeBreakdownIntro,
              style: t.secondary.copyWith(height: 1.4),
            ),
          ),
          for (final h in rows.listed)
            _AddressHoldingRow(
              holding: h,
              shownAs: h.address == identity,
              hidden: hidden,
              label: labelFor?.call(h.address),
              onLabel: onLabel,
            ),
          if (rows.emptyOthers > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(homeGutter, 8, homeGutter, 0),
              child: Text(
                context.l10n.homeBreakdownEmptyOthers(rows.emptyOthers),
                style: t.secondary,
              ),
            ),
        ],
      ),
    );
  }
}

class _AddressHoldingRow extends StatelessWidget {
  const _AddressHoldingRow({
    required this.holding,
    required this.shownAs,
    required this.hidden,
    this.label,
    this.onLabel,
  });

  final AddressHolding holding;
  final bool shownAs;
  final bool hidden;
  final String? label;
  final ValueChanged<String>? onLabel;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: holding.address));
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.l10n.commonAddressCopied)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = HomeText.of(context);
    final accent = ArgusColors.of(context).accentText;
    final tokens = holding.tokenCount;
    final index = holding.index == null ? '#?' : '#${holding.index}';
    final named = label != null && label!.trim().isNotEmpty ? label!.trim() : null;
    final amount = hidden ? '$maskedFigure${nbsp}ERG' : '${summaryErg(holding.nanoErg)}${nbsp}ERG';
    final tokenText = tokens > 0 && !hidden ? context.l10n.homeTokenCount(tokens, groupThousands('$tokens')) : null;
    final address = shorten(holding.address, head: 9, tail: 7);
    return HomeRow(
      inkKey: ValueKey('holding-${holding.address}'),
      onTap: onLabel == null ? null : () => onLabel!(holding.address),
      onLongPress: () => _copy(context),
      hint: onLabel == null ? context.l10n.homeLongPressCopy : context.l10n.homeNameAddressHint,
      semanticLabel: spoken([
        context.l10n.homeSpokenAddress(index),
        address,
        if (shownAs) context.l10n.homeSpokenShownAs,
        ?named,
        amount,
        ?tokenText,
      ].join(', ')),
      // The index sits in the mark column, shrunk to fit when it runs long.
      leading: SizedBox(
        width: homeMarkSize,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(index, style: monoStyle(context, size: 12.5).copyWith(color: t.muted)),
        ),
      ),
      title: Text(address, maxLines: 1, overflow: TextOverflow.ellipsis, style: monoStyle(context, size: 13).copyWith(color: t.ink)),
      subtitle: shownAs || named != null
          ? TextSpan(
              children: [
                if (shownAs)
                  TextSpan(text: context.l10n.homeShownAs, style: TextStyle(color: accent, fontWeight: FontWeight.w700)),
                if (named != null) TextSpan(text: shownAs ? '  ·  $named' : named),
              ],
            )
          : null,
      figure: TextSpan(text: amount),
      subfigure: tokenText == null ? null : TextSpan(text: tokenText),
    );
  }
}
