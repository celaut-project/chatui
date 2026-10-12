import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Celaut'**
  String get appTitle;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commonRemove;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get commonCopy;

  /// No description provided for @commonCopyId.
  ///
  /// In en, this message translates to:
  /// **'Copy id'**
  String get commonCopyId;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get commonName;

  /// No description provided for @commonAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get commonAddress;

  /// No description provided for @commonAddresses.
  ///
  /// In en, this message translates to:
  /// **'Addresses'**
  String get commonAddresses;

  /// No description provided for @commonAddressCopied.
  ///
  /// In en, this message translates to:
  /// **'Address copied'**
  String get commonAddressCopied;

  /// No description provided for @commonMinerFee.
  ///
  /// In en, this message translates to:
  /// **'Miner fee'**
  String get commonMinerFee;

  /// No description provided for @commonWallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get commonWallet;

  /// No description provided for @commonThisWallet.
  ///
  /// In en, this message translates to:
  /// **'This wallet'**
  String get commonThisWallet;

  /// No description provided for @commonToken.
  ///
  /// In en, this message translates to:
  /// **'Token'**
  String get commonToken;

  /// No description provided for @commonTokens.
  ///
  /// In en, this message translates to:
  /// **'Tokens'**
  String get commonTokens;

  /// No description provided for @commonContacts.
  ///
  /// In en, this message translates to:
  /// **'Contacts'**
  String get commonContacts;

  /// No description provided for @commonSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get commonSettings;

  /// No description provided for @commonPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get commonPending;

  /// No description provided for @commonOffline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get commonOffline;

  /// No description provided for @commonBalanceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Balance unavailable'**
  String get commonBalanceUnavailable;

  /// No description provided for @commonNotAnErgoAddress.
  ///
  /// In en, this message translates to:
  /// **'Not an Ergo address'**
  String get commonNotAnErgoAddress;

  /// No description provided for @commonWatchedAccount.
  ///
  /// In en, this message translates to:
  /// **'Watched account'**
  String get commonWatchedAccount;

  /// No description provided for @commonWatchedAddress.
  ///
  /// In en, this message translates to:
  /// **'Watched address'**
  String get commonWatchedAddress;

  /// No description provided for @commonStopWatching.
  ///
  /// In en, this message translates to:
  /// **'Stop watching'**
  String get commonStopWatching;

  /// No description provided for @monthShort1.
  ///
  /// In en, this message translates to:
  /// **'Jan'**
  String get monthShort1;

  /// No description provided for @monthShort2.
  ///
  /// In en, this message translates to:
  /// **'Feb'**
  String get monthShort2;

  /// No description provided for @monthShort3.
  ///
  /// In en, this message translates to:
  /// **'Mar'**
  String get monthShort3;

  /// No description provided for @monthShort4.
  ///
  /// In en, this message translates to:
  /// **'Apr'**
  String get monthShort4;

  /// No description provided for @monthShort5.
  ///
  /// In en, this message translates to:
  /// **'May'**
  String get monthShort5;

  /// No description provided for @monthShort6.
  ///
  /// In en, this message translates to:
  /// **'Jun'**
  String get monthShort6;

  /// No description provided for @monthShort7.
  ///
  /// In en, this message translates to:
  /// **'Jul'**
  String get monthShort7;

  /// No description provided for @monthShort8.
  ///
  /// In en, this message translates to:
  /// **'Aug'**
  String get monthShort8;

  /// No description provided for @monthShort9.
  ///
  /// In en, this message translates to:
  /// **'Sep'**
  String get monthShort9;

  /// No description provided for @monthShort10.
  ///
  /// In en, this message translates to:
  /// **'Oct'**
  String get monthShort10;

  /// No description provided for @monthShort11.
  ///
  /// In en, this message translates to:
  /// **'Nov'**
  String get monthShort11;

  /// No description provided for @monthShort12.
  ///
  /// In en, this message translates to:
  /// **'Dec'**
  String get monthShort12;

  /// A time of day. English uses a 12-hour clock with am or pm; Spanish a 24-hour clock.
  ///
  /// In en, this message translates to:
  /// **'{hour12}:{minute}{space}{period}'**
  String clockTime(
    String hour12,
    String hour24,
    String minute,
    String space,
    String period,
  );

  /// No description provided for @clockAm.
  ///
  /// In en, this message translates to:
  /// **'am'**
  String get clockAm;

  /// No description provided for @clockPm.
  ///
  /// In en, this message translates to:
  /// **'pm'**
  String get clockPm;

  /// No description provided for @dateMonthDay.
  ///
  /// In en, this message translates to:
  /// **'{month} {day}'**
  String dateMonthDay(String month, String day);

  /// No description provided for @dateMonthDayYear.
  ///
  /// In en, this message translates to:
  /// **'{month} {day}, {year}'**
  String dateMonthDayYear(String month, String day, String year);

  /// No description provided for @dateMonthDayTime.
  ///
  /// In en, this message translates to:
  /// **'{month} {day}, {time}'**
  String dateMonthDayTime(String month, String day, String time);

  /// No description provided for @dateDayMonthYear.
  ///
  /// In en, this message translates to:
  /// **'{day} {month} {year}'**
  String dateDayMonthYear(String month, String day, String year);

  /// No description provided for @dateNumeric.
  ///
  /// In en, this message translates to:
  /// **'{month}/{day}/{year}'**
  String dateNumeric(String month, String day, String year);

  /// No description provided for @timeToday.
  ///
  /// In en, this message translates to:
  /// **'Today, {time}'**
  String timeToday(String time);

  /// No description provided for @timeYesterdayAt.
  ///
  /// In en, this message translates to:
  /// **'Yesterday, {time}'**
  String timeYesterdayAt(String time);

  /// No description provided for @timeYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get timeYesterday;

  /// No description provided for @timeJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get timeJustNow;

  /// No description provided for @timeSecondsAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}s ago'**
  String timeSecondsAgo(int count);

  /// No description provided for @timeMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} min ago'**
  String timeMinutesAgo(int count);

  /// No description provided for @timeHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String timeHoursAgo(int count);

  /// No description provided for @timeDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} days ago'**
  String timeDaysAgo(int count);

  /// No description provided for @syncAgeJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get syncAgeJustNow;

  /// No description provided for @syncAgeMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count}m ago'**
  String syncAgeMinutes(int count);

  /// No description provided for @syncAgeHours.
  ///
  /// In en, this message translates to:
  /// **'{count}h ago'**
  String syncAgeHours(int count);

  /// No description provided for @syncAgeDays.
  ///
  /// In en, this message translates to:
  /// **'{count}d ago'**
  String syncAgeDays(int count);

  /// No description provided for @dateUnknownDay.
  ///
  /// In en, this message translates to:
  /// **'Unknown day'**
  String get dateUnknownDay;

  /// No description provided for @celautDeveloperGroup.
  ///
  /// In en, this message translates to:
  /// **'Developer'**
  String get celautDeveloperGroup;

  /// No description provided for @celautDeveloperScope.
  ///
  /// In en, this message translates to:
  /// **'App-wide'**
  String get celautDeveloperScope;

  /// No description provided for @celautNodeRowTitle.
  ///
  /// In en, this message translates to:
  /// **'Celaut node'**
  String get celautNodeRowTitle;

  /// No description provided for @celautNodeRowSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Connect to a node and show its advertisement'**
  String get celautNodeRowSubtitle;

  /// No description provided for @celautScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Celaut node'**
  String get celautScreenTitle;

  /// No description provided for @celautIntro.
  ///
  /// In en, this message translates to:
  /// **'Connect to a Celaut node and check who it is. The app checks the identity in its certificate and the signature of its advertisement. Nothing is started and nothing is paid.'**
  String get celautIntro;

  /// No description provided for @celautAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'Node address'**
  String get celautAddressLabel;

  /// No description provided for @celautAddressHint.
  ///
  /// In en, this message translates to:
  /// **'host:port'**
  String get celautAddressHint;

  /// No description provided for @celautExpectedLabel.
  ///
  /// In en, this message translates to:
  /// **'Expected peer id (optional)'**
  String get celautExpectedLabel;

  /// No description provided for @celautExpectedHint.
  ///
  /// In en, this message translates to:
  /// **'64 hexadecimal characters'**
  String get celautExpectedHint;

  /// No description provided for @celautConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get celautConnect;

  /// No description provided for @celautConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get celautConnecting;

  /// No description provided for @celautIdentityTitle.
  ///
  /// In en, this message translates to:
  /// **'Identity'**
  String get celautIdentityTitle;

  /// No description provided for @celautPeerIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Peer id'**
  String get celautPeerIdLabel;

  /// No description provided for @celautAdvertisedLabel.
  ///
  /// In en, this message translates to:
  /// **'Advertised at'**
  String get celautAdvertisedLabel;

  /// No description provided for @celautUrisTitle.
  ///
  /// In en, this message translates to:
  /// **'Addresses'**
  String get celautUrisTitle;

  /// No description provided for @celautRatesTitle.
  ///
  /// In en, this message translates to:
  /// **'Rates'**
  String get celautRatesTitle;

  /// No description provided for @celautContractsTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment contracts'**
  String get celautContractsTitle;

  /// No description provided for @celautResourcesTitle.
  ///
  /// In en, this message translates to:
  /// **'Resources'**
  String get celautResourcesTitle;

  /// No description provided for @celautProofsLabel.
  ///
  /// In en, this message translates to:
  /// **'Reputation proofs'**
  String get celautProofsLabel;

  /// No description provided for @celautNoUris.
  ///
  /// In en, this message translates to:
  /// **'The node advertises no address.'**
  String get celautNoUris;

  /// No description provided for @celautNoRates.
  ///
  /// In en, this message translates to:
  /// **'The node advertises no rates.'**
  String get celautNoRates;

  /// No description provided for @celautNoContracts.
  ///
  /// In en, this message translates to:
  /// **'The node advertises no payment contract. It cannot be paid yet.'**
  String get celautNoContracts;

  /// No description provided for @celautNoResources.
  ///
  /// In en, this message translates to:
  /// **'The node gives no data about its resources.'**
  String get celautNoResources;

  /// No description provided for @celautRatesNote.
  ///
  /// In en, this message translates to:
  /// **'Rates are in MU.'**
  String get celautRatesNote;

  /// No description provided for @celautVerifiedNote.
  ///
  /// In en, this message translates to:
  /// **'The certificate and the signature were checked. This node is who it says it is.'**
  String get celautVerifiedNote;

  /// No description provided for @celautAddressEmpty.
  ///
  /// In en, this message translates to:
  /// **'Enter the address of the node as host:port.'**
  String get celautAddressEmpty;

  /// No description provided for @celautAddressInvalid.
  ///
  /// In en, this message translates to:
  /// **'This address is not valid. Use host:port, for example 203.0.113.7:8090.'**
  String get celautAddressInvalid;

  /// No description provided for @celautPortInvalid.
  ///
  /// In en, this message translates to:
  /// **'The port must be a number from 1 to 65535.'**
  String get celautPortInvalid;

  /// No description provided for @celautExpectedInvalid.
  ///
  /// In en, this message translates to:
  /// **'The peer id must be 64 hexadecimal characters, or empty.'**
  String get celautExpectedInvalid;

  /// No description provided for @celautErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Cannot show this node'**
  String get celautErrorTitle;

  /// No description provided for @celautErrorInvalidInput.
  ///
  /// In en, this message translates to:
  /// **'The address is not valid. Check the host and the port.'**
  String get celautErrorInvalidInput;

  /// No description provided for @celautErrorUnreachable.
  ///
  /// In en, this message translates to:
  /// **'The app cannot connect to this address. Check the address and the network, and check that the node is running.'**
  String get celautErrorUnreachable;

  /// No description provided for @celautErrorTimeout.
  ///
  /// In en, this message translates to:
  /// **'The node did not answer in time. Try again, or check the address.'**
  String get celautErrorTimeout;

  /// No description provided for @celautErrorIdentityMismatch.
  ///
  /// In en, this message translates to:
  /// **'The identity of this node is not the one that was expected. The address may now belong to another node. The app did not trust it.'**
  String get celautErrorIdentityMismatch;

  /// No description provided for @celautErrorBadCertificate.
  ///
  /// In en, this message translates to:
  /// **'The certificate of this server has no valid Celaut identity. It may not be a Celaut node. The app did not trust it.'**
  String get celautErrorBadCertificate;

  /// No description provided for @celautErrorBadSignature.
  ///
  /// In en, this message translates to:
  /// **'The signature of the node advertisement is not valid. The app did not trust it.'**
  String get celautErrorBadSignature;

  /// No description provided for @celautErrorStaleTimestamp.
  ///
  /// In en, this message translates to:
  /// **'This advertisement is older than one that the app accepted before. Someone may be replaying an old message. The app did not trust it.'**
  String get celautErrorStaleTimestamp;

  /// No description provided for @celautErrorUnsupportedScheme.
  ///
  /// In en, this message translates to:
  /// **'The node signs with a scheme that this app does not support.'**
  String get celautErrorUnsupportedScheme;

  /// No description provided for @celautErrorProofOfWork.
  ///
  /// In en, this message translates to:
  /// **'The node asks for more work than the app does for a new client, or it did not accept the work.'**
  String get celautErrorProofOfWork;

  /// No description provided for @celautErrorProtocol.
  ///
  /// In en, this message translates to:
  /// **'The node refused the request or sent an answer that the app cannot use.'**
  String get celautErrorProtocol;

  /// No description provided for @celautErrorStorage.
  ///
  /// In en, this message translates to:
  /// **'The app cannot read or write its list of known advertisements.'**
  String get celautErrorStorage;

  /// No description provided for @celautDetailLabel.
  ///
  /// In en, this message translates to:
  /// **'Detail: {detail}'**
  String celautDetailLabel(String detail);

  /// CPU cores. count is 1 when the value is exactly one, else 2; value is the formatted number.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{value} core} other{{value} cores}}'**
  String celautCores(int count, String value);

  /// No description provided for @celautMemoryLabel.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get celautMemoryLabel;

  /// No description provided for @celautDiskLabel.
  ///
  /// In en, this message translates to:
  /// **'Disk'**
  String get celautDiskLabel;

  /// No description provided for @celautCpuLabel.
  ///
  /// In en, this message translates to:
  /// **'CPU'**
  String get celautCpuLabel;

  /// No description provided for @celautBenchmarkLabel.
  ///
  /// In en, this message translates to:
  /// **'Benchmark'**
  String get celautBenchmarkLabel;

  /// No description provided for @celautNoExpiry.
  ///
  /// In en, this message translates to:
  /// **'no expiry given'**
  String get celautNoExpiry;

  /// No description provided for @celautExpires.
  ///
  /// In en, this message translates to:
  /// **'valid until {when}'**
  String celautExpires(String when);

  /// No description provided for @celautPerUnit.
  ///
  /// In en, this message translates to:
  /// **'{mu} MU per base unit'**
  String celautPerUnit(String mu);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
