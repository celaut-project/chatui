import '../format.dart';
import '../l10n/l10n.dart';
import 'token_amounts.dart';

// What a history entry did, read from the whole wallet's point of view.
//
// Each history row carries `io` (see `wallet_net::activity::TxIo`): the
// transaction's inputs and outputs grouped by owner, each marked `mine`
// when the address is one of the wallet's own, and tagged when the wallet
// knows the box (`babel`, `oracle`, `argus_fee`). From that the wallet's
// net change per asset is exact: a box moving between two of its addresses
// changes nothing, a fee is a fee, a token in its inputs that no output
// holds was burned. Rows without `io` (a just-broadcast transaction, a
// snapshot saved by an older version) fall back to the legacy per-row
// reading.

/// The icon family of a history entry: which way value went.
enum ActivityKind { received, sent, selfTransfer, contract }

/// What happened, from the wallet's point of view.
enum ActivityCategory {
  received,
  sent,

  /// Between the wallet's own addresses; only fees left.
  moved,

  /// Many of the wallet's boxes merged into few.
  consolidated,

  /// Tokens the wallet held that no output holds any more.
  burned,

  /// A token created here (its id is the first input's).
  minted,
  contract,
}

/// Mainnet P2PK addresses are 51 base58 characters starting with 9; anything
/// longer is a script (a contract).
bool isContractAddress(String? address) {
  if (address == null || address.isEmpty) return false;
  return !(address.startsWith('9') && address.length == 51);
}

BigInt _big(Object? v) => switch (v) {
      final int i => BigInt.from(i),
      final BigInt b => b,
      final double d => BigInt.from(d),
      final String s => BigInt.tryParse(s) ?? BigInt.zero,
      _ => BigInt.zero,
    };

/// Every box of one owner on one side of a transaction.
class TxParty {
  const TxParty({
    required this.address,
    required this.value,
    required this.assets,
    this.boxes = 1,
    this.tag,
    this.mine = false,
  });

  factory TxParty.fromJson(Map m) => TxParty(
        address: m['address']?.toString() ?? '',
        value: _big(m['value']),
        assets: {
          for (final a in (m['assets'] as List? ?? const []).whereType<Map>())
            a['token_id']?.toString() ?? '': _big(a['amount']),
        },
        boxes: (m['boxes'] as num?)?.toInt() ?? 1,
        tag: m['tag']?.toString(),
        mine: m['mine'] == true,
      );

  Map<String, dynamic> toJson() => {
        'address': address,
        'value': value.isValidInt ? value.toInt() : value.toString(),
        'assets': [
          for (final e in assets.entries)
            {'token_id': e.key, 'amount': e.value.isValidInt ? e.value.toInt() : e.value.toString()},
        ],
        'boxes': boxes,
        'tag': ?tag,
        if (mine) 'mine': true,
      };

  /// Empty for the folded remainder of many foreign owners.
  final String address;
  final BigInt value;

  /// Token id to amount, in the order the boxes list them.
  final Map<String, BigInt> assets;
  final int boxes;
  final String? tag;
  final bool mine;

  TxParty owned(bool mine) =>
      TxParty(address: address, value: value, assets: assets, boxes: boxes, tag: tag, mine: mine);
}

/// A transaction's inputs and outputs, grouped by owner.
class TxFlows {
  const TxFlows({
    required this.inputs,
    required this.outputs,
    required this.minerFee,
    required this.firstInput,
    this.complete = true,
  });

  static TxFlows? of(Map tx) {
    final io = tx['io'];
    if (io is! Map) return null;
    List<TxParty> side(String key) =>
        [for (final p in (io[key] as List? ?? const []).whereType<Map>()) TxParty.fromJson(p)];
    return TxFlows(
      inputs: side('inputs'),
      outputs: side('outputs'),
      minerFee: _big(io['miner_fee']),
      firstInput: io['first_input']?.toString() ?? '',
      complete: io['complete'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'inputs': [for (final p in inputs) p.toJson()],
        'outputs': [for (final p in outputs) p.toJson()],
        'miner_fee': minerFee.toInt(),
        'first_input': firstInput,
        'complete': complete,
      };

  final List<TxParty> inputs;
  final List<TxParty> outputs;
  final BigInt minerFee;
  final String firstInput;

  /// False when some inputs could not be read (a pending transaction
  /// spending a foreign box).
  final bool complete;
}

/// One amount that moved: ERG when [tokenId] is null. Signed: positive
/// arrived, negative left.
class ActivityLeg {
  const ActivityLeg(this.tokenId, this.amount);
  final String? tokenId;
  final BigInt amount;
  bool get isErg => tokenId == null;
  ActivityLeg get abs => ActivityLeg(tokenId, amount.abs());
  @override
  String toString() => '${tokenId ?? 'ERG'}:$amount';
}

/// What a row's amount column shows on one line: legs, or a label and one
/// unsigned figure ("Fee 0.0011 ERG").
class ActivityFigure {
  const ActivityFigure(this.legs, {this.label});
  final List<ActivityLeg> legs;
  final String? label;
}

/// A transaction as the wallet saw it.
class WalletActivity {
  const WalletActivity({
    required this.category,
    required this.flows,
    required this.erg,
    required this.received,
    required this.sent,
    required this.burned,
    required this.minted,
    required this.minerFee,
    required this.appFee,
    required this.internalNano,
    required this.recipients,
    required this.senders,
    this.protocol,
    this.contract,
  });

  final ActivityCategory category;
  final TxFlows flows;

  /// The wallet's net nanoERG change, fees included.
  final BigInt erg;

  /// Tokens that arrived (net, minted ones excluded) and that left (net,
  /// burned ones excluded), as positive amounts.
  final List<ActivityLeg> received;
  final List<ActivityLeg> sent;
  final List<ActivityLeg> burned;
  final List<ActivityLeg> minted;

  /// What the wallet paid: zero when someone else built the transaction.
  final BigInt minerFee;
  final BigInt appFee;

  /// nanoERG that left one of the wallet's addresses for another (change
  /// included).
  final BigInt internalNano;

  /// Outside addresses paid (never the wallet's).
  final List<String> recipients;

  /// Outside addresses that funded an arrival.
  final List<String> senders;

  /// `argus_fee` for an arrival that is only another wallet's app fee.
  final String? protocol;

  /// An unrecognised script the wallet dealt with.
  final String? contract;

  BigInt get feesPaid => minerFee + appFee;

  bool get funded => flows.inputs.any((p) => p.mine);

  ActivityKind get kind => switch (category) {
        ActivityCategory.received || ActivityCategory.minted => ActivityKind.received,
        ActivityCategory.sent || ActivityCategory.burned => ActivityKind.sent,
        ActivityCategory.moved || ActivityCategory.consolidated => ActivityKind.selfTransfer,
        ActivityCategory.contract => ActivityKind.contract,
      };

  /// Everything that arrived, ERG first when it is the point.
  List<ActivityLeg> get inLegs => [
        for (final t in minted) t,
        for (final t in received) t,
        if (erg > BigInt.zero) ActivityLeg(null, erg),
      ];

  /// Everything that left, fees included in the ERG leg.
  List<ActivityLeg> get outLegs => [
        for (final t in sent) ActivityLeg(t.tokenId, -t.amount),
        for (final t in burned) ActivityLeg(t.tokenId, -t.amount),
        if (erg < BigInt.zero) ActivityLeg(null, erg),
      ];
}

Map<String, BigInt> _sum(Iterable<TxParty> parties) {
  final out = <String, BigInt>{};
  for (final p in parties) {
    p.assets.forEach((id, n) => out[id] = (out[id] ?? BigInt.zero) + n);
  }
  return out;
}

BigInt _value(Iterable<TxParty> parties) => parties.fold(BigInt.zero, (a, p) => a + p.value);

/// The wallet's reading of [tx], or null for a row without `io`.
WalletActivity? walletActivity(Map tx) {
  final flows = TxFlows.of(tx);
  return flows == null ? null : readFlows(flows);
}

/// Classifies one transaction's flows.
WalletActivity readFlows(TxFlows f) {
  final selfIn = f.inputs.where((p) => p.mine).toList();
  final selfOut = f.outputs.where((p) => p.mine).toList();
  final foreignIn = f.inputs.where((p) => !p.mine).toList();
  final foreignOut = f.outputs.where((p) => !p.mine).toList();
  final funded = selfIn.isNotEmpty;

  final inSelf = _sum(selfIn), outSelf = _sum(selfOut);
  final inAll = _sum(f.inputs), outAll = _sum(f.outputs);
  final erg = _value(selfOut) - _value(selfIn);

  final ids = <String>{...inSelf.keys, ...outSelf.keys};
  final received = <ActivityLeg>[], sent = <ActivityLeg>[];
  final burned = <ActivityLeg>[], minted = <ActivityLeg>[];
  for (final id in ids) {
    final net = (outSelf[id] ?? BigInt.zero) - (inSelf[id] ?? BigInt.zero);
    // Burned: what the wallet put in and no output holds. Only a whole
    // input side can tell; a pending transaction's foreign inputs are
    // unread, which can only make this smaller.
    final destroyed = (inAll[id] ?? BigInt.zero) - (outAll[id] ?? BigInt.zero);
    var burnt = BigInt.zero;
    if (funded && destroyed > BigInt.zero) {
      final mineIn = inSelf[id] ?? BigInt.zero;
      burnt = destroyed < mineIn ? destroyed : mineIn;
    }
    if (burnt > BigInt.zero) burned.add(ActivityLeg(id, burnt));
    if (net > BigInt.zero) {
      final issued = id == f.firstInput && (inAll[id] ?? BigInt.zero) == BigInt.zero;
      (issued ? minted : received).add(ActivityLeg(id, net));
    } else if (net < BigInt.zero && -net > burnt) {
      sent.add(ActivityLeg(id, -net - burnt));
    }
  }

  final appFeeParties = foreignOut.where((p) => p.tag == 'argus_fee');
  final appFee = funded ? _value(appFeeParties) : BigInt.zero;
  final minerFee = funded ? f.minerFee : BigInt.zero;
  final internal = funded ? _value(selfOut) : BigInt.zero;
  final paid = foreignOut.where((p) => p.tag != 'argus_fee').toList();
  final recipients = [
    for (final p in paid)
      if (p.tag == null && p.address.isNotEmpty) p.address,
  ];
  final senders = [
    for (final p in foreignIn)
      if (p.tag == null && p.address.isNotEmpty) p.address,
  ];

  WalletActivity make(
    ActivityCategory c, {
    String? protocol,
    String? contract,
  }) =>
      WalletActivity(
        category: c,
        flows: f,
        erg: erg,
        received: received,
        sent: sent,
        burned: burned,
        minted: minted,
        minerFee: minerFee,
        appFee: appFee,
        internalNano: internal,
        recipients: recipients,
        senders: senders,
        protocol: protocol,
        contract: contract,
      );

  final gains = erg > BigInt.zero || received.isNotEmpty || minted.isNotEmpty;
  final losses = erg < BigInt.zero || sent.isNotEmpty || burned.isNotEmpty;

  // Arrivals that are only the app fee another wallet paid.
  if (!funded && selfOut.isNotEmpty && selfOut.every((p) => p.tag == 'argus_fee')) {
    return make(ActivityCategory.received, protocol: 'argus_fee');
  }

  if (!funded) {
    return make(gains ? ActivityCategory.received : ActivityCategory.contract);
  }
  if (minted.isNotEmpty) return make(ActivityCategory.minted);

  final scripts = paid.where((p) => p.tag == null && isContractAddress(p.address)).toList();
  if (paid.isEmpty) {
    if (burned.isNotEmpty) return make(ActivityCategory.burned);
    // A script's box claimed back into the wallet (a refunded order): an
    // arrival, though the wallet paid the fee.
    if (foreignIn.isNotEmpty && gains) return make(ActivityCategory.received);
    final inBoxes = selfIn.fold(0, (a, p) => a + p.boxes);
    final outBoxes = selfOut.where((p) => p.tag != 'argus_fee').fold(0, (a, p) => a + p.boxes);
    return make(inBoxes >= 3 && outBoxes < inBoxes ? ActivityCategory.consolidated : ActivityCategory.moved);
  }
  if (scripts.isNotEmpty || (received.isNotEmpty && losses)) {
    return make(ActivityCategory.contract, contract: scripts.isEmpty ? null : scripts.first.address);
  }
  return make(ActivityCategory.sent);
}

/// [tx] re-read for a wallet that owns [owned] as well: a wallet whose
/// later addresses were found after its first history reads. The
/// wallet-wide summary fields
/// (`value_nano_erg`, `tokens_*`, `counterparty`) are recomputed with the
/// flows. Rows without `io`, and rows where [owned] marks nothing new,
/// come back unchanged.
Map<String, dynamic> reownActivity(Map<String, dynamic> tx, Set<String> owned) {
  final flows = TxFlows.of(tx);
  if (flows == null || owned.isEmpty) return tx;
  bool claims(TxParty p) => !p.mine && owned.contains(p.address);
  if (!flows.inputs.any(claims) && !flows.outputs.any(claims)) return tx;
  TxParty mark(TxParty p) => claims(p) ? p.owned(true) : p;
  final next = TxFlows(
    inputs: [for (final p in flows.inputs) mark(p)],
    outputs: [for (final p in flows.outputs) mark(p)],
    minerFee: flows.minerFee,
    firstInput: flows.firstInput,
    complete: flows.complete,
  );
  final a = readFlows(next);
  List<Map<String, dynamic>> tokens(Iterable<ActivityLeg> legs) => [
        for (final l in legs) {'token_id': l.tokenId, 'amount': l.amount.toInt()},
      ];
  final out = a.erg < BigInt.zero || a.sent.isNotEmpty || a.burned.isNotEmpty;
  return {
    ...tx,
    'io': next.toJson(),
    'value_nano_erg': a.erg.toInt(),
    'tokens_received': tokens([...a.minted, ...a.received]),
    'tokens_sent': tokens([...a.sent, ...a.burned]),
    'counterparty': out
        ? (a.recipients.isEmpty ? null : a.recipients.first)
        : (a.senders.isEmpty ? null : a.senders.first),
  };
}

// ─── Wording ──────────────────────────────────────────────────────────────

typedef TokenNamer = String? Function(String id);
typedef TokenScaler = int? Function(String id);

/// A row's words and figures.
class ActivityView {
  const ActivityView({
    required this.kind,
    required this.title,
    required this.primary,
    this.secondary,
    this.who,
    this.activity,
  });

  final ActivityKind kind;
  final String title;

  /// "to 9fRx…3kQe", "between your addresses"; null for none.
  final String? who;

  /// The amount column: the figure, and the line under it.
  final ActivityFigure primary;
  final ActivityFigure? secondary;

  /// Null for a row read the legacy way.
  final WalletActivity? activity;
}

String _short(String a) => shorten(a, head: 6, tail: 4);

String _name(TokenNamer name, String? id) {
  if (id == null) return 'ERG';
  final n = name(id)?.trim();
  return n == null || n.isEmpty ? shortTokenId(id) : n;
}

String activityTitleFor(WalletActivity a, {required TokenNamer name}) {
  final t = appL10n;
  return switch (a.category) {
    ActivityCategory.received => t.activityTitleReceived,
    ActivityCategory.sent => t.activityTitleSent,
    ActivityCategory.moved => t.activityTitleMoved,
    ActivityCategory.consolidated => t.activityTitleConsolidated,
    ActivityCategory.burned => t.activityTitleBurned(a.burned.length),
    ActivityCategory.minted => t.activityTitleIssued(a.minted.length),
    ActivityCategory.contract => t.activityTitleContractInteraction,
  };
}

String? _who(WalletActivity a) {
  final t = appL10n;
  String list(bool from, List<String> addresses) {
    final first = addresses.first;
    final more = addresses.length - 1;
    final short = _short(first);
    final head = isContractAddress(first)
        ? (from ? t.activityFromContract(short) : t.activityToContract(short))
        : (from ? t.activityFrom(short) : t.activityTo(short));
    return more > 0 ? t.activityAndMore(head, '$more') : head;
  }

  return switch (a.category) {
    ActivityCategory.received when a.protocol == 'argus_fee' => t.activityArgusAppFee,
    ActivityCategory.received => a.senders.isEmpty ? null : list(true, a.senders),
    ActivityCategory.sent => a.recipients.isEmpty ? null : list(false, a.recipients),
    ActivityCategory.moved || ActivityCategory.consolidated => t.activityBetweenYourAddresses,
    ActivityCategory.burned || ActivityCategory.minted => null,
    ActivityCategory.contract => a.contract != null
        ? t.activityContract(_short(a.contract!))
        : (a.recipients.isNotEmpty ? list(false, a.recipients) : null),
  };
}

/// The fee the wallet paid, as a labelled figure; null when it paid none.
ActivityFigure? _feeFigure(WalletActivity a) {
  final fee = -a.erg;
  return fee > BigInt.zero ? ActivityFigure([ActivityLeg(null, fee)], label: appL10n.activityFeeLabel) : null;
}

/// The amount column of [a].
({ActivityFigure primary, ActivityFigure? secondary}) activityFigures(WalletActivity a) {
  final ergLeg = a.erg == BigInt.zero ? null : ActivityLeg(null, a.erg);
  List<ActivityLeg> pos(List<ActivityLeg> l) => l;
  List<ActivityLeg> neg(List<ActivityLeg> l) => [for (final t in l) ActivityLeg(t.tokenId, -t.amount)];
  switch (a.category) {
    case ActivityCategory.moved:
    case ActivityCategory.consolidated:
      return (
        primary: _feeFigure(a) ?? ActivityFigure([ActivityLeg(null, BigInt.zero)], label: appL10n.activityFeeLabel),
        secondary: null,
      );
    case ActivityCategory.burned:
      return (primary: ActivityFigure(neg(a.burned)), secondary: _feeFigure(a));
    case ActivityCategory.minted:
      return (primary: ActivityFigure(pos(a.minted)), secondary: _feeFigure(a));
    case ActivityCategory.received:
      final tokens = [...a.minted, ...a.received];
      if (tokens.isEmpty) return (primary: ActivityFigure([?ergLeg]), secondary: null);
      return (primary: ActivityFigure(tokens), secondary: ergLeg == null ? null : ActivityFigure([ergLeg]));
    case ActivityCategory.sent:
      final tokens = [...neg(a.sent), ...neg(a.burned)];
      if (tokens.isEmpty) {
        final ins = [...a.received];
        return (
          primary: ActivityFigure([?ergLeg]),
          secondary: ins.isEmpty ? null : ActivityFigure(ins),
        );
      }
      return (primary: ActivityFigure(tokens), secondary: ergLeg == null ? null : ActivityFigure([ergLeg]));
    case ActivityCategory.contract:
      final legs = [...a.inLegs, ...a.outLegs];
      if (legs.isEmpty) return (primary: _feeFigure(a) ?? ActivityFigure([?ergLeg]), secondary: null);
      final tokens = legs.where((l) => !l.isErg).toList();
      return tokens.isEmpty || ergLeg == null
          ? (primary: ActivityFigure(legs), secondary: null)
          : (primary: ActivityFigure(tokens), secondary: ActivityFigure([ergLeg]));
  }
}

/// [tx] in words and figures: from its flows when it has them, else the
/// legacy reading.
ActivityView describeActivity(Map tx, {required TokenNamer name}) {
  final a = walletActivity(tx);
  if (a != null) {
    final f = activityFigures(a);
    // Named tokens lead, as in [tokenSummary]: the words a person can read
    // are the ones a row keeps.
    bool known(ActivityLeg l) => l.isErg || (name(l.tokenId!)?.trim().isNotEmpty ?? false);
    ActivityFigure order(ActivityFigure f) =>
        ActivityFigure([...f.legs.where(known), ...f.legs.where((l) => !known(l))], label: f.label);
    return ActivityView(
      kind: a.kind,
      title: activityTitleFor(a, name: name),
      who: _who(a),
      primary: order(f.primary),
      secondary: f.secondary == null ? null : order(f.secondary!),
      activity: a,
    );
  }
  return _legacyView(Map<String, dynamic>.from(tx));
}

ActivityView _legacyView(Map<String, dynamic> tx) {
  final kind = classifyActivity(tx);
  final nano = (tx['value_nano_erg'] as num?)?.toInt() ?? 0;
  List<ActivityLeg> tokens(String key, int sign) => [
        for (final t in _tokens(tx, key))
          ActivityLeg(t['token_id']?.toString() ?? '', _big(t['amount']) * BigInt.from(sign)),
      ];
  final erg = nano == 0 ? null : ActivityLeg(null, BigInt.from(nano));
  final received = tokens('tokens_received', 1), sent = tokens('tokens_sent', -1);
  final legs = [?erg, ...received, ...sent];
  final counterparty = tx['counterparty']?.toString();
  final outgoing = kind == ActivityKind.sent || (kind != ActivityKind.received && nano < 0);
  final who = counterparty == null || counterparty.isEmpty
      ? null
      : isContractAddress(counterparty)
          ? appL10n.activityContract(_short(counterparty))
          : outgoing
              ? appL10n.activityTo(_short(counterparty))
              : appL10n.activityFrom(_short(counterparty));
  return ActivityView(
    kind: kind,
    title: activityTitle(kind),
    who: who,
    primary: ActivityFigure(legs.isEmpty ? const [] : [legs.first]),
    secondary: legs.length < 2 ? null : ActivityFigure(legs.sublist(1)),
  );
}

// ─── Legacy reading ──────────────────────────────────────────────────────

List<Map> _tokens(Map tx, String key) =>
    (tx[key] as List?)?.whereType<Map>().toList() ?? const [];

/// The icon family of [tx]. From its flows when it has them.
ActivityKind classifyActivity(Map tx) {
  if (walletActivity(tx) case final a?) return a.kind;
  final nano = (tx['value_nano_erg'] as num?)?.toInt() ?? 0;
  final counterparty = tx['counterparty']?.toString();
  final tokensOut = _tokens(tx, 'tokens_sent').isNotEmpty;
  if (counterparty == null || counterparty.isEmpty) {
    return nano > 0 ? ActivityKind.received : ActivityKind.selfTransfer;
  }
  if (isContractAddress(counterparty)) {
    if (nano > 0 && !tokensOut) return ActivityKind.received;
    if (nano < 0 && tokensOut) return ActivityKind.sent;
    return ActivityKind.contract;
  }
  return nano < 0 || (nano == 0 && tokensOut) ? ActivityKind.sent : ActivityKind.received;
}

String activityTitle(ActivityKind kind) => switch (kind) {
      ActivityKind.received => appL10n.activityTitleReceived,
      ActivityKind.sent => appL10n.activityTitleSent,
      ActivityKind.selfTransfer => appL10n.activityTitleMoved,
      ActivityKind.contract => appL10n.activityTitleContract,
    };

/// The most tokens a row names before summing up the rest.
const namedTokensPerRow = 2;

/// The tokens of one row, by name: `69 COMET`, `69 COMET + 1.5 SigUSD`, and
/// past [namedTokensPerRow], the first ones then `+ 3 more tokens`. Null for
/// none.
///
/// [name] and [decimals] are the token lookup's answers. A token with no
/// name shows its short id; one whose decimals nothing knows is shown in raw
/// units and says so. Named tokens come first, otherwise in the order the
/// transaction lists them, so the words a person can read are the ones the
/// row keeps.
String? tokenSummary(
  List<Map> tokens, {
  required String? Function(String id) name,
  required int? Function(String id) decimals,
}) {
  if (tokens.isEmpty) return null;
  String? named(String id) {
    final n = name(id)?.trim();
    return n == null || n.isEmpty ? null : n;
  }

  final entries = [
    for (final t in tokens)
      (
        id: t['token_id']?.toString() ?? '',
        amount: _big(t['amount']),
      ),
  ];
  final ordered = [
    ...entries.where((e) => named(e.id) != null),
    ...entries.where((e) => named(e.id) == null),
  ];
  final more = ordered.length - namedTokensPerRow;
  return [
    for (final e in ordered.take(namedTokensPerRow))
      unitsWithLabel(e.amount, decimals(e.id), named(e.id) ?? shortTokenId(e.id)),
    if (more > 0) appL10n.activityMoreTokens(more),
  ].join(' + ');
}

/// One unsigned figure: "1.5 SigUSD", "0.0011 ERG".
String legAmountText(
  ActivityLeg leg, {
  required TokenNamer name,
  required TokenScaler decimals,
}) =>
    leg.isErg
        ? formatErg(leg.amount.abs().toInt(), unit: true, maxFrac: 4)
        : unitsWithLabel(leg.amount.abs(), decimals(leg.tokenId!), _name(name, leg.tokenId));

/// One figure line in words: "Fee 0.0011 ERG", "100 Test Asset 3 + 5 more".
String figureText(
  ActivityFigure f, {
  required TokenNamer name,
  required TokenScaler decimals,
}) {
  if (f.legs.isEmpty) return formatErg(0, unit: true);
  final first = legAmountText(f.legs.first, name: name, decimals: decimals);
  final more = f.legs.length - 1;
  return [
    if (f.label != null) f.label!,
    first,
    if (more > 0) appL10n.activityPlusMore('$more'),
  ].join(' ');
}

/// Second line of an Activity tab row: what moved, e.g. `100 Test Asset 3
/// + 5 more · fee 0.0011 ERG`.
String activityLine(
  Map<String, dynamic> tx, {
  required String? Function(String id) name,
  required int? Function(String id) decimals,
  bool hidden = false,
}) {
  if (hidden) return '••••';
  final view = describeActivity(tx, name: name);
  final a = view.activity;
  if (a == null) return _legacyLine(tx, name: name, decimals: decimals);
  String text(ActivityFigure f) => figureText(f, name: name, decimals: decimals);
  final secondary = view.secondary;
  final second = secondary == null
      ? null
      : secondary.label == null
          ? text(secondary)
          : text(ActivityFigure(secondary.legs, label: secondary.label!.toLowerCase()));
  return [text(view.primary), ?second].join(' · ');
}

String _legacyLine(
  Map<String, dynamic> tx, {
  required String? Function(String id) name,
  required int? Function(String id) decimals,
}) {
  final nano = (tx['value_nano_erg'] as num?)?.toInt() ?? 0;
  final sent = _tokens(tx, 'tokens_sent');
  final received = _tokens(tx, 'tokens_received');
  String erg(int n) => formatErg(n.abs(), unit: true, maxFrac: 4);
  String? summary(List<Map> t) => tokenSummary(t, name: name, decimals: decimals);

  final tokens = nano < 0 || (nano == 0 && sent.isNotEmpty) ? sent : received;
  final parts = <String>[
    if (summary(tokens) case final t?) t,
    if (nano != 0) erg(nano),
  ];
  return parts.isEmpty ? formatErg(0, unit: true) : parts.join(' + ');
}

/// Newest first, as one total order: rows not yet in a block (height 0)
/// come first, then by height descending, and rows on the same height (or
/// all pending) by timestamp descending.
int compareActivityRows(Map<String, dynamic> a, Map<String, dynamic> b) {
  int rank(Map<String, dynamic> r) {
    final h = (r['height'] as num?)?.toInt() ?? 0;
    return h > 0 ? h : 0x7fffffff;
  }

  final byHeight = rank(b).compareTo(rank(a));
  if (byHeight != 0) return byHeight;
  final ta = (a['timestamp'] as num?)?.toInt() ?? 0;
  final tb = (b['timestamp'] as num?)?.toInt() ?? 0;
  return tb.compareTo(ta);
}
