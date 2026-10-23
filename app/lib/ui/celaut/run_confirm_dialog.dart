import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../bridge/api/celaut_service.dart';
import '../../celaut/celaut_format.dart';
import '../../celaut/launcher.dart';
import '../../celaut/service_strings.dart';
import '../../l10n/l10n.dart';
import '../home/home_style.dart';

/// What the user chose in the confirmation of a launch.
class RunChoice {
  const RunChoice({this.minSurvival});

  /// The least time that the instance must run; null for the default start balance.
  final Duration? minSurvival;
}

/// The last minimum time that the user typed, in minutes, for the next confirmation.
const minSurvivalKey = 'celaut_min_survival_minutes_v1';

/// "5 min", "2 h 10 min", "3 d 4 h".
String formatSurvival(Duration d) {
  final days = d.inDays, hours = d.inHours % 24, minutes = d.inMinutes % 60;
  if (days > 0) return hours > 0 ? '$days d $hours h' : '$days d';
  if (hours > 0) return minutes > 0 ? '$hours h $minutes min' : '$hours h';
  return '${d.inMinutes} min';
}

/// Ask before a launch: an instance uses credit until it stops. The dialog shows the node
/// that the balancer would use now, with its start cost, and a field for the least time
/// that the instance must run (Josemi, 2026-10-23). With a time, the estimate is the start
/// cost with the balance for that time on that node ([survivalBalanceMu]); without one,
/// the app uses its default start balance, and the dialog says how long it lasts there.
/// Gives the choice of the user, or null if the user cancelled.
Future<RunChoice?> showRunConfirmation(
  BuildContext context, {
  required String name,
  required Future<QuoteView?> quote,
  required void Function(QuoteView? best) onDetails,
}) async {
  String initial = '';
  try {
    final prefs = await SharedPreferences.getInstance();
    final kept = prefs.getInt(minSurvivalKey);
    if (kept != null && kept > 0) initial = '$kept';
  } catch (_) {
    // No preferences (a test): the field starts empty.
  }
  if (!context.mounted) return null;
  final choice = await showDialog<RunChoice>(
    context: context,
    builder: (_) => _RunConfirmDialog(name: name, quote: quote, onDetails: onDetails, initial: initial),
  );
  if (choice != null) {
    try {
      final prefs = await SharedPreferences.getInstance();
      final minutes = choice.minSurvival?.inMinutes;
      if (minutes == null) {
        await prefs.remove(minSurvivalKey);
      } else {
        await prefs.setInt(minSurvivalKey, minutes);
      }
    } catch (_) {
      // Not kept: the next confirmation starts empty.
    }
  }
  return choice;
}

class _RunConfirmDialog extends StatefulWidget {
  const _RunConfirmDialog({
    required this.name,
    required this.quote,
    required this.onDetails,
    required this.initial,
  });

  final String name;
  final Future<QuoteView?> quote;
  final void Function(QuoteView? best) onDetails;
  final String initial;

  @override
  State<_RunConfirmDialog> createState() => _RunConfirmDialogState();
}

class _RunConfirmDialogState extends State<_RunConfirmDialog> {
  late final _minutes = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _minutes.dispose();
    super.dispose();
  }

  /// The time typed, null if the field is empty; [Duration.zero] marks a wrong value.
  Duration? get _survival {
    final text = _minutes.text.trim();
    if (text.isEmpty) return null;
    final minutes = int.tryParse(text);
    if (minutes == null || minutes <= 0) return Duration.zero;
    final d = Duration(minutes: minutes);
    return d > maxMinSurvival ? Duration.zero : d;
  }

  String _estimate(BuildContext context, QuoteView best) {
    final l = context.l10n;
    final survival = _survival;
    final defaultBalance = BigInt.parse(ServiceStrings.initialDefault);
    if (survival == null) {
      final lasts = survivalOf(best, defaultBalance);
      return lasts == null
          ? l.celautRunDefaultBalance(muOrUnknown(ServiceStrings.initialDefault))
          : l.celautRunDefaultBalanceLasts(muOrUnknown(ServiceStrings.initialDefault), formatSurvival(lasts));
    }
    final need = survivalBalanceMu(best, survival);
    if (need == null) return l.celautRunSurvivalNoPrice;
    final cost = startCostWith(best, defaultBalance, need);
    return l.celautRunSurvivalEstimate(
      muOrUnknown(cost?.toString()),
      muOrUnknown(need.toString()),
      formatSurvival(survival),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final t = HomeText.of(context);
    final survival = _survival;
    final wrong = survival == Duration.zero;
    return AlertDialog(
      key: const Key('run-confirm'),
      title: Text(l.celautRunConfirmTitle(widget.name)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.celautRunConfirmBody),
            const SizedBox(height: 12),
            TextField(
              key: const Key('run-confirm-minutes'),
              controller: _minutes,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 5,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: l.celautRunSurvivalLabel,
                hintText: l.celautRunSurvivalHint,
                suffixText: 'min',
                errorText: wrong ? l.celautRunSurvivalWrong : null,
                counterText: '',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            FutureBuilder<QuoteView?>(
              future: widget.quote,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return Text(l.celautRunPreviewLoading, style: t.secondary);
                }
                final best = snapshot.hasError ? null : snapshot.data;
                if (best == null) {
                  return Text(l.celautRunConfirmNoQuote, key: const Key('run-confirm-quote'), style: t.secondary);
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.celautRunPreview('${best.address.host}:${best.address.port}', muOrUnknown(best.costMu)),
                      key: const Key('run-confirm-quote'),
                      style: t.secondary,
                    ),
                    if (!wrong) ...[
                      const SizedBox(height: 4),
                      Text(_estimate(context, best), key: const Key('run-confirm-survival'), style: t.secondary),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('run-confirm-details'),
          onPressed: () async {
            QuoteView? best;
            try {
              best = await widget.quote;
            } catch (_) {
              // No quote: the details read the library file, or say that there is none.
            }
            widget.onDetails(best);
          },
          child: Text(l.celautRunConfirmDetails),
        ),
        TextButton(
          key: const Key('run-confirm-cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(l.celautSendCancel),
        ),
        FilledButton(
          key: const Key('run-confirm-ok'),
          onPressed: wrong ? null : () => Navigator.pop(context, RunChoice(minSurvival: survival)),
          child: Text(l.celautRunButton),
        ),
      ],
    );
  }
}
