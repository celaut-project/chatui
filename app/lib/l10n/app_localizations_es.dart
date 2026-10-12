// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Celaut';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonSave => 'Guardar';

  @override
  String get commonRetry => 'Reintentar';

  @override
  String get commonRemove => 'Quitar';

  @override
  String get commonDone => 'Listo';

  @override
  String get commonCopy => 'Copiar';

  @override
  String get commonCopyId => 'Copiar id';

  @override
  String get commonClose => 'Cerrar';

  @override
  String get commonName => 'Nombre';

  @override
  String get commonAddress => 'Dirección';

  @override
  String get commonAddresses => 'Direcciones';

  @override
  String get commonAddressCopied => 'Dirección copiada';

  @override
  String get commonMinerFee => 'Comisión de minería';

  @override
  String get commonWallet => 'Billetera';

  @override
  String get commonThisWallet => 'Esta billetera';

  @override
  String get commonToken => 'Token';

  @override
  String get commonTokens => 'Tokens';

  @override
  String get commonContacts => 'Contactos';

  @override
  String get commonSettings => 'Ajustes';

  @override
  String get commonPending => 'Pendiente';

  @override
  String get commonOffline => 'Sin conexión';

  @override
  String get commonBalanceUnavailable => 'Saldo no disponible';

  @override
  String get commonNotAnErgoAddress => 'No es una dirección de Ergo';

  @override
  String get commonWatchedAccount => 'Cuenta observada';

  @override
  String get commonWatchedAddress => 'Dirección observada';

  @override
  String get commonStopWatching => 'Dejar de observar';

  @override
  String get monthShort1 => 'ene';

  @override
  String get monthShort2 => 'feb';

  @override
  String get monthShort3 => 'mar';

  @override
  String get monthShort4 => 'abr';

  @override
  String get monthShort5 => 'may';

  @override
  String get monthShort6 => 'jun';

  @override
  String get monthShort7 => 'jul';

  @override
  String get monthShort8 => 'ago';

  @override
  String get monthShort9 => 'sept';

  @override
  String get monthShort10 => 'oct';

  @override
  String get monthShort11 => 'nov';

  @override
  String get monthShort12 => 'dic';

  @override
  String clockTime(
    String hour12,
    String hour24,
    String minute,
    String space,
    String period,
  ) {
    return '$hour24:$minute';
  }

  @override
  String get clockAm => 'a. m.';

  @override
  String get clockPm => 'p. m.';

  @override
  String dateMonthDay(String month, String day) {
    return '$day $month';
  }

  @override
  String dateMonthDayYear(String month, String day, String year) {
    return '$day $month $year';
  }

  @override
  String dateMonthDayTime(String month, String day, String time) {
    return '$day $month, $time';
  }

  @override
  String dateDayMonthYear(String month, String day, String year) {
    return '$day $month $year';
  }

  @override
  String dateNumeric(String month, String day, String year) {
    return '$day/$month/$year';
  }

  @override
  String timeToday(String time) {
    return 'Hoy, $time';
  }

  @override
  String timeYesterdayAt(String time) {
    return 'Ayer, $time';
  }

  @override
  String get timeYesterday => 'Ayer';

  @override
  String get timeJustNow => 'Ahora mismo';

  @override
  String timeSecondsAgo(int count) {
    return 'hace $count s';
  }

  @override
  String timeMinutesAgo(int count) {
    return 'hace $count min';
  }

  @override
  String timeHoursAgo(int count) {
    return 'hace $count h';
  }

  @override
  String timeDaysAgo(int count) {
    return 'hace $count días';
  }

  @override
  String get syncAgeJustNow => 'ahora mismo';

  @override
  String syncAgeMinutes(int count) {
    return 'hace $count min';
  }

  @override
  String syncAgeHours(int count) {
    return 'hace $count h';
  }

  @override
  String syncAgeDays(int count) {
    return 'hace $count d';
  }

  @override
  String get dateUnknownDay => 'Día desconocido';

  @override
  String get celautDeveloperGroup => 'Desarrollador';

  @override
  String get celautDeveloperScope => 'Toda la app';

  @override
  String get celautNodeRowTitle => 'Nodo Celaut';

  @override
  String get celautNodeRowSubtitle =>
      'Conéctate a un nodo y muestra su anuncio';

  @override
  String get celautScreenTitle => 'Nodo Celaut';

  @override
  String get celautIntro =>
      'Conéctate a un nodo Celaut y comprueba quién es. La app comprueba la identidad de su certificado y la firma de su anuncio. No se inicia nada y no se paga nada.';

  @override
  String get celautAddressLabel => 'Dirección del nodo';

  @override
  String get celautAddressHint => 'host:puerto';

  @override
  String get celautExpectedLabel => 'Id de par esperado (opcional)';

  @override
  String get celautExpectedHint => '64 caracteres hexadecimales';

  @override
  String get celautConnect => 'Conectar';

  @override
  String get celautConnecting => 'Conectando…';

  @override
  String get celautIdentityTitle => 'Identidad';

  @override
  String get celautPeerIdLabel => 'Id de par';

  @override
  String get celautAdvertisedLabel => 'Anunciado el';

  @override
  String get celautUrisTitle => 'Direcciones';

  @override
  String get celautRatesTitle => 'Tarifas';

  @override
  String get celautContractsTitle => 'Contratos de pago';

  @override
  String get celautResourcesTitle => 'Recursos';

  @override
  String get celautProofsLabel => 'Pruebas de reputación';

  @override
  String get celautNoUris => 'El nodo no anuncia ninguna dirección.';

  @override
  String get celautNoRates => 'El nodo no anuncia tarifas.';

  @override
  String get celautNoContracts =>
      'El nodo no anuncia ningún contrato de pago. Todavía no se le puede pagar.';

  @override
  String get celautNoResources => 'El nodo no da datos sobre sus recursos.';

  @override
  String get celautRatesNote => 'Las tarifas están en MU.';

  @override
  String get celautVerifiedNote =>
      'Se comprobaron el certificado y la firma. Este nodo es quien dice ser.';

  @override
  String get celautAddressEmpty =>
      'Escribe la dirección del nodo como host:puerto.';

  @override
  String get celautAddressInvalid =>
      'Esta dirección no es válida. Usa host:puerto, por ejemplo 203.0.113.7:8090.';

  @override
  String get celautPortInvalid =>
      'El puerto debe ser un número del 1 al 65535.';

  @override
  String get celautExpectedInvalid =>
      'El id de par debe tener 64 caracteres hexadecimales o estar vacío.';

  @override
  String get celautErrorTitle => 'No se puede mostrar este nodo';

  @override
  String get celautErrorInvalidInput =>
      'La dirección no es válida. Comprueba el host y el puerto.';

  @override
  String get celautErrorUnreachable =>
      'La app no puede conectarse a esta dirección. Comprueba la dirección y la red, y que el nodo esté en marcha.';

  @override
  String get celautErrorTimeout =>
      'El nodo no respondió a tiempo. Vuelve a intentarlo o comprueba la dirección.';

  @override
  String get celautErrorIdentityMismatch =>
      'La identidad de este nodo no es la esperada. Puede que la dirección pertenezca ahora a otro nodo. La app no confió en él.';

  @override
  String get celautErrorBadCertificate =>
      'El certificado de este servidor no tiene una identidad Celaut válida. Puede que no sea un nodo Celaut. La app no confió en él.';

  @override
  String get celautErrorBadSignature =>
      'La firma del anuncio del nodo no es válida. La app no confió en él.';

  @override
  String get celautErrorStaleTimestamp =>
      'Este anuncio es más antiguo que otro que la app ya aceptó. Puede que alguien esté reenviando un mensaje antiguo. La app no confió en él.';

  @override
  String get celautErrorUnsupportedScheme =>
      'El nodo firma con un esquema que esta app no admite.';

  @override
  String get celautErrorProofOfWork =>
      'El nodo pide más trabajo del que la app hace para un cliente nuevo, o no aceptó el trabajo.';

  @override
  String get celautErrorProtocol =>
      'El nodo rechazó la solicitud o envió una respuesta que la app no puede usar.';

  @override
  String get celautErrorStorage =>
      'La app no puede leer ni escribir su lista de anuncios conocidos.';

  @override
  String celautDetailLabel(String detail) {
    return 'Detalle: $detail';
  }

  @override
  String celautCores(int count, String value) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$value núcleos',
      one: '$value núcleo',
    );
    return '$_temp0';
  }

  @override
  String get celautMemoryLabel => 'Memoria';

  @override
  String get celautDiskLabel => 'Disco';

  @override
  String get celautCpuLabel => 'CPU';

  @override
  String get celautBenchmarkLabel => 'Prueba de rendimiento';

  @override
  String get celautNoExpiry => 'sin fecha de caducidad';

  @override
  String celautExpires(String when) {
    return 'válido hasta $when';
  }

  @override
  String celautPerUnit(String mu) {
    return '$mu MU por unidad base';
  }
}
