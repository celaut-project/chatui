import 'package:flutter/material.dart';

import '../../bridge/api/celaut_deposit.dart';
import '../../celaut/deposit_strings.dart';
import '../../format.dart';
import '../../l10n/l10n.dart';
import '../confirm_transaction_sheet.dart';

/// An amount of MU with its thousands grouped, as the wallet groups token amounts. Any
/// text that is not a whole number stays as it is.
String groupMu(String mu) {
  if (!RegExp(r'^[0-9]+$').hasMatch(mu)) return mu;
  final buf = StringBuffer();
  for (var i = 0; i < mu.length; i++) {
    if (i > 0 && (mu.length - i) % 3 == 0) buf.write(',');
    buf.write(mu[i]);
  }
  return buf.toString();
}

/// The rows of the confirmation sheet of a deposit: the ERG that the node gets, the MU
/// that it buys, the fee, the change, and the use of the limit of the node.
List<ConfirmTxRow> depositConfirmRows(BuildContext context, DepositPreparedView v) {
  final amount = v.amountNanoErg.toInt();
  return [
    ConfirmTxRow(DepositStrings.rowNode, shorten(v.peerId, head: 10, tail: 8)),
    ConfirmTxRow(DepositStrings.rowAmount, formatErg(amount), bold: true),
    ConfirmTxRow(DepositStrings.rowMu, '${groupMu(v.amountMu)} MU', bold: true),
    ConfirmTxRow(DepositStrings.rowRate, DepositStrings.rate(groupMu(v.muPerNanoErg))),
    ConfirmTxRow(context.l10n.commonMinerFee, formatErg(v.minerFeeNanoErg)),
    ConfirmTxRow(context.l10n.ergopayRowChange, formatErg(v.changeNanoErg)),
    ConfirmTxRow(DepositStrings.rowTotal, formatErg(amount + v.minerFeeNanoErg)),
    ConfirmTxRow(
      DepositStrings.rowUsed,
      DepositStrings.used(
        formatErg(v.depositedNanoErg.toInt()),
        formatErg(v.limitNanoErg.toInt()),
      ),
    ),
  ];
}

/// The confirmation sheet of the wallet for a deposit. The deposit has no "sign only":
/// the app must follow the transaction to the explorer and then tell the node.
Future<ConfirmChoice> showDepositConfirmation(
  BuildContext context,
  DepositPreparedView v,
) {
  return showConfirmTransactionChoice(
    context,
    title: DepositStrings.confirmTitle,
    confirmLabel: DepositStrings.confirmLabel,
    rows: depositConfirmRows(context, v),
    recipientAddress: v.payToAddress,
    detail: DepositStrings.confirmDetail(v.tokenSeconds ~/ 60),
    preparationId: v.preparationId.toInt(),
  );
}
