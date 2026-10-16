import '../l10n/l10n.dart';

/// Every text of the Celaut deposit screen (milestone M3), in one place. The texts are
/// in lib/l10n/app_*.arb (keys `celautDeposit…`).
class DepositStrings {
  const DepositStrings._();

  // Settings
  static String get rowTitle => appL10n.celautDepositRowTitle;
  static String get rowSubtitle => appL10n.celautDepositRowSubtitle;

  // Screen
  static String get screenTitle => appL10n.celautDepositScreenTitle;
  static String get intro => appL10n.celautDepositIntro;
  static String get nodeLabel => appL10n.celautDepositNodeLabel;
  static String get nodeHint => appL10n.celautDepositNodeHint;
  static String get check => appL10n.celautDepositCheck;
  static String get checking => appL10n.celautDepositChecking;

  // Node
  static String get nodeTitle => appL10n.celautDepositNodeTitle;
  static String payTo(String address) => appL10n.celautDepositPayTo(address);
  static String rate(String mu) => appL10n.celautDepositRate(mu);
  static String balance(String mu) => appL10n.celautDepositBalance(mu);
  static String used(String used, String limit) => appL10n.celautDepositUsed(used, limit);
  static String usedValue(String used, String limit) =>
      appL10n.celautDepositUsedValue(used, limit);
  static String get limitLabel => appL10n.celautDepositLimitLabel;
  static String get setLimit => appL10n.celautDepositSetLimit;
  static String get limitInvalid => appL10n.celautDepositLimitInvalid;

  // Amount
  static String get amountLabel => appL10n.celautDepositAmountLabel;
  static String get amountHint => appL10n.celautDepositAmountHint;
  static String get amountInvalid => appL10n.celautDepositAmountInvalid;
  static String get prepare => appL10n.celautDepositPrepare;
  static String get preparing => appL10n.celautDepositPreparing;

  // Paying wallet (docs/celaut/ui.md, section 1)
  static String get payerTitle => appL10n.celautDepositPayerTitle;
  static String payerBalance(String amount) => appL10n.celautDepositPayerBalance(amount);
  static String get payerOpen => appL10n.celautDepositPayerOpen;
  static String get payerLocked => appL10n.celautDepositPayerLocked;
  static String get noFullWallet => appL10n.celautNoFullWallet;
  static String get unknown => appL10n.celautUnknown;

  // Confirmation sheet
  static String get confirmTitle => appL10n.celautDepositConfirmTitle;
  static String get confirmLabel => appL10n.celautDepositConfirmLabel;
  static String get rowNode => appL10n.celautDepositRowNode;
  static String get rowAmount => appL10n.celautDepositRowAmount;
  static String get rowMu => appL10n.celautDepositRowMu;
  static String get rowRate => appL10n.celautDepositRowRate;
  static String get rowTotal => appL10n.celautDepositRowTotal;
  static String get rowUsed => appL10n.celautDepositRowUsed;
  static String get rowPayer => appL10n.celautDepositRowPayer;
  static String get rowPayerBalance => appL10n.celautDepositRowPayerBalance;
  static String confirmDetail(int minutes) =>
      appL10n.celautDepositConfirmDetail('$minutes');

  // After the confirmation
  static String get waiting => appL10n.celautDepositWaiting;
  static String get waitAgain => appL10n.celautDepositWaitAgain;
  static String tx(String id) => appL10n.celautDepositTx(id);
  static String box(String id) => appL10n.celautDepositBox(id);
  static String accepted(String mu) => appL10n.celautDepositAccepted(mu);
  static String refused(String message) => appL10n.celautDepositRefused(message);
  static String get cancelled => appL10n.celautDepositCancelled;
  static String sendFailed(String error) => appL10n.celautDepositSendFailed(error);

  // Deposits sent in this run or an earlier one
  static String get sentTitle => appL10n.celautDepositSentTitle;
  static String sentRow(String amount, String mu, String node) =>
      appL10n.celautDepositSentRow(amount, mu, node);
  static String get sentExpired => appL10n.celautDepositSentExpired;
}
