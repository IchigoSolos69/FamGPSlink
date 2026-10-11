import { writeFileSync } from 'node:fs';

// Keep expressions centralized so every authorization check uses the same
// binding AND active-profile identity check. Deploy the generated JSON file.
const owner = "auth !== null && auth.uid === root.child('config/ownerUid').val()";
const binding = "root.child('family/bindings').child(auth.uid).val()";
const approved = `auth !== null && root.child('family/bindings').child(auth.uid).isString() && root.child('family/members').child(${binding}).child('active').val() === true && root.child('family/members').child(${binding}).child('authUid').val() === auth.uid`;
const own = `(${approved}) && ${binding} === $member`;
const selfOrOwner = `(${owner}) || (${own})`;
const familyViewer = `(${approved}) && root.child('family/members').child(${binding}).child('visibility').val() === 'family'`;
// Query constraints prevent a collection read from exposing hidden profiles.
// Direct profile/location reads use the same symmetric audience check.
const visible = `(${approved}) && root.child('family/members').child($member).child('active').val() === true && ((${owner}) || ${binding} === $member || $member === root.child('config/ownerMemberId').val() || ((${familyViewer}) && root.child('family/members').child($member).child('visibility').val() === 'family'))`;
const rules = {
  rules: {
    '.read': false, '.write': false,
    config: { '.read': 'auth !== null', '.write': false },
    pairingRequests: {
      '.read': owner,
      '$uid': {
        '.read': `auth !== null && (auth.uid === $uid || (${owner}))`,
        '.write': `(${owner}) || (auth !== null && auth.uid === $uid && !root.child('family/bindings').child(auth.uid).exists())`,
        '.validate': "newData.hasChildren(['name', 'installationId', 'code', 'createdAt'])",
        name: { '.validate': 'newData.isString() && newData.val().length > 0 && newData.val().length <= 40' },
        installationId: { '.validate': 'newData.isString() && newData.val().length === 32' },
        code: { '.validate': "newData.isString() && newData.val().matches(/^[A-HJ-NP-Z2-9]{8}$/)" },
        createdAt: { '.validate': 'newData.isNumber() && newData.val() === now' },
        '$other': { '.validate': false },
      },
    },
    family: {
      bindings: {
        '$uid': {
          '.read': `auth !== null && (auth.uid === $uid || (${owner}))`,
          '.write': `(${owner}) && ($uid !== root.child('config/ownerUid').val() || newData.val() === root.child('config/ownerMemberId').val())`,
          '.validate': "newData.isString() && newData.parent().parent().child('members').child(newData.val()).child('authUid').val() === $uid",
        },
      },
      members: {
        '.read': `(${owner}) || ((${familyViewer}) && query.orderByChild === 'visibility' && query.equalTo === 'family')`,
        '.indexOn': ['visibility'],
        '$member': {
          '.read': visible,
          '.write': `(${owner}) && ($member !== root.child('config/ownerMemberId').val() || (newData.exists() && newData.child('authUid').val() === root.child('config/ownerUid').val()))`,
          '.validate': "newData.hasChildren(['name', 'authUid', 'installationId', 'active', 'visibility']) && newData.parent().parent().child('bindings').child(newData.child('authUid').val()).val() === $member",
          name: { '.validate': 'newData.isString() && newData.val().length > 0 && newData.val().length <= 40' },
          authUid: { '.validate': 'newData.isString() && newData.val().length > 0' },
          installationId: { '.validate': 'newData.isString() && newData.val().length >= 5 && newData.val().length <= 32' },
          active: { '.validate': 'newData.isBoolean()' },
          visibility: { '.validate': "(newData.val() === 'family' || newData.val() === 'ownerOnly') && (!data.exists() || newData.val() === data.val()) && ($member !== root.child('config/ownerMemberId').val() || newData.val() === 'family')" },
          '$other': { '.validate': false },
        },
      },
      states: {
        '$member': {
          '.read': own,
          '.write': `(${owner}) || ((${own}) && newData.exists())`,
          '.validate': `newData.hasChild('control') && (newData.child('control/sharingEnabled').val() === true || !newData.hasChild('location')) && ((${owner}) || (newData.child('control/overrideActive').val() === false && (newData.child('control/revision').val() === data.child('control/revision').val() || newData.child('control/revision').val() === data.child('control/revision').val() + 1))) && (!data.exists() || newData.child('control/sharingEnabled').val() === data.child('control/sharingEnabled').val() || newData.child('control/revision').val() > data.child('control/revision').val())`,
          control: {
            '.read': selfOrOwner,
            '.validate': "newData.hasChildren(['sharingEnabled', 'overrideActive', 'revision']) && (newData.child('overrideActive').val() === newData.hasChild('manual'))",
            sharingEnabled: { '.validate': 'newData.isBoolean()' },
            overrideActive: { '.validate': "newData.isBoolean() && (newData.val() === false || $member === root.child('config/ownerMemberId').val())" },
            revision: { '.validate': 'newData.isNumber() && newData.val() >= 0 && (!data.exists() || newData.val() >= data.val())' },
            manual: {
              '.validate': "newData.hasChildren(['latitude', 'longitude', 'setAt']) && $member === root.child('config/ownerMemberId').val()",
              latitude: { '.validate': 'newData.isNumber() && newData.val() >= -90 && newData.val() <= 90' },
              longitude: { '.validate': 'newData.isNumber() && newData.val() >= -180 && newData.val() <= 180' },
              setAt: { '.validate': 'newData.isNumber() && newData.val() > 0 && newData.val() <= now + 60000' },
              '$other': { '.validate': false },
            },
            '$other': { '.validate': false },
          },
          location: {
            '.read': visible,
            '.validate': "newData.hasChildren(['latitude', 'longitude', 'measuredAt', 'publishedAt']) && (newData.parent().child('control/overrideActive').val() === false || !newData.hasChild('accuracy')) && (!data.exists() || newData.child('measuredAt').val() >= data.child('measuredAt').val() || (newData.parent().child('control/revision').val() > data.parent().child('control/revision').val() && newData.child('measuredAt').val() >= now - 60000))",
            latitude: { '.validate': 'newData.isNumber() && newData.val() >= -90 && newData.val() <= 90' },
            longitude: { '.validate': 'newData.isNumber() && newData.val() >= -180 && newData.val() <= 180' },
            measuredAt: { '.validate': 'newData.isNumber() && newData.val() > 0 && newData.val() <= now + 60000' },
            publishedAt: { '.validate': 'newData.isNumber() && newData.val() === now' },
            accuracy: { '.validate': 'newData.isNumber() && newData.val() >= 0' },
            '$other': { '.validate': false },
          },
          '$other': { '.validate': false },
        },
      },
    },
  },
};
writeFileSync(new URL('../database.rules.json', import.meta.url), JSON.stringify(rules, null, 2) + '\n');
