import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../bridge/api/celaut.dart';
import '../../bridge/api/celaut_network.dart';
import '../../celaut/network_route.dart';
import '../../celaut/network_strings.dart';
import '../settings/settings_shared.dart';
import '../widgets/soft_card.dart';

/// Settings, Developer, Tor (milestone M5): no Tor, the Tor client inside the app, or an
/// external SOCKS5 proxy. The state is read from the Rust core every second.
class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key, NetworkRoute? route}) : _route = route;

  final NetworkRoute? _route;

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen> {
  late final NetworkRoute _route = widget._route ?? networkRoute;
  late final TextEditingController _socks = TextEditingController(text: _route.socksAddress);
  late NetworkMode _mode = _route.mode;
  Timer? _poll;
  String? _socksError;
  String? _error;
  bool _applying = false;
  late NetworkStatusView _status = _route.status;

  @override
  void initState() {
    super.initState();
    _route.load().then((_) {
      if (!mounted) return;
      setState(() {
        _mode = _route.mode;
        _socks.text = _route.socksAddress;
      });
    });
    _poll = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _status = _route.status);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _socks.dispose();
    super.dispose();
  }

  /// An IP address and a port: `127.0.0.1:9050` or `[::1]:9050`.
  static bool _validSocks(String text) {
    final match = RegExp(r'^(?:\[([^\]]+)\]|([^:\[\]]+)):(\d{1,5})$').firstMatch(text.trim());
    if (match == null) return false;
    final host = match.group(1) ?? match.group(2)!;
    final port = int.parse(match.group(3)!);
    return InternetAddress.tryParse(host) != null && port >= 1 && port <= 65535;
  }

  Future<void> _apply() async {
    final socks = _socks.text.trim();
    if (_mode == NetworkMode.socks && !_validSocks(socks)) {
      setState(() => _socksError = NetworkStrings.socksInvalid);
      return;
    }
    setState(() {
      _socksError = null;
      _error = null;
      _applying = true;
    });
    try {
      await _route.choose(_mode, socksAddress: socks);
    } on CelautError catch (e) {
      // The core refused the settings and blocked the connections.
      if (mounted) setState(() => _error = e.message);
    } on StateError {
      if (mounted) setState(() => _error = NetworkStrings.saveFailed);
    } finally {
      if (mounted) {
        setState(() {
          _applying = false;
          _status = _route.status;
        });
      }
    }
  }

  Widget _option(NetworkMode mode, String title, {String? note}) {
    return RadioListTile<NetworkMode>(
      key: Key('network-${mode.name}'),
      value: mode,
      title: Text(title),
      subtitle: note == null ? null : Text(note),
      contentPadding: EdgeInsets.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      title: NetworkStrings.screenTitle,
      children: [
        const SettingsNote(NetworkStrings.intro),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RadioGroup<NetworkMode>(
                groupValue: _mode,
                onChanged: (mode) {
                  if (mode != null && !_applying) setState(() => _mode = mode);
                },
                child: Column(
                  children: [
                    _option(NetworkMode.off, NetworkStrings.optionOff),
                    _option(
                      NetworkMode.embedded,
                      NetworkStrings.optionEmbedded,
                      note: NetworkStrings.optionEmbeddedNote,
                    ),
                    _option(
                      NetworkMode.socks,
                      NetworkStrings.optionSocks,
                      note: NetworkStrings.optionSocksNote,
                    ),
                  ],
                ),
              ),
              if (_mode == NetworkMode.socks) ...[
                const SizedBox(height: 8),
                TextField(
                  key: const Key('network-socks-address'),
                  controller: _socks,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: NetworkStrings.socksLabel,
                    hintText: NetworkStrings.socksHint,
                    errorText: _socksError,
                    errorMaxLines: 2,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('network-apply'),
                onPressed: _applying ? null : _apply,
                child: const Text(NetworkStrings.apply),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(NetworkStrings.statusTitle, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(NetworkStrings.status(_status), key: const Key('network-status')),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  key: const Key('network-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
