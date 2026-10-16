import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A `.celaut.bee` file that the user picked, copied into the cache of the app.
@immutable
class PickedPackage {
  const PickedPackage({required this.path, required this.bytes, required this.name});

  final String path;
  final int bytes;

  /// The name of the file that the user chose.
  final String name;
}

/// The Android side of a transfer of a service (`docs/celaut/package.md`): the file
/// picker, and whether the network is metered. Off Android, or without the channel, it
/// does nothing and never throws.
abstract class PackageChannel {
  /// Let the user pick a `.celaut.bee` file. Null if the user cancels, or off Android.
  Future<PickedPackage?> pick();

  /// True on mobile data (a metered network).
  Future<bool> isMetered();
}

class AndroidPackageChannel implements PackageChannel {
  /// [android] stands in for the platform check in tests.
  const AndroidPackageChannel({bool? android}) : _android = android;

  static const channel = MethodChannel('org.celaut.chatui/package');

  final bool? _android;

  bool get _onAndroid => _android ?? Platform.isAndroid;

  @override
  Future<PickedPackage?> pick() async {
    if (!_onAndroid) return null;
    try {
      final answer = await channel.invokeMapMethod<String, Object?>('pickPackage');
      if (answer == null) return null;
      final path = answer['path'];
      final bytes = answer['bytes'];
      if (path is! String || bytes is! int) return null;
      final name = answer['name'];
      return PickedPackage(path: path, bytes: bytes, name: name is String ? name : path);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      debugPrint('The package was not picked: ${e.message}');
      return null;
    }
  }

  @override
  Future<bool> isMetered() async {
    if (!_onAndroid) return false;
    try {
      return await channel.invokeMethod<bool>('isMetered') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
