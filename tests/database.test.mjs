import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { ref, get, set, update, runTransaction, serverTimestamp, query, orderByChild, equalTo } from 'firebase/database';

let environment;
const control = (revision = 1, overrideActive = false, sharingEnabled = true) => ({ revision, overrideActive, sharingEnabled });
const fix = (extra = {}) => ({ latitude: 19.076, longitude: 72.8777, accuracy: 12,
  measuredAt: Date.now(), publishedAt: serverTimestamp(), ...extra });
const db = (uid) => environment.authenticatedContext(uid).database();
const member = (name, uid, visibility = 'family') => ({ name, authUid: uid, installationId: 'A'.repeat(32), active: true, visibility });
const familyProfiles = (uid) => query(ref(db(uid), 'family/members'), orderByChild('visibility'), equalTo('family'));
const request = { name: 'Charlie', installationId: 'B'.repeat(32), code: 'ABCD2345', createdAt: serverTimestamp() };
const manualState = (location, revision = 2) => ({
  control: { ...control(revision, true), manual: { latitude: location.latitude, longitude: location.longitude, setAt: location.measuredAt } },
  location,
});

before(async () => {
  environment = await initializeTestEnvironment({ projectId: 'demo-famgpslink',
    database: { host: '127.0.0.1', port: 9000, rules: readFileSync(new URL('../database.rules.json', import.meta.url), 'utf8') } });
});
beforeEach(async () => {
  await environment.clearDatabase();
  await environment.withSecurityRulesDisabled(async (context) => set(ref(context.database()), {
    config: { ownerUid: 'owner-uid', ownerMemberId: 'owner' },
    family: {
      bindings: { 'owner-uid': 'owner', 'alice-uid': 'alice', 'bob-uid': 'bob', 'partner-uid': 'partner' },
      members: { owner: member('Owner', 'owner-uid'), alice: member('Alice', 'alice-uid'), bob: member('Bob', 'bob-uid'), partner: member('Partner', 'partner-uid', 'ownerOnly') },
      states: { owner: { control: control(), location: fix({ measuredAt: Date.now() - 10000 }) },
        alice: { control: control(), location: fix({ measuredAt: Date.now() - 10000 }) },
        bob: { control: control(), location: fix({ measuredAt: Date.now() - 10000 }) },
        partner: { control: control(), location: fix({ measuredAt: Date.now() - 10000 }) } },
    },
  }));
});
after(async () => environment?.cleanup());

test('approved family members read locations but cannot read private owner state', async () => {
  await assertSucceeds(get(ref(db('alice-uid'), 'family/states/owner/location')));
  await assertFails(get(ref(db('alice-uid'), 'family/states/owner/control')));
  await assertFails(get(ref(db('alice-uid'), 'family/states/owner')));
  await assertFails(get(ref(db('alice-uid'), 'family/states')));
  await assertSucceeds(get(ref(db('alice-uid'), 'family/states/alice')));
});
test('unauthenticated and unapproved installations cannot read family data', async () => {
  await assertFails(get(ref(environment.unauthenticatedContext().database(), 'family/members')));
  await assertFails(get(ref(db('stranger'), 'family/states/alice/location')));
  await assertFails(get(ref(db('stranger'), 'family/members')));
});
test('pending installation creates and reads only its own pairing request', async () => {
  await assertSucceeds(set(ref(db('charlie-uid'), 'pairingRequests/charlie-uid'), request));
  await assertSucceeds(get(ref(db('charlie-uid'), 'pairingRequests/charlie-uid')));
  await assertFails(get(ref(db('charlie-uid'), 'pairingRequests')));
  await assertFails(set(ref(db('charlie-uid'), 'pairingRequests/someone-else'), request));
  await assertFails(get(ref(db('charlie-uid'), 'family/states/alice/location')));
});
test('members cannot approve themselves, elevate privileges, or replace the owner', async () => {
  await assertFails(set(ref(db('charlie-uid'), 'family/bindings/charlie-uid'), 'alice'));
  await assertFails(update(ref(db('alice-uid'), 'family/members/alice'), { authUid: 'charlie-uid' }));
  await assertFails(set(ref(db('alice-uid'), 'config/ownerUid'), 'alice-uid'));
  await assertFails(set(ref(db('owner-uid'), 'config/ownerUid'), 'alice-uid'));
});
test('a member publishes their own GPS fix and cannot impersonate another', async () => {
  await assertSucceeds(set(ref(db('alice-uid'), 'family/states/alice'), { control: control(), location: fix() }));
  await assertFails(set(ref(db('alice-uid'), 'family/states/bob'), { control: control(), location: fix() }));
});
test('coordinate bounds, timestamps, accuracy and unexpected fields are validated', async () => {
  for (const invalid of [{ latitude: 91 }, { longitude: -181 }, { accuracy: -1 },
    { measuredAt: Date.now() + 120000 }, { publishedAt: 1 }, { rawGps: { latitude: 1 } }]) {
    await assertFails(set(ref(db('alice-uid'), 'family/states/alice'), { control: control(), location: fix(invalid) }));
  }
});
test('an older fix cannot replace a newer one, including after reconnect', async () => {
  await assertSucceeds(set(ref(db('alice-uid'), 'family/states/alice'), { control: control(), location: fix() }));
  await assertFails(set(ref(db('alice-uid'), 'family/states/alice'), { control: control(), location: fix({ measuredAt: Date.now() - 120000 }) }));
});
test('non-owner cannot activate an override, including on their own profile', async () => {
  const manual = fix(); delete manual.accuracy;
  await assertFails(set(ref(db('alice-uid'), 'family/states/alice'), { control: control(2, true), location: manual }));
  await assertFails(set(ref(db('alice-uid'), 'family/states/owner'), { control: control(2, true), location: manual }));
  await assertFails(set(ref(db('owner-uid'), 'family/states/alice'), { control: control(2, true), location: manual }));
});
test('owner manual pin has no fake accuracy and only the location is family-readable', async () => {
  const manual = { latitude: 28.6, longitude: 77.2, measuredAt: serverTimestamp(), publishedAt: serverTimestamp() };
  await assertSucceeds(set(ref(db('owner-uid'), 'family/states/owner'), manualState(manual)));
  const shared = (await get(ref(db('alice-uid'), 'family/states/owner/location'))).val();
  assert.equal(shared.latitude, 28.6);
  assert.equal(shared.accuracy, undefined);
  assert.equal(shared.overrideActive, undefined);
  await assertFails(set(ref(db('owner-uid'), 'family/states/owner/location'), fix()));
});
test('transaction upload aborts if an override or newer control revision wins the race', async () => {
  const queuedRevision = 1;
  await set(ref(db('owner-uid'), 'family/states/owner'), manualState(
    { latitude: 1, longitude: 2, measuredAt: serverTimestamp(), publishedAt: serverTimestamp() }));
  const result = await runTransaction(ref(db('owner-uid'), 'family/states/owner'), (state) => {
    if (state == null) return state;
    if (state.control.overrideActive || !state.control.sharingEnabled || state.control.revision !== queuedRevision) return;
    return { ...state, location: fix() };
  }, { applyLocally: false });
  assert.equal(result.committed, false);
  assert.equal((await get(ref(db('owner-uid'), 'family/states/owner/location'))).val().latitude, 1);
});
test('manual pin survives sharing pause and resume without resetting its selection time', async () => {
  const reference = ref(db('owner-uid'), 'family/states/owner');
  await set(reference, manualState({ latitude: 4, longitude: 5, measuredAt: serverTimestamp(), publishedAt: serverTimestamp() }));
  const original = (await get(reference)).val();
  await assertSucceeds(set(reference, { control: { ...original.control, revision: 3, sharingEnabled: false } }));
  await assertFails(get(ref(db('alice-uid'), 'family/states/owner/control/manual')));
  assert.equal((await get(ref(db('alice-uid'), 'family/states/owner/location'))).exists(), false);
  await assertSucceeds(set(reference, { control: { ...original.control, revision: 4 },
    location: { ...original.location, publishedAt: serverTimestamp() } }));
  const resumed = (await get(ref(db('alice-uid'), 'family/states/owner/location'))).val();
  assert.equal(resumed.measuredAt, original.location.measuredAt);
  assert.equal(resumed.accuracy, undefined);
});
test('clearing an override publishes a fresh GPS fix and rejects a stale restore', async () => {
  const reference = ref(db('owner-uid'), 'family/states/owner');
  await set(reference, manualState({ latitude: 4, longitude: 5, measuredAt: serverTimestamp(), publishedAt: serverTimestamp() }));
  await assertFails(set(reference, { control: control(3), location: fix({ measuredAt: Date.now() - 120000 }) }));
  await assertSucceeds(set(reference, { control: control(3), location: fix() }));
  assert.equal((await get(reference)).val().control.overrideActive, false);
});
test('pausing removes the pin and publishing while paused is rejected', async () => {
  await assertSucceeds(set(ref(db('alice-uid'), 'family/states/alice'), { control: control(2, false, false) }));
  assert.equal((await get(ref(db('bob-uid'), 'family/states/alice/location'))).exists(), false);
  await assertFails(set(ref(db('alice-uid'), 'family/states/alice'), { control: control(2, false, false), location: fix() }));
  await assertFails(set(ref(db('alice-uid'), 'family/states/alice'), { control: control(1), location: fix() }));
});
test('owner atomically approves a new phone and creates a stable profile', async () => {
  await set(ref(db('charlie-uid'), 'pairingRequests/charlie-uid'), request);
  await assertSucceeds(update(ref(db('owner-uid')), {
    'family/bindings/charlie-uid': 'charlie',
    'family/members/charlie': member('Charlie', 'charlie-uid'),
    'family/states/charlie': { control: control(0, false, false) },
    'pairingRequests/charlie-uid': null,
  }));
  await assertSucceeds(get(ref(db('charlie-uid'), 'family/states/alice/location')));
});
test('recovery preserves the profile and revokes the old device immediately', async () => {
  await assertSucceeds(update(ref(db('owner-uid')), {
    'family/bindings/alice-uid': null, 'family/bindings/new-alice-uid': 'alice',
    'family/members/alice': member('Alice', 'new-alice-uid'),
    'family/states/alice': { control: control(2, false, false) },
  }));
  await assertFails(get(ref(db('alice-uid'), 'family/states/bob/location')));
  await assertFails(set(ref(db('alice-uid'), 'family/states/alice'), { control: control(), location: fix() }));
  await assertSucceeds(get(familyProfiles('new-alice-uid')));
  assert.equal((await get(ref(db('new-alice-uid'), 'family/members/alice'))).val().name, 'Alice');
});
test('owner removes access and coordinates together; owner identity cannot be removed', async () => {
  await assertSucceeds(update(ref(db('owner-uid')), {
    'family/bindings/bob-uid': null, 'family/members/bob': null, 'family/states/bob': null,
  }));
  await assertFails(get(ref(db('bob-uid'), 'family/members')));
  await assertFails(set(ref(db('owner-uid'), 'family/bindings/owner-uid'), null));
  await assertFails(set(ref(db('owner-uid'), 'family/members/owner'), null));
});

test('family directory query omits private profiles and forbids unfiltered or widened reads', async () => {
  const profiles = (await assertSucceeds(get(familyProfiles('alice-uid')))).val();
  assert.deepEqual(Object.keys(profiles).sort(), ['alice', 'bob', 'owner']);
  await assertFails(get(ref(db('alice-uid'), 'family/members')));
  await assertFails(get(query(ref(db('alice-uid'), 'family/members'), orderByChild('visibility'))));
  await assertFails(get(query(ref(db('alice-uid'), 'family/members'), orderByChild('visibility'), equalTo('ownerOnly'))));
});

test('family members cannot retrieve a private profile or location by guessing its path', async () => {
  for (const path of ['family/members/partner', 'family/members/partner/name',
    'family/members/partner/authUid', 'family/states/partner/location',
    'family/states/partner/location/latitude', 'family/states/partner/control',
    'family/states/partner', 'family/bindings/partner-uid']) {
    await assertFails(get(ref(db('alice-uid'), path)));
  }
});

test('private connection reads only owner and self, including direct paths and queries', async () => {
  for (const id of ['owner', 'partner']) {
    await assertSucceeds(get(ref(db('partner-uid'), `family/members/${id}`)));
    await assertSucceeds(get(ref(db('partner-uid'), `family/states/${id}/location`)));
  }
  await assertSucceeds(get(ref(db('partner-uid'), 'family/states/partner')));
  await assertFails(get(familyProfiles('partner-uid')));
  for (const path of ['family/members', 'family/members/alice', 'family/members/bob/name',
    'family/states/alice/location', 'family/states/bob/location/latitude',
    'family/states/owner/control', 'family/states/owner', 'pairingRequests']) {
    await assertFails(get(ref(db('partner-uid'), path)));
  }
});

test('owner sees both family and private locations; private member can publish and pause only themselves', async () => {
  const profiles = (await assertSucceeds(get(ref(db('owner-uid'), 'family/members')))).val();
  assert.equal(profiles.partner.visibility, 'ownerOnly');
  await assertSucceeds(get(ref(db('owner-uid'), 'family/states/partner/location')));
  await assertSucceeds(set(ref(db('partner-uid'), 'family/states/partner'), { control: control(), location: fix() }));
  await assertFails(set(ref(db('partner-uid'), 'family/states/owner'), { control: control(), location: fix() }));
  await assertSucceeds(set(ref(db('partner-uid'), 'family/states/partner'), { control: control(2, false, false) }));
  assert.equal((await get(ref(db('owner-uid'), 'family/states/partner/location'))).exists(), false);
});

test('audiences cannot be escalated or silently broadened after approval', async () => {
  await assertFails(update(ref(db('partner-uid'), 'family/members/partner'), { visibility: 'family' }));
  await assertFails(update(ref(db('alice-uid'), 'family/members/alice'), { visibility: 'ownerOnly' }));
  await assertFails(update(ref(db('owner-uid'), 'family/members/partner'), { visibility: 'family' }));
  await assertFails(update(ref(db('owner-uid'), 'family/members/alice'), { visibility: 'ownerOnly' }));
  await assertFails(update(ref(db('owner-uid'), 'family/members/owner'), { visibility: 'ownerOnly' }));
  await assertFails(update(ref(db('owner-uid'), 'family/members/partner'), { visibility: null }));
});

test('private phone recovery retains its audience and revokes the old phone', async () => {
  await assertSucceeds(update(ref(db('owner-uid')), {
    'family/bindings/partner-uid': null, 'family/bindings/new-partner-uid': 'partner',
    'family/members/partner': member('Partner', 'new-partner-uid', 'ownerOnly'),
    'family/states/partner': { control: control(2, false, false) },
  }));
  await assertFails(get(ref(db('partner-uid'), 'family/states/owner/location')));
  await assertFails(set(ref(db('partner-uid'), 'family/states/partner'), { control: control(), location: fix() }));
  await assertSucceeds(get(ref(db('new-partner-uid'), 'family/states/owner/location')));
  await assertFails(get(familyProfiles('new-partner-uid')));
  await assertFails(get(ref(db('new-partner-uid'), 'family/states/alice/location')));
  await assertFails(get(ref(db('alice-uid'), 'family/members/partner')));
});

test('new private profile is atomically approved with sharing disabled and stays outside the family directory', async () => {
  await assertSucceeds(update(ref(db('owner-uid')), {
    'family/bindings/charlie-uid': 'charlie',
    'family/members/charlie': member('Charlie', 'charlie-uid', 'ownerOnly'),
    'family/states/charlie': { control: control(0, false, false) },
  }));
  assert.equal((await get(familyProfiles('alice-uid'))).hasChild('charlie'), false);
  await assertSucceeds(get(ref(db('charlie-uid'), 'family/states/owner/location')));
  await assertFails(get(ref(db('charlie-uid'), 'family/states/alice/location')));
  await assertFails(get(ref(db('charlie-uid'), 'family/states/partner/location')));
  await assertFails(get(ref(db('partner-uid'), 'family/members/charlie')));
  assert.equal((await get(ref(db('owner-uid'), 'family/states/charlie/location'))).exists(), false);
});
