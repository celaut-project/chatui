import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../bridge/api/celaut.dart';
import '../../bridge/api/celaut_service.dart';
import '../../celaut/celaut_strings.dart';
import '../../l10n/l10n.dart';

/// Open the first web slot of [instance] in the browser of the phone.
///
/// The slot gets a local port (`celautOpenTunnel`) on 127.0.0.1, and the browser goes to
/// it. Each TCP connection of the browser is one tunnel stream, and the node charges each
/// one. The port stays while the app runs. [openTunnel] and [launch] are for tests.
Future<void> openWebInBrowser(
  BuildContext context,
  InstanceListView instance, {
  Future<int> Function(String instanceId, int slot)? openTunnel,
  Future<bool> Function(Uri uri)? launch,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  if (instance.webSlots.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(l.chatsNoInterface)));
    return;
  }
  try {
    final port =
        await (openTunnel ??
            (id, s) => celautOpenTunnel(instanceId: id, slot: s))(
          instance.instanceId,
          instance.webSlots.first,
        );
    final open =
        launch ?? (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!await open(Uri.parse('http://127.0.0.1:$port/'))) {
      messenger.showSnackBar(SnackBar(content: Text(l.chatsBrowserFailed)));
    }
  } on CelautError catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(CelautStrings.errorText(e.kind))),
    );
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l.chatsBrowserFailed)));
  }
}
