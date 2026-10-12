import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

import '../l10n/l10n.dart';
import '../services/session_lock.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _done = false;
  bool _cameraFailed = false;

  @override
  void initState() {
    super.initState();
    sessionLock.suppress();
  }

  @override
  void dispose() {
    sessionLock.release();
    super.dispose();
  }

  void _onScan(Code code) {
    if (_done || !mounted || !code.isValid) return;
    final raw = code.text?.trim();
    if (raw == null || raw.isEmpty) return;
    _done = true;
    Navigator.pop(context, raw);
  }

  // A phone without a flash also reports an error here; the camera still works.
  void _onControllerCreated(CameraController? controller, Exception? error) {
    if (error == null || !mounted) return;
    if (error.toString().contains('setFlashModeFailed')) return;
    setState(() => _cameraFailed = true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.scanTitle)),
      body: _cameraFailed
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      context.l10n.scanCameraUnavailable,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.l10n.scanBack),
                    ),
                  ],
                ),
              ),
            )
          : ReaderWidget(
              codeFormat: Format.qrCode,
              onScan: _onScan,
              onControllerCreated: _onControllerCreated,
              showGallery: false,
              showToggleCamera: false,
              scanDelaySuccess: Duration.zero,
            ),
    );
  }
}
