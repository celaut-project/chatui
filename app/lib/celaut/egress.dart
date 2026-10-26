import '../bridge/api/celaut_service.dart' show QuoteView;
import '../bridge/api/celaut_service_info.dart';
import 'launcher.dart' show wouldAskToStart;

/// Where a service can send what it is given, by the networks that it declares
/// (`Service.network`, `docs/celaut/env-variables.md`, section 3.1). The first version is
/// from PR #50 (`egressOf`); the rule of a tag now follows the node (nodo
/// `network_policy.direct_egress_reason`).
class EgressReport {
  const EgressReport({
    this.anyAddress = false,
    this.hosts = const [],
    this.local = const [],
    this.steered = const {},
  });

  /// A domain with the tag `*`: the instance can connect to every address.
  final bool anyAddress;

  /// The host names and chains (`api.example.com`, `pow:ergo`) that the service can
  /// connect to, outside the node. Without repeats, in order.
  final List<String> hosts;

  /// The networks that only instances on the same node answer (a group such as
  /// `postgres`): the traffic stays on the node. Without repeats, in order.
  final List<String> local;

  /// The variables that a network parameter takes by `${NAME}` (the node uses their value
  /// to resolve the domain), by name: the destination that the value chooses.
  final Map<String, List<String>> steered;

  /// True if what the service is given can leave the node.
  bool get egress => anyAddress || hosts.isNotEmpty;

  /// True if the service declares any network.
  bool get exposed => egress || local.isNotEmpty;
}

final _variableRef = RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}');
final _cased = RegExp('[a-z]');

/// A tag whose traffic leaves the node, as the node decides: `*`, a chain (`pow:` and a
/// name), or a host name (lower case, with a dot). Any other tag is a group that only the
/// instances of this node answer. A node operator can also give a group addresses of its
/// own (seeds); the app cannot see that.
bool tagLeavesNode(String tag) =>
    tag == '*' || tag.startsWith('pow:') || (tag == tag.toLowerCase() && _cased.hasMatch(tag) && tag.contains('.'));

/// Read the exits of a service from its networks. The tags of one network are names of the
/// same domain, so one network counts once: as an exit if any of its tags leaves the node.
EgressReport egressOf(List<NetworkView> networks) {
  var anyAddress = false;
  final hosts = <String>[];
  final local = <String>[];
  final steered = <String, List<String>>{};
  void add(List<String> list, String tag) {
    if (!list.contains(tag)) list.add(tag);
  }

  for (final n in networks) {
    final tags = [for (final t in n.tags) if (t.trim().isNotEmpty) t.trim()];
    if (tags.contains('*')) anyAddress = true;
    final exits = [for (final t in tags) if (t != '*' && tagLeavesNode(t)) t];
    for (final h in exits) {
      add(hosts, h);
    }
    if (exits.isEmpty && !tags.contains('*') && tags.isNotEmpty) add(local, tags.first);
    // The domain that a variable steers: name it by its first tag.
    final label = tags.isEmpty ? '' : tags.first;
    for (final m in _variableRef.allMatches(n.formal)) {
      final domains = steered.putIfAbsent(m.group(1)!, () => []);
      if (label.isNotEmpty && !domains.contains(label)) domains.add(label);
    }
  }
  return EgressReport(anyAddress: anyAddress, hosts: hosts, local: local, steered: steered);
}

/// A node that can get the start request, and so the values (`launchService`).
class EnvTargetNode {
  const EnvTargetNode({required this.peerId, required this.address, required this.trusted});

  final String peerId;

  /// `host:port`.
  final String address;

  /// True if the user marked the node as fully trusted.
  final bool trusted;
}

/// The nodes of [quotes] that `launchService` can ask to start the service, best first:
/// the ones where the credit of the app is not less than the price. Each of them reads the
/// values if it gets the request, also if it refuses the start.
List<EnvTargetNode> envTargetNodes(List<QuoteView> quotes, Set<String> trustedPeers) => [
      for (final q in quotes)
        if (wouldAskToStart(q))
          EnvTargetNode(
            peerId: q.peerId,
            address: '${q.address.host}:${q.address.port}',
            trusted: trustedPeers.contains(q.peerId.toLowerCase()),
          ),
    ];

/// The warnings before sensitive values go to a service (`docs/celaut/env-variables.md`,
/// section 3.2). A value that is not sensitive is not a credential and warns of nothing, so
/// with no sensitive value there is no warning.
class EnvWarnings {
  const EnvWarnings({
    this.egress = false,
    this.anyAddress = false,
    this.hosts = const [],
    this.local = const [],
    this.untrusted = const [],
  });

  /// From the networks of the service and the nodes that can start it, for the values
  /// that the user gives; [sensitive] is true if any of them is sensitive.
  factory EnvWarnings.of({
    required bool sensitive,
    required EgressReport report,
    required List<EnvTargetNode> nodes,
  }) {
    if (!sensitive) return const EnvWarnings();
    return EnvWarnings(
      egress: report.egress,
      anyAddress: report.anyAddress,
      hosts: report.hosts,
      local: report.local,
      untrusted: [for (final n in nodes) if (!n.trusted) n],
    );
  }

  /// The service can send the values out of the node: the red warning, and Deny is the
  /// default.
  final bool egress;
  final bool anyAddress;
  final List<String> hosts;

  /// Networks that stay on the node: a normal warning.
  final List<String> local;

  /// The nodes that can start the service and that the user did not mark as trusted.
  final List<EnvTargetNode> untrusted;

  bool get any => egress || local.isNotEmpty || untrusted.isNotEmpty;
}
