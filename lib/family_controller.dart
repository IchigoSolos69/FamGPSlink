import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'location_bridge.dart';
import 'models.dart';

class FamilyController extends ChangeNotifier {
  FamilyController({
    FirebaseAuth? auth,
    FirebaseDatabase? database,
    LocationBridge? bridge,
  }) : auth = auth ?? FirebaseAuth.instance,
       database = database ?? FirebaseDatabase.instance,
       bridge = bridge ?? LocationBridge();

  final FirebaseAuth auth;
  final FirebaseDatabase database;
  final LocationBridge bridge;
  final _storage = const FlutterSecureStorage();
  final _sessionSubscriptions = <StreamSubscription<dynamic>>[];
  final _mapSubscriptions = <StreamSubscription<dynamic>>[];
  StreamSubscription<User?>? _authSubscription;
  String installationId = '';
  String? ownerUid;
  String? ownerMemberId;
  Member? self;
  PairingRequest? request;
  TrackingControl control = const TrackingControl();
  List<Member> members = [];
  final locations = <String, SharedLocation>{};
  bool loading = true;
  bool connected = false;
  String? error;
  bool _mapVisible = false;
  int _generation = 0;
  int _bindingGeneration = 0;
  bool _disposed = false;

  bool get isOwner => auth.currentUser?.uid == ownerUid && ownerUid != null;
  bool get isPrivateConnection => self?.ownerOnly == true;
  DatabaseReference get _family => database.ref('family');
  DatabaseReference get _state => _family.child('states/${self!.id}');

  Future<void> initialize() async {
    // Native Firebase defaults to disk persistence disabled. Do not reconfigure
    // it here: iOS may already have resumed tracking before Dart starts.
    installationId =
        await _storage.read(key: 'installationId') ?? randomCode(32);
    await _storage.write(key: 'installationId', value: installationId);
    _authSubscription = auth.authStateChanges().listen((user) {
      unawaited(_loadSession(user));
    });
    if (auth.currentUser == null) await auth.signInAnonymously();
  }

  void _failure(Object exception) {
    if (_disposed) return;
    final revoked =
        exception is FirebaseException && exception.code == 'permission-denied';
    if (revoked) {
      self = null;
      members = [];
      locations.clear();
      control = const TrackingControl();
      unawaited(_detachMap());
      unawaited(bridge.stop());
    }
    error = revoked
        ? 'Access has changed. Your device may need approval again.'
        : exception is PlatformException
        ? exception.message ?? 'Check location permissions and reopen the app.'
        : 'The service is unavailable. Check your connection and try again.';
    notifyListeners();
  }

  Future<void> _loadSession(User? user) async {
    final generation = ++_generation;
    _bindingGeneration++;
    loading = true;
    self = null;
    request = null;
    control = const TrackingControl();
    members = [];
    locations.clear();
    connected = false;
    final previousSubscriptions = List<StreamSubscription<dynamic>>.of(
      _sessionSubscriptions,
    );
    _sessionSubscriptions.clear();
    _selfSubscription = null;
    _controlSubscription = null;
    for (final subscription in previousSubscriptions) {
      await subscription.cancel();
    }
    await _detachMap();
    if (user == null) await bridge.stop();
    if (generation != _generation || _disposed) return;
    if (user == null) loading = false;
    notifyListeners();
    if (user == null) return;
    try {
      final config = objectMap((await database.ref('config').get()).value);
      if (generation != _generation) return;
      ownerUid = config['ownerUid'] as String?;
      ownerMemberId = config['ownerMemberId'] as String?;
      if (ownerUid == null || ownerMemberId == null) {
        throw StateError('Owner has not been configured');
      }
      _sessionSubscriptions.add(
        database.ref('.info/connected').onValue.listen((event) {
          connected = event.snapshot.value == true;
          notifyListeners();
        }),
      );
      _sessionSubscriptions.add(
        database.ref('pairingRequests/${user.uid}').onValue.listen((event) {
          request = event.snapshot.exists
              ? PairingRequest(user.uid, event.snapshot.value)
              : null;
          notifyListeners();
        }, onError: _failure),
      );
      _sessionSubscriptions.add(
        _family.child('bindings/${user.uid}').onValue.listen((event) {
          unawaited(
            _bindingChanged(event.snapshot.value as String?, generation),
          );
        }, onError: _failure),
      );
      loading = false;
      error = null;
      notifyListeners();
    } catch (exception) {
      if (generation != _generation) return;
      loading = false;
      error = 'Family setup or connection is unavailable. Ask the owner to check Firebase setup.';
      notifyListeners();
    }
  }

  StreamSubscription<DatabaseEvent>? _selfSubscription;
  StreamSubscription<DatabaseEvent>? _controlSubscription;
  Future<void> _bindingChanged(String? id, int generation) async {
    if (generation != _generation) return;
    final bindingGeneration = ++_bindingGeneration;
    await _selfSubscription?.cancel();
    await _controlSubscription?.cancel();
    await _detachMap();
    if (generation != _generation ||
        bindingGeneration != _bindingGeneration ||
        _disposed) {
      return;
    }
    self = null;
    if (id == null) {
      members = [];
      locations.clear();
      control = const TrackingControl();
      await bridge.stop();
      notifyListeners();
      return;
    }
    _selfSubscription = _family.child('members/$id').onValue.listen((event) {
      if (generation != _generation ||
          bindingGeneration != _bindingGeneration) {
        return;
      }
      final data = objectMap(event.snapshot.value);
      if (data['active'] != true || data['authUid'] != auth.currentUser?.uid) {
        self = null;
        unawaited(bridge.stop());
      } else {
        self = Member.fromMap(id, data);
      }
      _syncMap();
      notifyListeners();
    }, onError: _failure);
    _controlSubscription = _stateFor(id)
        .child('control')
        .onValue
        .listen((event) {
          if (generation != _generation ||
              bindingGeneration != _bindingGeneration) {
            return;
          }
          control = TrackingControl.fromMap(event.snapshot.value);
          if (control.sharing && !control.override) {
            unawaited(bridge.start(id).catchError(_failure));
          } else {
            unawaited(bridge.stop());
          }
          notifyListeners();
        }, onError: _failure);
    _sessionSubscriptions.addAll([_selfSubscription!, _controlSubscription!]);
  }

  DatabaseReference _stateFor(String id) => _family.child('states/$id');

  Future<void> createRequest(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 40) {
      throw StateError('Use a name of 1–40 characters.');
    }
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }
    await database.ref('pairingRequests/${auth.currentUser!.uid}').set({
      'name': trimmed,
      'installationId': installationId,
      'code': request?.code ?? randomCode(8),
      'createdAt': ServerValue.timestamp,
    });
  }

  Future<void> signInOwner(String email, String password) async {
    final credential = await auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    // A fresh phone may not have loaded config before owner sign-in.
    final configuredOwner = objectMap(
      (await database.ref('config').get()).value,
    )['ownerUid'];
    if (configuredOwner == null || credential.user?.uid != configuredOwner) {
      await auth.signOut();
      await auth.signInAnonymously();
      throw StateError('This account is not the configured family owner.');
    }
  }

  Future<void> resetOwnerPassword(String email) =>
      auth.sendPasswordResetEmail(email: email.trim());
  Future<void> retry() async {
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    } else {
      await _loadSession(auth.currentUser);
    }
  }

  void setMapVisible(bool visible) {
    _mapVisible = visible;
    _syncMap();
  }

  void _syncMap() {
    if (!_mapVisible || self == null) {
      unawaited(_detachMap());
      return;
    }
    final scope = '${self!.id}:$isOwner:$isPrivateConnection';
    if (_mapScope == scope) return;
    unawaited(_attachMap(scope));
  }

  String? _mapScope;
  int _mapGeneration = 0;
  Future<void> _attachMap(String scope) async {
    final generation = ++_mapGeneration;
    _mapScope = scope;
    await _cancelMapSubscriptions();
    if (generation != _mapGeneration || _disposed || self == null) return;
    members = [];
    locations.clear();
    notifyListeners();
    if (isPrivateConnection) {
      final profiles = <String, Member>{};
      for (final id in {self!.id, ownerMemberId!}) {
        _mapSubscriptions.add(
          _family.child('members/$id').onValue.listen((event) {
            if (generation != _mapGeneration || _disposed) return;
            if (objectMap(event.snapshot.value)['active'] == true) {
              profiles[id] = Member.fromMap(id, event.snapshot.value);
            } else {
              profiles.remove(id);
            }
            _setMapMembers(profiles.values.toList(), generation);
          }, onError: (Object error) => _mapFailure(error, generation)),
        );
      }
    } else {
      final Query query = isOwner
          ? _family.child('members')
          : _family
                .child('members')
                .orderByChild('visibility')
                .equalTo('family');
      _mapSubscriptions.add(
        query.onValue.listen((event) {
          if (generation != _mapGeneration || _disposed) return;
          _setMapMembers(
            objectMap(event.snapshot.value).entries
                .where((entry) => objectMap(entry.value)['active'] == true)
                .map((entry) => Member.fromMap(entry.key, entry.value))
                .toList(),
            generation,
          );
        }, onError: (Object error) => _mapFailure(error, generation)),
      );
    }
  }

  void _setMapMembers(List<Member> profiles, int generation) {
    members = profiles..sort((a, b) => a.name.compareTo(b.name));
    _refreshLocationSubscriptions(generation);
    notifyListeners();
  }

  void _mapFailure(Object exception, int generation) {
    if (generation != _mapGeneration || _disposed) return;
    error = 'Map access is unavailable. Try again to refresh your connection.';
    unawaited(_detachMap());
    notifyListeners();
  }

  final _locationSubscriptions = <String, StreamSubscription<DatabaseEvent>>{};
  void _refreshLocationSubscriptions(int generation) {
    final ids = members.map((member) => member.id).toSet();
    for (final id in _locationSubscriptions.keys.toList()) {
      if (!ids.contains(id)) {
        unawaited(_locationSubscriptions.remove(id)!.cancel());
        locations.remove(id);
      }
    }
    for (final member in members) {
      _locationSubscriptions.putIfAbsent(
        member.id,
        () => _stateFor(member.id)
            .child('location')
            .onValue
            .listen(
              (event) {
                if (generation != _mapGeneration ||
                    _disposed ||
                    !members.any((profile) => profile.id == member.id)) {
                  return;
                }
                if (event.snapshot.exists) {
                  try {
                    locations[member.id] = SharedLocation.fromMap(
                      event.snapshot.value,
                    );
                  } catch (_) {
                    locations.remove(member.id);
                  }
                } else {
                  locations.remove(member.id);
                }
                notifyListeners();
              },
              onError: (Object exception) {
                if (generation != _mapGeneration || _disposed) return;
                // A peer being removed must not stop this phone's own sharing.
                locations.remove(member.id);
                notifyListeners();
              },
            ),
      );
    }
  }

  Future<void> _detachMap() async {
    _mapGeneration++;
    _mapScope = null;
    final hadData = members.isNotEmpty || locations.isNotEmpty;
    members = [];
    locations.clear();
    if (hadData && !_disposed) notifyListeners();
    await _cancelMapSubscriptions();
  }

  Future<void> _cancelMapSubscriptions() async {
    final subscriptions = [
      ..._mapSubscriptions,
      ..._locationSubscriptions.values,
    ];
    _mapSubscriptions.clear();
    _locationSubscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }

  Future<void> _requireConnection() async {
    if (!connected) {
      throw StateError(
        'Reconnect before changing sharing or location settings.',
      );
    }
  }

  Future<void> setSharing(bool enabled) async {
    await _requireConnection();
    final reference = _state;
    await _requireTrackingState(reference);
    final result = await reference.runTransaction((value) {
      // iOS/Android may have no complete cached state even after get(). Let
      // Firebase fetch the current server state and rerun this transaction.
      if (value == null) return Transaction.success(null);
      final state = objectMap(value);
      if (state.isEmpty) return Transaction.abort();
      final control = objectMap(state['control']);
      // A repeated request must not republish an old GPS fix or invalidate
      // queued uploads by changing the control revision unnecessarily.
      if (control['sharingEnabled'] == enabled) return Transaction.abort();
      control['sharingEnabled'] = enabled;
      control['revision'] = (control['revision'] as num).toInt() + 1;
      if (!enabled) state.remove('location');
      if (enabled && control['overrideActive'] == true) {
        final manual = objectMap(control['manual']);
        if (manual.isEmpty) return Transaction.abort();
        state['location'] = {
          'latitude': manual['latitude'],
          'longitude': manual['longitude'],
          'measuredAt': manual['setAt'],
          'publishedAt': ServerValue.timestamp,
        };
      }
      state['control'] = control;
      return Transaction.success(state);
    }, applyLocally: false);
    final saved = objectMap(result.snapshot.value);
    final savedControl = objectMap(saved['control']);
    if (savedControl['sharingEnabled'] != enabled) {
      throw StateError('Sharing could not be updated. Try again.');
    }
    if (enabled && savedControl['overrideActive'] == false) {
      await bridge.start(self!.id);
    } else {
      await bridge.stop();
    }
  }

  Future<void> _requireTrackingState(DatabaseReference reference) async {
    final snapshot = await reference.get();
    if (!objectMap(snapshot.value).containsKey('control')) {
      throw StateError(
        'Your device has no tracking settings. Retry the connection or ask the owner to approve it again.',
      );
    }
  }

  Future<void> setManual(double latitude, double longitude) async {
    if (!isOwner) throw StateError('Owner access required.');
    if (latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw StateError('Choose a valid point on the map.');
    }
    await _requireConnection();
    final reference = _state;
    await _requireTrackingState(reference);
    final result = await reference.runTransaction((value) {
      if (value == null) return Transaction.success(null);
      final state = objectMap(value);
      if (state.isEmpty) return Transaction.abort();
      final control = objectMap(state['control']);
      control['overrideActive'] = true;
      control['manual'] = {
        'latitude': latitude,
        'longitude': longitude,
        'setAt': ServerValue.timestamp,
      };
      control['sharingEnabled'] = true;
      control['revision'] = (control['revision'] as num).toInt() + 1;
      state['control'] = control;
      state['location'] = {
        'latitude': latitude,
        'longitude': longitude,
        'measuredAt': ServerValue.timestamp,
        'publishedAt': ServerValue.timestamp,
      };
      return Transaction.success(state);
    }, applyLocally: false);
    if (!result.committed ||
        objectMap(
              objectMap(result.snapshot.value)['control'],
            )['overrideActive'] !=
            true) {
      throw StateError('Location was not saved. Try again.');
    }
    await bridge.stop();
  }

  Future<void> clearManual() async {
    if (!isOwner) throw StateError('Owner access required.');
    await _requireConnection();
    final reference = _state;
    await _requireTrackingState(reference);
    final expectedRevision = control.revision;
    final fix = await bridge.freshFix();
    await _requireConnection();
    final result = await reference.runTransaction((value) {
      if (value == null) return Transaction.success(null);
      final state = objectMap(value);
      final control = objectMap(state['control']);
      if (control['revision'] != expectedRevision ||
          control['overrideActive'] != true) {
        return Transaction.abort();
      }
      if (DateTime.now().millisecondsSinceEpoch - (fix['measuredAt'] as num) >
          60000) {
        return Transaction.abort();
      }
      control['overrideActive'] = false;
      control.remove('manual');
      control['sharingEnabled'] = true;
      control['revision'] = expectedRevision + 1;
      state['control'] = control;
      state['location'] = {...fix, 'publishedAt': ServerValue.timestamp};
      return Transaction.success(state);
    }, applyLocally: false);
    if (!result.committed ||
        objectMap(
              objectMap(result.snapshot.value)['control'],
            )['overrideActive'] !=
            false) {
      throw StateError(
        'A fresh GPS fix could not be saved. Your manual pin is still active.',
      );
    }
    await bridge.start(self!.id);
  }

  Stream<List<PairingRequest>> pairingRequests() => database
      .ref('pairingRequests')
      .onValue
      .map(
        (event) =>
            objectMap(event.snapshot.value).entries
                .map((entry) => PairingRequest(entry.key, entry.value))
                .toList(),
      );

  Stream<List<Member>> familyMembers() => _family
      .child('members')
      .onValue
      .map(
        (event) =>
            objectMap(event.snapshot.value).entries
                .map((entry) => Member.fromMap(entry.key, entry.value))
                .toList(),
      );

  Future<void> approve(
    PairingRequest pairing, {
    String? recoverMemberId,
    bool ownerOnly = false,
  }) async {
    await _requireConnection();
    if (!isOwner) throw StateError('Owner access required.');
    final fresh = PairingRequest(
      pairing.uid,
      (await database.ref('pairingRequests/${pairing.uid}').get()).value,
    );
    if (fresh.code != pairing.code ||
        fresh.installationId != pairing.installationId) {
      throw StateError('Pairing request changed. Ask for the current code.');
    }
    final memberId = recoverMemberId ?? randomCode(20);
    if (recoverMemberId == null &&
        objectMap((await _family.child('members').get()).value).length >= 10) {
      throw StateError(
        'The pilot supports ten profiles. Remove a profile or recover an existing one.',
      );
    }
    if (memberId == ownerMemberId) {
      throw StateError('Recover the owner using email sign-in.');
    }
    final previous = objectMap(
      (await _family.child('members/$memberId').get()).value,
    );
    if (recoverMemberId != null && previous.isEmpty) {
      throw StateError('Profile no longer exists.');
    }
    final updates = <String, Object?>{
      'family/members/$memberId': {
        'name': previous['name'] ?? pairing.name,
        'authUid': pairing.uid,
        'installationId': pairing.installationId,
        'active': true,
        'visibility': recoverMemberId != null
            ? previous['visibility'] ?? 'family'
            : ownerOnly
            ? 'ownerOnly'
            : 'family',
      },
      'family/bindings/${pairing.uid}': memberId,
      'family/states/$memberId': {
        'control': {
          'sharingEnabled': false,
          'overrideActive': false,
          'revision': DateTime.now().millisecondsSinceEpoch,
        },
      },
      'pairingRequests/${pairing.uid}': null,
    };
    if (previous['authUid'] != null) {
      updates['family/bindings/${previous['authUid']}'] = null;
    }
    await database.ref().update(updates);
  }

  Future<void> reject(PairingRequest pairing) =>
      database.ref('pairingRequests/${pairing.uid}').remove();

  Future<void> removeMember(Member member) async {
    await _requireConnection();
    if (!isOwner || member.id == ownerMemberId) {
      throw StateError('Cannot remove the owner.');
    }
    await database.ref().update({
      'family/bindings/${member.authUid}': null,
      'family/members/${member.id}': null,
      'family/states/${member.id}': null,
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    unawaited(_authSubscription?.cancel());
    for (final subscription in _sessionSubscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_detachMap());
    super.dispose();
  }
}
