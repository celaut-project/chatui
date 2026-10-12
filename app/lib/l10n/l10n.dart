import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// English: the language of the code and the fallback for a device locale
/// that the app does not have.
final AppLocalizations _english = lookupAppLocalizations(const Locale('en'));

AppLocalizations _current = _english;

/// The texts in the language of the app, for code that has no BuildContext
/// (services, formatters, static labels). Widgets use [L10nContext.l10n].
AppLocalizations get appL10n => _current;

/// Sets the language of [appL10n]. The app calls it when its locale changes;
/// tests call it to check the Spanish texts.
void setAppLocale(Locale locale) {
  final supported = AppLocalizations.supportedLocales
      .any((l) => l.languageCode == locale.languageCode);
  _current = supported ? lookupAppLocalizations(locale) : _english;
}

extension L10nContext on BuildContext {
  /// The texts in the language of the app. English when there is no
  /// Localizations above this context (a widget test that pumps a bare
  /// MaterialApp).
  AppLocalizations get l10n =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ?? _current;
}

/// The short name of [month] (1 to 12): "Oct" or "oct".
String monthShort(int month) {
  final t = appL10n;
  return switch (month) {
    1 => t.monthShort1,
    2 => t.monthShort2,
    3 => t.monthShort3,
    4 => t.monthShort4,
    5 => t.monthShort5,
    6 => t.monthShort6,
    7 => t.monthShort7,
    8 => t.monthShort8,
    9 => t.monthShort9,
    10 => t.monthShort10,
    11 => t.monthShort11,
    _ => t.monthShort12,
  };
}

/// The time of day: "10:08 pm" in English, "22:08" in Spanish. [space] goes
/// between the time and am or pm.
String clockTime(DateTime at, {String space = ' '}) {
  final t = appL10n;
  final hour12 = at.hour % 12 == 0 ? 12 : at.hour % 12;
  return t.clockTime(
    hour12.toString(),
    at.hour.toString(),
    at.minute.toString().padLeft(2, '0'),
    space,
    at.hour < 12 ? t.clockAm : t.clockPm,
  );
}
