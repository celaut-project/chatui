import '../bridge/api/celaut.dart';

/// Every text that the Celaut screens show, in one place. The Spanish PR replaces
/// this file with localized texts.
class CelautStrings {
  const CelautStrings._();

  // Settings
  static const developerGroup = 'Developer';
  static const developerScope = 'App-wide';
  static const nodeRowTitle = 'Celaut node';
  static const nodeRowSubtitle = 'Connect to a node and show its advertisement';

  // Screen
  static const screenTitle = 'Celaut node';
  static const intro = 'Connect to a Celaut node and check who it is. The app checks the '
      'identity in its certificate and the signature of its advertisement. '
      'Nothing is started and nothing is paid.';
  static const addressLabel = 'Node address';
  static const addressHint = 'host:port';
  static const expectedLabel = 'Expected peer id (optional)';
  static const expectedHint = '64 hexadecimal characters';
  static const connect = 'Connect';
  static const connecting = 'Connecting…';

  // Result
  static const identityTitle = 'Identity';
  static const peerIdLabel = 'Peer id';
  static const advertisedLabel = 'Advertised at';
  static const urisTitle = 'Addresses';
  static const ratesTitle = 'Rates';
  static const contractsTitle = 'Payment contracts';
  static const resourcesTitle = 'Resources';
  static const proofsLabel = 'Reputation proofs';
  static const noUris = 'The node advertises no address.';
  static const noRates = 'The node advertises no rates.';
  static const noContracts =
      'The node advertises no payment contract. It cannot be paid yet.';
  static const noResources = 'The node gives no data about its resources.';
  static const ratesNote = 'Rates are in MU.';
  static const verifiedNote =
      'The certificate and the signature were checked. This node is who it says it is.';

  // Input errors
  static const addressEmpty = 'Enter the address of the node as host:port.';
  static const addressInvalid =
      'This address is not valid. Use host:port, for example 203.0.113.7:8090.';
  static const portInvalid = 'The port must be a number from 1 to 65535.';
  static const expectedInvalid =
      'The peer id must be 64 hexadecimal characters, or empty.';

  // Errors of the connection and of the checks
  static const errorTitle = 'Cannot show this node';

  static String errorText(CelautErrorKind kind) => switch (kind) {
        CelautErrorKind.invalidInput =>
          'The address is not valid. Check the host and the port.',
        CelautErrorKind.unreachable =>
          'The app cannot connect to this address. Check the address and the network, '
              'and check that the node is running.',
        CelautErrorKind.timeout =>
          'The node did not answer in time. Try again, or check the address.',
        CelautErrorKind.identityMismatch =>
          'The identity of this node is not the one that was expected. The address may '
              'now belong to another node. The app did not trust it.',
        CelautErrorKind.badCertificate =>
          'The certificate of this server has no valid Celaut identity. It may not be '
              'a Celaut node. The app did not trust it.',
        CelautErrorKind.badSignature =>
          'The signature of the node advertisement is not valid. The app did not '
              'trust it.',
        CelautErrorKind.staleTimestamp =>
          'This advertisement is older than one that the app accepted before. Someone '
              'may be replaying an old message. The app did not trust it.',
        CelautErrorKind.unsupportedScheme =>
          'The node signs with a scheme that this app does not support.',
        CelautErrorKind.proofOfWork =>
          'The node asks for more work than the app does for a new client, or it did '
              'not accept the work.',
        CelautErrorKind.protocol =>
          'The node refused the request or sent an answer that the app cannot use.',
        CelautErrorKind.storage =>
          'The app cannot read or write its list of known advertisements.',
      };

  static String detailLabel(String detail) => 'Detail: $detail';

  // Values
  static String cores(double value) {
    final text = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
    return '$text ${value == 1 ? 'core' : 'cores'}';
  }

  static String bytes(int value) {
    const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
    var size = value.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    final text = unit == 0 || size >= 100 ? size.toStringAsFixed(0) : size.toStringAsFixed(1);
    return '$text ${units[unit]}';
  }

  static const memoryLabel = 'Memory';
  static const diskLabel = 'Disk';
  static const cpuLabel = 'CPU';
  static const benchmarkLabel = 'Benchmark';
  static const noExpiry = 'no expiry given';
  static String expires(String when) => 'valid until $when';
  static String perUnit(String mu) => '$mu MU per base unit';
}
