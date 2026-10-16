import 'dart:io';

import 'package:flutter/services.dart';

import '../bridge/api/celaut.dart';
import '../bridge/api/celaut_package.dart';
import '../bridge/api/celaut_service.dart';
import '../services/secure_storage.dart';
import 'launcher.dart';

/// Where the app can get a service that a node does not have (`docs/celaut/package.md`).
enum TransferSource {
  /// A node of the list that has it.
  node,

  /// A `.celaut.bee` file that the user picks.
  file,
}

/// What the app can offer after a launch where some nodes do not have the service.
class TransferOffer {
  const TransferOffer({required this.source, this.from, required this.to, required this.missing});

  final TransferSource source;

  /// The node that has the service, for [TransferSource.node].
  final NodeAddress? from;

  /// The node that gets the service: the first one that does not have it.
  final NodeAddress to;

  /// Every node that does not have the service.
  final List<NodeAddress> missing;
}

/// The refusals after which a node does have the service: nodo checks them only when it
/// has the service (`abstract_input_service_iterable.py`: `generate` runs only for a saved
/// service).
const _holderKinds = {
  CelautErrorKind.nodeClosed,
  CelautErrorKind.noRoom,
  CelautErrorKind.insufficientCredit,
  CelautErrorKind.rateLimited,
  CelautErrorKind.launchFailed,
  CelautErrorKind.policyRefused,
  CelautErrorKind.unsupportedArchitecture,
};

String _key(NodeAddress a) => '${a.host}:${a.port}';

/// The offer for a failed launch, or null when no node said that it lacks the service.
///
/// - The nodes that lack it: a quote failure or a skip with
///   [CelautErrorKind.serviceMissing].
/// - The nodes that have it: every node that gave a quote (a skip that is not
///   serviceMissing), and the quote failures with a reason that nodo gives only for a
///   service that it has. Not the unreachable ones: nothing is known of them.
TransferOffer? transferOfferOf(LaunchFailure failure) {
  final missing = <NodeAddress>[];
  final holders = <NodeAddress>[];
  void add(List<NodeAddress> list, NodeAddress a) {
    if (!list.any((x) => _key(x) == _key(a))) list.add(a);
  }

  for (final f in failure.quoteFailures) {
    if (f.kind == CelautErrorKind.serviceMissing) {
      add(missing, f.address);
    } else if (_holderKinds.contains(f.kind)) {
      add(holders, f.address);
    }
  }
  for (final s in failure.skipped) {
    if (s.error.kind == CelautErrorKind.serviceMissing) {
      add(missing, s.quote.address);
    } else {
      add(holders, s.quote.address);
    }
  }
  if (missing.isEmpty) return null;
  final from = holders.where((h) => !missing.any((m) => _key(m) == _key(h)));
  return TransferOffer(
    source: from.isEmpty ? TransferSource.file : TransferSource.node,
    from: from.isEmpty ? null : from.first,
    to: missing.first,
    missing: missing,
  );
}

/// Why the app does not send a package.
enum PackageRefusal {
  /// The package holds another service.
  otherService,

  /// The package has no Service part.
  noService,

  /// The app has no private directory for the package.
  noDirectory,
}

class PackageRefused implements Exception {
  const PackageRefused(this.reason);

  final PackageRefusal reason;

  @override
  String toString() => 'PackageRefused($reason)';
}

/// The transfer of a service to a node, with the calls injected for tests.
class ServiceTransfer {
  ServiceTransfer({
    Future<PackageView> Function(NodeAddress source, String serviceId, String dir)? fetch,
    Future<PackageView> Function(String path)? inspect,
    Future<QuoteView> Function(NodeAddress node, String serviceId, String? initialMu, String path)?
        send,
    TransferView Function()? progress,
    void Function()? cancel,
    Future<String?> Function()? privateDir,
  }) : _fetch = fetch ??
           ((source, id, dir) =>
               celautFetchService(source: source, serviceIdHex: id, dir: dir)),
       _inspect = inspect ?? ((path) => celautInspectPackage(path: path)),
       _send = send ??
           ((node, id, initialMu, path) => celautSendService(
             node: node,
             serviceIdHex: id,
             initialMu: initialMu,
             path: path,
           )),
       progress = progress ?? celautTransferProgress,
       cancel = cancel ?? celautCancelTransfer,
       _privateDir = privateDir ?? _appPrivateDir;

  final Future<PackageView> Function(NodeAddress, String, String) _fetch;
  final Future<PackageView> Function(String) _inspect;
  final Future<QuoteView> Function(NodeAddress, String, String?, String) _send;
  final Future<String?> Function() _privateDir;

  /// The transfer that runs now.
  final TransferView Function() progress;

  /// Stop the transfer that runs. The node refuses the cut service.
  final void Function() cancel;

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

  /// Get the service from the node of the offer that has it, and give it to the node of
  /// the offer that does not. Gives the quote of that node. Throws [CelautError] or
  /// [PackageRefused].
  Future<QuoteView> fromNode(TransferOffer offer, String serviceId, String? initialMu) async {
    final from = offer.from;
    if (from == null) throw ArgumentError('the offer has no node with the service');
    final dir = await _privateDir();
    if (dir == null || dir.isEmpty) throw const PackageRefused(PackageRefusal.noDirectory);
    final package = await _fetch(from, serviceId, dir);
    try {
      return await _send(offer.to, serviceId, initialMu, package.path);
    } finally {
      // A service can be large: its copy does not stay on the phone.
      await _deleteQuietly(package.path);
    }
  }

  /// Delete the file at [path], if it is there. A failure is not an error of the
  /// transfer.
  ///
  /// Synchronous on purpose: a delete is quick, and it then works in the fake time of the
  /// widget tests too.
  static Future<void> _deleteQuietly(String path) async {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // The file stays; the next transfer of the same service writes it again.
    }
  }

  /// Give the service in the file at [path] to [to]. The file must hold [serviceId] (when
  /// it says its id) and its Service part. Throws [CelautError] or [PackageRefused].
  Future<QuoteView> fromFile(
    NodeAddress to,
    String serviceId,
    String? initialMu,
    String path,
  ) async {
    final package = await _inspect(path);
    if (!package.hasService) throw const PackageRefused(PackageRefusal.noService);
    final id = package.serviceId;
    if (id != null && id.toLowerCase() != serviceId.toLowerCase()) {
      throw const PackageRefused(PackageRefusal.otherService);
    }
    try {
      return await _send(to, serviceId, initialMu, path);
    } finally {
      // The picked file is a copy of the app (Android cache); the original stays.
      await _deleteQuietly(path);
    }
  }
}
