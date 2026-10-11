import 'package:famgpslink/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 11, 12);
  SharedLocation location(Duration age, {double? accuracy}) => SharedLocation(
    latitude: 19.0,
    longitude: 72.0,
    measuredAt: now.subtract(age).millisecondsSinceEpoch,
    publishedAt: now.millisecondsSinceEpoch,
    accuracy: accuracy,
  );
  test('staleness uses the measurement time, not a later upload timestamp', () {
    expect(location(const Duration(minutes: 15)).isStale(now), false);
    expect(
      location(const Duration(minutes: 15, seconds: 1)).isStale(now),
      true,
    );
  });
  test('manual pin has no inferred accuracy or automatic fresh timestamp', () {
    final fix = SharedLocation.fromMap({
      'latitude': 1,
      'longitude': 2,
      'measuredAt': now
          .subtract(const Duration(hours: 2))
          .millisecondsSinceEpoch,
      'publishedAt': now
          .subtract(const Duration(hours: 2))
          .millisecondsSinceEpoch,
    });
    expect(fix.accuracy, null);
    expect(fix.ageLabel(now), '2 hr ago');
    expect(fix.isStale(now), true);
  });
  test('pairing codes omit ambiguous characters and installation IDs are stable-length', () {
    expect(randomCode(8), matches(RegExp(r'^[A-HJ-NP-Z2-9]{8}$')));
    expect(randomCode(32).length, 32);
  });
  test('empty tracking state defaults to collection disabled', () {
    final control = TrackingControl.fromMap(null);
    expect(control.sharing, false);
    expect(control.override, false);
  });
}
