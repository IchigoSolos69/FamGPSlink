import 'dart:convert';

import 'package:famgpslink/family_controller.dart';
import 'package:famgpslink/location_bridge.dart';
import 'package:famgpslink/models.dart';
import 'package:famgpslink/screens.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';

class SharingUser extends Fake implements User {
  @override
  String get uid => 'owner-uid';
}

class SharingAuth extends Fake implements FirebaseAuth {
  @override
  User get currentUser => SharingUser();
}

class SharingSnapshot extends Fake implements DataSnapshot {
  SharingSnapshot(this.value);
  @override
  final Object? value;
  @override
  bool get exists => value != null;
}

class SharingResult extends Fake implements TransactionResult {
  SharingResult(this.committed, Object? value)
    : snapshot = SharingSnapshot(value);
  @override
  final bool committed;
  @override
  final DataSnapshot snapshot;
}

class SharingDatabase extends Fake implements FirebaseDatabase {
  SharingDatabase(this.state);
  Map<String, dynamic>? state;
  bool coldCacheRetried = false;
  int writes = 0;
  Object? error;
  @override
  DatabaseReference ref([String? path]) => SharingReference(this);
}

class SharingReference extends Fake implements DatabaseReference {
  SharingReference(this.database);
  final SharingDatabase database;
  @override
  DatabaseReference child(String relative) => this;
  @override
  Future<DataSnapshot> get() async => SharingSnapshot(database.state);
  @override
  Future<TransactionResult> runTransaction(
    TransactionHandler handler, {
    bool applyLocally = true,
  }) async {
    expect(applyLocally, false);
    if (database.error != null) throw database.error!;
    // Native transactions can first receive null even after get() succeeds.
    final initial = handler(null);
    if (initial.aborted) return SharingResult(false, null);
    database.coldCacheRetried = true;
    final transaction = handler(jsonDecode(jsonEncode(database.state)));
    if (transaction.aborted) return SharingResult(false, database.state);
    database.state = objectMap(transaction.value);
    database.writes++;
    return SharingResult(true, database.state);
  }
}

class SharingBridge extends LocationBridge {
  int starts = 0;
  int stops = 0;
  @override
  Future<void> start(String memberId) async => starts++;
  @override
  Future<void> stop() async => stops++;
  @override
  Future<Map<String, dynamic>> freshFix() async => {
    'latitude': 1.0,
    'longitude': 2.0,
    'accuracy': 8.0,
    'measuredAt': DateTime.now().millisecondsSinceEpoch,
  };
}

Map<String, dynamic> initialState({
  bool sharing = false,
  bool manual = false,
}) => {
  'control': {
    'sharingEnabled': sharing,
    'overrideActive': manual,
    'revision': 12345,
    if (manual) 'manual': {'latitude': 4.0, 'longitude': 5.0, 'setAt': 100},
  },
  if (sharing)
    'location': {
      'latitude': 4.0,
      'longitude': 5.0,
      'measuredAt': 100,
      'publishedAt': 100,
    },
};

FamilyController controller(SharingDatabase database, SharingBridge bridge) =>
    FamilyController(auth: SharingAuth(), database: database, bridge: bridge)
      ..connected = true
      ..ownerUid = 'owner-uid'
      ..self = const Member('owner', 'Owner', 'owner-uid');

void main() {
  test(
    'sharing on a newly approved phone retries the empty native cache',
    () async {
      final database = SharingDatabase(initialState());
      final bridge = SharingBridge();
      final family = controller(database, bridge);
      await family.setSharing(true);
      expect(database.coldCacheRetried, true);
      expect(database.state!['control']['sharingEnabled'], true);
      expect(database.state!['control']['revision'], 12346);
      expect(bridge.starts, 1);
      family.dispose();
    },
  );

  test('repeated enable preserves the existing fix and revision', () async {
    final database = SharingDatabase(initialState(sharing: true));
    final original = jsonEncode(database.state);
    final bridge = SharingBridge();
    final family = controller(database, bridge);
    await family.setSharing(true);
    expect(database.writes, 0);
    expect(jsonEncode(database.state), original);
    expect(bridge.starts, 1);
    family.dispose();
  });

  test('pause removes the pin and stops collection after the save', () async {
    final database = SharingDatabase(initialState(sharing: true));
    final bridge = SharingBridge();
    final family = controller(database, bridge);
    await family.setSharing(false);
    expect(database.state!.containsKey('location'), false);
    expect(database.state!['control']['sharingEnabled'], false);
    expect(bridge.stops, 1);
    family.dispose();
  });

  test(
    'manual resume uses the saved server override, not stale controller state',
    () async {
      final database = SharingDatabase(initialState(manual: true));
      final bridge = SharingBridge();
      final family = controller(database, bridge);
      await family.setSharing(true);
      expect(database.state!['location']['measuredAt'], 100);
      expect(database.state!['location'].containsKey('accuracy'), false);
      expect(bridge.starts, 0);
      expect(bridge.stops, 1);
      family.dispose();
    },
  );

  test('manual save and fresh GPS restore also retry an empty cache', () async {
    final database = SharingDatabase(initialState());
    final bridge = SharingBridge();
    final family = controller(database, bridge);
    await family.setManual(4, 5);
    expect(database.state!['control']['overrideActive'], true);
    family.control = TrackingControl.fromMap(database.state!['control']);
    await family.clearManual();
    expect(database.state!['control']['overrideActive'], false);
    expect(database.state!['control'].containsKey('manual'), false);
    expect(database.state!['location']['accuracy'], 8.0);
    family.dispose();
  });

  test(
    'failed save never starts collection and reports the database error code',
    () async {
      final database = SharingDatabase(initialState())
        ..error = FirebaseException(
          plugin: 'firebase_database',
          code: 'permission-denied',
        );
      final bridge = SharingBridge();
      final family = controller(database, bridge);
      await expectLater(
        family.setSharing(true),
        throwsA(isA<FirebaseException>()),
      );
      expect(bridge.starts, 0);
      expect(readableError(database.error!), contains('permission-denied'));
      family.dispose();
    },
  );
}
