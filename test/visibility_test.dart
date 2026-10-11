import 'dart:async';

import 'package:famgpslink/family_controller.dart';
import 'package:famgpslink/models.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_test/flutter_test.dart';

class VisibilityAuth extends Fake implements FirebaseAuth {
  @override
  User? get currentUser => null;
}

class VisibilitySnapshot extends Fake implements DataSnapshot {
  VisibilitySnapshot(this.value);
  @override
  final Object? value;
  @override
  bool get exists => value != null;
}

class VisibilityEvent extends Fake implements DatabaseEvent {
  VisibilityEvent(Object? value) : snapshot = VisibilitySnapshot(value);
  @override
  final DataSnapshot snapshot;
}

class VisibilityDatabase extends Fake implements FirebaseDatabase {
  final streams = <String, StreamController<DatabaseEvent>>{};
  final reads = <String>[];
  Stream<DatabaseEvent> stream(String key) {
    reads.add(key);
    return streams
        .putIfAbsent(key, () => StreamController<DatabaseEvent>.broadcast())
        .stream;
  }

  void emit(String key, Object? value) =>
      streams[key]!.add(VisibilityEvent(value));
  @override
  DatabaseReference ref([String? path]) =>
      VisibilityReference(this, path ?? '');

  Future<void> close() async {
    for (final stream in streams.values) {
      await stream.close();
    }
  }
}

class VisibilityQuery extends Fake implements Query {
  VisibilityQuery(this.database, this.path, this.order, [this.equal]);
  final VisibilityDatabase database;
  @override
  final String path;
  final String order;
  final Object? equal;
  @override
  Query equalTo(Object? value, {String? key}) =>
      VisibilityQuery(database, path, order, value);
  @override
  Stream<DatabaseEvent> get onValue => database.stream('$path|$order=$equal');
}

class VisibilityReference extends Fake implements DatabaseReference {
  VisibilityReference(this.database, this.path);
  final VisibilityDatabase database;
  @override
  final String path;
  @override
  DatabaseReference child(String relative) =>
      VisibilityReference(database, '$path/$relative');
  @override
  Stream<DatabaseEvent> get onValue => database.stream(path);
  @override
  Query orderByChild(String key) => VisibilityQuery(database, path, key);
}

Future<void> settleStreams() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('a roster permission error clears the map without revoking a valid device approval', () async {
    final database = VisibilityDatabase();
    final family = FamilyController(auth: VisibilityAuth(), database: database)
      ..ownerUid = 'owner-uid'
      ..ownerMemberId = 'owner'
      ..self = const Member('alice', 'Alice', 'alice-uid')
      ..control = const TrackingControl(sharing: true, revision: 1);
    family.setMapVisible(true);
    await settleStreams();
    database.emit('family/members|visibility=family', {
      'owner': {'name': 'Adi', 'active': true},
    });
    await settleStreams();
    database.emit('family/states/owner/location', {
      'latitude': 1,
      'longitude': 2,
      'measuredAt': 100,
      'publishedAt': 100,
    });
    await settleStreams();
    database.streams['family/members|visibility=family']!.addError(
      FirebaseException(plugin: 'firebase_database', code: 'permission-denied'),
    );
    await settleStreams();
    expect(family.self?.id, 'alice');
    expect(family.control.sharing, true);
    expect(family.members, isEmpty);
    expect(family.locations, isEmpty);
    expect(family.error, contains('Map access'));
    expect(family.error, isNot(contains('approval again')));
    family.setMapVisible(true);
    await settleStreams();
    database.emit('family/members|visibility=family', {
      'owner': {'name': 'Adi', 'active': true},
    });
    await settleStreams();
    expect(family.members.single.id, 'owner');
    family.dispose();
    await settleStreams();
    await database.close();
  });
  test(
    'private map subscribes only to owner and self and clears pins when hidden',
    () async {
      final database = VisibilityDatabase();
      final family =
          FamilyController(auth: VisibilityAuth(), database: database)
            ..ownerUid = 'owner-uid'
            ..ownerMemberId = 'owner'
            ..self = const Member(
              'partner',
              'Partner',
              'partner-uid',
              ownerOnly: true,
            );
      family.setMapVisible(true);
      await settleStreams();
      expect(database.reads.toSet(), {
        'family/members/owner',
        'family/members/partner',
      });
      database.emit('family/members/owner', {'name': 'Adi', 'active': true});
      database.emit('family/members/partner', {
        'name': 'Partner',
        'active': true,
        'visibility': 'ownerOnly',
      });
      await settleStreams();
      expect(family.members.map((member) => member.id).toSet(), {
        'owner',
        'partner',
      });
      database.emit('family/states/owner/location', {
        'latitude': 1,
        'longitude': 2,
        'measuredAt': 100,
        'publishedAt': 100,
      });
      await settleStreams();
      expect(family.locations.keys, ['owner']);
      expect(database.reads, isNot(contains('family/members')));
      expect(
        database.reads,
        isNot(contains('family/members|visibility=family')),
      );
      family.setMapVisible(false);
      expect(family.members, isEmpty);
      expect(family.locations, isEmpty);
      family.dispose();
      await settleStreams();
      await database.close();
    },
  );

  test('family map uses the constrained query and drops cached peers if its audience changes', () async {
    final database = VisibilityDatabase();
    final family = FamilyController(auth: VisibilityAuth(), database: database)
      ..ownerUid = 'owner-uid'
      ..ownerMemberId = 'owner'
      ..self = const Member('alice', 'Alice', 'alice-uid');
    family.setMapVisible(true);
    await settleStreams();
    expect(database.reads, ['family/members|visibility=family']);
    database.emit('family/members|visibility=family', {
      'owner': {'name': 'Adi', 'active': true},
      'bob': {'name': 'Bob', 'active': true},
    });
    await settleStreams();
    database.emit('family/states/bob/location', {
      'latitude': 3,
      'longitude': 4,
      'measuredAt': 100,
      'publishedAt': 100,
    });
    await settleStreams();
    expect(family.locations.keys, ['bob']);
    family.self = const Member('alice', 'Alice', 'alice-uid', ownerOnly: true);
    family.setMapVisible(true);
    await settleStreams();
    expect(family.members, isEmpty);
    expect(family.locations, isEmpty);
    expect(
      database.streams['family/members|visibility=family']!.hasListener,
      false,
    );
    expect(database.streams['family/states/bob/location']!.hasListener, false);
    database.emit('family/members/owner', {'name': 'Adi', 'active': true});
    database.emit('family/members/alice', {
      'name': 'Alice',
      'active': true,
      'visibility': 'ownerOnly',
    });
    await settleStreams();
    expect(family.members.map((member) => member.id).toSet(), {
      'owner',
      'alice',
    });
    family.dispose();
    await settleStreams();
    await database.close();
  });
}
