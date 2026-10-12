import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/l10n.dart';
import 'policy.dart';

typedef GatewayLookup = Future<List<InternetAddress>> Function(String host);

class PreviewSettings extends ChangeNotifier {
  String? _gateway;
  bool _never = false;
  int revision = 0;
  String? get gateway => _gateway;
  bool get never => _never;
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _never = prefs.getBool('preview_never') ?? false;
    final saved = prefs.getString('preview_gateway');
    // No DNS at startup. Revalidate syntax here and DNS at each explicit load.
    try {
      _gateway = saved == null ? null : gatewayOrigin(saved).toString();
    } catch (_) {
      _gateway = null;
    }
    revision++;
    notifyListeners();
  }

  Future<void> setNever(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setBool('preview_never', value))
      refuse(appL10n.previewSaveSettingFailed);
    _never = value;
    revision++;
    notifyListeners();
  }

  Future<void> setGateway(String text, {GatewayLookup? lookup}) async {
    final value = text.trim();
    final origin = value.isEmpty ? null : gatewayOrigin(value);
    if (origin != null) await resolveGateway(origin, lookup: lookup);
    final prefs = await SharedPreferences.getInstance();
    final ok = origin == null
        ? await prefs.remove('preview_gateway')
        : await prefs.setString('preview_gateway', origin.toString());
    if (!ok) refuse(appL10n.previewSaveGatewayFailed);
    _gateway = origin?.toString();
    revision++;
    notifyListeners();
  }
}

Future<InternetAddress> resolveGateway(
  Uri origin, {
  GatewayLookup? lookup,
}) async {
  final host = origin.host.replaceAll('[', '').replaceAll(']', '');
  final literal = InternetAddress.tryParse(host);
  final addresses = literal == null
      ? await (lookup ?? InternetAddress.lookup)(
          host,
        ).timeout(const Duration(seconds: 5))
      : [literal];
  if (addresses.isEmpty || addresses.any((a) => !publicAddress(a)))
    refuse(appL10n.previewGatewayNotPublic);
  // Keep the resolver's host as well as the validated numeric bytes.
  return addresses.first;
}

/// Dedicated one-shot transport. No shared node client, proxy, credentials,
/// cookies, redirects, automatic decompression, disk files or fallback hosts.
class PreviewTransport {
  HttpClient? _client;
  bool _cancelled = false;
  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  Future<(Uint8List, String)> fetch(Uri origin, List<String> path) async {
    try {
      return await _fetch(origin, path).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          cancel();
          refuse(appL10n.previewRequestTimedOut);
        },
      );
    } finally {
      _client?.close(force: true);
    }
  }

  Future<(Uint8List, String)> _fetch(Uri origin, List<String> path) async {
    final connecting = Stopwatch()..start();
    final address = await resolveGateway(origin);
    final remaining = const Duration(seconds: 5) - connecting.elapsed;
    if (remaining <= Duration.zero) refuse(appL10n.previewConnectionTimedOut);
    if (_cancelled) refuse(appL10n.previewCancelled);
    final client = _client = HttpClient()
      ..autoUncompress = false
      ..userAgent = null
      ..connectionTimeout = remaining
      ..findProxy = (_) => 'DIRECT';
    var connected = false;
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      if (_cancelled ||
          connected ||
          uri.host != origin.host ||
          uri.port != 443 ||
          proxyHost != null)
        refuse(appL10n.previewConnectionRefused);
      connected = true; // Prevent the HTTP client's implicit reconnect.
      final host = origin.host.replaceAll('[', '').replaceAll(']', '');
      if (address.host != host) refuse(appL10n.previewHostBindingFailed);
      // InternetAddress pins routing to its numeric bytes and retains the
      // lookup hostname for SNI/certificate verification. No second lookup.
      return SecureSocket.startConnect(address, 443);
    };
    final request = await client
        .getUrl(origin.replace(pathSegments: path))
        .timeout(
          remaining,
          onTimeout: () {
            cancel();
            refuse(appL10n.previewConnectionTimedOut);
          },
        );
    if (_cancelled) {
      request.abort();
      refuse(appL10n.previewCancelled);
    }
    request.followRedirects = false;
    request.persistentConnection = false;
    request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
    request.headers.set(HttpHeaders.acceptHeader, 'image/png, image/jpeg');
    final response = await request.close();
    return readPreviewResponse(
      response.statusCode,
      response.headers.value(HttpHeaders.contentTypeHeader) ?? '',
      response.headers.value(HttpHeaders.contentEncodingHeader),
      response.contentLength,
      response,
    );
  }
}

/// Shared response gate used by the real streaming transport and hostile fixtures.
Future<(Uint8List, String)> readPreviewResponse(
  int status,
  String contentType,
  String? encoding,
  int contentLength,
  Stream<List<int>> stream,
) async {
  if (status >= 300 && status < 400) refuse(appL10n.previewRedirectBlocked);
  if (status != 200) refuse(appL10n.previewNoArtwork);
  if (encoding != null && encoding.trim().toLowerCase() != 'identity')
    refuse(appL10n.previewCompressionRefused);
  if (contentLength > maxPreviewBytes) refuse(appL10n.previewArtworkTooLarge);
  final mime = contentType.split(';').first.trim().toLowerCase();
  if (mime != 'image/png' && mime != 'image/jpeg')
    refuse(appL10n.previewStaticOnly);
  final body = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    if (chunk.length > maxPreviewBytes - body.length)
      refuse(appL10n.previewArtworkTooLarge);
    body.add(chunk);
  }
  return (body.takeBytes(), mime);
}

class PreviewBytes {
  PreviewBytes(this.bytes, this.info);
  final Uint8List bytes;
  final CheckedImage info;
}

/// All jobs, including cancelled native decodes still returning, share a slot.
/// Flutter does not expose interruption of an in-flight native image codec.
class PreviewJob {
  PreviewJob({required this.allowed, PreviewTransport? transport})
    : _transport = transport ?? PreviewTransport();
  final bool Function() allowed;
  final PreviewTransport _transport;
  bool cancelled = false;
  static bool _busy = false;
  void cancel() {
    cancelled = true;
    _transport.cancel();
  }

  void check() {
    if (cancelled || !allowed()) refuse(appL10n.previewCancelled);
  }

  Future<PreviewBytes> fetch(
    String gateway,
    String artwork,
    String? hash,
  ) async {
    check();
    final path = ipfsPath(
      artwork,
    ); // Reject issuer HTTPS before DNS/client creation.
    final origin = gatewayOrigin(gateway);
    if (_busy) refuse(appL10n.previewBusy);
    _busy = true;
    try {
      final (bytes, mime) = await _transport.fetch(origin, path);
      check();
      // The isolate starts with English texts: give it the app's language.
      final locale = appL10n.localeName;
      final info = await Isolate.run(() {
        setAppLocale(ui.Locale(locale));
        return inspectImage(bytes, mime, hash);
      });
      check();
      return PreviewBytes(bytes, info);
    } finally {
      _busy = false;
    }
  }

  Future<ui.Image> decode(
    PreviewBytes source, {
    bool withoutIntegrity = false,
    bool thumbnail = false,
  }) async {
    check();
    if (!source.info.matchesHash && !withoutIntegrity)
      refuse(appL10n.previewIntegrityConsentRequired);
    if (_busy) refuse(appL10n.previewBusy);
    _busy = true;
    ui.Codec? codec;
    ui.Image? image;
    try {
      final edge = thumbnail ? 256 : 1024;
      final w = source.info.width, h = source.info.height;
      final scale = edge / (w > h ? w : h);
      // Flutter schedules codec work on the engine's image decoding worker.
      // Both axes are capped; Image.memory/global ImageCache are not involved.
      codec = await ui.instantiateImageCodec(
        source.bytes,
        targetWidth: scale < 1 ? (w * scale).floor().clamp(1, edge) : w,
        targetHeight: scale < 1 ? (h * scale).floor().clamp(1, edge) : h,
        allowUpscaling: false,
      );
      check();
      if (codec.frameCount != 1) refuse(appL10n.previewAnimatedUnsupported);
      image = (await codec.getNextFrame()).image;
      check();
      if (image.width > edge || image.height > edge)
        refuse(appL10n.previewDecodedTooLarge);
      final result = image;
      image = null;
      return result;
    } finally {
      image?.dispose();
      codec?.dispose();
      _busy = false;
    }
  }
}

final previewSettings = PreviewSettings();
