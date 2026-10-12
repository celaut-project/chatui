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

  @override
  String get settingsScopeAppWide => 'Toda la app';

  @override
  String get aboutTitle => 'Acerca de';

  @override
  String get securityTitle => 'Seguridad';

  @override
  String get networkTitle => 'Red';

  @override
  String get displayTitle => 'Pantalla';

  @override
  String get addressBookTitle => 'Libreta de direcciones';

  @override
  String get settingsAboutRowTitle => 'Acerca de Celaut';

  @override
  String get settingsAboutRowSubtitle =>
      'Versión, notas de la versión, licencias';

  @override
  String get settingsSeedWalletScope => 'Billetera con frase';

  @override
  String get settingsWalletRowTitle =>
      'Nombre, direcciones y copia de seguridad';

  @override
  String get settingsWalletRowSubtitle =>
      'Renombrar, dirección principal, política de cambio, quitar';

  @override
  String get settingsSecurityWalletSubtitle =>
      'PIN, desbloqueo biométrico, bloqueo automático';

  @override
  String get settingsAppGroup => 'App';

  @override
  String get settingsSecurityAppSubtitle =>
      'Bloqueo automático, capturas de pantalla, fondos sin confirmar';

  @override
  String get settingsOfflineSigningTitle => 'Firma sin conexión';

  @override
  String get settingsOfflineSigningSubtitle =>
      'Escanea, revisa y firma con esta billetera con frase';

  @override
  String get settingsRemotePreviewsTitle => 'Vistas previas remotas';

  @override
  String get settingsRemotePreviewsSubtitle =>
      'Pasarela IPFS y No cargar nunca vistas previas remotas';

  @override
  String settingsContactsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count contactos',
      one: '$count contacto',
    );
    return '$_temp0';
  }

  @override
  String get settingsAllWallets => 'Todas las billeteras';

  @override
  String get settingsUnlocked => 'Desbloqueada';

  @override
  String get settingsLocked => 'Bloqueada';

  @override
  String settingsWalletsOnDevice(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count billeteras en este dispositivo',
      one: '$count billetera en este dispositivo',
    );
    return '$_temp0';
  }

  @override
  String settingsWatchOnlyAccountDetail(String id) {
    return 'Cuenta de solo lectura · $id';
  }

  @override
  String settingsWatchOnlyAddressDetail(String id) {
    return 'Dirección de solo lectura · $id';
  }

  @override
  String get settingsThisAccount => 'Esta cuenta';

  @override
  String get settingsThisAddress => 'Esta dirección';

  @override
  String get settingsWatchOnlyScope => 'Solo lectura';

  @override
  String get settingsStopWatchingSubtitle =>
      'La quita de este dispositivo. No cambia nada en la cadena.';

  @override
  String get aboutSaveSettingFailed => 'No se pudo guardar el ajuste.';

  @override
  String get aboutAskingGithub => 'Consultando a GitHub…';

  @override
  String get aboutNotCheckedYet => 'Aún no se ha comprobado';

  @override
  String aboutUpToDateChecked(String when) {
    return 'Al día · comprobado $when';
  }

  @override
  String aboutVersionAvailableChecked(String version, String when) {
    return 'La versión $version está disponible · comprobado $when';
  }

  @override
  String aboutVersionBuild(String version, String build) {
    return '$version · compilación $build';
  }

  @override
  String get aboutUpdatesGroup => 'Actualizaciones';

  @override
  String get aboutCheckForUpdates => 'Buscar actualizaciones';

  @override
  String get aboutCheckForUpdatesSubtitle =>
      'Consulta a GitHub una vez al día. GitHub ve tu dirección IP.';

  @override
  String get aboutCheckNow => 'Comprobar ahora';

  @override
  String get aboutUpdatesNote =>
      'Desactivado por defecto. Si está activado, Celaut pide a api.github.com la última versión una vez al día al iniciarse. \"Comprobar ahora\" hace lo mismo cuando lo pides, aunque esto esté desactivado. No se envía nada más: ni cuenta, ni token, ni versión de la app, ni identificador del dispositivo. Una descarga viene de github.com y se comprueba con la clave de firma de esta app antes de pedir a Android que la instale.';

  @override
  String get aboutThisBuild => 'Esta compilación';

  @override
  String get aboutUnauditedTitle => 'Prototipo sin auditar';

  @override
  String get aboutUnauditedSubtitle =>
      'Las transacciones en Ergo son irreversibles. Usa solo fondos que puedas permitirte perder.';

  @override
  String get aboutReleasesTitle => 'Versiones y notas';

  @override
  String get aboutReleasesSubtitle =>
      'Qué cambió en cada alfa, y el APK más reciente.';

  @override
  String get aboutLicenses => 'Licencias de código abierto';

  @override
  String get aboutLightClientNote =>
      'Celaut es un cliente ligero: habla con nodos públicos de Ergo por HTTPS y nunca envía tus claves a ningún sitio.';

  @override
  String get aboutSigningCertificate => 'Certificado de firma';

  @override
  String get aboutSigningCertificateSubtitle =>
      'SHA-256 de la clave con la que está firmada esta compilación. Una actualización debe estar firmada con la misma.';

  @override
  String get aboutReading => 'Leyendo…';

  @override
  String get aboutNotAvailableOnDevice => 'No disponible en este dispositivo.';

  @override
  String get aboutFingerprintCopied => 'Huella copiada';

  @override
  String get addressBookContactsEmpty =>
      'Personas a las que envías. Guarda una desde la pantalla Enviar.';

  @override
  String addressBookContactsSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count guardados',
      one: '$count guardado',
    );
    return '$_temp0';
  }

  @override
  String get addressBookLabelsSection => 'Etiquetas de mis direcciones';

  @override
  String get addressBookNoLabelsTitle => 'Aún no hay etiquetas';

  @override
  String get addressBookNoLabelsBody =>
      'Toca cualquiera de tus direcciones en la pantalla de inicio o en Recibir para ponerle nombre.';

  @override
  String get addressBookRemoveLabel => 'Quitar etiqueta';

  @override
  String get displayAppearance => 'Apariencia';

  @override
  String get displayFollowSystem => 'Seguir el sistema';

  @override
  String get displayAlwaysDark => 'Siempre oscuro';

  @override
  String get displayAlwaysLight => 'Siempre claro';

  @override
  String displaySystemPalettes(String dark, String light) {
    return 'Oscuro → $dark, claro → $light';
  }

  @override
  String get displayDarkPalette => 'Paleta oscura';

  @override
  String get displayLightPalette => 'Paleta clara';

  @override
  String get displayMoney => 'Dinero';

  @override
  String get displayPricesInUsd => 'Precios en USD';

  @override
  String get displayHideBalances => 'Ocultar saldos';

  @override
  String get displayHideBalancesSubtitle =>
      'Oculta las cantidades en la pantalla de inicio';

  @override
  String get themeTealName => 'Celaut Turquesa';

  @override
  String get themeTealHint => 'Turquesa, texto crema, coral';

  @override
  String get themeCreamName => 'Celaut Crema';

  @override
  String get themeCreamHint => 'Crema, texto turquesa, coral';

  @override
  String get themeObsidianName => 'Obsidiana';

  @override
  String get themeObsidianHint => 'Negro puro, acento acero';

  @override
  String get themeHarborName => 'Puerto';

  @override
  String get themeHarborHint => 'Azul marino oscuro, acento turquesa';

  @override
  String get themeEmberName => 'Brasa';

  @override
  String get themeEmberHint => 'Carbón cálido, acento cobre';

  @override
  String get themeParchmentName => 'Pergamino';

  @override
  String get themeParchmentHint => 'Crema, acento salvia';

  @override
  String get themeFrostName => 'Escarcha';

  @override
  String get themeFrostHint => 'Blanco frío, acento azul pizarra';

  @override
  String get networkConnectedNode => 'Nodo conectado';

  @override
  String get networkChecking => 'Comprobando…';

  @override
  String get networkCheckNodes => 'Comprobar nodos';

  @override
  String get networkNodes => 'Nodos';

  @override
  String get networkAddNodeLabel => 'Añadir URL de nodo';

  @override
  String get networkAddNodeHint => 'https://host  o  1.2.3.4:9053';

  @override
  String get networkAdd => 'Añadir';

  @override
  String get networkNodesNote =>
      'Toca un nodo para usarlo. Automático elige el nodo accesible con extraIndex y el menor retraso de índice. Los nodos integrados usan HTTPS; puedes añadir http://ip:port para un nodo que ejecutas o en el que confías, sin cifrar.';

  @override
  String get networkFindMoreNodes => 'Buscar más nodos';

  @override
  String get networkDiscovering =>
      'Pidiendo sus pares a cada nodo y comprobando cada uno…';

  @override
  String get networkDiscoverIntro =>
      'Pares de tus nodos que publican una API HTTPS.';

  @override
  String get networkSearching => 'Buscando…';

  @override
  String get networkSearch => 'Buscar';

  @override
  String get networkOpenInExplorer => 'Abrir en el explorador';

  @override
  String get networkCustom => 'Personalizado';

  @override
  String get networkCustomSiteSubtitle =>
      'Un sitio web que usa las rutas del explorador de Ergo Platform';

  @override
  String get networkExplorerWebsite => 'Sitio web del explorador';

  @override
  String get networkExplorerSiteNote =>
      'Dónde se abren los enlaces de transacciones y tokens. Esto no cambia ningún dato que lee la billetera.';

  @override
  String get networkExplorerApi => 'API del explorador';

  @override
  String get networkCustomApiSubtitle =>
      'Cualquier servidor que hable la API del explorador de Ergo Platform';

  @override
  String get networkExplorerApiUrl => 'URL de la API del explorador';

  @override
  String get networkExplorerApiNote =>
      'La fuente de los metadatos de tokens cuando los nodos no los tienen. ErgExplorer y Kadia usan sus propias API, así que no se pueden elegir aquí.';

  @override
  String get networkAutomatic => 'Automático';

  @override
  String get networkBestReachable => 'El mejor nodo accesible con extraIndex';

  @override
  String networkUsingHost(String host) {
    return 'Usando $host';
  }

  @override
  String networkExtraIndexLag(String lag) {
    return 'extraIndex, retraso $lag';
  }

  @override
  String get networkNoExtraIndex => 'sin extraIndex';

  @override
  String get networkDisable => 'Desactivar';

  @override
  String get networkEnable => 'Activar';

  @override
  String get networkNodeOff => 'Desactivado';

  @override
  String get networkNodeInUse => 'En uso';

  @override
  String get networkNodeStandby => 'En espera';

  @override
  String get networkNodeChosen => 'elegido';

  @override
  String get networkNodeUnreachable => 'inaccesible';

  @override
  String get networkAddNodeInvalid => 'Escribe https://host o http://ip:port';

  @override
  String get networkNodeAlreadyAdded => 'Este nodo ya está añadido';

  @override
  String get networkSearchNoAnswer =>
      'Ningún nodo respondió a la petición de pares. Comprueba tu conexión o prueba con otro nodo.';

  @override
  String networkSearchNoNewApi(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Se preguntó a $count nodos: sus pares no publican ninguna API HTTPS que no tengas ya.',
      one:
          'Se preguntó a $count nodo: sus pares no publican ninguna API HTTPS que no tengas ya.',
    );
    return '$_temp0';
  }

  @override
  String networkSearchNoneReachable(String found) {
    return 'Encontrados y comprobados: $found. Ninguno es accesible ahora.';
  }

  @override
  String networkSearchNoneReachablePartial(String checked, String found) {
    return 'Encontrados: $found; comprobados: $checked. Ninguno es accesible ahora.';
  }

  @override
  String networkSearchReachable(String reachable, String found) {
    return 'Encontrados: $found; accesibles: $reachable, primero los mejores.';
  }

  @override
  String networkSearchReachablePartial(
    String reachable,
    String checked,
    String found,
  ) {
    return 'Encontrados: $found; comprobados: $checked; accesibles: $reachable, primero los mejores.';
  }

  @override
  String get pinHelper => '6–32 caracteres. Primero el teclado numérico.';

  @override
  String get pinConfirm => 'Confirmar PIN';

  @override
  String get pinMismatch => 'Los PIN no coinciden';

  @override
  String get pinIncorrect => 'PIN incorrecto';

  @override
  String get securityBiometricDisabled => 'Desbloqueo biométrico desactivado';

  @override
  String get securityBiometricDisableFailed =>
      'No se pudo desactivar la biometría';

  @override
  String get securityPinLockoutCheckFailed =>
      'No se pudo comprobar el bloqueo del PIN';

  @override
  String get securityNoPinWalletFound =>
      'No se encontró ninguna billetera protegida con PIN.';

  @override
  String get securityBiometricEnabled => 'Desbloqueo biométrico activado';

  @override
  String get securityBiometricEnableFailed => 'No se pudo activar la biometría';

  @override
  String get securityChangePin => 'Cambiar PIN';

  @override
  String get securityNewPin => 'PIN nuevo';

  @override
  String get securityChange => 'Cambiar';

  @override
  String get securityNoPinWallet =>
      'No se encontró ninguna billetera protegida con PIN';

  @override
  String get securityPinChanged => 'PIN cambiado';

  @override
  String get securityPinChangedLockoutNotReset =>
      'PIN cambiado, pero no se pudo restablecer el estado de bloqueo';

  @override
  String get securityChangePinFailed => 'No se pudo cambiar el PIN';

  @override
  String get securityLockImmediately => 'Inmediatamente';

  @override
  String securityLockAfterSeconds(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tras $count segundos',
      one: 'Tras $count segundo',
    );
    return '$_temp0';
  }

  @override
  String securityLockAfterMinutes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tras $count minutos',
      one: 'Tras $count minuto',
    );
    return '$_temp0';
  }

  @override
  String get securityLockWhenBackgrounded => 'Bloquear en segundo plano';

  @override
  String get securityAutoLockUpdateFailed =>
      'No se pudo actualizar el bloqueo automático';

  @override
  String get securityAutoLock => 'Bloqueo automático';

  @override
  String get securityUnlockGroup => 'Desbloqueo';

  @override
  String get securityUnlockFirst => 'Primero desbloquea la billetera';

  @override
  String get securityUnlockFirstSubtitle =>
      'Los ajustes de biometría y PIN necesitan una billetera desbloqueada.';

  @override
  String get securityRetryUnlockSettings => 'Reintentar ajustes de desbloqueo';

  @override
  String get securityReadSetupFailed =>
      'No se pudo leer la configuración actual.';

  @override
  String get securityBiometricUnlock => 'Desbloqueo biométrico';

  @override
  String get securityBiometricOn =>
      'Activado. El PIN sigue desenvolviendo la clave.';

  @override
  String get securityOff => 'Desactivado';

  @override
  String get securitySetPinHint =>
      'Establece un PIN al crear o restaurar una billetera.';

  @override
  String get securityPinNote =>
      'Cinco PIN erróneos bloquean el acceso durante un tiempo. Celaut nunca guarda el PIN; solo desenvuelve la clave que descifra la frase de recuperación.';

  @override
  String get securityScreen => 'Pantalla';

  @override
  String get securityBlockScreenshots => 'Bloquear capturas de pantalla';

  @override
  String get securityScreenshotsBlocked =>
      'No se pueden capturar ni grabar las pantallas';

  @override
  String get securityScreenshotsAllowed =>
      'Desactivado: puedes capturar pantallas para informar de problemas';

  @override
  String get securitySeedScreensNote =>
      'Las pantallas de la frase de recuperación siempre bloquean las capturas, diga lo que diga este ajuste.';

  @override
  String get securitySpending => 'Gastos';

  @override
  String get securitySpendUnconfirmed => 'Gastar fondos sin confirmar';

  @override
  String get securitySpendUnconfirmedOn =>
      'Activado: los fondos recibidos y el cambio se pueden gastar al momento';

  @override
  String get securitySpendUnconfirmedOff =>
      'Desactivado: los fondos recibidos y el cambio esperan 1 confirmación';

  @override
  String get securitySpendingSaveFailed =>
      'No se pudo guardar el ajuste de gastos';

  @override
  String get updateAvailableTitle => 'Actualización disponible';

  @override
  String updateCardVersion(String version) {
    return 'Celaut $version';
  }

  @override
  String updateCardVersionDate(String version, String date) {
    return 'Celaut $version · $date';
  }

  @override
  String get updateHideNotes => 'Ocultar notas de la versión';

  @override
  String get updateReleaseNotes => 'Notas de la versión';

  @override
  String get updateDownloadProgress => 'Progreso de la descarga';

  @override
  String get updateDownloading => 'Descargando…';

  @override
  String updateDownloadingOf(String done, String total) {
    return 'Descargando $done de $total';
  }

  @override
  String get updateCheckingDownload => 'Comprobando la descarga';

  @override
  String get updateCheckingAgainstKey =>
      'Comprobando la descarga con la clave de firma de esta app…';

  @override
  String get updateCertMatches =>
      'El certificado de firma coincide con el de esta app.';

  @override
  String updateCertMatchesWith(String fingerprint) {
    return 'El certificado de firma coincide con el de esta app (SHA-256 $fingerprint…).';
  }

  @override
  String get updateAndroidChecksSignature =>
      'Android comprueba la firma por sí mismo al instalar.';

  @override
  String get updateInstall => 'Instalar';

  @override
  String get updateTryAgain => 'Volver a intentarlo';

  @override
  String get updateDownloadAndVerify => 'Descargar y verificar';

  @override
  String updateAssetNote(String name, String size) {
    return '$name · $size. Antes de instalar nada, Celaut comprueba el archivo con la suma de verificación que indica GitHub y con la clave con la que está firmada esta app.';
  }

  @override
  String get updateOpenReleasesPage => 'Abrir la página de versiones';

  @override
  String get updateNoApkForPhone =>
      'Esta versión no tiene APK para tu teléfono.';

  @override
  String updateNoticeAvailable(String version) {
    return 'Celaut $version está disponible.';
  }

  @override
  String get updateNoticeView => 'Ver';

  @override
  String get updateNoticeDismiss => 'Descartar';

  @override
  String get updateErrorTimeout => 'GitHub no respondió a tiempo.';

  @override
  String get updateErrorUnreachable =>
      'No se pudo conectar con GitHub. Comprueba tu conexión.';

  @override
  String updateErrorStatus(String status) {
    return 'GitHub respondió con un error ($status).';
  }

  @override
  String get updateErrorBadRedirect =>
      'GitHub envió una redirección que no se entendió.';

  @override
  String get updateErrorRedirectedAway =>
      'La solicitud se redirigió fuera de GitHub, así que se detuvo.';

  @override
  String get updateErrorTooManyRedirects =>
      'GitHub redirigió la solicitud demasiadas veces.';

  @override
  String get updateErrorRateLimited =>
      'GitHub está limitando las solicitudes desde esta red. Vuelve a intentarlo más tarde.';

  @override
  String get updateErrorNoRelease =>
      'GitHub no tiene ninguna versión que ofrecer.';

  @override
  String get updateErrorNotUnderstood =>
      'No se entendió la respuesta de GitHub.';

  @override
  String get updateErrorTooLarge =>
      'La respuesta de GitHub era más grande de lo esperado.';

  @override
  String get updateErrorNotOnGithub =>
      'La dirección de descarga no está en GitHub.';

  @override
  String get updateErrorDownloadTooLarge =>
      'La descarga es más grande de lo que Celaut acepta.';

  @override
  String get updateErrorStorage =>
      'Celaut no pudo guardar la descarga. ¿El teléfono se quedó sin espacio?';

  @override
  String get updateErrorLargerThanListed =>
      'La descarga es más grande de lo que indica GitHub, así que se detuvo.';

  @override
  String get updateErrorEndedEarly => 'La descarga terminó antes de tiempo.';

  @override
  String get updateRejectedWrongSigner =>
      'Esta descarga no está firmada con la misma clave que esta app, así que no debe instalarse. Se ha eliminado.';

  @override
  String get updateRejectedChecksum =>
      'Esta descarga no coincide con la suma de verificación SHA-256 que indica GitHub, así que puede estar dañada o manipulada. Se ha eliminado.';

  @override
  String get updateRejectedUnreadable =>
      'No se pudo leer la clave de firma de esta descarga, así que no se ofreció para instalar. Se ha eliminado.';

  @override
  String get updateRejectedAppKeyUnknown =>
      'Celaut no pudo leer su propia clave de firma, así que no puede comprobar esta descarga. Se ha eliminado.';

  @override
  String get updateCheckFailed => 'La búsqueda de actualizaciones falló.';

  @override
  String get updateNoApkSeeReleases =>
      'Esta versión no tiene APK para tu teléfono. La página de versiones tiene los archivos.';

  @override
  String get updateCannotKeepDownload =>
      'Este dispositivo no puede guardar una descarga.';

  @override
  String get updateDownloadCancelled => 'Descarga cancelada.';

  @override
  String get updateDownloadFailed => 'La descarga falló.';

  @override
  String get updateInstallPermission =>
      'Android necesita tu permiso primero. Permite que Celaut instale apps en la siguiente pantalla y vuelve a tocar Instalar.';

  @override
  String get updateInstallerFailed =>
      'Android no pudo abrir su instalador. La página de versiones tiene el archivo.';

  @override
  String get walletSettingsRenameFailed => 'No se pudo renombrar la billetera';

  @override
  String walletSettingsRemoveTitle(String name) {
    return '¿Quitar $name?';
  }

  @override
  String get walletSettingsRemoveBody =>
      'Esto quita la billetera de este dispositivo. Celaut no guarda una copia de la frase de recuperación; el papel en el que la escribiste al crear esta billetera es la única forma de volver a entrar.';

  @override
  String get walletSettingsRemoveFailed => 'No se pudo quitar la billetera';

  @override
  String get walletSettingsPinIndexTitle => 'Fijar índice de dirección';

  @override
  String get walletSettingsPinIndexIntro =>
      'Deriva la dirección en este índice y úsala como dirección principal para enviar y recibir. El índice 0 vuelve al valor predeterminado. El saldo sigue contando todas las direcciones de la billetera.';

  @override
  String get walletSettingsIndexLabel => 'Índice';

  @override
  String get walletSettingsPin => 'Fijar';

  @override
  String get walletSettingsInvalidIndex => 'Índice no válido';

  @override
  String walletSettingsIndexTooHigh(String max) {
    return 'Esta billetera no puede derivar más allá del índice $max';
  }

  @override
  String walletSettingsCannotDerive(String index) {
    return 'La billetera no puede derivar el índice $index';
  }

  @override
  String walletSettingsPinnedIndex(String index, String address) {
    return 'Índice $index fijado · $address';
  }

  @override
  String walletSettingsPinnedOutOfRange(String index) {
    return 'El índice fijado #$index no se puede derivar';
  }

  @override
  String walletSettingsPrimaryPinned(String index) {
    return 'Dirección principal: índice #$index';
  }

  @override
  String get walletSettingsPrimaryDefault => 'Dirección principal: índice 0';

  @override
  String walletSettingsOutOfRangeHint(String max) {
    return 'Esta billetera deriva hasta el índice $max. Quita el índice fijado o elige uno menor.';
  }

  @override
  String get walletSettingsPrimaryHint =>
      'La recepción y el cambio usan esta dirección por defecto hasta que se use.';

  @override
  String get walletSettingsUnpin => 'Quitar fijación';

  @override
  String get walletSettingsFreshAddresses => 'Direcciones nuevas';

  @override
  String get walletSettingsFreshAddressesSubtitle =>
      'La recepción y el cambio van a una dirección nueva cada vez, como en Nautilus. Desactivado: todo usa tu dirección fijada o la primera.';

  @override
  String get walletSettingsUnlockToChange =>
      'Desbloquea una billetera para cambiar este ajuste';

  @override
  String get walletSettingsPrivacySaveFailed =>
      'No se pudo actualizar el ajuste de privacidad';

  @override
  String get walletSettingsBackup => 'Copia de seguridad';

  @override
  String get walletSettingsBackupNote =>
      'Celaut no guarda una copia de la frase de recuperación. El papel en el que la escribiste al crear o restaurar es la única forma de volver a entrar.';

  @override
  String get walletSettingsRemoveWallet => 'Quitar billetera';

  @override
  String get walletSettingsRemoveWalletSubtitle =>
      'Solo de este dispositivo. Conserva la frase de recuperación.';

  @override
  String get secureSaveFailed => 'No se pudo guardar';

  @override
  String get secureSaveWrapKeyFailed =>
      'No se pudo guardar la clave envolvente';

  @override
  String get secureSavePinWrapFailed =>
      'No se pudo guardar la envoltura del PIN';

  @override
  String get secureLoadWrapKeyFailed => 'No se pudo cargar la clave envolvente';

  @override
  String get secureLoadPinWrapFailed =>
      'No se pudo cargar la envoltura del PIN';

  @override
  String get secureLoadFailed => 'No se pudo cargar';

  @override
  String secureDeleteWrapKeyFailed(String detail) {
    return 'No se pudo eliminar la clave envolvente: $detail';
  }

  @override
  String secureDeleteSecretsFailed(String detail) {
    return 'No se pudieron eliminar los secretos de la billetera: $detail';
  }

  @override
  String secureDeleteWalletFailed(String detail) {
    return 'No se pudo eliminar la billetera: $detail';
  }

  @override
  String secureCheckFailed(String detail) {
    return 'No se pudo comprobar: $detail';
  }

  @override
  String get secureCheckPinWrapFailed =>
      'No se pudo comprobar la envoltura del PIN';

  @override
  String get secureCheckWrapKeyFailed =>
      'No se pudo comprobar la clave envolvente';

  @override
  String get secureCheckBiometricsFailed => 'No se pudo comprobar la biometría';

  @override
  String get secureBiometric => 'Biometría';

  @override
  String get secureLoadPinGateFailed => 'No se pudo cargar el bloqueo del PIN';

  @override
  String secureTooManyAttempts(String seconds) {
    return 'Demasiados intentos. Vuelve a intentarlo en $seconds s';
  }

  @override
  String securePersistPinGateFailed(String detail) {
    return 'No se pudo guardar el bloqueo del PIN: $detail';
  }

  @override
  String secureListWalletsFailed(String detail) {
    return 'No se pudieron listar las billeteras: $detail';
  }

  @override
  String get secureBiometricChanged =>
      'La biometría registrada cambió; vuelve a escribir la frase de recuperación';

  @override
  String get notifyChannelName => 'Pagos entrantes';

  @override
  String get notifyChannelDescription =>
      'Se vio en la red un pago a una de tus direcciones.';

  @override
  String notifyIncomingBody(String amount, String wallet) {
    return '$amount a $wallet';
  }

  @override
  String get notifyPaymentOnTheWay => 'Pago en camino';

  @override
  String get notifyPaymentReceived => 'Pago recibido';

  @override
  String utxoBoxCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cajas',
      one: '$count caja',
    );
    return '$_temp0';
  }

  @override
  String utxoNBoxes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cajas',
      one: '$count caja',
    );
    return '$_temp0';
  }

  @override
  String utxoTokenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tokens',
      one: '$count token',
    );
    return '$_temp0';
  }

  @override
  String coinPrivacyNote(String count, String addresses) {
    return 'Estas $count cajas están en $addresses direcciones distintas. Gastarlas juntas vincula públicamente esas direcciones a una misma billetera.';
  }

  @override
  String coinConfirmationNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count de estas cajas aún se están confirmando. Esta transacción solo puede confirmarse después de la que las creó, y falla si esa se descarta.',
      one:
          'Una de estas cajas aún se está confirmando. Esta transacción solo puede confirmarse después de la que la creó, y falla si esa se descarta.',
    );
    return '$_temp0';
  }

  @override
  String get coinSelectionNone => 'Ninguna caja elegida — Celaut las elegirá.';

  @override
  String coinRawUnits(int count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$amount unidades base',
      one: '$amount unidad base',
    );
    return '$_temp0';
  }

  @override
  String get coinRawUnitsLabel => 'unidades base';

  @override
  String coinRawUnitsOf(String units, String label) {
    return '$units de $label';
  }

  @override
  String get pendingBalanceHidden => '•••• ERG pendientes';

  @override
  String pendingBalanceTotalUnknown(String total) {
    return '$total ERG · pendiente';
  }

  @override
  String pendingBalanceTotalMoved(String total, String moved) {
    return '$total ERG · $moved pendientes';
  }

  @override
  String pendingBalanceMoved(String moved, String confirmed) {
    return '$moved ERG pendientes · $confirmed confirmados';
  }

  @override
  String pendingBalanceUnknown(String confirmed) {
    return 'Pendiente · $confirmed confirmados';
  }

  @override
  String get spendUnconfirmedNote =>
      'Desactivado: el dinero que recibes, y el cambio de tus propios envíos, espera una confirmación (el siguiente bloque, normalmente unos minutos) antes de que Celaut lo gaste. Activado: se puede gastar al momento, pero si la transacción que lo trajo se descarta, la que lo gasta también falla. En ambos casos, las monedas que una transacción pendiente ya está gastando nunca se vuelven a usar.';

  @override
  String get rentNoChargeZeroRate =>
      'No se cobra alquiler de almacenamiento con la tarifa actual.';

  @override
  String rentNoChargeOverflow(String bytes) {
    return 'Con las reglas actuales no se puede cobrar alquiler de almacenamiento a una caja de más de $bytes bytes.';
  }

  @override
  String rentRatePerByte(String fee) {
    return '$fee por byte';
  }

  @override
  String rentRatePerByteDefault(String fee) {
    return '$fee por byte (tarifa predeterminada)';
  }

  @override
  String get rentWhenNow => 'ahora';

  @override
  String get rentWhenWithinDay => 'en menos de un día';

  @override
  String rentWhenInDays(String days) {
    return 'en ~$days días';
  }

  @override
  String rentWhenMonthYear(String month, String year) {
    return '~$month $year';
  }

  @override
  String get separateNeedsSourceAddress =>
      'Actualiza las cajas para identificar la dirección de origen.';

  @override
  String get separateMinPerBox =>
      'Cada caja de token necesita al menos 0.001 ERG.';

  @override
  String get separateFundingInvalid =>
      'Los fondos deben ser otras cajas solo con ERG en la dirección de origen.';

  @override
  String get separateInvalidTokenAmount =>
      'El origen contiene una cantidad de token no válida.';

  @override
  String get separateTokenTypeRange =>
      'Elige una caja que tenga entre 2 y 150 tipos de token.';

  @override
  String get separateInvalidErgValue =>
      'Las cajas seleccionadas contienen un valor de ERG no válido.';

  @override
  String get separateOverLimit =>
      'La cantidad de ERG seleccionada supera el límite de la transacción.';

  @override
  String separateAddFunding(String amount) {
    return 'Añade $amount en cajas de fondos.';
  }

  @override
  String get utxoHealthTidy => 'Ordenada';

  @override
  String get utxoHealthTidyHint =>
      'Pocas cajas: los envíos eligen entradas rápido y pagan lo mínimo.';

  @override
  String get utxoHealthModerate => 'Moderada';

  @override
  String get utxoHealthModerateHint =>
      'Los envíos pueden necesitar varias entradas; consolidar el polvo (dust) mantiene bajas las comisiones.';

  @override
  String get utxoHealthFragmented => 'Fragmentada';

  @override
  String get utxoHealthFragmentedHint =>
      'Muchas cajas pequeñas hacen que cada envío use más entradas. Barre el polvo o consolida.';

  @override
  String sendRecipientPrefix(String number) {
    return 'Destinatario $number: ';
  }

  @override
  String sendErrorNotErgoAddress(String who) {
    return '${who}no es una dirección de Ergo';
  }

  @override
  String sendErrorMinimum(String who, String amount) {
    return '${who}mínimo $amount ERG';
  }

  @override
  String sendErrorTokenNotInWallet(String who) {
    return '${who}el token no está en esta billetera';
  }

  @override
  String sendErrorEnterTokenAmount(String who, String token) {
    return '${who}escribe una cantidad de token para $token';
  }

  @override
  String sendErrorTokenOverAllocated(String who, String amount, String token) {
    return '${who}tienes $amount $token en total entre todos los destinatarios';
  }

  @override
  String get coldUnlockBeforeReview =>
      'Desbloquea la billetera con frase de recuperación antes de revisar.';

  @override
  String get coldWalletLockedOrChanged =>
      'Billetera bloqueada o cambiada. Reinicia y revisa con la billetera seleccionada.';

  @override
  String get coldRefusingBroadcast =>
      'Difusión rechazada: no hay ninguna respuesta verificada.';

  @override
  String get coldTxIdMismatch => 'El ID de transacción del nodo no coincide.';

  @override
  String get coldTitleHot => 'Envío desde billetera fría';

  @override
  String get coldTitleOffline => 'Firma sin conexión';

  @override
  String get coldSessionNote =>
      'Las sesiones sin firmar caducan a los 30 minutos. Atrás pausa; vuelve aquí para continuar. Las respuestas verificadas siguen disponibles para reintentar. Cerrar la app descarta todas las sesiones.';

  @override
  String coldRefused(String error) {
    return 'Rechazado: $error';
  }

  @override
  String get coldScanRequestCodes =>
      'Escanea cada código de solicitud con el firmante sin conexión.';

  @override
  String get coldSignedScanResponse =>
      'Firmada. Escanea cada código de respuesta con la billetera en línea.';

  @override
  String get coldLoadQrCodes => 'Cargar códigos QR';

  @override
  String get coldScanSignedResponse => 'Escanear respuesta firmada';

  @override
  String get coldShowRequestAgain =>
      'Volver a mostrar los códigos de solicitud';

  @override
  String get coldCollectResponse => 'Recopilar respuesta firmada (CSTX)';

  @override
  String get coldCollectRequest => 'Recopilar solicitud de firma (CSR)';

  @override
  String coldScannedProgress(String received, String total) {
    return '$received de $total escaneados';
  }

  @override
  String coldMissingPages(String pages) {
    return 'Páginas que faltan: $pages';
  }

  @override
  String get coldScanRefused =>
      'Se rechazó este escaneo. Descarta las páginas recopiladas y empieza de nuevo.';

  @override
  String get coldScanACode => 'Escanear un código';

  @override
  String get coldScanNextCode => 'Escanear el siguiente código';

  @override
  String get coldResetPages => 'Reiniciar páginas recopiladas';

  @override
  String get coldVerifySigned => 'Verificar transacción firmada';

  @override
  String get coldReviewTransaction => 'Revisar transacción';

  @override
  String get coldReviewWarning =>
      'Comprueba por tu cuenta las direcciones completas de los destinatarios y las cantidades. Mantén este dispositivo sin conexión. No se usan las etiquetas de la billetera en línea.';

  @override
  String get coldCheckedEverything =>
      'Comprobé cada salida, token y comisión en este dispositivo';

  @override
  String get coldConfirmSign => 'Confirmar y firmar sin conexión';

  @override
  String get coldRejectReset => 'Rechazar y reiniciar';

  @override
  String get coldVerifiedMatch =>
      'Todas las firmas son válidas y la transacción coincide exactamente con el pago preparado.';

  @override
  String coldTransactionId(String id) {
    return 'ID de transacción: $id';
  }

  @override
  String get coldBroadcastVerified => 'Difundir transacción verificada';

  @override
  String get coldRetryNote =>
      'Si la red falla, reintentar envía la misma transacción verificada. No la vuelvas a crear mientras su estado sea incierto.';

  @override
  String get coldSubmitted => 'Transacción enviada';

  @override
  String get coldDiscardSession => 'Descartar sesión';

  @override
  String coldReviewNetwork(String network) {
    return 'Revisión · $network';
  }

  @override
  String coldMinerFeeValue(String fee) {
    return 'Comisión de minería: $fee';
  }

  @override
  String get coldOutputsNote =>
      'Abajo aparecen todas las salidas. “Tu dirección” se verifica con las claves locales; puede ser cambio o un pago a ti mismo.';

  @override
  String get coldYourAddress => 'Tu dirección';

  @override
  String get coldExternalRecipient =>
      'Destinatario externo / pago a una aplicación';

  @override
  String coldTokenId(String id) {
    return 'ID de token: $id';
  }

  @override
  String coldQuantityBaseUnits(String amount) {
    return 'Cantidad: $amount unidades base';
  }

  @override
  String coldTokenBurns(String none) {
    return 'Quemas de tokens: $none';
  }

  @override
  String coldTokenCreation(String none) {
    return 'Creación de tokens: $none';
  }

  @override
  String get coldNone => 'Ninguna';

  @override
  String coldTokenAmountBaseUnits(String id, String amount) {
    return '$id · $amount unidades base';
  }

  @override
  String coldCodeOf(String page, String total) {
    return 'Código $page de $total';
  }

  @override
  String get coldPrevious => 'Anterior';

  @override
  String get coldAutoRepeat => 'Repetición automática';

  @override
  String get coldPause => 'Pausar';

  @override
  String get coldNext => 'Siguiente';

  @override
  String get coldRefreshWatchedFirst =>
      'Primero actualiza la cuenta observada.';

  @override
  String get coldChooseNodeFirst => 'Primero elige un nodo en línea.';

  @override
  String get coldAmountPositive =>
      'Escribe un número entero positivo en Cantidad (nanoERG).';

  @override
  String get coldTokenQuantityPositive =>
      'Escribe un número entero positivo en Cantidad de tokens.';

  @override
  String get coldNodeChanged =>
      'El nodo cambió durante la preparación. Vuelve a intentarlo.';

  @override
  String get coldSendTitle => 'Enviar con firmante sin conexión';

  @override
  String get coldWatchIntro =>
      'Pagos P2PK en mainnet. Este origen de solo lectura no tiene claves. Una billetera con frase de recuperación sin conexión debe revisar y firmar la solicitud.';

  @override
  String get coldChangeNote =>
      'El cambio, incluidos los tokens restantes, vuelve a esta misma dirección observada. Reutilizarla reduce la privacidad. Una cuenta observada sigue más direcciones.';

  @override
  String get coldSignerMustOwn =>
      'El firmante sin conexión debe poseer esta dirección P2PK de mainnet. Celaut busca automáticamente en la cuenta 0 de EIP-3, índices externos 0–512.';

  @override
  String get coldResumeSend => 'Reanudar envío en frío';

  @override
  String get coldRecipientLabel => 'Dirección completa del destinatario';

  @override
  String get coldAmountNanoLabel => 'Cantidad en nanoERG (1 ERG = 1000000000)';

  @override
  String get coldTokenIdOptional => 'ID de token (opcional)';

  @override
  String get coldTokenQuantityLabel =>
      'Cantidad de tokens en unidades base (opcional)';

  @override
  String get coldPrepareRequest => 'Preparar solicitud en frío';

  @override
  String get priceHistoryNeedsExtraIndex =>
      'Este nodo no puede dar el historial de precios: necesita el índice extra.';

  @override
  String get oracleSigmaUsd => 'Oráculo SigmaUSD';

  @override
  String get oracleDexyUsd => 'Oráculo Dexy USD';

  @override
  String get oracleDexyGold => 'Oráculo de oro Dexy';

  @override
  String get oracleAvl => 'Oráculo AVL';

  @override
  String priceAgeMinutes(String count) {
    return '$count min';
  }

  @override
  String priceAgeHours(String count) {
    return '$count h';
  }

  @override
  String priceAgeDays(String count) {
    return '$count días';
  }

  @override
  String priceAgeOld(String age) {
    return 'hace $age';
  }

  @override
  String priceSourceLine(String source, String via) {
    return '$source · ERG vía $via';
  }

  @override
  String priceSourceLineStale(String source, String via) {
    return '$source · sin actualizar · ERG vía $via';
  }

  @override
  String priceHistoryUnreadable(String error) {
    return 'No se pudo leer el historial de precios: $error';
  }

  @override
  String get priceNoNode => 'No hay ningún nodo conectado.';

  @override
  String get priceNoHeight => 'Aún no se conoce la altura del nodo.';

  @override
  String priceNoHistoryYet(String source) {
    return 'Este nodo aún no tiene historial de precios de $source.';
  }

  @override
  String get priceOraclePools => 'Pools de oráculos';

  @override
  String get priceSourceBlurb =>
      'En cadena: ERG del pool de oráculos de SigmaUSD (el pool de oráculos ERG/USD), oro del oráculo de oro Dexy y las principales monedas envueltas del multioráculo AVL. Un precio antiguo se muestra con su antigüedad, nunca como actual. Solo lee tu nodo. Los demás tokens no tienen precio.';

  @override
  String priceNoneYet(String source) {
    return 'Aún sin precio · $source no han respondido';
  }

  @override
  String get priceNoPool =>
      'Sin precio · ningún pool de oráculos cotiza este token';

  @override
  String priceEach(String price) {
    return '$price cada uno';
  }

  @override
  String priceHeld(String value) {
    return '$value en tu poder';
  }

  @override
  String get priceNotCounted => 'no cuenta en los totales (sin actualizar)';

  @override
  String get verifiedNetaNote =>
      'Su equipo abandonó el proyecto anetaBTC y los poseedores se quedaron sin el producto prometido. Considera que NETA no tiene respaldo.';

  @override
  String get tokenErrorNoName => 'Ponle un nombre al token';

  @override
  String get tokenErrorNameTooLong =>
      'El nombre es demasiado largo (64 caracteres como máximo)';

  @override
  String get tokenErrorDecimalsRange =>
      'Los decimales deben estar entre 0 y 18';

  @override
  String get tokenErrorAmountMissing => 'Escribe la cantidad que vas a emitir';

  @override
  String get tokenErrorAmountZero => 'La cantidad debe ser mayor que cero';

  @override
  String get tokenErrorAmountTooBig =>
      'La cantidad supera lo que cabe en una caja';

  @override
  String get nftErrorDecimals => 'Un NFT no tiene decimales';

  @override
  String get nftErrorOneUnit => 'Un NFT es una sola unidad';

  @override
  String get nftErrorHash =>
      'El hash del contenido debe tener 64 caracteres hexadecimales (SHA-256)';

  @override
  String get nftErrorLink => 'El enlace debe empezar por https:// o ipfs://';

  @override
  String get tokenIssue => 'Emitir';

  @override
  String get tokenBurn => 'Quemar';

  @override
  String get tokenIssueNftTitle => 'Emitir un NFT';

  @override
  String get tokenIssueTokenTitle => 'Emitir un token';

  @override
  String get tokenIssueDetail =>
      'El nuevo token llega a esta billetera. Su nombre, descripción y decimales se escriben en la cadena y no se pueden cambiar después.';

  @override
  String get tokenSupply => 'Suministro';

  @override
  String tokenSupplyDecimals(int count, String amount) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$amount · $count decimales',
      one: '$amount · $count decimal',
    );
    return '$_temp0';
  }

  @override
  String get tokenDescription => 'Descripción';

  @override
  String get tokenKind => 'Tipo';

  @override
  String get tokenLink => 'Enlace';

  @override
  String get tokenIdRow => 'ID del token';

  @override
  String get tokenBoxValue => 'Valor de la caja';

  @override
  String get tokenIssuanceSubmitted => 'Emisión del token enviada';

  @override
  String get tokenIssuanceNote =>
      'El ID del token queda en la pantalla de emisión. El token aparece en tus activos tras la confirmación.';

  @override
  String tokenNamedIssuanceSubmitted(String name) {
    return 'Emisión de $name enviada';
  }

  @override
  String get tokenIssuedExplainer =>
      'Aparece en tus activos cuando se confirme la transacción. El ID del token es como lo conocen otras billeteras y sitios.';

  @override
  String get tokenIdLabel => 'ID del token';

  @override
  String get tokenCopyId => 'Copiar ID del token';

  @override
  String get tokenIdCopied => 'ID del token copiado';

  @override
  String get tokenViewReceipt => 'Ver recibo de la transacción';

  @override
  String get tokenTransactionId => 'ID de transacción';

  @override
  String get tokenIssueAnother => 'Emitir otro';

  @override
  String get tokenIssueIntro =>
      'Un token se crea con una transacción desde esta billetera. Esa transacción fija su ID, y su nombre, descripción y decimales se escriben una sola vez, en la cadena.';

  @override
  String get nftSubtitle =>
      'Una sola unidad con un hash de contenido y un enlace';

  @override
  String get tokenDescriptionOptional => 'Descripción (opcional)';

  @override
  String get tokenSupplyHelper => 'Unidades enteras, se admiten decimales';

  @override
  String get tokenDecimals => 'Decimales';

  @override
  String get tokenDecimalsHelper => '0 a 18';

  @override
  String get nftKindPicture => 'Imagen';

  @override
  String get nftKindAudio => 'Audio';

  @override
  String get nftKindVideo => 'Video';

  @override
  String get nftHashLabel => 'SHA-256 del contenido (hex, opcional)';

  @override
  String get nftHashHelper => '64 caracteres hex';

  @override
  String get nftLinkLabel => 'Enlace (opcional)';

  @override
  String get nftLinkHelper => 'https:// o ipfs://';

  @override
  String get tokenIssueCost =>
      'Cuesta 0.001 ERG por la caja del token más la comisión de minería.';

  @override
  String get tokenPreparing => 'Preparando…';

  @override
  String tokenBurnEnterAmount(String token) {
    return 'Escribe cuánto $token quieres quemar';
  }

  @override
  String tokenBurnYouHold(String amount, String token) {
    return 'Tienes $amount $token';
  }

  @override
  String get tokenBurnPick => 'Elige un token para quemar';

  @override
  String tokenBurnTypeToGoOn(String word) {
    return 'Escribe $word para continuar';
  }

  @override
  String get tokenBurnTitle => 'Quemar tokens';

  @override
  String get tokenBurnForGood => 'Quemar para siempre';

  @override
  String get tokenBurnDetail =>
      'Estas unidades quedan fuera de todas las salidas de la transacción y dejan de existir. Nadie, ni siquiera Celaut, puede recuperarlas.';

  @override
  String get tokenBurnBackToYou => 'Vuelve a ti';

  @override
  String get tokenBurnSubmitted => 'Quema de tokens enviada';

  @override
  String get tokenBurnWarning =>
      'Quemar destruye los tokens para siempre. No es un envío: las unidades salen de la cadena en vez de pasar a alguien. Úsalo con tokens que seguro que no quieres recuperar, como spam o un suministro que quieres reducir.';

  @override
  String get tokenBurnNoTokens => 'Esta billetera no tiene tokens.';

  @override
  String get tokenBurnInWallet => 'Tokens en esta billetera';

  @override
  String tokenBurnHeldRow(String amount, String id) {
    return '$amount en tu poder · $id';
  }

  @override
  String tokenBurnOneUnit(String token) {
    return '$token: la única unidad';
  }

  @override
  String tokenBurnAmountLabel(String token) {
    return '$token para quemar';
  }

  @override
  String tokenBurnOf(String amount) {
    return 'De $amount';
  }

  @override
  String get tokenBurnAll => 'TODO';

  @override
  String tokenBurnTypeToConfirm(String word) {
    return 'Escribe $word para confirmar';
  }

  @override
  String get assetsTitle => 'Activos';

  @override
  String get assetsShowList => 'Mostrar lista de coleccionables';

  @override
  String get assetsShowGrid => 'Mostrar cuadrícula de coleccionables';

  @override
  String get assetsClearCache =>
      'Borrar caché de coleccionables (los activos guardados conservan sus metadatos)';

  @override
  String get assetsAll => 'Todos';

  @override
  String get assetsCollectibles => 'Coleccionables';

  @override
  String get assetsSearchLabel => 'Buscar nombre o ID de token';

  @override
  String get assetsClearSearch => 'Borrar búsqueda';

  @override
  String assetsCollectibleCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count coleccionables identificados · las vistas previas solo se cargan cuando tú eliges',
      one:
          '$count coleccionable identificado · las vistas previas solo se cargan cuando tú eliges',
    );
    return '$_temp0';
  }

  @override
  String assetsTokenIdCount(String count) {
    return '$count ID de token';
  }

  @override
  String assetsTokenIdCountIncomplete(String count, String unknown) {
    return '$count ID de token · $unknown con metadatos incompletos';
  }

  @override
  String get assetsPublicOnly => 'Solo activos públicos';

  @override
  String get assetsNotLoaded => 'Activos sin cargar';

  @override
  String assetsLastSynced(String age) {
    return 'Última sincronización de activos: $age';
  }

  @override
  String get assetsHidden => 'Activos ocultos';

  @override
  String get assetsNoMatch => 'Ningún activo coincide con tu búsqueda';

  @override
  String get assetsNoCollectibles =>
      'No hay coleccionables identificados en los activos cargados';

  @override
  String get assetsIncompleteHint =>
      'Algunos tokens tienen metadatos incompletos. Ábrelos en Todos para ver sus detalles.';

  @override
  String get tokenCautionFlagged => 'Precaución: este token está marcado';

  @override
  String assetsHeld(String amount) {
    return 'En tu poder: $amount';
  }

  @override
  String tokenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ID de token (incl. NFT)',
      one: '$count ID de token (incl. NFT)',
    );
    return '$_temp0';
  }

  @override
  String tokenCountPublic(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ID públicos de token (incl. NFT)',
      one: '$count ID público de token (incl. NFT)',
    );
    return '$_temp0';
  }

  @override
  String get artworkClose => 'Cerrar imagen';

  @override
  String get artworkTitle => 'Imagen';

  @override
  String get artworkResetZoom => 'Restablecer zoom';

  @override
  String get artworkPreviewHidden =>
      'Vista previa oculta. Vuelve a abrir los detalles del activo para verla.';

  @override
  String get artworkZoomHint =>
      'Pellizca o desplázate para hacer zoom. Arrastra para mover.';

  @override
  String get tokenMetaAsciiProvider =>
      'Configura un proveedor de metadatos HTTPS con ASCII/punycode';

  @override
  String tokenMetaLoadFrom(String host) {
    return 'Cargar metadatos de $host';
  }

  @override
  String tokenMetaLoadFromNode(String host) {
    return 'Cargar metadatos de $host (nodo)';
  }

  @override
  String get tokenMetaHostNode => 'nodo';

  @override
  String get tokenMetaHostProvider => 'proveedor';

  @override
  String get tokenMetaPrivacy =>
      'Este proveedor puede ver tu dirección IP y el ID del token solicitado. El texto del emisor puede ser engañoso. No se descargará ninguna imagen.';

  @override
  String get tokenMetaLoad => 'Cargar metadatos';

  @override
  String get tokenMetaBusy =>
      'Otra solicitud de metadatos está terminando — vuelve a intentarlo';

  @override
  String tokenMetaUnavailableFrom(String host) {
    return 'Metadatos no disponibles en $host';
  }

  @override
  String get tokenDetailsHidden => 'Detalles del activo ocultos';

  @override
  String get tokenMetaOffline => 'Metadatos no disponibles sin conexión';

  @override
  String get tokenMetaCancel => 'Cancelar solicitud de metadatos';

  @override
  String get tokenMetaLoading => 'Cargando metadatos…';

  @override
  String tokenCurated(String project) {
    return 'Token curado · $project';
  }

  @override
  String tokenCaution(String note) {
    return 'Precaución: $note';
  }

  @override
  String get tokenCautionDefault => 'este token está marcado.';

  @override
  String tokenImpersonation(String ticker, String project) {
    return 'Este token se llama como $ticker, pero no es el $ticker verificado de $project. Comprueba el ID antes de confiar en él.';
  }

  @override
  String get artworkNoMediaLink =>
      'No hay enlace multimedia en los metadatos de emisión.';

  @override
  String get artworkLoadBelow =>
      'Carga los metadatos abajo para buscar una imagen.';

  @override
  String get artworkPreviewUnsupported => 'Vista previa no compatible';

  @override
  String get artworkLinkUnavailable => 'Enlace de la imagen no disponible';

  @override
  String get artworkMediaUnavailable => 'Metadatos multimedia no disponibles';

  @override
  String get artworkConsent => 'La imagen solo se carga con tu consentimiento';

  @override
  String get tokenYouHold => 'TIENES';

  @override
  String get tokenIdCaps => 'ID DEL TOKEN';

  @override
  String tokenLeaveFor(String host) {
    return '¿Salir de Celaut hacia $host?';
  }

  @override
  String get tokenExplorerPrivacy =>
      'El explorador puede ver tu dirección IP y el ID de este token.';

  @override
  String get tokenOpenExplorer => 'Abrir explorador';

  @override
  String get tokenExplorer => 'Explorador';

  @override
  String get tokenMetaDetails => 'Detalles de metadatos y multimedia';

  @override
  String tokenOriginalEmission(String amount) {
    return 'Emisión original: $amount (según el proveedor)';
  }

  @override
  String get tokenOriginalEmissionUnavailable =>
      'Emisión original no disponible';

  @override
  String tokenDecimalsLine(String decimals, String evidence) {
    return 'Decimales: $decimals · $evidence';
  }

  @override
  String get tokenDecimalsDeclared => 'declarados por el emisor';

  @override
  String get tokenDecimalsNone => 'ninguno declarado, así que unidades enteras';

  @override
  String get tokenDecimalsListed => 'de una lista de tokens';

  @override
  String get tokenDecimalsLastShown => 'como se mostraron la última vez';

  @override
  String get tokenDecimalsUnknown =>
      'Decimales desconocidos · las cantidades se muestran en unidades sin escalar';

  @override
  String tokenDeclaredKind(String kind) {
    return 'Tipo de contenido declarado: $kind';
  }

  @override
  String tokenMetaSource(String source) {
    return 'Origen de los metadatos: $source';
  }

  @override
  String get tokenMediaHashMissing =>
      'Hash multimedia de emisión ausente o no válido';

  @override
  String tokenMediaHash(String hash) {
    return 'Hash multimedia de emisión: $hash';
  }

  @override
  String get tokenCopyMediaUri => 'Copiar URI multimedia como texto';

  @override
  String get tokenIssuanceRegisters => 'Registros de emisión originales (hex)';

  @override
  String tokenSend(String token) {
    return 'Enviar $token';
  }

  @override
  String get syncLockedWalletsExplainer =>
      'Las billeteras bloqueadas se actualizan con datos públicos cada 5 minutos, solo en las direcciones que esta app ya conoce. Desbloquea una para incluir direcciones nuevas.';

  @override
  String get watchSaveAddressesFailed =>
      'No se pudieron guardar las direcciones observadas. Vuelve a intentarlo.';

  @override
  String get watchLimitations =>
      'Solo direcciones de pago públicas. No puede firmar localmente; para enviar hace falta un firmante sin conexión.';

  @override
  String watchDisclosure(String limitations) {
    return 'Una clave pública extendida permite a quien la tenga derivar y vincular para siempre todas las direcciones de pago públicas de esta cuenta. Importa solo una clave que quieras compartir con este dispositivo. $limitations';
  }

  @override
  String get watchExpected =>
      'Se esperaba una clave pública extendida de Ergo Wallet App: 156 caracteres hexadecimales que empiezan por 0488b21e (mainnet), profundidad 4 cadena externa /0 o profundidad 3 cuenta 0. No se admiten xpub en Base58 ni testnet.';

  @override
  String get watchIncompleteDerivation => 'Derivación incompleta';

  @override
  String watchScanIncomplete(String count) {
    return 'Escaneo incompleto tras $count direcciones; no se confirmó ninguna dirección de recepción sin usar.';
  }

  @override
  String get watchNodeChanged =>
      'El nodo cambió. Actualiza la cuenta antes de recibir.';

  @override
  String get watchSaveAccountsFailed =>
      'No se pudieron guardar las cuentas observadas. Vuelve a intentarlo.';

  @override
  String get watchNodeChangedDuringScan =>
      'El nodo cambió durante el escaneo; vuelve a actualizar.';

  @override
  String watchAccountRefreshUnavailable(String detail) {
    return 'No se pudo actualizar la cuenta: $detail';
  }

  @override
  String get syncPublicKnownOnly =>
      'Datos públicos · solo direcciones conocidas';

  @override
  String get syncSyncing => 'Sincronizando…';

  @override
  String get syncOutOfSync => 'Desactualizada';

  @override
  String get syncHistoryIncomplete => 'Historial incompleto';

  @override
  String get syncSynced => 'Sincronizada';

  @override
  String get syncNotSynced => 'Sin sincronizar';

  @override
  String syncPinIssue(String index, String max) {
    return 'No se puede derivar el índice fijado $index (máx. $max). Restablécelo en Ajustes.';
  }

  @override
  String dashboardStartupError(String detail) {
    return 'Error: $detail';
  }

  @override
  String get dashboardUnlockForErgoPay =>
      'Desbloquea una billetera para continuar con la solicitud de ErgoPay.';

  @override
  String get dashboardUnlockForNotification =>
      'Desbloquea una billetera para abrir lo que indica la notificación.';

  @override
  String get dashboardScanNotErgo =>
      'No es una dirección de Ergo ni un enlace de ErgoPay';

  @override
  String dashboardOpenFailed(String detail) {
    return 'No se pudo abrir la billetera: $detail';
  }

  @override
  String dashboardWalletRemoved(String name) {
    return '\"$name\" eliminada';
  }

  @override
  String get dashboardStoppedWatching => 'Ya no se observa';

  @override
  String get dashboardNoAddressDerived =>
      'Desbloqueada, pero no se pudo derivar ninguna dirección';

  @override
  String get dashboardPinLockoutCheckFailed =>
      'No se pudo comprobar el bloqueo del PIN';

  @override
  String get dashboardNoPinWallet =>
      'No se encontró ninguna billetera protegida con PIN.';

  @override
  String get dashboardBiometricNotSetUp =>
      'El desbloqueo biométrico no está configurado para esta billetera. Usa su PIN.';

  @override
  String get dashboardBiometricCancelled =>
      'Desbloqueo biométrico cancelado. Toca Desbloquear para volver a intentarlo, o usa tu PIN.';

  @override
  String get dashboardWalletDataMissing =>
      'No se encontraron los datos de la billetera en este dispositivo.';

  @override
  String get dashboardNoWalletFound =>
      'No se encontró ninguna billetera. Crea o restaura una.';

  @override
  String get dashboardSetPinTitle => 'Crea un PIN';

  @override
  String get dashboardLater => 'Más tarde';

  @override
  String get dashboardUnlockFirst => 'Primero desbloquea la billetera';

  @override
  String get dashboardAddressLoading => 'La dirección todavía se está cargando';

  @override
  String get dashboardScanQrTooltip => 'Escanear un código QR';

  @override
  String get dashboardWalletSettingsTooltip => 'Ajustes de la billetera';

  @override
  String get homeUnlocked => 'Desbloqueada';

  @override
  String get homeLocked => 'Bloqueada';

  @override
  String get offlineNoNodes =>
      'No hay nodos accesibles. Toca Reintentar para comprobarlo.';

  @override
  String get overviewReorderHint =>
      'Mantén pulsada una billetera para cambiar el orden.';

  @override
  String get discoverTokensBlurb =>
      'Emite un token o un NFT, o quema tokens que tengas.';

  @override
  String get discoverTokensWhat =>
      'Cualquier transacción de Ergo puede crear un token nuevo: su id es el id de la primera caja de entrada, y su nombre, decimales y descripción están en los registros de la caja que lo lleva (EIP-4). Un NFT es un token con una sola unidad y un enlace a su contenido multimedia.';

  @override
  String get discoverTokensCanIssue =>
      'Emitir un token fungible con nombre, decimales y suministro';

  @override
  String get discoverTokensCanNft =>
      'Emitir un NFT que apunte a una imagen, un audio o un video';

  @override
  String get discoverTokensCanBurn =>
      'Quemar tokens que tengas para sacarlos de circulación';

  @override
  String get discoverTokensRiskName =>
      'El nombre de un token no es único: cualquiera puede emitir uno con el mismo nombre';

  @override
  String get discoverTokensRiskBurn =>
      'Quemar es definitivo; el suministro no se puede recuperar';

  @override
  String get discoverTokensRiskCost =>
      'Emitir cuesta una comisión de minería y bloquea el valor mínimo de caja junto con el token';

  @override
  String get discoverTokensGo => 'Abrir tokens';

  @override
  String get homeUtxoManagement => 'Gestión de UTXO';

  @override
  String get discoverUtxosBlurb =>
      'Consolida, divide y reorganiza las cajas en las que está tu dinero.';

  @override
  String get discoverUtxosWhat =>
      'En Ergo tu saldo es un conjunto de cajas, cada una una moneda aparte. Muchas cajas pequeñas hacen que cada envío sea más grande y más lento de construir; una sola caja enorme vincula todo lo que tienes en un mismo lugar. Esta herramienta las reorganiza.';

  @override
  String get discoverUtxosCanConsolidate =>
      'Consolidar muchas cajas pequeñas en una';

  @override
  String get discoverUtxosCanSplit =>
      'Dividir una caja en varias del tamaño que elijas';

  @override
  String get discoverUtxosCanRestructure =>
      'Reorganizar los fondos para que los tokens estén en cajas propias';

  @override
  String get discoverUtxosRiskPublic =>
      'Cada reorganización es una transacción: cuesta una comisión de minería y es pública';

  @override
  String get discoverUtxosRiskLinks =>
      'Consolidar vincula a un mismo propietario todas las cajas que gasta';

  @override
  String get discoverUtxosRiskMinimum =>
      'No se puede crear una caja por debajo del valor mínimo';

  @override
  String get discoverUtxosGo => 'Abrir gestión de UTXO';

  @override
  String get discoverWhatYouCanDo => 'LO QUE PUEDES HACER';

  @override
  String get discoverWatchFor => 'TEN EN CUENTA';

  @override
  String get discoverIntro =>
      'Lo que Celaut puede hacer además de enviar y recibir. Cada herramienta explica qué es, qué puedes hacer con ella y qué tener en cuenta antes de abrirla.';

  @override
  String get discoverTools => 'Herramientas';

  @override
  String get discoverRowHint => 'Qué es y cómo entrar';

  @override
  String watchAddFailed(String detail) {
    return 'No se pudo añadir la dirección observada: $detail';
  }

  @override
  String get watchAddressAdded => 'Dirección de solo lectura añadida';

  @override
  String get watchAddInvalid =>
      'Ya se observa o el dato no es válido. Usa una dirección de Ergo, una clave pública comprimida de 33 bytes o su árbol P2PK 0008cd (hex, sin 0x). Las claves sin procesar usan mainnet.';

  @override
  String get watchAddressTitle => 'Observar una dirección';

  @override
  String get watchAddressIntro =>
      'Mira el saldo y la actividad de cualquier dirección de Ergo. No se guarda ninguna clave, así que no puede gastar.';

  @override
  String get watchAddressLabel => 'Dirección o clave pública';

  @override
  String get watchAddressHelper =>
      'Clave de mainnet en hex: 02/03… o 0008cd02/03…';

  @override
  String get watchAction => 'Observar';

  @override
  String get watchXpubTitle => 'Observar una clave pública extendida';

  @override
  String get watchXpubLabel => 'Clave pública extendida de Ergo Wallet App';

  @override
  String get watchXpubHelper =>
      '156 caracteres hexadecimales, mainnet. Sin suma de verificación: comprueba la primera dirección con la billetera de origen.';

  @override
  String get watchXpubAlreadyWatched => 'Esta clave extendida ya se observa.';

  @override
  String get watchAccountAction => 'Observar cuenta';

  @override
  String get watchNameOptional => 'Nombre (opcional)';

  @override
  String watchSaveNameFailed(String detail) {
    return 'No se pudo guardar el nombre: $detail';
  }

  @override
  String get watchStopTitle => '¿Dejar de observar?';

  @override
  String get watchStopAccountBody =>
      'La clave extendida se elimina de este dispositivo. Vuelve a importarla para observar la cuenta otra vez.';

  @override
  String watchStopFailed(String detail) {
    return 'No se pudo dejar de observar: $detail';
  }

  @override
  String get navActivity => 'Actividad';

  @override
  String get navDiscover => 'Descubrir';

  @override
  String navActivityPending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Actividad, $count pendientes',
      one: 'Actividad, $count pendiente',
    );
    return '$_temp0';
  }

  @override
  String homePricesOld(String age) {
    return 'precios de hace $age';
  }

  @override
  String get homePricesStale => 'precios desactualizados';

  @override
  String homePricesAsOf(String when) {
    return 'precios de $when';
  }

  @override
  String get homePriceUnavailable => 'no disponible';

  @override
  String get homePriceUnavailableRetrying => 'no disponible · reintentando';

  @override
  String get homeNetworkConnected => 'Conectado';

  @override
  String get homeNetworkLooking => 'Buscando un nodo…';

  @override
  String get homeNoReachableNodes => 'No hay nodos accesibles';

  @override
  String homeAgeOld(String age) {
    return 'de hace $age';
  }

  @override
  String homePriceAsOf(String when) {
    return 'de $when';
  }

  @override
  String homeHistoryOutOfDate(String source) {
    return 'Historial de $source desactualizado';
  }

  @override
  String homeLegsMore(String first, String count) {
    return '$first + $count más';
  }

  @override
  String homeWalletsNotLoaded(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n billeteras sin cargar',
      one: '$n billetera sin cargar',
    );
    return '$_temp0';
  }

  @override
  String homeAsOf(String when) {
    return 'datos de $when';
  }

  @override
  String homeSpokenLoading(String label) {
    return '$label cargando';
  }

  @override
  String homeSpokenUnavailable(String label) {
    return '$label no disponible';
  }

  @override
  String homeSpokenHidden(String label) {
    return '$label oculto';
  }

  @override
  String get homeSpokenSomethingPending => 'algo pendiente';

  @override
  String homeSpokenAbout(String value, String code) {
    return 'aproximadamente $value $code';
  }

  @override
  String homeSpokenUnpriced(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tokens sin precio',
      one: '$count token sin precio',
    );
    return '$_temp0';
  }

  @override
  String homeUnpricedTokens(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tokens sin precio',
      one: '$count token sin precio',
    );
    return '$_temp0';
  }

  @override
  String homeSpokenPinnedAddress(String index, String address) {
    return 'Dirección fijada #$index, $address';
  }

  @override
  String homeSpokenAddress(String address) {
    return 'Dirección $address';
  }

  @override
  String get homeCopyAddress => 'Copiar dirección';

  @override
  String get homeErgPriceUnavailable => 'Precio de ERG no disponible';

  @override
  String homePriceVia(String window, String source) {
    return '$window vía $source';
  }

  @override
  String homeSpokenErgPrice(String value, String code) {
    return 'Precio de ERG $value $code';
  }

  @override
  String homeSpokenUp(String percent, String window) {
    return 'sube un $percent% en $window';
  }

  @override
  String homeSpokenDown(String percent, String window) {
    return 'baja un $percent% en $window';
  }

  @override
  String get homeShowBalances => 'Mostrar saldos';

  @override
  String get homeHideBalances => 'Ocultar saldos';

  @override
  String get homeNetworkSettings => 'Ajustes de red';

  @override
  String homeBlock(String height) {
    return 'Bloque $height';
  }

  @override
  String get homeLoading => 'Cargando…';

  @override
  String get homeEmpty => 'Vacía';

  @override
  String homeTokenCount(int count, String n) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$n tokens',
      one: '$n token',
    );
    return '$_temp0';
  }

  @override
  String homeAsOfCompact(String when) {
    return 'datos de $when';
  }

  @override
  String get homeOpensWallet => 'Abre la billetera';

  @override
  String get homeSpokenUnlocked => 'desbloqueada';

  @override
  String get homeSpokenWatchOnly => 'solo lectura';

  @override
  String get homeSpokenBalanceHidden => 'saldo oculto';

  @override
  String homeSpokenIncl(String other) {
    return 'incl. $other';
  }

  @override
  String homePriceNote(String note) {
    return 'Precio $note';
  }

  @override
  String get homeAssetHidden => 'Activo oculto';

  @override
  String get homeSpokenVerified => 'verificado';

  @override
  String get homeSpokenCaution => 'cuidado, se llama como un token verificado';

  @override
  String homeSpokenPrice(String value) {
    return 'precio $value';
  }

  @override
  String get homeSpokenPending => 'pendiente';

  @override
  String get homeSpokenAmountHidden => 'cantidad oculta';

  @override
  String get overviewOpenToLoad => 'Ábrela para cargar';

  @override
  String get overviewNotLoadedYet => 'Aún sin cargar';

  @override
  String get overviewTagline => 'Computación descentralizada';

  @override
  String get overviewTotalBalance => 'Saldo total';

  @override
  String get overviewWallets => 'Billeteras';

  @override
  String get overviewAddWallet => 'Añadir una billetera';

  @override
  String get overviewWatchedAddresses => 'Direcciones observadas';

  @override
  String get overviewWatchTooltip => 'Observar una dirección o una cuenta';

  @override
  String get overviewPrototypeTitle => 'Software prototipo';

  @override
  String get overviewPrototypeBody =>
      'Celaut es un prototipo sin auditar. Las transacciones en Ergo son irreversibles — usa solo fondos que puedas permitirte perder.';

  @override
  String get overviewGotIt => 'Entendido';

  @override
  String get overviewPrototypeNote =>
      'Prototipo sin auditar. Usa solo fondos que puedas permitirte perder.';

  @override
  String get overviewLearnMore => 'Más información';

  @override
  String get overviewWelcomeTitle => 'Aquí viven tus billeteras';

  @override
  String get overviewWelcomeBody =>
      'Aún no hay billeteras. Crea una billetera nueva, restaura una con su frase de recuperación u observa una dirección o una cuenta sin sus claves. Cada una se abre desde esta pantalla.';

  @override
  String get overviewCreateWallet => 'Crear una billetera';

  @override
  String get overviewRestoreWallet => 'Restaurar con la frase de recuperación';

  @override
  String get overviewWatchAccountXpub => 'Observar una cuenta (xpub)';

  @override
  String get overviewAddCreate => 'Crear una billetera nueva';

  @override
  String get overviewAddCreateBlurb =>
      'Una frase de recuperación nueva, guardada en este teléfono.';

  @override
  String get overviewAddRestore => 'Restaurar una billetera';

  @override
  String get overviewAddRestoreBlurb =>
      'Con su frase de recuperación de 12, 15 o 24 palabras.';

  @override
  String get overviewAddWatchAddressBlurb =>
      'Saldo y actividad, sin sus claves.';

  @override
  String get overviewAddWatchAccount => 'Observar una cuenta';

  @override
  String get overviewAddWatchAccountBlurb =>
      'Todas las direcciones de una clave pública extendida (xpub).';

  @override
  String get homeBalanceLabel => 'Saldo';

  @override
  String get homeUnlockPrompt =>
      'Desbloquea para ver la actividad, enviar y recibir.';

  @override
  String get homeUnlock => 'Desbloquear';

  @override
  String get homeUsePin => 'Usar PIN';

  @override
  String get homeUseBiometrics => 'Usar biometría';

  @override
  String get homeUnlockAndSetPin => 'Desbloquear y crear PIN';

  @override
  String get homeKeysNotHere =>
      'Las claves de esta billetera no están guardadas en este dispositivo.';

  @override
  String get homeActionSend => 'Enviar';

  @override
  String get homeActionSendOffline => 'Enviar con firmante sin conexión';

  @override
  String get homeActionReceive => 'Recibir';

  @override
  String get homeActionMore => 'Más';

  @override
  String get homeToolTokensBlurb => 'Emite tokens y NFT, o quema tokens.';

  @override
  String get homeToolUtxosBlurb => 'Consolida, divide y ordena tus cajas.';

  @override
  String get homeToolAddressesBlurb =>
      'Cada dirección de esta billetera y lo que contiene.';

  @override
  String get homeToolLock => 'Bloquear billetera';

  @override
  String get homeToolLockBlurb =>
      'Al abrirla de nuevo se pedirá tu PIN o tu huella.';

  @override
  String get homeBreakdownIntro =>
      'La billetera se muestra como una dirección, pero su saldo cubre todas las direcciones que conoce. Cualquiera de ellas puede gastar de esta billetera.';

  @override
  String homeBreakdownEmptyOthers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count direcciones conocidas más no tienen fondos.',
      one: '$count dirección conocida más no tiene fondos.',
    );
    return '$_temp0';
  }

  @override
  String get homeLongPressCopy => 'Mantén pulsado para copiar';

  @override
  String get homeNameAddressHint =>
      'Pone nombre a esta dirección. Mantén pulsado para copiar';

  @override
  String get homeSpokenShownAs => 'mostrada como esta billetera';

  @override
  String get homeShownAs => 'Mostrada como esta billetera';

  @override
  String get homeAllWallets => 'Todas las billeteras';

  @override
  String get homeOtherAddressesHint =>
      'Muestra cada dirección y lo que contiene';

  @override
  String get homeUtxos => 'UTXO';

  @override
  String homeUtxoCount(String count) {
    return '$count UTXO';
  }

  @override
  String get homeUtxoTools => 'Herramientas de UTXO';

  @override
  String homeSpokenFragmented(String utxos) {
    return '$utxos, fragmentados. Ordenar';
  }

  @override
  String get homeTidyUp => 'Ordenar';

  @override
  String get homeFragmented => 'Fragmentados';

  @override
  String get homeAllAssets => 'Todos los activos';

  @override
  String homeAllAssetsCount(String count) {
    return 'Todos los activos ($count)';
  }

  @override
  String get homeRecentActivity => 'Actividad reciente';

  @override
  String get homeViewAll => 'Ver todo';

  @override
  String get homeReadingActivity => 'Leyendo la actividad';

  @override
  String get homeReadingActivityEllipsis => 'Leyendo la actividad…';

  @override
  String get homeFullHistory => 'Historial completo';

  @override
  String get homeEveryAddress => 'Cada dirección y lo que contiene';

  @override
  String get homeNoAddresses => 'Aún no se ha leído ninguna dirección';

  @override
  String get homeNoAddressesWatched =>
      'Aún no se ha leído ninguna dirección. Aparecen después del primer escaneo.';

  @override
  String get homeNoAddressesDot => 'Aún no se ha leído ninguna dirección.';

  @override
  String homeSpokenCountFragmented(String count) {
    return '$count, fragmentados';
  }

  @override
  String get homeAssets => 'Activos';

  @override
  String get homeShowMyAddress => 'Mostrar mi dirección';

  @override
  String get homeNoActivity => 'Aún no hay actividad';

  @override
  String watchBalanceUnavailable(String detail) {
    return 'Saldo no disponible: $detail';
  }

  @override
  String get watchActivityPartial => 'No se pudo leer parte de la actividad.';

  @override
  String get watchActivityFailed => 'No se pudo cargar la actividad.';

  @override
  String get watchAccountRefreshRetry =>
      'No se pudo actualizar la cuenta. Vuelve a intentarlo.';

  @override
  String get watchRescanAccount => 'Volver a escanear la cuenta';

  @override
  String get watchRefresh => 'Actualizar';

  @override
  String get watchMoreOptions => 'Más opciones';

  @override
  String get watchRename => 'Cambiar nombre';

  @override
  String get watchNotScannedTitle => 'Cuenta sin escanear';

  @override
  String get watchNotScannedBody =>
      'Actualiza la cuenta para leer sus direcciones y su actividad.';

  @override
  String get watchRefreshAccount => 'Actualizar cuenta';

  @override
  String get watchRefreshToReadActivity =>
      'Actualiza la cuenta para leer su actividad.';

  @override
  String get watchShowItsAddress => 'Mostrar su dirección';

  @override
  String get watchStatusWatchOnly => 'Solo lectura · no puede firmar aquí';

  @override
  String get watchScanning => 'Escaneando…';

  @override
  String get watchRefreshing => 'Actualizando…';

  @override
  String watchUpdated(String when) {
    return 'Actualizada $when';
  }

  @override
  String get watchGapNote =>
      'La búsqueda se detiene tras 20 direcciones sin usar. Los pagos más allá de un hueco mayor pueden pasarse por alto.';

  @override
  String get watchAddressNote =>
      'No puede firmar localmente. Envía con un firmante sin conexión; el cambio vuelve a esta misma dirección. Una cuenta observada sigue más direcciones.';

  @override
  String get watchFirstAddress => 'Primera dirección';

  @override
  String watchFirstAddressNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Comprueba que coincide con la primera dirección de la billetera de la que viene la clave: una clave extendida no tiene suma de verificación. $count direcciones escaneadas.',
      one:
          'Comprueba que coincide con la primera dirección de la billetera de la que viene la clave: una clave extendida no tiene suma de verificación. $count dirección escaneada.',
    );
    return '$_temp0';
  }

  @override
  String get activityTitleReceived => 'Recibido';

  @override
  String get activityTitleSent => 'Enviado';

  @override
  String get activityTitleMoved => 'Movido';

  @override
  String get activityTitleConsolidated => 'Consolidado';

  @override
  String activityTitleBurned(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tokens quemados',
      one: 'Token quemado',
    );
    return '$_temp0';
  }

  @override
  String activityTitleIssued(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tokens emitidos',
      one: 'Token emitido',
    );
    return '$_temp0';
  }

  @override
  String get activityTitleContractInteraction => 'Interacción con un contrato';

  @override
  String get activityTitleContract => 'Contrato';

  @override
  String activityFrom(String address) {
    return 'de $address';
  }

  @override
  String activityFromContract(String address) {
    return 'del contrato $address';
  }

  @override
  String activityTo(String address) {
    return 'a $address';
  }

  @override
  String activityToContract(String address) {
    return 'al contrato $address';
  }

  @override
  String activityContract(String address) {
    return 'contrato $address';
  }

  @override
  String activityAndMore(String who, String count) {
    return '$who y $count más';
  }

  @override
  String get activityArgusAppFee => 'Comisión de la app Argus';

  @override
  String get activityBetweenYourAddresses => 'entre tus direcciones';

  @override
  String get activityFeeLabel => 'Comisión';

  @override
  String activityMoreTokens(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tokens más',
      one: '$count token más',
    );
    return '$_temp0';
  }

  @override
  String activityPlusMore(String count) {
    return '+ $count más';
  }

  @override
  String get activityScreenTitle => 'Actividad';

  @override
  String get activityPartial =>
      'No se pudieron comprobar algunas direcciones. La actividad está incompleta.';

  @override
  String activityLoadFailed(String error) {
    return 'No se pudo cargar la actividad: $error';
  }

  @override
  String activityLoadMoreFailed(String error) {
    return 'No se pudo cargar la actividad anterior: $error';
  }

  @override
  String get activityNoneToExport => 'No hay transacciones para exportar';

  @override
  String activityExportFailed(String error) {
    return 'No se pudo exportar: $error';
  }

  @override
  String activityCount(String count) {
    return '$count transacciones';
  }

  @override
  String get activityExportCsv => 'Exportar CSV';

  @override
  String get activityEmptyTitle => 'Aún no hay actividad';

  @override
  String get activityEmptyBody =>
      'Las transacciones que entren o salgan de esta billetera aparecerán aquí, las más recientes primero.';

  @override
  String get activityRefresh => 'Actualizar';

  @override
  String ergopayErrorUnreachable(String detail) {
    return 'No se pudo contactar con la dApp: $detail';
  }

  @override
  String ergopayErrorHttp(String status) {
    return 'La dApp respondió HTTP $status';
  }

  @override
  String get ergopayErrorUnreadable =>
      'La dApp envió una solicitud de firma ilegible';

  @override
  String ergopayErrorNotify(String detail) {
    return 'No se pudo avisar a la dApp: $detail';
  }

  @override
  String ergopayErrorReplyRejected(String status) {
    return 'La dApp rechazó la respuesta (HTTP $status)';
  }

  @override
  String get ergopayWarningInputsUnknown =>
      'No se pudieron obtener del nodo los valores de las entradas, así que no se sabe el total que gastas. Revisa las salidas con atención.';

  @override
  String get ergopayWarningForeignInputs =>
      'Algunas entradas no son de esta billetera. La dApp está añadiendo sus propias cajas a esta transacción.';

  @override
  String get ergopayRowRecipients => 'Destinatarios';

  @override
  String get ergopayRowSent => 'Enviado';

  @override
  String get ergopayRowTokensOut => 'Tokens que salen';

  @override
  String get ergopayRowChange => 'Cambio para ti';

  @override
  String get ergopayRowYouSpend => 'Gastas';

  @override
  String get ergopayRowInputs => 'Entradas';

  @override
  String get ergopayStatusContacting => 'Contactando con la dApp…';

  @override
  String get ergopayNotALink => 'Esto no es un enlace de ErgoPay.';

  @override
  String ergopayWrongAddress(String address) {
    return 'Esta solicitud es para $address, que no es una dirección de esta billetera.';
  }

  @override
  String get ergopayStatusReading => 'Leyendo la transacción…';

  @override
  String get ergopayPickAddressTitle => '¿Qué dirección debe usar la dApp?';

  @override
  String get ergopayMainAddress => 'Dirección principal';

  @override
  String get ergopaySignTitle => 'Firmar para la dApp';

  @override
  String get ergopayNodeNotChosen => 'Aún no se ha elegido un nodo';

  @override
  String get ergopayStatusSigning => 'Firmando…';

  @override
  String get ergopayStatusBroadcasting => 'Enviando a la red…';

  @override
  String get ergopayStatusNotifying => 'Avisando a la dApp…';

  @override
  String get ergopaySignedAndSent => 'Firmada y enviada';

  @override
  String get ergopayNoTransaction =>
      'La dApp no envió ninguna transacción para firmar.';

  @override
  String get ergopayThisTransaction => 'Esta transacción';

  @override
  String get ergopayReviewAndSign => 'Revisar y firmar';

  @override
  String get ergopayDecline => 'Rechazar';

  @override
  String ergopayNotifyFailed(String error) {
    return 'La transacción está en la red, pero no se pudo avisar a la dApp: $error';
  }

  @override
  String get errorSomethingWentWrong => 'Algo salió mal';

  @override
  String get errorCopied => 'Error copiado';

  @override
  String get errorContractRejected =>
      'Un contrato rechazó esta transacción, así que no se firmó. No se envió nada.';

  @override
  String get errorNothingSent => 'No se envió nada.';

  @override
  String get errorSigningFailed => 'No se pudo firmar';

  @override
  String get errorBroadcastMayHaveFailed => 'Puede que el envío haya fallado';

  @override
  String get errorCheckActivity =>
      'Comprueba la Actividad antes de reintentar; puede que la transacción ya esté en la red.';

  @override
  String get contactsNoneToExport => 'No hay contactos para exportar';

  @override
  String contactsExportFailed(String error) {
    return 'No se pudo exportar: $error';
  }

  @override
  String get contactsSelectTitle => 'Elegir contacto';

  @override
  String get contactsExportTooltip => 'Exportar contactos';

  @override
  String get contactsEmptySelect => 'Aún no hay contactos guardados.';

  @override
  String get contactsEmpty =>
      'Aún no hay contactos guardados.\nToca + para añadir uno.';

  @override
  String get contactsYourWallets => 'Tus billeteras';

  @override
  String get contactsDeleteTitle => '¿Eliminar el contacto?';

  @override
  String get contactsDelete => 'Eliminar';

  @override
  String get contactsInvalidAddress => 'No es una dirección de Ergo válida';

  @override
  String get contactsAddTitle => 'Añadir contacto';

  @override
  String get contactsEditTitle => 'Editar contacto';

  @override
  String get contactsAdd => 'Añadir';

  @override
  String get createPhraseMismatch =>
      'La confirmación no coincide con la frase de recuperación';

  @override
  String get createSkipTitle => '¿Omitir la comprobación?';

  @override
  String get createSkipBody =>
      'Nada demostrará que la frase que escribiste está completa y en orden. Si una palabra está mal o falta, no se podrán recuperar los fondos de esta billetera.';

  @override
  String get createSkip => 'Omitir';

  @override
  String get createFailedTitle => 'No se pudo crear la billetera';

  @override
  String get createTitle => 'Crear billetera';

  @override
  String get createWriteDownTitle => 'Anota estas palabras';

  @override
  String get createWriteDownBody =>
      'Solo en papel. Son la única forma de recuperar esta billetera. Android bloquea aquí las capturas de pantalla; iOS oculta la app en el selector de apps y durante la grabación de pantalla.';

  @override
  String get createGenerate => 'Generar frase de recuperación';

  @override
  String get createHide => 'Ocultar';

  @override
  String get createReveal => 'Mostrar';

  @override
  String get createWroteDown => 'Ya las anoté';

  @override
  String get createConfirmTitle => 'Confirma la frase';

  @override
  String get createConfirmBody =>
      'Vuelve a escribir las palabras en orden. Así compruebas que la copia de seguridad se puede leer.';

  @override
  String get createPhraseLabel => 'Frase de recuperación';

  @override
  String get createContinue => 'Continuar';

  @override
  String get createSkipCheck => 'Omitir esta comprobación';

  @override
  String get createSetPin => 'Elige un PIN';

  @override
  String get createPinBody =>
      'El PIN descifra la clave en este dispositivo. No es una copia de seguridad.';

  @override
  String get createWalletNameLabel => 'Nombre de la billetera (opcional)';

  @override
  String get createWalletNameHint => 'p. ej., Ahorros, Trading';

  @override
  String get createReplaceTitle => '¿Reemplazar la billetera existente?';

  @override
  String get createReplaceBody =>
      'Ya hay una billetera guardada en este dispositivo. Si la reemplazas, se sobrescribe la semilla cifrada. La frase de recuperación es la única forma de recuperar la billetera anterior.';

  @override
  String get createReplace => 'Reemplazar';

  @override
  String get createScreenshotBlockUnavailable =>
      'El bloqueo de capturas de pantalla no está disponible en este dispositivo';

  @override
  String get restoreEnterPhrase => 'Escribe una frase de recuperación';

  @override
  String get restoreWordCount =>
      'La frase de recuperación debe tener 12, 15, 18, 21 o 24 palabras';

  @override
  String get restoreFailedTitle => 'No se pudo restaurar la billetera';

  @override
  String get restoreTitle => 'Restaurar billetera';

  @override
  String get restoreIntro =>
      '12, 15, 18, 21 o 24 palabras, en orden — 15 es el estándar de Ergo. Frase de contraseña BIP-39 opcional, si usaste una.';

  @override
  String get restorePhraseHint => '12, 15, 18, 21 o 24 palabras';

  @override
  String get restorePassphraseLabel => 'Frase de contraseña BIP-39 (opcional)';

  @override
  String get restoreButton => 'Restaurar';

  @override
  String receiveCopied(String address) {
    return '$address copiada';
  }

  @override
  String get receiveTitle => 'Recibir';

  @override
  String get receiveUnusedAddress => 'Dirección sin usar';

  @override
  String get receiveAddress => 'Dirección para recibir';

  @override
  String receiveWatchAccountNote(String limitations) {
    return 'Dirección de pago sin usar. Después del pago se ofrece una nueva. $limitations';
  }

  @override
  String get receiveWatchedNote =>
      'Los pagos a esta dirección van a la billetera observada.';

  @override
  String get receiveFreshNote =>
      'Cuando se use esta dirección, se mostrará una nueva.';

  @override
  String get receiveStaticNote =>
      'Esta dirección no cambia. Activa Direcciones nuevas en Ajustes para usar una nueva después de cada pago.';

  @override
  String get receiveAmountLabel => 'Cantidad opcional (ERG)';

  @override
  String get receiveAddLabel => 'Añadir etiqueta';

  @override
  String get receiveEditLabel => 'Editar etiqueta';

  @override
  String get receiveCopyAddress => 'Copiar dirección';

  @override
  String get receiveShare => 'Compartir';

  @override
  String get receiveUsedAddresses => 'Direcciones usadas';

  @override
  String get receiveUsedAddressesNote =>
      'Las direcciones anteriores siguen funcionando; toca una para copiarla.';

  @override
  String get receiveAmountInvalid =>
      'La cantidad debe ser un número decimal, como 0.001';

  @override
  String get receiveAmountNotPositive => 'La cantidad debe ser mayor que cero';

  @override
  String get scanTitle => 'Escanear';

  @override
  String get scanCameraUnavailable =>
      'La cámara no está disponible. Permite el acceso a la cámara y vuelve a intentarlo.';

  @override
  String get scanBack => 'Volver';

  @override
  String get txArgusFee => 'Comisión de Argus';

  @override
  String get txLeftWallet => 'Salió de tu billetera';

  @override
  String get txBurned => 'Quemado';

  @override
  String get txBurnedNote => 'Ninguna salida los tiene ya: ya no existen.';

  @override
  String get txIssued => 'Emitido';

  @override
  String get txArrived => 'Llegó';

  @override
  String get txFees => 'Comisiones';

  @override
  String get txMovedBetween => 'Movido entre tus direcciones';

  @override
  String get txMovedNote => 'Cambio y cajas que se quedaron en esta billetera.';

  @override
  String get txTo => 'Para';

  @override
  String get txFrom => 'De';

  @override
  String get txContract => 'Contrato';

  @override
  String get txIncompleteInputs =>
      'Algunas entradas de esta transacción pendiente aún no se pueden leer; puede faltar lo que aportó la otra parte.';

  @override
  String txSentAmount(String amount) {
    return 'Enviado $amount';
  }

  @override
  String txReceivedAmount(String amount) {
    return 'Recibido $amount';
  }

  @override
  String get txTitle => 'Transacción';

  @override
  String txConfirmedAt(String height) {
    return 'Confirmada $height';
  }

  @override
  String get txConfirmed => 'Confirmada';

  @override
  String get txNotInBlock => 'Aún no está en un bloque';

  @override
  String get txTokensSent => 'Tokens enviados';

  @override
  String get txIdLabel => 'Id';

  @override
  String get txTokensReceived => 'Tokens recibidos';

  @override
  String txFurtherTokenIds(String count) {
    return '$count id(s) de token más implicados — consulta el explorador.';
  }

  @override
  String get txIdCopied => 'Id de transacción copiado';

  @override
  String get txExplorerFailed => 'No se pudo abrir el explorador';

  @override
  String get txOpenExplorer => 'Abrir en el explorador';

  @override
  String txDetailsLoadFailed(String error) {
    return 'No se pudieron cargar los detalles de la transacción: $error';
  }

  @override
  String get txChange => 'Cambio';

  @override
  String txInputsCount(String count) {
    return 'Entradas ($count)';
  }

  @override
  String get txYours => 'Tuya';

  @override
  String get txInput => 'Entrada';

  @override
  String get txValueUnknown => 'valor desconocido';

  @override
  String txOutputsCount(String count) {
    return 'Salidas ($count)';
  }

  @override
  String get txMiner => 'Minería';

  @override
  String txDataInputsCount(String count) {
    return 'Entradas de datos ($count)';
  }

  @override
  String get txBox => 'Caja';

  @override
  String get txIdHeading => 'Id de transacción';

  @override
  String get txUnsignedCopied => 'Transacción sin firmar copiada';

  @override
  String get txCopyUnsigned => 'Copiar transacción sin firmar';

  @override
  String get dialogBiometricTitle => '¿Desbloquear con biometría?';

  @override
  String get dialogBiometricBody =>
      'Usa tu huella o tu cara para desbloquear esta billetera en lugar de escribir el PIN cada vez. Puedes cambiarlo más tarde en Ajustes › Seguridad.';

  @override
  String get dialogNotNow => 'Ahora no';

  @override
  String get dialogEnable => 'Activar';

  @override
  String get dialogBiometricEnabled => 'Desbloqueo biométrico activado';

  @override
  String get dialogBiometricFailed =>
      'No se pudo activar la biometría; vuelve a intentarlo en Ajustes › Seguridad';

  @override
  String get dialogRenameTitle => 'Cambiar el nombre de la billetera';

  @override
  String get dialogRename => 'Cambiar nombre';

  @override
  String get entryCurrentPin => 'PIN actual';

  @override
  String get entryContinue => 'Continuar';

  @override
  String get labelDialogTitle => 'Etiqueta de la dirección';

  @override
  String get labelOptional => 'Etiqueta (opcional)';

  @override
  String get coreTokenMetadataInvalid => 'Metadatos no válidos';

  @override
  String get coreTokenMetadataConflict => 'Conflicto de metadatos';

  @override
  String get coreTokenCollection => 'Token de colección';

  @override
  String get coreTokenDeclaredNftUnsupported =>
      'NFT declarado · tipo no compatible';

  @override
  String coreTokenSingleUnitArtwork(String kind) {
    return 'Obra de una sola unidad · $kind';
  }

  @override
  String get coreTokenDeclaredArtworkMultiple =>
      'Obra declarada · varias unidades';

  @override
  String get coreTokenDeclaredArtworkUnconfirmed =>
      'Obra declarada · suministro sin confirmar';

  @override
  String get coreTokenSingleUnit => 'Token de una sola unidad';

  @override
  String get coreTokenMetadataUnavailable => 'Token · metadatos no disponibles';

  @override
  String get corePinLength => 'El PIN debe tener de 6 a 32 caracteres';

  @override
  String coreWalletNumbered(String number) {
    return 'Billetera $number';
  }

  @override
  String get coreCuratedTokenSource =>
      'Lista de tokens seleccionados por Argus';

  @override
  String coreBroadcastActivityWarning(String error) {
    return 'Transacción enviada, pero no se pudo actualizar Actividad: $error. Guarda este ID de transacción.';
  }

  @override
  String get coreActivityLoadFailed => 'No se pudo cargar la actividad';

  @override
  String get coreWalletLocked => 'La billetera está bloqueada';

  @override
  String holdingsTokenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tokens',
      one: '1 token',
    );
    return '$_temp0';
  }

  @override
  String holdingsFundsElsewhere(String parts, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'incl. $parts en otras $count direcciones',
      one: 'incl. $parts en otra dirección',
    );
    return '$_temp0';
  }

  @override
  String holdingsFundsElsewhereHidden(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'incl. fondos en otras $count direcciones',
      one: 'incl. fondos en otra dirección',
    );
    return '$_temp0';
  }

  @override
  String get previewGatewayOriginRule =>
      'Usa un origen de pasarela HTTPS en el puerto 443, sin credenciales, ruta ni consulta.';

  @override
  String get previewGatewayNotPublic =>
      'La dirección de la pasarela no es pública.';

  @override
  String get previewGatewayPublicHostname =>
      'Usa un nombre de host público para la pasarela.';

  @override
  String get previewCidMalformed => 'CID de IPFS mal formado.';

  @override
  String get previewOnlyIpfs =>
      'Solo se pueden mostrar obras de IPFS. Se rechazan los hosts del emisor porque el emisor elegiría quién se entera de que la miraste.';

  @override
  String get previewCidNoncanonical => 'CID de IPFS no canónico.';

  @override
  String get previewCidUnsupported => 'CID de IPFS no compatible.';

  @override
  String get previewCidFormat =>
      'Usa una URI de IPFS con CIDv0 o con CIDv1 en base32 en minúsculas.';

  @override
  String get previewPathUnsupported => 'Ruta de IPFS no compatible.';

  @override
  String get previewImageDimensions =>
      'Las dimensiones de la imagen superan 4096 por eje u 8 megapíxeles.';

  @override
  String get previewArtworkTooLarge => 'La obra supera 5 MiB.';

  @override
  String get previewPngMalformed => 'PNG mal formado.';

  @override
  String get previewPngAnimated => 'Los PNG animados no son compatibles.';

  @override
  String get previewJpegMalformed => 'JPEG mal formado.';

  @override
  String get previewJpegFrame => 'Marco JPEG no compatible.';

  @override
  String get previewFormatMismatch =>
      'Solo se admiten PNG y JPEG estáticos cuyos bytes coincidan con el tipo MIME.';

  @override
  String get previewHashMismatch =>
      'El contenido no coincide con el hash de emisión.';

  @override
  String get previewSaveSettingFailed =>
      'No se pudo guardar el ajuste de vista previa.';

  @override
  String get previewSaveGatewayFailed => 'No se pudo guardar la pasarela.';

  @override
  String get previewRequestTimedOut =>
      'Se agotó el tiempo de la solicitud de vista previa.';

  @override
  String get previewConnectionTimedOut =>
      'Se agotó el tiempo de conexión de la vista previa.';

  @override
  String get previewCancelled => 'Vista previa cancelada.';

  @override
  String get previewConnectionRefused => 'Conexión de vista previa rechazada.';

  @override
  String get previewHostBindingFailed =>
      'No se pudo vincular el nombre de host de la pasarela.';

  @override
  String get previewRedirectBlocked => 'Redirección bloqueada.';

  @override
  String get previewNoArtwork => 'La pasarela no devolvió la obra.';

  @override
  String get previewCompressionRefused => 'Compresión de transporte rechazada.';

  @override
  String get previewStaticOnly => 'Solo se admiten PNG y JPEG estáticos.';

  @override
  String get previewBusy => 'Otra vista previa aún está terminando.';

  @override
  String get previewIntegrityConsentRequired =>
      'Ver sin comprobación de integridad requiere tu consentimiento explícito.';

  @override
  String get previewAnimatedUnsupported =>
      'Las obras animadas no son compatibles.';

  @override
  String get previewDecodedTooLarge =>
      'La vista previa decodificada supera el tamaño objetivo.';

  @override
  String previewLoadThroughTitle(String host) {
    return '¿Cargar la vista previa a través de $host?';
  }

  @override
  String get previewLoadConsentBody =>
      'Esta pasarela puede ver tu dirección IP y qué obra se pidió. Se descargarán hasta 5 MiB. La obra puede tener contenido no solicitado o engañoso.';

  @override
  String get previewLoad => 'Cargar vista previa';

  @override
  String get previewHashMissingTitle => 'Hash de emisión ausente o no válido';

  @override
  String get previewHashMissingBody =>
      'El formato y las dimensiones pasaron las comprobaciones de la vista previa, pero estos bytes no se pueden comparar con un hash de emisión.';

  @override
  String get previewViewWithoutIntegrity =>
      'Ver sin comprobación de integridad';

  @override
  String get previewMatchesHash => 'Coincide con el hash de emisión';

  @override
  String get previewViewedWithoutIntegrity =>
      'Mostrada sin comprobación de integridad';

  @override
  String get previewLoadFailed => 'No se pudo cargar la vista previa.';

  @override
  String get previewMetadataUnsupported =>
      'La vista previa no es compatible con estos metadatos.';

  @override
  String get previewDisabled => 'Vistas previas remotas desactivadas.';

  @override
  String get previewNoGateway =>
      'No hay ninguna pasarela configurada. Las vistas previas no están disponibles.';

  @override
  String get previewUnavailableNow =>
      'Vistas previas no disponibles con la billetera bloqueada, oculta, sin conexión o fuera de esta sesión.';

  @override
  String get previewViewArtwork => 'Ver obra';

  @override
  String get previewHide => 'Ocultar vista previa';

  @override
  String get previewLoading => 'Cargando vista previa…';

  @override
  String get previewCancel => 'Cancelar vista previa';

  @override
  String get previewSettingsLink => 'Ajustes de vistas previas remotas';

  @override
  String get previewGatewaySaved =>
      'Pasarela guardada. Cada obra sigue requiriendo tu consentimiento.';

  @override
  String get previewSettingsTitle => 'Vistas previas remotas';

  @override
  String get previewNeverTitle => 'No cargar nunca vistas previas remotas';

  @override
  String get previewNeverSubtitle =>
      'Desactiva la carga y cierra las vistas previas abiertas. La decodificación de imágenes no tiene un límite total de memoria que se pueda imponer y una decodificación nativa en curso no se puede interrumpir. Usa este interruptor para evitar riesgos de memoria o de seguridad del decodificador.';

  @override
  String get previewSettingsIpfsOnly =>
      'Solo se pueden mostrar obras de IPFS. Se rechazan los hosts elegidos por el emisor porque el emisor elegiría quién se entera de que la miraste. No hay pasarela predeterminada ni alternativa.';

  @override
  String get previewGatewayFieldLabel => 'Tu pasarela IPFS HTTPS';

  @override
  String get previewGatewayFieldHelper =>
      'Solo el origen, puerto 443. Déjalo vacío para quitarla.';

  @override
  String get previewGatewayCheckInfo =>
      'Al guardar, se resuelve el nombre de host de la pasarela para comprobar que sus direcciones son públicas. Al cargar, se vuelve a comprobar y solo se conecta a esa dirección. La pasarela puede ver tu IP y qué obra pides.';

  @override
  String get previewCheckingGateway => 'Comprobando pasarela…';

  @override
  String get previewSaveGateway => 'Guardar pasarela';

  @override
  String get sendNoSpendableAddresses => 'No hay direcciones para gastar';

  @override
  String get sendCouldNotListBoxes => 'No se pudieron listar tus cajas';

  @override
  String sendContactName(String name) {
    return 'Contacto: $name';
  }

  @override
  String get sendSpendableUnknown => 'No se conoce el saldo disponible';

  @override
  String get sendNotEnoughForFee =>
      'No hay suficientes ERG para la comisión y el cambio';

  @override
  String get sendNoTokenSelected => 'No hay ningún token elegido';

  @override
  String get sendSaveToContacts => 'Guardar en contactos';

  @override
  String get sendContactSaved => 'Contacto guardado';

  @override
  String sendExceedsBalance(String balance) {
    return 'La cantidad más la comisión supera tus $balance';
  }

  @override
  String get sendCouldNotPrepare => 'No se pudo preparar el envío';

  @override
  String get sendClipboardTitle => 'El portapapeles tiene otra dirección';

  @override
  String get sendClipboardDiffersOne =>
      'Algo que copiaste antes es una dirección de Ergo distinta del destinatario. Un malware puede cambiar las direcciones del portapapeles. Comprueba cada carácter.';

  @override
  String get sendClipboardDiffersMany =>
      'Algo que copiaste antes es una dirección de Ergo distinta de todos los destinatarios. Un malware puede cambiar las direcciones del portapapeles. Comprueba cada carácter.';

  @override
  String get sendRecipientLabel => 'Destinatario:';

  @override
  String get sendRecipientsLabel => 'Destinatarios:';

  @override
  String get sendClipboardLabel => 'Portapapeles:';

  @override
  String get sendGoBack => 'Volver';

  @override
  String get sendRecipientCorrect => 'El destinatario es correcto';

  @override
  String get sendRecipientsCorrect => 'Los destinatarios son correctos';

  @override
  String get sendTotalSent => 'Total enviado';

  @override
  String get sendAmount => 'Cantidad';

  @override
  String sendFeePaidIn(String token) {
    return 'Comisión de minería pagada en $token';
  }

  @override
  String get sendTokenFallback => 'token';

  @override
  String sendTokensFor(String tokens, String erg) {
    return '$tokens por $erg';
  }

  @override
  String get sendConfirmMulti => 'Confirmar envío a varios destinatarios';

  @override
  String get sendConfirm => 'Confirmar envío';

  @override
  String get sendSent => '¡Enviado!';

  @override
  String sendAvailable(String amount) {
    return 'Disponible: $amount';
  }

  @override
  String sendAllAddresses(String all) {
    return 'Las $all direcciones';
  }

  @override
  String sendSomeAddresses(String picked, String all) {
    return '$picked de $all direcciones';
  }

  @override
  String sendBoxesChosen(String count) {
    return '$count cajas elegidas';
  }

  @override
  String sendFeeErg(String amount) {
    return 'Comisión $amount ERG';
  }

  @override
  String sendFeeIn(String token) {
    return 'Comisión en $token';
  }

  @override
  String sendTokensPage(String count, String page, String pages) {
    return '$count tokens elegidos · Página $page de $pages';
  }

  @override
  String get sendPreviousTokens => 'Tokens anteriores';

  @override
  String get sendNextTokens => 'Tokens siguientes';

  @override
  String sendSendsOne(String token) {
    return 'Envía 1 $token · Disponible: 1';
  }

  @override
  String sendTokenAmount(String token) {
    return 'Cantidad de $token';
  }

  @override
  String get sendMax => 'MÁX';

  @override
  String get sendEnterAmount => 'Escribe una cantidad';

  @override
  String get sendTooMuch => 'Demasiado';

  @override
  String sendRemoveToken(String token) {
    return 'Quitar $token';
  }

  @override
  String sendPlusTokens(String count) {
    return ' + $count tokens';
  }

  @override
  String get sendRawTitle => 'Transacción firmada en bruto';

  @override
  String get sendRawNote =>
      'La transacción está firmada pero no se ha difundido. Comparte o guarda la transacción en bruto para enviarla más tarde desde un explorador u otra billetera.';

  @override
  String get sendDestination => 'Destino';

  @override
  String get sendRecipientAddress => 'Dirección del destinatario';

  @override
  String get sendRecipientHint => 'O toca contactos para elegir uno guardado';

  @override
  String get sendRequired => 'Obligatorio';

  @override
  String get sendAsset => 'Activo';

  @override
  String get sendChooseTokens => 'Elegir tokens';

  @override
  String sendChooseTokensCount(String count) {
    return 'Elegir tokens ($count)';
  }

  @override
  String get sendMinimumBox => 'Mínimo 0.001 ERG';

  @override
  String get sendErgWithIt => 'ERG que se envían con él (opcional)';

  @override
  String sendBlankFundsTokens(String available) {
    return 'En blanco, lleva el mínimo de ERG para estos tokens. La revisión muestra la cantidad exacta. $available';
  }

  @override
  String get sendAdditionalRecipients => 'Más destinatarios';

  @override
  String sendRecipientNAddress(String number) {
    return 'Dirección del destinatario $number';
  }

  @override
  String get sendAmountErg => 'Cantidad (ERG)';

  @override
  String get sendBlankFundsToken =>
      'En blanco, lleva el mínimo de ERG para este token.';

  @override
  String get sendTokenNone => 'Ninguno';

  @override
  String get sendEnterTokenAmount => 'Escribe una cantidad de token';

  @override
  String sendYouHold(String amount) {
    return 'Tienes $amount';
  }

  @override
  String get sendAddRecipient => 'Añadir otro destinatario';

  @override
  String get sendAdvanced => 'Avanzado';

  @override
  String get sendErgCarried => 'ERG que lleva el token';

  @override
  String sendBlankMinimumBox(String amount) {
    return 'Déjalo en blanco para el valor mínimo de caja, $amount.';
  }

  @override
  String get sendChoose => 'Elegir';

  @override
  String get sendSpendFrom => 'Gastar desde';

  @override
  String get sendDeselectedNote =>
      'Las direcciones sin marcar quedan fuera de la selección de monedas.';

  @override
  String get sendUseAllAddresses => 'Usar todas las direcciones';

  @override
  String get sendPayFeeIn => 'Pagar la comisión de minería en';

  @override
  String get sendPayFeeInHelp =>
      'Una comisión en token se compra a una caja babel en la cadena a su precio publicado; la comisión en ERG de abajo es lo que compra.';

  @override
  String get sendMinerFeeErg => 'Comisión de minería (ERG)';

  @override
  String sendBlankDefaultFee(String amount) {
    return 'Déjalo en blanco para usar la predeterminada, $amount.';
  }

  @override
  String sendMinimum(String amount) {
    return 'Mínimo $amount';
  }

  @override
  String get sendReview => 'Revisar';

  @override
  String get sendChooseInputs => 'Elegir entradas';

  @override
  String get sendAutoInputsNote =>
      'Celaut elegirá las cajas por ti. Elige algunas para controlar exactamente qué gasta esta transacción.';

  @override
  String sendShortBy(String amount) {
    return 'Faltan $amount para esta cantidad más las comisiones.';
  }

  @override
  String sendBoxTokens(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tokens',
      one: '1 token',
    );
    return '$_temp0';
  }

  @override
  String sendBoxBlock(String height) {
    return 'bloque $height';
  }

  @override
  String utxoLoadFailed(String error) {
    return 'No se pudieron cargar los UTXO: $error';
  }

  @override
  String get utxoSpreadOut =>
      'Tus cajas están repartidas en muchas direcciones, y unirlas vincularía esas direcciones. Consolidar lo hace de todos modos.';

  @override
  String get utxoNothingToClean => 'Ahora no hay nada que limpiar';

  @override
  String get utxoConsolidateNeedsTwo => 'Consolidar necesita al menos 2 cajas';

  @override
  String get utxoConsolidateTitle => 'Consolidar UTXO';

  @override
  String utxoConsolidateInN(String count) {
    return 'Consolidar en $count transacciones';
  }

  @override
  String get utxoBoxesMerged => 'Cajas unidas';

  @override
  String get utxoInto => 'En';

  @override
  String get utxoTotalValueIn => 'Valor total de entrada';

  @override
  String get utxoTokenTypesCarried => 'Tipos de token incluidos';

  @override
  String get utxoValueAfterFees => 'Valor tras comisiones';

  @override
  String get utxoConsolidateOneDetail =>
      'Cada caja elegida se gasta en una caja nueva con todos sus ERG y tokens.';

  @override
  String utxoConsolidateManyDetail(String max, String count) {
    return 'Las transacciones de Ergo se mantienen por debajo de $max entradas cada una, así que esto se hace en $count transacciones seguidas. Después puedes volver a consolidar los resultados.';
  }

  @override
  String get utxoSignBroadcast => 'Firmar y difundir';

  @override
  String utxoSignBroadcastN(String count) {
    return 'Firmar y difundir $count';
  }

  @override
  String utxoStoppedAfter(String done, String total) {
    return 'Se detuvo tras $done de $total. Actualiza las cajas y revisa la actividad antes de reintentar.';
  }

  @override
  String get utxoConsolidationSubmitted => 'Consolidación enviada';

  @override
  String get utxoRefreshBeforeRetry =>
      'Actualiza las cajas y revisa la actividad antes de reintentar.';

  @override
  String get utxoFewDust => 'Hay menos de dos cajas de polvo para barrer';

  @override
  String utxoNewRent(String fee, String when) {
    return '$fee, vence $when';
  }

  @override
  String utxoNewRentCapped(String fee, String when) {
    return '$fee, vence $when; no guarda más que eso';
  }

  @override
  String get utxoSuggestedCleanup => 'Limpieza sugerida';

  @override
  String utxoMergedAtAddress(String count, String total) {
    return '$count de $total en esta dirección';
  }

  @override
  String get utxoResultingBoxes => 'Cajas resultantes';

  @override
  String get utxoOneOrMore => '1 o más';

  @override
  String get utxoRentClocksRestarted => 'Relojes de alquiler reiniciados';

  @override
  String get utxoNewBoxRent => 'Alquiler de la caja nueva';

  @override
  String utxoCleanupDetail(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Cada caja de la lista se gasta en $count cajas nuevas en esta dirección, con todos sus ERG y tokens. Una caja movida empieza un nuevo reloj de alquiler de almacenamiento de 4 años. Solo se unen cajas de esta dirección, así que no se vincula ninguna dirección.',
      one:
          'Cada caja de la lista se gasta en una caja nueva en esta dirección, con todos sus ERG y tokens. Una caja movida empieza un nuevo reloj de alquiler de almacenamiento de 4 años. Solo se unen cajas de esta dirección, así que no se vincula ninguna dirección.',
    );
    return '$_temp0';
  }

  @override
  String get utxoCleanupSubmitted => 'Limpieza enviada';

  @override
  String utxoAtRisk(String count) {
    return '$count en riesgo';
  }

  @override
  String utxoDueWithin(String count, String days) {
    return '$count vencen en menos de $days días';
  }

  @override
  String get utxoSplitTitle => 'Dividir UTXO';

  @override
  String get utxoOutputsCreated => 'Salidas creadas';

  @override
  String utxoBoxesN(String count) {
    return '$count cajas';
  }

  @override
  String get utxoAmountPerBox => 'Cantidad por caja';

  @override
  String utxoTokensN(String count) {
    return '$count tokens';
  }

  @override
  String get utxoChangeReturned => 'Cambio devuelto';

  @override
  String get utxoMinerFeeTitle => 'Comisión de minería';

  @override
  String get utxoFeeByBuilder =>
      'La comisión la calcula el constructor de transacciones.';

  @override
  String get utxoSignBroadcastSplit => 'Firmar y difundir la división';

  @override
  String get utxoSplitSubmitted => 'División enviada';

  @override
  String utxoSeparateTitle(String count) {
    return 'Separar $count tipos de token';
  }

  @override
  String get utxoSourceBox => 'Caja de origen';

  @override
  String get utxoInputsSpent => 'Entradas gastadas';

  @override
  String get utxoTokenBoxes => 'Cajas de tokens';

  @override
  String utxoRawUnits(String amount, String raw) {
    return '$amount ($raw unidades base)';
  }

  @override
  String get utxoErgInTokenBoxes => 'ERG en cajas de tokens';

  @override
  String get utxoErgChange => 'Cambio en ERG';

  @override
  String get utxoSeparateDetail =>
      'Cada tipo de token conserva todo su saldo en una caja aparte en tu dirección de origen. Todos los ERG restantes vuelven a tu billetera.';

  @override
  String get utxoSignBroadcastSeparation => 'Firmar y difundir la separación';

  @override
  String get utxoSeparationSubmitted => 'Separación de tokens enviada';

  @override
  String get utxoRestructureTitle => 'Reestructurar UTXO';

  @override
  String get utxoInputsConsumed => 'Entradas consumidas';

  @override
  String get utxoOutputsGenerated => 'Salidas generadas';

  @override
  String get utxoTotalValueInTitle => 'Valor total de entrada';

  @override
  String get utxoAllocatedToOutputs => 'Asignado a salidas';

  @override
  String get utxoChangeOutput => 'Salida de cambio';

  @override
  String get utxoSignBroadcastRestructure =>
      'Firmar y difundir la reestructuración';

  @override
  String get utxoRestructureSubmitted => 'Reestructuración enviada';

  @override
  String get utxoScreenTitle => 'Cajas de la billetera';

  @override
  String get utxoLastConsolidation => 'Resultado de la última consolidación';

  @override
  String get utxoRefreshBoxes => 'Actualizar cajas';

  @override
  String utxoCount(String count) {
    return '$count UTXO';
  }

  @override
  String utxoValueTokens(String value, String count) {
    return '$value · $count tokens';
  }

  @override
  String utxoDustLine(int count, String limit) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cajas de polvo por debajo de $limit.',
      one: '1 caja de polvo por debajo de $limit.',
    );
    return '$_temp0';
  }

  @override
  String get utxoOldestFirst =>
      'Primero las cajas más antiguas. Los envíos automáticos prefieren las cajas antiguas que se pueden usar, para reducir el riesgo de alquiler de almacenamiento; las reglas de privacidad y tu selección manual se siguen aplicando.';

  @override
  String get utxoConsolidate => 'Consolidar';

  @override
  String get utxoSplit => 'Dividir';

  @override
  String get utxoRestructure => 'Reestructurar';

  @override
  String get utxoSeparateTokenTypes => 'Separar tipos de token';

  @override
  String utxoSweepDust(String count) {
    return 'Barrer $count cajas de polvo en una';
  }

  @override
  String get utxoSearchHint => 'Buscar id de caja o token...';

  @override
  String utxoFilterAll(String count) {
    return 'Todas ($count)';
  }

  @override
  String utxoFilterErgOnly(String count) {
    return 'Solo ERG ($count)';
  }

  @override
  String utxoFilterTokens(String count) {
    return 'Tokens ($count)';
  }

  @override
  String utxoFilterDust(String count) {
    return 'Polvo ($count)';
  }

  @override
  String utxoFilterRent(String count) {
    return 'Alquiler ($count)';
  }

  @override
  String utxoClearSelection(String count) {
    return 'Borrar ($count)';
  }

  @override
  String get utxoSelectAll => 'Elegir todas';

  @override
  String get utxoNoMatch => 'Ningún UTXO coincide con el filtro';

  @override
  String get utxoCopyBoxId => 'Copiar id de caja';

  @override
  String get utxoBoxIdCopied => 'Id de caja copiado';

  @override
  String utxoHeight(String height) {
    return 'Alt.: $height';
  }

  @override
  String utxoSplitEqual(String count, String amount) {
    return '$count cajas de $amount';
  }

  @override
  String utxoSplitWithChange(String count, String amount, String change) {
    return '$count cajas de $amount · $change de cambio';
  }

  @override
  String utxoSplitToken(String count, String amount, String token, String erg) {
    return '$count cajas de $amount $token, cada una con $erg';
  }

  @override
  String utxoSplitNotEnough(String count) {
    return 'No hay suficientes ERG para $count cajas después de comisiones';
  }

  @override
  String get utxoSplitEnterErg =>
      'Escribe una cantidad de al menos 0.001 ERG que quepa en la selección';

  @override
  String get utxoSplitEnterToken =>
      'Escribe una cantidad de token que quepa en la selección';

  @override
  String utxoSplitFrom(int count, String total) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'De $count cajas con $total.',
      one: 'De 1 caja con $total.',
    );
    return '$_temp0';
  }

  @override
  String get utxoEqualParts => 'Partes iguales';

  @override
  String get utxoAmountEach => 'Cantidad por caja';

  @override
  String get utxoHowManyBoxes => 'CUÁNTAS CAJAS';

  @override
  String get utxoCustom => 'Otra';

  @override
  String utxoTokenAvailable(String token, String amount) {
    return '$token · $amount disponibles';
  }

  @override
  String utxoPerBox(String token) {
    return '$token por caja';
  }

  @override
  String get utxoErgPerBox => 'ERG por caja';

  @override
  String get utxoAdjustCount =>
      'Ajusta el número o la cantidad hasta que quepa en la selección.';

  @override
  String utxoSplitFeeNote(String fee) {
    return 'Comisión de minería: $fee. Los ERG restantes y todos los tokens vuelven a ti como cambio.';
  }

  @override
  String get utxoPreviewSplit => 'Vista previa de la división';

  @override
  String get utxoCustomRestructure => 'Reestructuración personalizada';

  @override
  String get utxoAddOutput => 'Añadir salida';

  @override
  String get utxoDefineOutputs =>
      'Define las cajas de salida que quieres. El resto vuelve como cambio.';

  @override
  String utxoBoxErgAmount(String number) {
    return 'Cantidad de ERG de la caja #$number';
  }

  @override
  String get utxoInvalidAmount =>
      'Cantidad no válida: mínimo 0.001 ERG por caja';

  @override
  String get utxoPreviewRestructure => 'Vista previa de la reestructuración';

  @override
  String utxoSelectedCount(String count) {
    return '$count elegidas';
  }
}
