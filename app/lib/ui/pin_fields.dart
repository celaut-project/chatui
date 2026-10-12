import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../services/wallet_service.dart';

class PinFields extends StatelessWidget {
  final TextEditingController pin;
  final TextEditingController? confirm;
  final String label;
  final ValueChanged<String>? onSubmitted;

  const PinFields({
    super.key,
    required this.pin,
    this.confirm,
    this.label = 'PIN',
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    // Sized to the fields: inside a dialog a full-height column stretched
    // the dialog to the whole screen around two text fields.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _box(pin, label, helper: context.l10n.pinHelper, onSubmitted: onSubmitted),
        if (confirm != null) ...[
          const SizedBox(height: 12),
          _box(confirm!, context.l10n.pinConfirm, onSubmitted: onSubmitted),
        ],
      ],
    );
  }

  Widget _box(
    TextEditingController controller,
    String label, {
    String? helper,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: true,
      enableSuggestions: false,
      autocorrect: false,
      enableIMEPersonalizedLearning: false,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      maxLength: 32,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
      ),
    );
  }
}

String? pinError(String pin, [String? confirm]) {
  final err = validatePin(pin);
  if (err != null) return err;
  if (confirm != null && confirm != pin) return appL10n.pinMismatch;
  return null;
}
