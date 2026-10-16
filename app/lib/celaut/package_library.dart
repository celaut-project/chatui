import 'dart:io';

import 'package:flutter/services.dart';

import '../bridge/api/celaut_package.dart';
import '../services/secure_storage.dart';
import 'package_channel.dart';
import 'service_transfer.dart';

/// The service files that the user loaded into the app (`docs/celaut/package.md`).
///
/// A file is loaded once: the app checks it, keeps it in a private directory under the id
/// of its service, and records its name. From then on the service can be run, and given to
/// a node that does not have it, with no need to choose the file again. The calls are
/// injected so that tests need no Rust.
class PackageLibrary {
  PackageLibrary({
    Future<LibraryPackageView> Function(String path, String name, String dir)? importPackage,
    List<LibraryPackageView> Function()? list,
    Future<void> Function(String serviceId)? remove,
    Future<String?> Function()? privateDir,
  })  : _import = importPackage ??
            ((path, name, dir) => celautImportPackage(path: path, name: name, dir: dir)),
        _list = list ?? celautPackages,
        _remove = remove ?? ((id) => celautRemovePackage(serviceIdHex: id)),
        _privateDir = privateDir ?? _appPrivateDir;

  final Future<LibraryPackageView> Function(String, String, String) _import;
  final List<LibraryPackageView> Function() _list;
  final Future<void> Function(String) _remove;
  final Future<String?> Function() _privateDir;

  /// The directory of the Celaut database: private to the app.
  static Future<String?> _appPrivateDir() async {
    try {
      final path = await SecureStorageService.celautDbPath();
      if (path == null || path.isEmpty) return null;
      return File(path).parent.path;
    } on MissingPluginException {
      return null;
    }
  }

  /// The loaded services, by name.
  List<LibraryPackageView> list() => _list();

  /// The loaded service with this id, if its file is there. A record whose file is gone is
  /// not a service that the app can send.
  LibraryPackageView? find(String serviceId) {
    final id = serviceId.toLowerCase();
    for (final p in _list()) {
      if (p.serviceId == id && p.present) return p;
    }
    return null;
  }

  /// Load the file that the user picked. Throws [CelautError] (`invalidInput` for a file
  /// that is not a package of a service) or [PackageRefused] when the app has no private
  /// directory.
  Future<LibraryPackageView> importPicked(PickedPackage picked) async {
    final dir = await _privateDir();
    if (dir == null || dir.isEmpty) throw const PackageRefused(PackageRefusal.noDirectory);
    return _import(picked.path, picked.name, dir);
  }

  /// Remove a loaded service: its file is deleted. The nodes that have it keep it.
  Future<void> remove(String serviceId) => _remove(serviceId);
}
