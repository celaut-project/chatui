import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../celaut/auto_top_up.dart';
import '../../celaut/celaut_format.dart';
import '../../celaut/payers.dart';
import '../../l10n/l10n.dart';
import '../home/home_style.dart';

/// Settings, Compute, "Automatic top-up" (Josemi, 2026-10-23): the switch, off by
/// default, the threshold and the amount ([AutoTopUp]).
///
/// To turn it on, the user opens the wallet (fingerprint or screen lock): the app then moves
/// credit of the user without asking each time. It never pays a node by itself: a top-up
/// moves credit that the app already has on the node, and with too little credit the app
/// asks the user, who can make a deposit with its own confirmation.
class AutoTopUpScreen extends StatefulWidget {
  const AutoTopUpScreen({super.key, this.topUp, this.wallets = const AppFullWallets()});

  /// The top-up of the app. Tests give their own.
  final AutoTopUp? topUp;

  final FullWallets wallets;

  @override
  State<AutoTopUpScreen> createState() => _AutoTopUpScreenState();
}

class _AutoTopUpScreenState extends State<AutoTopUpScreen> {
  late final AutoTopUp _topUp = widget.topUp ?? autoTopUp;
  final _threshold = TextEditingController();
  final _amount = TextEditingController();
  bool _ready = false;
  bool _on = false;

  @override
  void initState() {
    super.initState();
    _topUp.load().then((_) {
      if (!mounted) return;
      setState(() {
        _on = _topUp.on;
        _threshold.text = '${_topUp.threshold}';
        _amount.text = '${_topUp.amount}';
        _ready = true;
      });
    });
  }

  @override
  void dispose() {
    _threshold.dispose();
    _amount.dispose();
    super.dispose();
  }

  BigInt? _value(TextEditingController c, BigInt max) {
    final v = BigInt.tryParse(c.text.trim());
    if (v == null || v < AutoTopUp.minMu || v > max) return null;
    return v;
  }

  String? _error(TextEditingController c, BigInt max) => _value(c, max) == null
      ? context.l10n.celautTopUpRange(muOrUnknown('${AutoTopUp.minMu}'), muOrUnknown('$max'))
      : null;

  Future<void> _save({bool? on}) async {
    final threshold = _value(_threshold, AutoTopUp.maxThreshold);
    final amount = _value(_amount, AutoTopUp.maxAmount);
    if (threshold == null || amount == null) {
      setState(() {});
      return;
    }
    final turnOn = on ?? _on;
    if (turnOn && !_topUp.on) {
      // The app will move credit without asking each time: the user says so with the key
      // of the wallet.
      if (!await ensureOpenFullWallet(context, widget.wallets)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.celautOpenFullWalletNeeded)),
          );
        }
        return;
      }
    }
    await _topUp.save(on: turnOn, threshold: threshold, amount: amount);
    if (mounted) setState(() => _on = turnOn);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = HomeText.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.celautTopUpTitle)),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.fromLTRB(homeGutter, 8, homeGutter, 32 + MediaQuery.paddingOf(context).bottom),
              children: [
                SwitchListTile(
                  key: const Key('top-up-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.celautTopUpSwitch),
                  value: _on,
                  onChanged: (v) => _save(on: v),
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('top-up-threshold'),
                  controller: _threshold,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    labelText: l.celautTopUpThreshold,
                    suffixText: 'MU',
                    errorText: _error(_threshold, AutoTopUp.maxThreshold),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('top-up-amount'),
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _save(),
                  decoration: InputDecoration(
                    labelText: l.celautTopUpAmount,
                    suffixText: 'MU',
                    errorText: _error(_amount, AutoTopUp.maxAmount),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    key: const Key('top-up-save'),
                    // The theme asks for the full width; this button is alone in its row.
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                    onPressed: _save,
                    child: Text(l.commonSave),
                  ),
                ),
                const SizedBox(height: 20),
                Text(l.celautTopUpNote, key: const Key('top-up-note'), style: t.secondary),
              ],
            ),
    );
  }
}
