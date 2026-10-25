import '../bridge/api/celaut_service_info.dart';

/// How far a service can send what it is given, by the networks that it declares
/// (`Service.network`, `docs/celaut/service-info.md`).
enum EgressLevel {
  /// No network that leaves the node: only peers of the service itself, or none.
  none,

  /// The service declares hosts or chains that it connects to (`api.example.com`,
  /// `pow:ergo`): what it is given can be sent there.
  named,

  /// A domain with the tag `*`: the instance can connect to every address.
  open,
}

/// What the app can say about the exit of a service, to show the user before it gives
/// the service an environment variable.
class EgressReport {
  const EgressReport({
    this.level = EgressLevel.none,
    this.hosts = const [],
    this.steered = const {},
  });

  final EgressLevel level;

  /// The hosts and chains that the service declares, without repeats, in order.
  final List<String> hosts;

  /// The variables that a network parameter takes by `${NAME}` (the node uses their value
  /// to resolve the domain), by name: the destination that the value chooses.
  final Map<String, List<String>> steered;

  bool get leaves => level != EgressLevel.none;
}

final _variableRef = RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]*)\}');

/// A tag that names a host or a chain: `pow:` and a name, or a host name with a dot. A tag
/// with neither is the name of a group of peers of the service, which is not an exit.
bool _isExit(String tag) => tag.startsWith('pow:') || (tag.contains('.') && !tag.contains(' '));

/// Read the exits of a service from its networks.
EgressReport egressOf(List<NetworkView> networks) {
  var level = EgressLevel.none;
  final hosts = <String>[];
  final steered = <String, List<String>>{};
  for (final n in networks) {
    final exits = [for (final t in n.tags) if (t != '*' && _isExit(t)) t];
    if (n.tags.contains('*')) {
      level = EgressLevel.open;
    } else if (exits.isNotEmpty && level == EgressLevel.none) {
      level = EgressLevel.named;
    }
    for (final h in exits) {
      if (!hosts.contains(h)) hosts.add(h);
    }
    // The domain that a variable steers: name it by its first tag.
    final label = n.tags.isEmpty ? '' : n.tags.first;
    for (final m in _variableRef.allMatches(n.formal)) {
      final domains = steered.putIfAbsent(m.group(1)!, () => []);
      if (label.isNotEmpty && !domains.contains(label)) domains.add(label);
    }
  }
  return EgressReport(level: level, hosts: hosts, steered: steered);
}
