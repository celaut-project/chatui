/// Every text of the Celaut service screen (milestone M2), in one place.
class ServiceStrings {
  const ServiceStrings._();

  // Settings
  static const rowTitle = 'Celaut service';
  static const rowSubtitle = 'Quote, start, call and stop a service on free credit';

  // Screen
  static const screenTitle = 'Celaut service';
  static const intro = 'Ask nodes for the price of a service, start it on one of them, '
      'and call it through a port on this device. A new client gets free credit from '
      'each node, so nothing is paid. The node must already have the service.';
  static const nodesLabel = 'Node addresses';
  static const nodesHint = 'One host:port on each line';
  static const serviceLabel = 'Service id';
  static const serviceHint = '64 hexadecimal characters';
  static const initialLabel = 'Start balance in MU (optional)';
  static const initialHint = 'Empty: the default of the node, one hour of resources';
  static const initialDefault = '1000000';
  static const quote = 'Get quotes';
  static const quoting = 'Asking the nodes…';

  // Input errors
  static const nodesEmpty = 'Enter at least one node address as host:port.';
  static String nodeInvalid(String line) => 'This address is not valid: $line';
  static const serviceInvalid = 'The service id must be 64 hexadecimal characters.';
  static const initialInvalid = 'The start balance must be a whole number, more than 0.';

  // Quotes
  static const quotesTitle = 'Quotes, best first';
  static const noQuotes = 'No node gave a quote.';
  static const failuresTitle = 'Nodes without a quote';
  static String cost(String mu) => 'Start: $mu MU';
  static String maintenance(String mu, int seconds) => 'Then $mu MU every $seconds s';
  static String compared(String? nanoErg) => nanoErg == null
      ? 'No ERG rate: the price cannot be compared with other nodes.'
      : 'For the comparison: $nanoErg nanoERG';
  static const start = 'Start here';
  static const starting = 'Starting…';

  // Instance
  static const instanceTitle = 'Running instance';
  static String slot(int slot) => 'Port $slot of the service';
  static String localPort(int port) => 'Local port 127.0.0.1:$port';
  static const openPort = 'Open a local port';
  static const pathLabel = 'Path';
  static const call = 'Call GET';
  static String answer(int status) => 'HTTP $status';
  static const refresh = 'Refresh the balance';
  static String clientBalance(String mu) => 'Balance of the client: $mu MU';
  static String instanceBalance(String mu) => 'Balance of the instance: $mu MU';
  static String streams(BigInt n) => 'Tunnel streams opened: $n (one per TCP connection)';
  static const keepAliveNote = 'The node charges each new TCP connection to the local port. '
      'This screen keeps one connection alive for all its calls.';
  static String tunnelError(String e) => 'Last tunnel error: $e';
  static const stop = 'Stop';
  static const stopping = 'Stopping…';
  static String stopped(String refund, String balance) =>
      'Stopped. Refund: $refund MU. Balance of the client: $balance MU.';
  static String callFailed(String e) => 'The call failed: $e';
}
