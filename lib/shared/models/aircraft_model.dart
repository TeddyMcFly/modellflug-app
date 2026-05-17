enum AircraftStatus {
  ready,
  maintenance,
  destroyed,
}

extension AircraftStatusText on AircraftStatus {
  String get label {
    switch (this) {
      case AircraftStatus.ready:
        return 'Flugbereit';
      case AircraftStatus.maintenance:
        return 'Wartung';
      case AircraftStatus.destroyed:
        return 'Zerstört';
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
  final String receiver;
  final String propeller;
  final DateTime purchaseDate;
  final String drive;
  final int batteryCount;
  final int totalFlights;
  final double flightHours;
  final AircraftStatus status;
  final DateTime lastService;
  final DateTime nextService;
  final String notes;
  final String? photoDataUri;
  final List<String> photoDataUris;

  const AircraftModel({
    required this.id,
    required this.name,
    required this.type,
    required this.manufacturer,
    required this.registration,
    required this.wingspanMeters,
    required this.lengthMeters,
    required this.weightKg,
    required this.receiver,
    required this.propeller,
    required this.purchaseDate,
    required this.drive,
    required this.batteryCount,
    required this.totalFlights,
    required this.flightHours,
    required this.status,
    required this.lastService,
    required this.nextService,
    required this.notes,
    this.photoDataUri,
    this.photoDataUris = const [],
  });

  List<String> get photos {
    if (photoDataUris.isNotEmpty) {
      return photoDataUris;
    }
    if (photoDataUri != null && photoDataUri!.isNotEmpty) {
      return [photoDataUri!];
    }
    return const [];
  }

  AircraftModel copyWith({
    String? id,
    String? name,
    String? type,
    String? manufacturer,
    String? registration,
    double? wingspanMeters,
    double? lengthMeters,
    double? weightKg,
    String? receiver,
    String? propeller,
    DateTime? purchaseDate,
    String? drive,
    int? batteryCount,
    int? totalFlights,
    double? flightHours,
    AircraftStatus? status,
    DateTime? lastService,
    DateTime? nextService,
    String? notes,
    String? photoDataUri,
    List<String>? photoDataUris,
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
      receiver: receiver ?? this.receiver,
      propeller: propeller ?? this.propeller,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      drive: drive ?? this.drive,
      batteryCount: batteryCount ?? this.batteryCount,
      totalFlights: totalFlights ?? this.totalFlights,
      flightHours: flightHours ?? this.flightHours,
      status: status ?? this.status,
      lastService: lastService ?? this.lastService,
      nextService: nextService ?? this.nextService,
      notes: notes ?? this.notes,
      photoDataUri: photoDataUri ?? this.photoDataUri,
      photoDataUris: photoDataUris ?? this.photoDataUris,
    );
  }

  factory AircraftModel.fromJson(Map<String, dynamic> json) {
    return AircraftModel(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      manufacturer: json['manufacturer'] as String,
      registration: json['registration'] as String,
      wingspanMeters: (json['wingspanMeters'] as num).toDouble(),
      lengthMeters: (json['lengthMeters'] as num?)?.toDouble() ?? 0,
      weightKg: (json['weightKg'] as num).toDouble(),
      receiver: json['receiver'] as String? ?? '',
      propeller: json['propeller'] as String? ?? '',
      purchaseDate: DateTime.tryParse(json['purchaseDate'] as String? ?? '') ??
          DateTime(2026),
      drive: json['drive'] as String? ?? '',
      batteryCount: json['batteryCount'] as int,
      totalFlights: json['totalFlights'] as int,
      flightHours: (json['flightHours'] as num).toDouble(),
      status: _aircraftStatusFromJson(json['status'] as String?),
      lastService: DateTime.parse(json['lastService'] as String),
      nextService: DateTime.parse(json['nextService'] as String),
      notes: json['notes'] as String,
      photoDataUri: json['photoDataUri'] as String?,
      photoDataUris: [
        for (final item in json['photoDataUris'] as List<dynamic>? ?? [])
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
      'receiver': receiver,
      'propeller': propeller,
      'purchaseDate': purchaseDate.toIso8601String(),
      'drive': drive,
      'batteryCount': batteryCount,
      'totalFlights': totalFlights,
      'flightHours': flightHours,
      'status': status.name,
      'lastService': lastService.toIso8601String(),
      'nextService': nextService.toIso8601String(),
      'notes': notes,
      'photoDataUri': photoDataUri,
      'photoDataUris': photoDataUris,
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
  final String club;
  final String licenseNumber;
  final String phone;
  final String email;
  final String notes;
  final String? photoDataUri;

  const PilotProfile({
    required this.name,
    required this.homeAirfield,
    required this.club,
    required this.licenseNumber,
    required this.phone,
    required this.email,
    required this.notes,
    this.photoDataUri,
  });

  PilotProfile copyWith({
    String? name,
    String? homeAirfield,
    String? club,
    String? licenseNumber,
    String? phone,
    String? email,
    String? notes,
    String? photoDataUri,
  }) {
    return PilotProfile(
      name: name ?? this.name,
      homeAirfield: homeAirfield ?? this.homeAirfield,
      club: club ?? this.club,
      licenseNumber: licenseNumber ?? this.licenseNumber,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      notes: notes ?? this.notes,
      photoDataUri: photoDataUri ?? this.photoDataUri,
    );
  }

  factory PilotProfile.fromJson(Map<String, dynamic> json) {
    return PilotProfile(
      name: json['name'] as String? ?? 'Teddy',
      homeAirfield: json['homeAirfield'] as String? ?? 'MFC Suedhang',
      club: json['club'] as String? ?? 'MFC Adler',
      licenseNumber: json['licenseNumber'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      notes: json['notes'] as String? ??
          'Modellpilot mit Fokus auf Segler und Kunstflug.',
      photoDataUri: json['photoDataUri'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'homeAirfield': homeAirfield,
      'club': club,
      'licenseNumber': licenseNumber,
      'phone': phone,
      'email': email,
      'notes': notes,
      'photoDataUri': photoDataUri,
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
        return 'Am Platz';
      case LocationPresenceStatus.flying:
        return 'Beim Fliegen';
    }
  }
}

class AppSettings {
  final bool shareLocationWithFriends;
  final bool reachableByChat;
  final LocationPresenceStatus presenceStatus;

  const AppSettings({
    required this.shareLocationWithFriends,
    required this.reachableByChat,
    required this.presenceStatus,
  });

  AppSettings copyWith({
    bool? shareLocationWithFriends,
    bool? reachableByChat,
    LocationPresenceStatus? presenceStatus,
  }) {
    return AppSettings(
      shareLocationWithFriends:
          shareLocationWithFriends ?? this.shareLocationWithFriends,
      reachableByChat: reachableByChat ?? this.reachableByChat,
      presenceStatus: presenceStatus ?? this.presenceStatus,
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      shareLocationWithFriends:
          json['shareLocationWithFriends'] as bool? ?? false,
      reachableByChat: json['reachableByChat'] as bool? ?? true,
      presenceStatus: LocationPresenceStatus.values.firstWhere(
        (status) => status.name == json['presenceStatus'],
        orElse: () => LocationPresenceStatus.offline,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'shareLocationWithFriends': shareLocationWithFriends,
      'reachableByChat': reachableByChat,
      'presenceStatus': presenceStatus.name,
    };
  }
}

enum BatteryStatus {
  charged,
  storage,
  charging,
  service,
}

extension BatteryStatusText on BatteryStatus {
  String get label {
    switch (this) {
      case BatteryStatus.charged:
        return 'Voll';
      case BatteryStatus.storage:
        return 'Lagerspannung';
      case BatteryStatus.charging:
        return 'Laedt';
      case BatteryStatus.service:
        return 'Pruefen';
    }
  }
}

class BatteryPack {
  final String id;
  final String label;
  final String chemistry;
  final int cells;
  final int capacityMah;
  final int chargePercent;
  final int cycles;
  final BatteryStatus status;
  final DateTime lastUsed;
  final String assignedAircraftId;
  final String notes;

  const BatteryPack({
    required this.id,
    required this.label,
    required this.chemistry,
    required this.cells,
    required this.capacityMah,
    required this.chargePercent,
    required this.cycles,
    required this.status,
    required this.lastUsed,
    required this.assignedAircraftId,
    required this.notes,
  });

  BatteryPack copyWith({
    String? id,
    String? label,
    String? chemistry,
    int? cells,
    int? capacityMah,
    int? chargePercent,
    int? cycles,
    BatteryStatus? status,
    DateTime? lastUsed,
    String? assignedAircraftId,
    String? notes,
  }) {
    return BatteryPack(
      id: id ?? this.id,
      label: label ?? this.label,
      chemistry: chemistry ?? this.chemistry,
      cells: cells ?? this.cells,
      capacityMah: capacityMah ?? this.capacityMah,
      chargePercent: chargePercent ?? this.chargePercent,
      cycles: cycles ?? this.cycles,
      status: status ?? this.status,
      lastUsed: lastUsed ?? this.lastUsed,
      assignedAircraftId: assignedAircraftId ?? this.assignedAircraftId,
      notes: notes ?? this.notes,
    );
  }

  factory BatteryPack.fromJson(Map<String, dynamic> json) {
    return BatteryPack(
      id: json['id'] as String,
      label: json['label'] as String,
      chemistry: json['chemistry'] as String,
      cells: json['cells'] as int,
      capacityMah: json['capacityMah'] as int,
      chargePercent: json['chargePercent'] as int,
      cycles: json['cycles'] as int,
      status: BatteryStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => BatteryStatus.storage,
      ),
      lastUsed: DateTime.parse(json['lastUsed'] as String),
      assignedAircraftId: json['assignedAircraftId'] as String,
      notes: json['notes'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'chemistry': chemistry,
      'cells': cells,
      'capacityMah': capacityMah,
      'chargePercent': chargePercent,
      'cycles': cycles,
      'status': status.name,
      'lastUsed': lastUsed.toIso8601String(),
      'assignedAircraftId': assignedAircraftId,
      'notes': notes,
    };
  }
}
