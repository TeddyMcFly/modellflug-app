enum AircraftStatus {
  ready,
  maintenance,
  destroyed,
}

const _unset = Object();

const aircraftCategoryOptions = [
  'Drohne',
  'Hubschrauber',
  'Jet',
  'Kunstflieger',
  'Nurflügler',
  'Paragleiter',
  'Scale-Modell',
  'Segelflugzeug',
  'Slowflyer',
  'Sonstige',
  'Trainer',
];

const aircraftFeatureOptions = [
  'mehrmotorig',
  'Einziehfahrwerk',
  'Landeklappen',
  'LED-Beleuchtung',
  'Wasserflugzeug',
  'Doppeldecker',
  'Dreifachdecker',
  'Indoor-geeignet',
  'Warbird',
];

String normalizeAircraftFeature(String value) {
  if (value == 'Doppel-/Dreifachdecker') {
    return 'Doppeldecker';
  }
  return aircraftFeatureOptions.contains(value) ? value : value;
}

const aircraftDriveTypeOptions = [
  'Elektrisch',
  'Verbrenner',
];

String normalizeAircraftDriveType(String value) {
  final lower = value.toLowerCase().trim();
  if (lower.isEmpty) {
    return '';
  }
  if (lower.contains('elektro') ||
      lower.contains('elektrisch') ||
      lower.contains('brushless')) {
    return 'Elektrisch';
  }
  if (lower.contains('verbrenner') ||
      lower.contains('benzin') ||
      lower.contains('methanol') ||
      lower.contains('nitro')) {
    return 'Verbrenner';
  }
  return '';
}

String normalizeAircraftCategory(String value) {
  if (aircraftCategoryOptions.contains(value)) {
    return value;
  }

  final lower = value.toLowerCase();
  if (lower.contains('segler') || lower.contains('segelflug')) {
    return 'Segelflugzeug';
  }
  if (lower.contains('drohne') ||
      lower.contains('drone') ||
      lower.contains('multi') ||
      lower.contains('quad')) {
    return 'Drohne';
  }
  if (lower.contains('kunst') || lower.contains('acro')) {
    return 'Kunstflieger';
  }
  if (lower.contains('nurfl') || lower.contains('flying wing')) {
    return 'Nurflügler';
  }
  if (lower.contains('paragleiter') ||
      lower.contains('motorschirm') ||
      lower.contains('para')) {
    return 'Paragleiter';
  }
  if (lower.contains('scale')) {
    return 'Scale-Modell';
  }
  if (lower.contains('jet')) {
    return 'Jet';
  }
  if (lower.contains('trainer') || lower.contains('schule')) {
    return 'Trainer';
  }
  if (lower.contains('slow')) {
    return 'Slowflyer';
  }
  if (lower.contains('hubschrauber') || lower.contains('heli')) {
    return 'Hubschrauber';
  }
  return 'Sonstige';
}

extension AircraftStatusText on AircraftStatus {
  String get label {
    switch (this) {
      case AircraftStatus.ready:
        return 'Flugbereit';
      case AircraftStatus.maintenance:
        return 'Reparatur';
      case AircraftStatus.destroyed:
        return 'Ausgemustert';
    }
  }
}

class AircraftModel {
  final String id;
  final String name;
  final String type;
  final String manufacturer;
  final String registration;
  final double wingspanMeters;
  final double lengthMeters;
  final double weightKg;
  final String transmitter;
  final String transmitterMemorySlot;
  final String receiver;
  final String propeller;
  final String rcFunctions;
  final String materialFuselageWing;
  final String wingLoading;
  final String centerOfGravity;
  final String recommendedDriveBattery;
  final String servos;
  final DateTime purchaseDate;
  final String? purchaseDateInput;
  final String drive;
  final String driveType;
  final String speedController;
  final int batteryCount;
  final List<int> batteryCellOptions;
  final List<String> featureOptions;
  final int totalFlights;
  final double flightHours;
  final int previousFlightMinutes;
  final AircraftStatus status;
  final DateTime lastService;
  final DateTime nextService;
  final String notes;
  final String repairNotes;
  final String? photoDataUri;
  final List<String> photoDataUris;
  final List<String> photoStoragePaths;
  final List<String> photoDownloadUrls;

  const AircraftModel({
    required this.id,
    required this.name,
    required this.type,
    required this.manufacturer,
    required this.registration,
    required this.wingspanMeters,
    required this.lengthMeters,
    required this.weightKg,
    required this.transmitter,
    required this.transmitterMemorySlot,
    required this.receiver,
    required this.propeller,
    this.rcFunctions = '',
    this.materialFuselageWing = '',
    this.wingLoading = '',
    this.centerOfGravity = '',
    this.recommendedDriveBattery = '',
    this.servos = '',
    required this.purchaseDate,
    this.purchaseDateInput,
    required this.drive,
    this.driveType = '',
    this.speedController = '',
    required this.batteryCount,
    this.batteryCellOptions = const [],
    this.featureOptions = const [],
    required this.totalFlights,
    required this.flightHours,
    this.previousFlightMinutes = 0,
    required this.status,
    required this.lastService,
    required this.nextService,
    required this.notes,
    this.repairNotes = '',
    this.photoDataUri,
    this.photoDataUris = const [],
    this.photoStoragePaths = const [],
    this.photoDownloadUrls = const [],
  });

  List<String> get photos {
    if (photoDownloadUrls.isNotEmpty) {
      return photoDownloadUrls;
    }
    if (photoDataUris.isNotEmpty) {
      return photoDataUris;
    }
    if (photoDataUri != null && photoDataUri!.isNotEmpty) {
      return [photoDataUri!];
    }
    return const [];
  }

  List<int> get batteryCells {
    if (batteryCellOptions.isNotEmpty) {
      return batteryCellOptions;
    }
    if (batteryCount <= 0) {
      return const [];
    }
    return [batteryCount];
  }

  int get loggedFlightMinutes => (flightHours * 60).round();

  int get totalFlightMinutes =>
      loggedFlightMinutes +
      (previousFlightMinutes < 0 ? 0 : previousFlightMinutes);

  double get totalFlightHours => totalFlightMinutes / 60;

  AircraftModel copyWith({
    String? id,
    String? name,
    String? type,
    String? manufacturer,
    String? registration,
    double? wingspanMeters,
    double? lengthMeters,
    double? weightKg,
    String? transmitter,
    String? transmitterMemorySlot,
    String? receiver,
    String? propeller,
    String? rcFunctions,
    String? materialFuselageWing,
    String? wingLoading,
    String? centerOfGravity,
    String? recommendedDriveBattery,
    String? servos,
    DateTime? purchaseDate,
    Object? purchaseDateInput = _unset,
    String? drive,
    String? driveType,
    String? speedController,
    int? batteryCount,
    List<int>? batteryCellOptions,
    List<String>? featureOptions,
    int? totalFlights,
    double? flightHours,
    int? previousFlightMinutes,
    AircraftStatus? status,
    DateTime? lastService,
    DateTime? nextService,
    String? notes,
    String? repairNotes,
    Object? photoDataUri = _unset,
    List<String>? photoDataUris,
    List<String>? photoStoragePaths,
    List<String>? photoDownloadUrls,
  }) {
    return AircraftModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      manufacturer: manufacturer ?? this.manufacturer,
      registration: registration ?? this.registration,
      wingspanMeters: wingspanMeters ?? this.wingspanMeters,
      lengthMeters: lengthMeters ?? this.lengthMeters,
      weightKg: weightKg ?? this.weightKg,
      transmitter: transmitter ?? this.transmitter,
      transmitterMemorySlot:
          transmitterMemorySlot ?? this.transmitterMemorySlot,
      receiver: receiver ?? this.receiver,
      propeller: propeller ?? this.propeller,
      rcFunctions: rcFunctions ?? this.rcFunctions,
      materialFuselageWing: materialFuselageWing ?? this.materialFuselageWing,
      wingLoading: wingLoading ?? this.wingLoading,
      centerOfGravity: centerOfGravity ?? this.centerOfGravity,
      recommendedDriveBattery:
          recommendedDriveBattery ?? this.recommendedDriveBattery,
      servos: servos ?? this.servos,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      purchaseDateInput: identical(purchaseDateInput, _unset)
          ? this.purchaseDateInput
          : purchaseDateInput as String?,
      drive: drive ?? this.drive,
      driveType: driveType ?? this.driveType,
      speedController: speedController ?? this.speedController,
      batteryCount: batteryCount ?? this.batteryCount,
      batteryCellOptions: batteryCellOptions ?? this.batteryCellOptions,
      featureOptions: featureOptions ?? this.featureOptions,
      totalFlights: totalFlights ?? this.totalFlights,
      flightHours: flightHours ?? this.flightHours,
      previousFlightMinutes:
          previousFlightMinutes ?? this.previousFlightMinutes,
      status: status ?? this.status,
      lastService: lastService ?? this.lastService,
      nextService: nextService ?? this.nextService,
      notes: notes ?? this.notes,
      repairNotes: repairNotes ?? this.repairNotes,
      photoDataUri: identical(photoDataUri, _unset)
          ? this.photoDataUri
          : photoDataUri as String?,
      photoDataUris: photoDataUris ?? this.photoDataUris,
      photoStoragePaths: photoStoragePaths ?? this.photoStoragePaths,
      photoDownloadUrls: photoDownloadUrls ?? this.photoDownloadUrls,
    );
  }

  factory AircraftModel.fromJson(Map<String, dynamic> json) {
    return AircraftModel(
      id: json['id'] as String,
      name: json['name'] as String,
      type: normalizeAircraftCategory(json['type'] as String? ?? 'Sonstige'),
      manufacturer: json['manufacturer'] as String,
      registration: json['registration'] as String,
      wingspanMeters: (json['wingspanMeters'] as num).toDouble(),
      lengthMeters: (json['lengthMeters'] as num?)?.toDouble() ?? 0,
      weightKg: (json['weightKg'] as num).toDouble(),
      transmitter: json['transmitter'] as String? ?? '',
      transmitterMemorySlot: json['transmitterMemorySlot'] as String? ?? '',
      receiver: json['receiver'] as String? ?? '',
      propeller: json['propeller'] as String? ?? '',
      rcFunctions: json['rcFunctions'] as String? ?? '',
      materialFuselageWing: json['materialFuselageWing'] as String? ?? '',
      wingLoading: json['wingLoading'] as String? ?? '',
      centerOfGravity: json['centerOfGravity'] as String? ?? '',
      recommendedDriveBattery: json['recommendedDriveBattery'] as String? ?? '',
      servos: json['servos'] as String? ?? '',
      purchaseDate: DateTime.tryParse(json['purchaseDate'] as String? ?? '') ??
          DateTime(2026),
      purchaseDateInput: json.containsKey('purchaseDateInput')
          ? json['purchaseDateInput'] as String? ?? ''
          : null,
      drive: json['drive'] as String? ?? '',
      driveType: _aircraftDriveTypeFromJson(json),
      speedController: json['speedController'] as String? ?? '',
      batteryCount: json['batteryCount'] as int,
      batteryCellOptions: [
        for (final item in json['batteryCellOptions'] as List<dynamic>? ?? [])
          (item as num).toInt(),
      ],
      featureOptions: [
        for (final item in json['featureOptions'] as List<dynamic>? ?? [])
          normalizeAircraftFeature(item as String),
      ],
      totalFlights: json['totalFlights'] as int,
      flightHours: (json['flightHours'] as num).toDouble(),
      previousFlightMinutes:
          (json['previousFlightMinutes'] as num?)?.toInt() ?? 0,
      status: _aircraftStatusFromJson(json['status'] as String?),
      lastService: DateTime.parse(json['lastService'] as String),
      nextService: DateTime.parse(json['nextService'] as String),
      notes: json['notes'] as String,
      repairNotes: json['repairNotes'] as String? ?? '',
      photoDataUri: json['photoDataUri'] as String?,
      photoDataUris: [
        for (final item in json['photoDataUris'] as List<dynamic>? ?? [])
          item as String,
      ],
      photoStoragePaths: [
        for (final item in json['photoStoragePaths'] as List<dynamic>? ?? [])
          item as String,
      ],
      photoDownloadUrls: [
        for (final item in json['photoDownloadUrls'] as List<dynamic>? ?? [])
          item as String,
      ],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'manufacturer': manufacturer,
      'registration': registration,
      'wingspanMeters': wingspanMeters,
      'lengthMeters': lengthMeters,
      'weightKg': weightKg,
      'transmitter': transmitter,
      'transmitterMemorySlot': transmitterMemorySlot,
      'receiver': receiver,
      'propeller': propeller,
      'rcFunctions': rcFunctions,
      'materialFuselageWing': materialFuselageWing,
      'wingLoading': wingLoading,
      'centerOfGravity': centerOfGravity,
      'recommendedDriveBattery': recommendedDriveBattery,
      'servos': servos,
      'purchaseDate': purchaseDate.toIso8601String(),
      'purchaseDateInput': purchaseDateInput,
      'drive': drive,
      'driveType': driveType,
      'speedController': speedController,
      'batteryCount': batteryCount,
      'batteryCellOptions': batteryCellOptions,
      'featureOptions': featureOptions,
      'totalFlights': totalFlights,
      'flightHours': flightHours,
      'previousFlightMinutes': previousFlightMinutes,
      'status': status.name,
      'lastService': lastService.toIso8601String(),
      'nextService': nextService.toIso8601String(),
      'notes': notes,
      'repairNotes': repairNotes,
      'photoDataUri': photoDataUri,
      'photoDataUris': photoDataUris,
      'photoStoragePaths': photoStoragePaths,
      'photoDownloadUrls': photoDownloadUrls,
    };
  }
}

AircraftStatus _aircraftStatusFromJson(String? value) {
  if (value == 'grounded') {
    return AircraftStatus.destroyed;
  }

  return AircraftStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => AircraftStatus.ready,
  );
}

String _aircraftDriveTypeFromJson(Map<String, dynamic> json) {
  final explicit =
      normalizeAircraftDriveType(json['driveType'] as String? ?? '');
  if (explicit.isNotEmpty) {
    return explicit;
  }

  final features = json['featureOptions'] as List<dynamic>? ?? const [];
  for (final feature in features) {
    final normalized = normalizeAircraftDriveType(feature.toString());
    if (normalized.isNotEmpty) {
      return normalized;
    }
  }

  return normalizeAircraftDriveType(json['drive'] as String? ?? '');
}

class FlightLogEntry {
  final String id;
  final String aircraftId;
  final DateTime date;
  final String location;
  final int durationMinutes;
  final int batteryPacks;
  final String pilot;
  final String notes;

  const FlightLogEntry({
    required this.id,
    required this.aircraftId,
    required this.date,
    required this.location,
    required this.durationMinutes,
    required this.batteryPacks,
    required this.pilot,
    required this.notes,
  });

  FlightLogEntry copyWith({
    String? id,
    String? aircraftId,
    DateTime? date,
    String? location,
    int? durationMinutes,
    int? batteryPacks,
    String? pilot,
    String? notes,
  }) {
    return FlightLogEntry(
      id: id ?? this.id,
      aircraftId: aircraftId ?? this.aircraftId,
      date: date ?? this.date,
      location: location ?? this.location,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      batteryPacks: batteryPacks ?? this.batteryPacks,
      pilot: pilot ?? this.pilot,
      notes: notes ?? this.notes,
    );
  }

  factory FlightLogEntry.fromJson(Map<String, dynamic> json) {
    return FlightLogEntry(
      id: json['id'] as String,
      aircraftId: json['aircraftId'] as String,
      date: DateTime.parse(json['date'] as String),
      location: json['location'] as String,
      durationMinutes: json['durationMinutes'] as int,
      batteryPacks: json['batteryPacks'] as int,
      pilot: json['pilot'] as String,
      notes: json['notes'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'aircraftId': aircraftId,
      'date': date.toIso8601String(),
      'location': location,
      'durationMinutes': durationMinutes,
      'batteryPacks': batteryPacks,
      'pilot': pilot,
      'notes': notes,
    };
  }
}

class PilotProfile {
  final String name;
  final String homeAirfield;
  final List<String> flightAreas;
  final String club;
  final String licenseNumber;
  final String phone;
  final String email;
  final List<String> transmitters;
  final String notes;
  final String? photoDataUri;
  final String? photoThumbnailDataUri;
  final String? photoStoragePath;
  final String? photoDownloadUrl;
  final String? insuranceDocumentName;
  final String? insuranceDocumentDataUri;
  final String? insuranceDocumentStoragePath;
  final String? insuranceDocumentDownloadUrl;

  const PilotProfile({
    required this.name,
    required this.homeAirfield,
    this.flightAreas = const [],
    required this.club,
    required this.licenseNumber,
    required this.phone,
    required this.email,
    this.transmitters = const [],
    required this.notes,
    this.photoDataUri,
    this.photoThumbnailDataUri,
    this.photoStoragePath,
    this.photoDownloadUrl,
    this.insuranceDocumentName,
    this.insuranceDocumentDataUri,
    this.insuranceDocumentStoragePath,
    this.insuranceDocumentDownloadUrl,
  });

  String? get photoSource => photoDownloadUrl ?? photoDataUri;

  String? get memberPhotoSource => photoThumbnailDataUri;

  String? get insuranceDocumentSource =>
      insuranceDocumentDownloadUrl ?? insuranceDocumentDataUri;

  PilotProfile copyWith({
    String? name,
    String? homeAirfield,
    List<String>? flightAreas,
    String? club,
    String? licenseNumber,
    String? phone,
    String? email,
    List<String>? transmitters,
    String? notes,
    Object? photoDataUri = _unset,
    Object? photoThumbnailDataUri = _unset,
    Object? photoStoragePath = _unset,
    Object? photoDownloadUrl = _unset,
    Object? insuranceDocumentName = _unset,
    Object? insuranceDocumentDataUri = _unset,
    Object? insuranceDocumentStoragePath = _unset,
    Object? insuranceDocumentDownloadUrl = _unset,
  }) {
    return PilotProfile(
      name: name ?? this.name,
      homeAirfield: homeAirfield ?? this.homeAirfield,
      flightAreas: flightAreas ?? this.flightAreas,
      club: club ?? this.club,
      licenseNumber: licenseNumber ?? this.licenseNumber,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      transmitters: transmitters ?? this.transmitters,
      notes: notes ?? this.notes,
      photoDataUri: identical(photoDataUri, _unset)
          ? this.photoDataUri
          : photoDataUri as String?,
      photoThumbnailDataUri: identical(photoThumbnailDataUri, _unset)
          ? this.photoThumbnailDataUri
          : photoThumbnailDataUri as String?,
      photoStoragePath: identical(photoStoragePath, _unset)
          ? this.photoStoragePath
          : photoStoragePath as String?,
      photoDownloadUrl: identical(photoDownloadUrl, _unset)
          ? this.photoDownloadUrl
          : photoDownloadUrl as String?,
      insuranceDocumentName: identical(insuranceDocumentName, _unset)
          ? this.insuranceDocumentName
          : insuranceDocumentName as String?,
      insuranceDocumentDataUri: identical(insuranceDocumentDataUri, _unset)
          ? this.insuranceDocumentDataUri
          : insuranceDocumentDataUri as String?,
      insuranceDocumentStoragePath:
          identical(insuranceDocumentStoragePath, _unset)
              ? this.insuranceDocumentStoragePath
              : insuranceDocumentStoragePath as String?,
      insuranceDocumentDownloadUrl:
          identical(insuranceDocumentDownloadUrl, _unset)
              ? this.insuranceDocumentDownloadUrl
              : insuranceDocumentDownloadUrl as String?,
    );
  }

  factory PilotProfile.fromJson(Map<String, dynamic> json) {
    return PilotProfile(
      name: json['name'] as String? ?? 'Teddy',
      homeAirfield: json['homeAirfield'] as String? ?? 'MFC Suedhang',
      flightAreas: [
        for (final item in json['flightAreas'] as List<dynamic>? ?? [])
          item as String,
      ],
      club: json['club'] as String? ?? 'MFC Adler',
      licenseNumber: json['licenseNumber'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      transmitters: [
        for (final item in json['transmitters'] as List<dynamic>? ?? [])
          item as String,
      ],
      notes: json['notes'] as String? ??
          'Modellpilot mit Fokus auf Segelflugzeuge und Kunstflug.',
      photoDataUri: json['photoDataUri'] as String?,
      photoThumbnailDataUri: json['photoThumbnailDataUri'] as String?,
      photoStoragePath: json['photoStoragePath'] as String?,
      photoDownloadUrl: json['photoDownloadUrl'] as String?,
      insuranceDocumentName: json['insuranceDocumentName'] as String?,
      insuranceDocumentDataUri: json['insuranceDocumentDataUri'] as String?,
      insuranceDocumentStoragePath:
          json['insuranceDocumentStoragePath'] as String?,
      insuranceDocumentDownloadUrl:
          json['insuranceDocumentDownloadUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'homeAirfield': homeAirfield,
      'flightAreas': flightAreas,
      'club': club,
      'licenseNumber': licenseNumber,
      'phone': phone,
      'email': email,
      'transmitters': transmitters,
      'notes': notes,
      'photoDataUri': photoDataUri,
      'photoThumbnailDataUri': photoThumbnailDataUri,
      'photoStoragePath': photoStoragePath,
      'photoDownloadUrl': photoDownloadUrl,
      'insuranceDocumentName': insuranceDocumentName,
      'insuranceDocumentDataUri': insuranceDocumentDataUri,
      'insuranceDocumentStoragePath': insuranceDocumentStoragePath,
      'insuranceDocumentDownloadUrl': insuranceDocumentDownloadUrl,
    };
  }
}

enum LocationPresenceStatus {
  offline,
  atField,
  flying,
}

extension LocationPresenceStatusText on LocationPresenceStatus {
  String get label {
    switch (this) {
      case LocationPresenceStatus.offline:
        return 'Offline';
      case LocationPresenceStatus.atField:
        return 'Online';
      case LocationPresenceStatus.flying:
        return 'Beim Fliegen';
    }
  }
}

class AppSettings {
  final bool shareLocationWithFriends;
  final bool reachableByChat;
  final LocationPresenceStatus presenceStatus;
  final String timeZone;
  final String distanceUnit;
  final String windUnit;
  final String temperatureUnit;
  final String language;
  final bool wifiOnlySync;
  final int batteryProblemCycleThreshold;
  final int fullBatteryStorageReminderDays;
  final int batteryAgeWarningYears;
  final List<String> batteryTypes;
  final List<String> webcams;
  final List<String> webcamUrls;
  final bool notifyFriendsAtField;
  final bool notifyBatteryLimits;
  final bool notifyRepairs;
  final bool notifyGoodWeather;
  final bool playStartSound;
  final bool playFlightTimerMinuteTone;
  final bool autoOpenDashboardAfterLoading;
  final bool surfaceSettingsInitialized;
  final bool automaticBackupEnabled;
  final String? lastAutomaticBackupAt;
  final String? lastAutomaticBackupSignature;

  const AppSettings({
    required this.shareLocationWithFriends,
    required this.reachableByChat,
    required this.presenceStatus,
    this.timeZone = 'Europe/Berlin',
    this.distanceUnit = 'km',
    this.windUnit = 'km/h',
    this.temperatureUnit = 'Celsius',
    this.language = 'Deutsch',
    this.wifiOnlySync = true,
    this.batteryProblemCycleThreshold = 300,
    this.fullBatteryStorageReminderDays = 3,
    this.batteryAgeWarningYears = 5,
    this.batteryTypes = defaultSelectedBatteryTypes,
    this.webcams = defaultWebcams,
    this.webcamUrls = defaultWebcamUrls,
    this.notifyFriendsAtField = true,
    this.notifyBatteryLimits = true,
    this.notifyRepairs = true,
    this.notifyGoodWeather = true,
    this.playStartSound = true,
    this.playFlightTimerMinuteTone = true,
    this.autoOpenDashboardAfterLoading = true,
    this.surfaceSettingsInitialized = true,
    this.automaticBackupEnabled = true,
    this.lastAutomaticBackupAt,
    this.lastAutomaticBackupSignature,
  });

  AppSettings copyWith({
    bool? shareLocationWithFriends,
    bool? reachableByChat,
    LocationPresenceStatus? presenceStatus,
    String? timeZone,
    String? distanceUnit,
    String? windUnit,
    String? temperatureUnit,
    String? language,
    bool? wifiOnlySync,
    int? batteryProblemCycleThreshold,
    int? fullBatteryStorageReminderDays,
    int? batteryAgeWarningYears,
    List<String>? batteryTypes,
    List<String>? webcams,
    List<String>? webcamUrls,
    bool? notifyFriendsAtField,
    bool? notifyBatteryLimits,
    bool? notifyRepairs,
    bool? notifyGoodWeather,
    bool? playStartSound,
    bool? playFlightTimerMinuteTone,
    bool? autoOpenDashboardAfterLoading,
    bool? surfaceSettingsInitialized,
    bool? automaticBackupEnabled,
    String? lastAutomaticBackupAt,
    String? lastAutomaticBackupSignature,
  }) {
    return AppSettings(
      shareLocationWithFriends:
          shareLocationWithFriends ?? this.shareLocationWithFriends,
      reachableByChat: reachableByChat ?? this.reachableByChat,
      presenceStatus: presenceStatus ?? this.presenceStatus,
      timeZone: timeZone ?? this.timeZone,
      distanceUnit: distanceUnit ?? this.distanceUnit,
      windUnit: windUnit ?? this.windUnit,
      temperatureUnit: temperatureUnit ?? this.temperatureUnit,
      language: language ?? this.language,
      wifiOnlySync: wifiOnlySync ?? this.wifiOnlySync,
      batteryProblemCycleThreshold:
          batteryProblemCycleThreshold ?? this.batteryProblemCycleThreshold,
      fullBatteryStorageReminderDays:
          fullBatteryStorageReminderDays ?? this.fullBatteryStorageReminderDays,
      batteryAgeWarningYears:
          batteryAgeWarningYears ?? this.batteryAgeWarningYears,
      batteryTypes: batteryTypes ?? this.batteryTypes,
      webcams: webcams ?? this.webcams,
      webcamUrls: webcamUrls ?? this.webcamUrls,
      notifyFriendsAtField: notifyFriendsAtField ?? this.notifyFriendsAtField,
      notifyBatteryLimits: notifyBatteryLimits ?? this.notifyBatteryLimits,
      notifyRepairs: notifyRepairs ?? this.notifyRepairs,
      notifyGoodWeather: notifyGoodWeather ?? this.notifyGoodWeather,
      playStartSound: playStartSound ?? this.playStartSound,
      playFlightTimerMinuteTone:
          playFlightTimerMinuteTone ?? this.playFlightTimerMinuteTone,
      autoOpenDashboardAfterLoading:
          autoOpenDashboardAfterLoading ?? this.autoOpenDashboardAfterLoading,
      surfaceSettingsInitialized:
          surfaceSettingsInitialized ?? this.surfaceSettingsInitialized,
      automaticBackupEnabled:
          automaticBackupEnabled ?? this.automaticBackupEnabled,
      lastAutomaticBackupAt:
          lastAutomaticBackupAt ?? this.lastAutomaticBackupAt,
      lastAutomaticBackupSignature:
          lastAutomaticBackupSignature ?? this.lastAutomaticBackupSignature,
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final shareLocationWithFriends =
        json['shareLocationWithFriends'] as bool? ?? false;
    final presenceStatus = LocationPresenceStatus.values.firstWhere(
      (status) => status.name == json['presenceStatus'],
      orElse: () => LocationPresenceStatus.offline,
    );
    return AppSettings(
      shareLocationWithFriends: shareLocationWithFriends,
      reachableByChat: json['reachableByChat'] as bool? ?? true,
      presenceStatus: shareLocationWithFriends
          ? presenceStatus
          : LocationPresenceStatus.offline,
      timeZone: json['timeZone'] as String? ?? 'Europe/Berlin',
      distanceUnit: json['distanceUnit'] as String? ?? 'km',
      windUnit: json['windUnit'] as String? ?? 'km/h',
      temperatureUnit: json['temperatureUnit'] as String? ?? 'Celsius',
      language: json['language'] as String? ?? 'Deutsch',
      wifiOnlySync: json['wifiOnlySync'] as bool? ?? true,
      batteryProblemCycleThreshold:
          json['batteryProblemCycleThreshold'] as int? ?? 300,
      fullBatteryStorageReminderDays:
          json['fullBatteryStorageReminderDays'] as int? ?? 3,
      batteryAgeWarningYears: json['batteryAgeWarningYears'] as int? ?? 5,
      batteryTypes: [
        for (final item in json['batteryTypes'] as List<dynamic>? ??
            defaultSelectedBatteryTypes)
          if (item is String && item.trim().isNotEmpty) item.trim(),
      ],
      webcams: [
        for (final item in json['webcams'] as List<dynamic>? ?? defaultWebcams)
          if (item is String && item.trim().isNotEmpty) item.trim(),
      ],
      webcamUrls: [
        for (final item
            in json['webcamUrls'] as List<dynamic>? ?? defaultWebcamUrls)
          if (item is String) item.trim(),
      ],
      notifyFriendsAtField: json['notifyFriendsAtField'] as bool? ?? true,
      notifyBatteryLimits: json['notifyBatteryLimits'] as bool? ?? true,
      notifyRepairs: json['notifyRepairs'] as bool? ?? true,
      notifyGoodWeather: json['notifyGoodWeather'] as bool? ?? true,
      playStartSound: json['playStartSound'] as bool? ?? true,
      playFlightTimerMinuteTone:
          json['playFlightTimerMinuteTone'] as bool? ?? true,
      autoOpenDashboardAfterLoading:
          json['autoOpenDashboardAfterLoading'] as bool? ?? true,
      surfaceSettingsInitialized:
          json['surfaceSettingsInitialized'] as bool? ?? false,
      automaticBackupEnabled: json['automaticBackupEnabled'] as bool? ?? true,
      lastAutomaticBackupAt: json['lastAutomaticBackupAt'] as String?,
      lastAutomaticBackupSignature:
          json['lastAutomaticBackupSignature'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final visiblePresenceStatus = shareLocationWithFriends
        ? presenceStatus
        : LocationPresenceStatus.offline;
    return {
      'shareLocationWithFriends': shareLocationWithFriends,
      'reachableByChat': reachableByChat,
      'presenceStatus': visiblePresenceStatus.name,
      'timeZone': timeZone,
      'distanceUnit': distanceUnit,
      'windUnit': windUnit,
      'temperatureUnit': temperatureUnit,
      'language': language,
      'wifiOnlySync': wifiOnlySync,
      'batteryProblemCycleThreshold': batteryProblemCycleThreshold,
      'fullBatteryStorageReminderDays': fullBatteryStorageReminderDays,
      'batteryAgeWarningYears': batteryAgeWarningYears,
      'batteryTypes': batteryTypes,
      'webcams': webcams,
      'webcamUrls': webcamUrls,
      'notifyFriendsAtField': notifyFriendsAtField,
      'notifyBatteryLimits': notifyBatteryLimits,
      'notifyRepairs': notifyRepairs,
      'notifyGoodWeather': notifyGoodWeather,
      'playStartSound': playStartSound,
      'playFlightTimerMinuteTone': playFlightTimerMinuteTone,
      'autoOpenDashboardAfterLoading': autoOpenDashboardAfterLoading,
      'surfaceSettingsInitialized': surfaceSettingsInitialized,
      'automaticBackupEnabled': automaticBackupEnabled,
      'lastAutomaticBackupAt': lastAutomaticBackupAt,
      'lastAutomaticBackupSignature': lastAutomaticBackupSignature,
    };
  }
}

const defaultSelectedBatteryTypes = [
  'LiPo 1S',
  'LiPo 2S',
  'LiPo 3S',
  'LiPo 4S',
];

const defaultBatteryTypes = [
  'LiPo 1S',
  'LiPo 2S',
  'LiPo 3S',
  'LiPo 4S',
  'LiPo 5S',
  'LiPo 6S',
  'LiPo 7S',
  'LiPo 8S',
  'LiPo 9S',
  'LiPo 10S',
  'LiPo 11S',
  'LiPo 12S',
  'LiFePo4 / LiFe',
  'LiIon',
  'NiMH',
];

const defaultWebcams = [
  'LMFC-Fluggelaende',
  'Startbahn Nord',
  'Vereinsheim',
];

const defaultWebcamUrls = [
  '',
  '',
  '',
];

enum BatteryStatus {
  charged,
  storage,
  discharged,
  service,
}

extension BatteryStatusText on BatteryStatus {
  String get label {
    switch (this) {
      case BatteryStatus.charged:
        return 'Flug-ready';
      case BatteryStatus.storage:
        return 'Lagerspannung';
      case BatteryStatus.discharged:
        return 'Leer geflogen';
      case BatteryStatus.service:
        return 'Pruefen';
    }
  }
}

class BatteryPack {
  final String id;
  final int inventoryNumber;
  final String label;
  final String manufacturer;
  final String chemistry;
  final int cells;
  final int capacityMah;
  final String cRate;
  final String weightWithCable;
  final String dimensionsLxBxH;
  final String chargeRateRecommendedMax;
  final int chargePercent;
  final int cycles;
  final BatteryStatus status;
  final DateTime purchaseDate;
  final DateTime lastUsed;
  final String assignedAircraftId;
  final List<String> assignedAircraftIds;
  final String notes;
  final String? photoDataUri;
  final String? photoThumbnailDataUri;
  final String? photoStoragePath;
  final String? photoDownloadUrl;

  const BatteryPack({
    required this.id,
    this.inventoryNumber = 0,
    required this.label,
    this.manufacturer = '',
    required this.chemistry,
    required this.cells,
    required this.capacityMah,
    this.cRate = '30',
    this.weightWithCable = '',
    this.dimensionsLxBxH = '',
    this.chargeRateRecommendedMax = '',
    required this.chargePercent,
    required this.cycles,
    required this.status,
    required this.purchaseDate,
    required this.lastUsed,
    required this.assignedAircraftId,
    this.assignedAircraftIds = const [],
    required this.notes,
    this.photoDataUri,
    this.photoThumbnailDataUri,
    this.photoStoragePath,
    this.photoDownloadUrl,
  });

  List<String> get aircraftIds {
    if (assignedAircraftIds.isNotEmpty) {
      return assignedAircraftIds;
    }
    return assignedAircraftId.isEmpty ? const [] : [assignedAircraftId];
  }

  String get dischargeRateLabel {
    final value = cRate.trim();
    if (value.isEmpty) {
      return '-';
    }
    return value.toLowerCase().contains('c') ? value : '${value}C';
  }

  String? get photoSource {
    final downloadUrl = photoDownloadUrl?.trim();
    if (downloadUrl != null && downloadUrl.isNotEmpty) {
      return downloadUrl;
    }
    final dataUri = photoDataUri?.trim();
    if (dataUri != null && dataUri.isNotEmpty) {
      return dataUri;
    }
    return null;
  }

  String? get photoPreviewSource {
    final thumbnail = photoThumbnailDataUri?.trim();
    if (thumbnail != null && thumbnail.isNotEmpty) {
      return thumbnail;
    }
    return photoSource;
  }

  BatteryPack copyWith({
    String? id,
    int? inventoryNumber,
    String? label,
    String? manufacturer,
    String? chemistry,
    int? cells,
    int? capacityMah,
    String? cRate,
    String? weightWithCable,
    String? dimensionsLxBxH,
    String? chargeRateRecommendedMax,
    int? chargePercent,
    int? cycles,
    BatteryStatus? status,
    DateTime? purchaseDate,
    DateTime? lastUsed,
    String? assignedAircraftId,
    List<String>? assignedAircraftIds,
    String? notes,
    Object? photoDataUri = _unset,
    Object? photoThumbnailDataUri = _unset,
    Object? photoStoragePath = _unset,
    Object? photoDownloadUrl = _unset,
  }) {
    return BatteryPack(
      id: id ?? this.id,
      inventoryNumber: inventoryNumber ?? this.inventoryNumber,
      label: label ?? this.label,
      manufacturer: manufacturer ?? this.manufacturer,
      chemistry: chemistry ?? this.chemistry,
      cells: cells ?? this.cells,
      capacityMah: capacityMah ?? this.capacityMah,
      cRate: cRate ?? this.cRate,
      weightWithCable: weightWithCable ?? this.weightWithCable,
      dimensionsLxBxH: dimensionsLxBxH ?? this.dimensionsLxBxH,
      chargeRateRecommendedMax:
          chargeRateRecommendedMax ?? this.chargeRateRecommendedMax,
      chargePercent: chargePercent ?? this.chargePercent,
      cycles: cycles ?? this.cycles,
      status: status ?? this.status,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      lastUsed: lastUsed ?? this.lastUsed,
      assignedAircraftId: assignedAircraftId ?? this.assignedAircraftId,
      assignedAircraftIds: assignedAircraftIds ?? this.assignedAircraftIds,
      notes: notes ?? this.notes,
      photoDataUri: identical(photoDataUri, _unset)
          ? this.photoDataUri
          : photoDataUri as String?,
      photoThumbnailDataUri: identical(photoThumbnailDataUri, _unset)
          ? this.photoThumbnailDataUri
          : photoThumbnailDataUri as String?,
      photoStoragePath: identical(photoStoragePath, _unset)
          ? this.photoStoragePath
          : photoStoragePath as String?,
      photoDownloadUrl: identical(photoDownloadUrl, _unset)
          ? this.photoDownloadUrl
          : photoDownloadUrl as String?,
    );
  }

  factory BatteryPack.fromJson(Map<String, dynamic> json) {
    return BatteryPack(
      id: json['id'] as String,
      inventoryNumber: json['inventoryNumber'] as int? ?? 0,
      label: json['label'] as String,
      manufacturer: json['manufacturer'] as String? ?? '',
      chemistry: json['chemistry'] as String,
      cells: json['cells'] as int,
      capacityMah: json['capacityMah'] as int,
      cRate: _textFromJson(json['cRate'], '30'),
      weightWithCable: json['weightWithCable'] as String? ?? '',
      dimensionsLxBxH: json['dimensionsLxBxH'] as String? ?? '',
      chargeRateRecommendedMax:
          json['chargeRateRecommendedMax'] as String? ?? '',
      chargePercent: json['chargePercent'] as int,
      cycles: json['cycles'] as int,
      status: _batteryStatusFromJson(json['status'] as String?),
      purchaseDate: DateTime.tryParse(json['purchaseDate'] as String? ?? '') ??
          DateTime(2026),
      lastUsed: DateTime.parse(json['lastUsed'] as String),
      assignedAircraftId: json['assignedAircraftId'] as String? ?? '',
      assignedAircraftIds: [
        for (final item
            in json['assignedAircraftIds'] as List<dynamic>? ?? const [])
          item as String,
      ],
      notes: json['notes'] as String,
      photoDataUri: json['photoDataUri'] as String?,
      photoThumbnailDataUri: json['photoThumbnailDataUri'] as String?,
      photoStoragePath: json['photoStoragePath'] as String?,
      photoDownloadUrl: json['photoDownloadUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'inventoryNumber': inventoryNumber,
      'label': label,
      'manufacturer': manufacturer,
      'chemistry': chemistry,
      'cells': cells,
      'capacityMah': capacityMah,
      'cRate': cRate,
      'weightWithCable': weightWithCable,
      'dimensionsLxBxH': dimensionsLxBxH,
      'chargeRateRecommendedMax': chargeRateRecommendedMax,
      'chargePercent': chargePercent,
      'cycles': cycles,
      'status': status.name,
      'purchaseDate': purchaseDate.toIso8601String(),
      'lastUsed': lastUsed.toIso8601String(),
      'assignedAircraftId': assignedAircraftId,
      'assignedAircraftIds': aircraftIds,
      'notes': notes,
      'photoDataUri': photoDataUri,
      'photoThumbnailDataUri': photoThumbnailDataUri,
      'photoStoragePath': photoStoragePath,
      'photoDownloadUrl': photoDownloadUrl,
    };
  }
}

String _textFromJson(Object? value, String fallback) {
  if (value == null) {
    return fallback;
  }
  return value.toString();
}

BatteryStatus _batteryStatusFromJson(String? value) {
  if (value == 'charging') {
    return BatteryStatus.discharged;
  }

  return BatteryStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => BatteryStatus.storage,
  );
}
