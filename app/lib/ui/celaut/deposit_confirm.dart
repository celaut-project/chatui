import 'package:flutter/material.dart';

import '../../bridge/api/celaut_deposit.dart';
import '../../celaut/celaut_format.dart';
import '../../celaut/deposit_strings.dart';
import '../../celaut/payers.dart';
import '../../format.dart';
import '../../l10n/l10n.dart';
import '../confirm_transaction_sheet.dart';

export '../../celaut/celaut_format.dart' show groupMu;

/// The rows of the confirmation sheet of a deposit: the full wallet that pays and its
/// balance, the ERG that the node gets, the MU that it buys, the fee, the change, and
/// the use of the limit of the node (`docs/celaut/ui.md`, section 1).
List<ConfirmTxRow> depositConfirmRows(
  BuildContext context,
  DepositPreparedView v,
  PayerWallet payer,
) {
  final amount = v.amountNanoErg.toInt();
  return [
    ConfirmTxRow(DepositStrings.rowPayer, payer.name, bold: true),
    ConfirmTxRow(DepositStrings.rowPayerBalance, ergOrUnknown(payer.balanceNano)),
    ConfirmTxRow(DepositStrings.rowNode, shorten(v.peerId, head: 10, tail: 8)),
    ConfirmTxRow(DepositStrings.rowAmount, formatErg(amount), bold: true),
    ConfirmTxRow(DepositStrings.rowMu, '${groupMu(v.amountMu)} MU', bold: true),
    ConfirmTxRow(DepositStrings.rowRate, DepositStrings.rate(groupMu(v.muPerNanoErg))),
    ConfirmTxRow(context.l10n.commonMinerFee, formatErg(v.minerFeeNanoErg)),
    ConfirmTxRow(context.l10n.ergopayRowChange, formatErg(v.changeNanoErg)),
    ConfirmTxRow(DepositStrings.rowTotal, formatErg(amount + v.minerFeeNanoErg)),
    ConfirmTxRow(
      DepositStrings.rowUsed,
      DepositStrings.used(formatErg(v.depositedNanoErg.toInt()), formatErg(v.limitNanoErg.toInt())),
    ),
  ];
}

/// The confirmation sheet of the wallet for a deposit. The deposit has no "sign only":
/// the app must follow the transaction to the explorer and then tell the node.
Future<ConfirmChoice> showDepositConfirmation(
  BuildContext context,
  DepositPreparedView v,
  PayerWallet payer,
) {
  return showConfirmTransactionChoice(
    context,
    title: DepositStrings.confirmTitle,
    confirmLabel: DepositStrings.confirmLabel,
    rows: depositConfirmRows(context, v, payer),
    recipientAddress: v.payToAddress,
    detail: DepositStrings.confirmDetail(v.tokenSeconds ~/ 60),
    preparationId: v.preparationId.toInt(),
  );
}
