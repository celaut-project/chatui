import '../bridge/api/celaut_network.dart';

/// Every text of the Tor screen (milestone M5), in one place.
class NetworkStrings {
  const NetworkStrings._();

  // Settings
  static const rowTitle = 'Tor';
  static const rowSubtitle = 'Send the node, explorer and update connections through Tor';

  // Screen
  static const screenTitle = 'Tor';
  static const intro =
      'With Tor on, the connections to Celaut nodes, to the Ergo explorer and to GitHub '
      '(the update check) go through Tor, so they do not see the IP address of this '
      'phone. If Tor is not ready, those '
      'connections fail: the app never connects directly. A node in a private network '
      '(for example 10.0.2.2 or 192.168.1.5) cannot be reached through Tor.';
  static const optionOff = 'Off: direct connections';
  static const optionEmbedded = 'Tor inside the app';
  static const optionEmbeddedNote =
      'The first start takes up to a minute. It adds the Tor client of the Arti project to the app.';
  static const optionSocks = 'External SOCKS5 proxy';
  static const optionSocksNote =
      'For example Orbot. The app trusts that the proxy is a Tor proxy.';
  static const socksLabel = 'Proxy address';
  static const socksHint = '127.0.0.1:9050';
  static const socksInvalid = 'Enter an IP address and a port, for example 127.0.0.1:9050.';
  static const apply = 'Apply';
  static const saveFailed = 'The setting could not be saved.';

  // Status
  static const statusTitle = 'State';
  static String status(NetworkStatusView s) => switch (s.state) {
        NetworkState.off => 'Direct connections.',
        NetworkState.starting => s.choice == NetworkChoice.embedded
            ? 'Starting Tor… ${s.percent}%'
            : 'Checking the proxy…',
        NetworkState.ready => s.choice == NetworkChoice.embedded
            ? 'The connections go through Tor.'
            : 'The connections go through the proxy.',
        NetworkState.failed =>
          'Not available: ${s.error}. The connections fail until it is.',
      };
}
