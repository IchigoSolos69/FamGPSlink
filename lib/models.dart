import 'dart:math';

Map<String, dynamic> objectMap(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : <String, dynamic>{};

String randomCode([int length = 16]) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final random = Random.secure();
  return List.generate(length, (_) => alphabet[random.nextInt(alphabet.length)])
      .join();
}

class Member {
  const Member(this.id, this.name, this.authUid);
  final String id;
  final String name;
  final String authUid;

  factory Member.fromMap(String id, Object? value) {
    final map = objectMap(value);
    return Member(id, map['name'] as String? ?? 'Family member',
        map['authUid'] as String? ?? '');
  }
}

class SharedLocation {
  const SharedLocation({
    required this.latitude,
    required this.longitude,
    required this.measuredAt,
    required this.publishedAt,
    this.accuracy,
  });
  final double latitude;
  final double longitude;
  final int measuredAt;
  final int publishedAt;
  final double? accuracy;

  factory SharedLocation.fromMap(Object? value) {
    final map = objectMap(value);
    return SharedLocation(
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      measuredAt: (map['measuredAt'] as num).toInt(),
      publishedAt: (map['publishedAt'] as num).toInt(),
      accuracy: (map['accuracy'] as num?)?.toDouble(),
    );
  }

  bool isStale(DateTime now) =>
      now.millisecondsSinceEpoch - measuredAt > const Duration(minutes: 15).inMilliseconds;

  String ageLabel(DateTime now) {
    final seconds = max(0, (now.millisecondsSinceEpoch - measuredAt) ~/ 1000);
    if (seconds < 60) return 'Just updated';
    if (seconds < 3600) return '${seconds ~/ 60} min ago';
    if (seconds < 86400) return '${seconds ~/ 3600} hr ago';
    return '${seconds ~/ 86400} days ago';
  }
}

class TrackingControl {
  const TrackingControl({this.sharing = false, this.override = false, this.revision = 0});
  final bool sharing;
  final bool override;
  final int revision;

  factory TrackingControl.fromMap(Object? value) {
    final map = objectMap(value);
    return TrackingControl(
      sharing: map['sharingEnabled'] == true,
      override: map['overrideActive'] == true,
      revision: (map['revision'] as num?)?.toInt() ?? 0,
    );
  }
}

class PairingRequest {
  PairingRequest(this.uid, Object? value) : data = objectMap(value);
  final String uid;
  final Map<String, dynamic> data;
  String get name => data['name'] as String? ?? '';
  String get code => data['code'] as String? ?? '';
  String get installationId => data['installationId'] as String? ?? '';
}
