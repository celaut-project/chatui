import '../bridge/api/celaut.dart';
import '../bridge/api/celaut_env.dart';
import '../bridge/api/celaut_health.dart';
import '../bridge/api/celaut_home.dart';
import '../bridge/api/celaut_service.dart';
import 'host_port.dart';

typedef QuoteCall = Future<QuotesView> Function({
  required List<NodeAddress> nodes,
  required String serviceIdHex,
  String? initialMu,
});

typedef StartCall = Future<InstanceView> Function({
  required NodeAddress node,
  required String serviceIdHex,
  String? initialMu,
  required List<EnvChoice> environment,
});

/// The question about the environment variables of the service (`docs/celaut/env-variables.md`),
/// asked after the quotes and before the first start. It gives the values that the user
/// chose (a variable that the user skipped is not in the list), or null if the user
/// cancelled the launch.
typedef EnvironmentStep = Future<List<EnvChoice>?> Function(QuotesView quotes);

/// The user cancelled the launch in the question about the variables. Nothing was sent
/// to a node except the quotes.
class LaunchCancelled implements Exception {
  const LaunchCancelled();

  @override
  String toString() => 'LaunchCancelled()';
}

/// A node that gave a quote but did not start the service.
class LaunchSkip {
  const LaunchSkip(this.quote, this.error);

  final QuoteView quote;

  /// Why. The `message` is the text of the node (without the wrapper of the transport),
  /// or, for [CelautErrorKind.insufficientCredit], the numbers.
  final CelautError error;

  /// True if the app did not ask the node to start: the balance of the client on the node
  /// is less than the price. [quote] has both numbers.
  bool get isCreditProblem => error.kind == CelautErrorKind.insufficientCredit;
}

/// A node that was not asked because its last checks say that it does not answer.
class LeftOutNode {
  const LeftOutNode({
    required this.address,
    required this.peerId,
    this.kind,
    this.message = '',
  });

  /// The address of the node (`host:port`).
  final String address;
  final String peerId;

  /// Why its last check failed, if the record says.
  final CelautErrorKind? kind;

  /// The text of its last failure, if the record has it.
  final String message;
}

/// The service started on the node of [quote], the best one that could start it.
class LaunchOutcome {
  const LaunchOutcome({
    required this.quote,
    required this.instance,
    required this.skipped,
    this.leftOut = const [],
  });

  final QuoteView quote;
  final InstanceView instance;

  /// The nodes that were better than [quote] and did not start the service.
  final List<LaunchSkip> skipped;

  /// The nodes that were not asked, because their last checks say that they do not answer.
  final List<LeftOutNode> leftOut;
}

enum LaunchFailureKind {
  /// No node to ask: none typed and none known.
  noNodes,

  /// No node gave a quote.
  noQuotes,

  /// Nodes gave quotes, and none of them started the service.
  allFailed,
}

class LaunchFailure implements Exception {
  const LaunchFailure(
    this.kind, {
    this.quoteFailures = const [],
    this.skipped = const [],
    this.leftOut = const [],
  });

  final LaunchFailureKind kind;
  final List<QuoteFailureView> quoteFailures;
  final List<LaunchSkip> skipped;

  /// The nodes that were not asked, because their last checks say that they do not answer.
  final List<LeftOutNode> leftOut;

  /// The nodes that forgot the client id of the app. The app asks the user what to do;
  /// it never makes a new client by itself (`docs/celaut/ui.md`).
  List<LaunchSkip> get clientUnknown => [
        for (final s in skipped)
          if (s.error.kind == CelautErrorKind.clientUnknown) s,
      ];

  @override
  String toString() => 'LaunchFailure($kind, skipped: ${skipped.length})';
}

/// The nodes to ask when the user typed none: the most recent address of each known
/// node. An address that does not parse is left out.
List<NodeAddress> knownNodeAddresses(List<KnownNodeView> known) {
  final nodes = <NodeAddress>[];
  for (final node in known) {
    if (node.addresses.isEmpty) continue;
    final parsed = parseHostPort(node.addresses.first).value;
    if (parsed != null) nodes.add(NodeAddress(host: parsed.host, port: parsed.port));
  }
  return nodes;
}

/// A node whose last checks failed this many times in a row is left out of the quotes.
const leaveOutAfterFailures = 2;

String _hostPort(NodeAddress a) => '${a.host}:${a.port}';

/// Split [asked] into the nodes to ask and the nodes to leave out: the ones that the
/// health records say are unreachable after [leaveOutAfterFailures] checks in a row. If
/// that would leave no node, all of them are asked: a node may be back.
({List<NodeAddress> ask, List<LeftOutNode> leftOut}) chooseNodesToAsk(
  List<NodeAddress> asked,
  List<NodeHealthView> health,
) {
  final down = <String, NodeHealthView>{
    for (final h in health)
      if (h.availability == NodeAvailability.unreachable && h.failures >= leaveOutAfterFailures)
        h.address: h,
  };
  final ask = <NodeAddress>[];
  final leftOut = <LeftOutNode>[];
  for (final a in asked) {
    final h = down[_hostPort(a)];
    if (h == null) {
      ask.add(a);
    } else {
      leftOut.add(
        LeftOutNode(
          address: h.address,
          peerId: h.peerId,
          kind: h.errorKind,
          message: h.error ?? '',
        ),
      );
    }
  }
  if (ask.isEmpty) return (ask: asked, leftOut: const []);
  return (ask: ask, leftOut: leftOut);
}

/// Start a service on the best node (`docs/celaut/balancer.md`): ask every node for a
/// quote, take the quotes best first, and use the first node that starts the service.
/// A node that fails is skipped, and the next one is tried.
///
/// Two checks save time and give a reason:
/// - A node whose last checks say that it does not answer is not asked (see
///   [chooseNodesToAsk]).
/// - A node where the balance of the client is less than the price is not asked to
///   start: it would refuse. It is skipped with [CelautErrorKind.insufficientCredit].
///
/// [nodes] are the nodes to ask. Without them, the known nodes of the app.
///
/// [environment] asks the user for the environment variables of the service once the
/// quotes are in. A quote carries no variable: only a start does, so a node that only
/// prices the service never reads them. Throws [LaunchCancelled] if the user cancels.
Future<LaunchOutcome> launchService({
  required String serviceIdHex,
  String? initialMu,
  List<NodeAddress>? nodes,
  EnvironmentStep? environment,
  QuoteCall quote = celautQuoteService,
  StartCall start = celautStartService,
  List<KnownNodeView> Function() knownNodes = celautKnownNodes,
  List<NodeHealthView> Function() health = celautNodesHealth,
}) async {
  final all = nodes ?? knownNodeAddresses(knownNodes());
  if (all.isEmpty) throw const LaunchFailure(LaunchFailureKind.noNodes);
  final chosen = chooseNodesToAsk(all, health());
  final leftOut = chosen.leftOut;
  final quotes = await quote(nodes: chosen.ask, serviceIdHex: serviceIdHex, initialMu: initialMu);
  if (quotes.quotes.isEmpty) {
    throw LaunchFailure(
      LaunchFailureKind.noQuotes,
      quoteFailures: quotes.failures,
      leftOut: leftOut,
    );
  }
  final values = environment == null ? const <EnvChoice>[] : await environment(quotes);
  if (values == null) throw const LaunchCancelled();
  final skipped = <LaunchSkip>[];
  for (final candidate in quotes.quotes) {
    final credit = BigInt.tryParse(candidate.clientBalanceMu);
    final cost = BigInt.tryParse(candidate.costMu);
    if (credit != null && cost != null && credit < cost) {
      skipped.add(
        LaunchSkip(
          candidate,
          CelautError(
            kind: CelautErrorKind.insufficientCredit,
            message: 'credit $credit MU, price $cost MU',
          ),
        ),
      );
      continue;
    }
    try {
      final instance = await start(
        node: candidate.address,
        serviceIdHex: serviceIdHex,
        // The node takes the build out of initial_mu, and its quote is the build plus
        // the balance asked for: the least that a start needs.
        initialMu: candidate.costMu,
        environment: values,
      );
      return LaunchOutcome(
        quote: candidate,
        instance: instance,
        skipped: skipped,
        leftOut: leftOut,
      );
    } on CelautError catch (e) {
      skipped.add(LaunchSkip(candidate, e));
    }
  }
  throw LaunchFailure(
    LaunchFailureKind.allFailed,
    quoteFailures: quotes.failures,
    skipped: skipped,
    leftOut: leftOut,
  );
}
