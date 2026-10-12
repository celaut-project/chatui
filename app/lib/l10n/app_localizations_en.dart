// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Celaut';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonDone => 'Done';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonCopyId => 'Copy id';

  @override
  String get commonClose => 'Close';

  @override
  String get commonName => 'Name';

  @override
  String get commonAddress => 'Address';

  @override
  String get commonAddresses => 'Addresses';

  @override
  String get commonAddressCopied => 'Address copied';

  @override
  String get commonMinerFee => 'Miner fee';

  @override
  String get commonWallet => 'Wallet';

  @override
  String get commonThisWallet => 'This wallet';

  @override
  String get commonToken => 'Token';

  @override
  String get commonTokens => 'Tokens';

  @override
  String get commonContacts => 'Contacts';

  @override
  String get commonSettings => 'Settings';

  @override
  String get commonPending => 'Pending';

  @override
  String get commonOffline => 'Offline';

  @override
  String get commonBalanceUnavailable => 'Balance unavailable';

  @override
  String get commonNotAnErgoAddress => 'Not an Ergo address';

  @override
  String get commonWatchedAccount => 'Watched account';

  @override
  String get commonWatchedAddress => 'Watched address';

  @override
  String get commonStopWatching => 'Stop watching';

  @override
  String get monthShort1 => 'Jan';

  @override
  String get monthShort2 => 'Feb';

  @override
  String get monthShort3 => 'Mar';

  @override
  String get monthShort4 => 'Apr';

  @override
  String get monthShort5 => 'May';

  @override
  String get monthShort6 => 'Jun';

  @override
  String get monthShort7 => 'Jul';

  @override
  String get monthShort8 => 'Aug';

  @override
  String get monthShort9 => 'Sep';

  @override
  String get monthShort10 => 'Oct';

  @override
  String get monthShort11 => 'Nov';

  @override
  String get monthShort12 => 'Dec';

  @override
  String clockTime(
    String hour12,
    String hour24,
    String minute,
    String space,
    String period,
  ) {
    return '$hour12:$minute$space$period';
  }

  @override
  String get clockAm => 'am';

  @override
  String get clockPm => 'pm';

  @override
  String dateMonthDay(String month, String day) {
    return '$month $day';
  }

  @override
  String dateMonthDayYear(String month, String day, String year) {
    return '$month $day, $year';
  }

  @override
  String dateMonthDayTime(String month, String day, String time) {
    return '$month $day, $time';
  }

  @override
  String dateDayMonthYear(String month, String day, String year) {
    return '$day $month $year';
  }

  @override
  String dateNumeric(String month, String day, String year) {
    return '$month/$day/$year';
  }

  @override
  String timeToday(String time) {
    return 'Today, $time';
  }

  @override
  String timeYesterdayAt(String time) {
    return 'Yesterday, $time';
  }

  @override
  String get timeYesterday => 'Yesterday';

  @override
  String get timeJustNow => 'Just now';

  @override
  String timeSecondsAgo(int count) {
    return '${count}s ago';
  }

  @override
  String timeMinutesAgo(int count) {
    return '$count min ago';
  }

  @override
  String timeHoursAgo(int count) {
    return '${count}h ago';
  }

  @override
  String timeDaysAgo(int count) {
    return '$count days ago';
  }

  @override
  String get syncAgeJustNow => 'just now';

  @override
  String syncAgeMinutes(int count) {
    return '${count}m ago';
  }

  @override
  String syncAgeHours(int count) {
    return '${count}h ago';
  }

  @override
  String syncAgeDays(int count) {
    return '${count}d ago';
  }

  @override
  String get dateUnknownDay => 'Unknown day';

  @override
  String get celautDeveloperGroup => 'Developer';

  @override
  String get celautDeveloperScope => 'App-wide';

  @override
  String get celautNodeRowTitle => 'Celaut node';

  @override
  String get celautNodeRowSubtitle =>
      'Connect to a node and show its advertisement';

  @override
  String get celautScreenTitle => 'Celaut node';

  @override
  String get celautIntro =>
      'Connect to a Celaut node and check who it is. The app checks the identity in its certificate and the signature of its advertisement. Nothing is started and nothing is paid.';

  @override
  String get celautAddressLabel => 'Node address';

  @override
  String get celautAddressHint => 'host:port';

  @override
  String get celautExpectedLabel => 'Expected peer id (optional)';

  @override
  String get celautExpectedHint => '64 hexadecimal characters';

  @override
  String get celautConnect => 'Connect';

  @override
  String get celautConnecting => 'Connecting…';

  @override
  String get celautIdentityTitle => 'Identity';

  @override
  String get celautPeerIdLabel => 'Peer id';

  @override
  String get celautAdvertisedLabel => 'Advertised at';

  @override
  String get celautUrisTitle => 'Addresses';

  @override
  String get celautRatesTitle => 'Rates';

  @override
  String get celautContractsTitle => 'Payment contracts';

  @override
  String get celautResourcesTitle => 'Resources';

  @override
  String get celautProofsLabel => 'Reputation proofs';

  @override
  String get celautNoUris => 'The node advertises no address.';

  @override
  String get celautNoRates => 'The node advertises no rates.';

  @override
  String get celautNoContracts =>
      'The node advertises no payment contract. It cannot be paid yet.';

  @override
  String get celautNoResources => 'The node gives no data about its resources.';

  @override
  String get celautRatesNote => 'Rates are in MU.';

  @override
  String get celautVerifiedNote =>
      'The certificate and the signature were checked. This node is who it says it is.';

  @override
  String get celautAddressEmpty =>
      'Enter the address of the node as host:port.';

  @override
  String get celautAddressInvalid =>
      'This address is not valid. Use host:port, for example 203.0.113.7:8090.';

  @override
  String get celautPortInvalid => 'The port must be a number from 1 to 65535.';

  @override
  String get celautExpectedInvalid =>
      'The peer id must be 64 hexadecimal characters, or empty.';

  @override
  String get celautErrorTitle => 'Cannot show this node';

  @override
  String get celautErrorInvalidInput =>
      'The address is not valid. Check the host and the port.';

  @override
  String get celautErrorUnreachable =>
      'The app cannot connect to this address. Check the address and the network, and check that the node is running.';

  @override
  String get celautErrorTimeout =>
      'The node did not answer in time. Try again, or check the address.';

  @override
  String get celautErrorIdentityMismatch =>
      'The identity of this node is not the one that was expected. The address may now belong to another node. The app did not trust it.';

  @override
  String get celautErrorBadCertificate =>
      'The certificate of this server has no valid Celaut identity. It may not be a Celaut node. The app did not trust it.';

  @override
  String get celautErrorBadSignature =>
      'The signature of the node advertisement is not valid. The app did not trust it.';

  @override
  String get celautErrorStaleTimestamp =>
      'This advertisement is older than one that the app accepted before. Someone may be replaying an old message. The app did not trust it.';

  @override
  String get celautErrorUnsupportedScheme =>
      'The node signs with a scheme that this app does not support.';

  @override
  String get celautErrorProofOfWork =>
      'The node asks for more work than the app does for a new client, or it did not accept the work.';

  @override
  String get celautErrorProtocol =>
      'The node refused the request or sent an answer that the app cannot use.';

  @override
  String get celautErrorStorage =>
      'The app cannot read or write its list of known advertisements.';

  @override
  String celautDetailLabel(String detail) {
    return 'Detail: $detail';
  }

  @override
  String celautCores(int count, String value) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$value cores',
      one: '$value core',
    );
    return '$_temp0';
  }

  @override
  String get celautMemoryLabel => 'Memory';

  @override
  String get celautDiskLabel => 'Disk';

  @override
  String get celautCpuLabel => 'CPU';

  @override
  String get celautBenchmarkLabel => 'Benchmark';

  @override
  String get celautNoExpiry => 'no expiry given';

  @override
  String celautExpires(String when) {
    return 'valid until $when';
  }

  @override
  String celautPerUnit(String mu) {
    return '$mu MU per base unit';
  }
}
