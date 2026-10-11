import { applicationDefault, initializeApp, deleteApp } from 'firebase-admin/app';
import { getDatabase } from 'firebase-admin/database';
import { createRequire } from 'node:module';

// Upgrade profile metadata before deploying the private-connection rules.
// Default is a dry run. Does not access locations, change bindings, or approve devices.
const cliMode = process.argv.includes('--cli');
const apply = process.argv.includes('--apply');
const [projectId, databaseURL] = process.argv.slice(2).filter((arg) => !arg.startsWith('--'));
if (!projectId || !databaseURL) {
  throw new Error('Usage: node tools/migrate-visibility.mjs [--cli] [--apply] PROJECT_ID DATABASE_URL');
}
let credential = applicationDefault();
if (cliMode) {
  const require = createRequire(import.meta.url);
  const { configstore } = require('firebase-tools/lib/configstore');
  const { getAccessToken } = require('firebase-tools/lib/auth');
  const scopes = require('firebase-tools/lib/scopes');
  const refreshToken = configstore.get('tokens')?.refresh_token;
  if (!refreshToken) throw new Error('Run firebase login locally before using --cli.');
  credential = {
    async getAccessToken() {
      const token = await getAccessToken(refreshToken, [scopes.FIREBASE_PLATFORM, scopes.CLOUD_PLATFORM, scopes.USERINFO_EMAIL]);
      if (!token.access_token || !token.expires_at) throw new Error('Firebase CLI sign-in needs renewal.');
      return { access_token: token.access_token, expires_in: Math.max(1, Math.floor((token.expires_at - Date.now()) / 1000)) };
    },
  };
}
const app = initializeApp({ credential, projectId, databaseURL });
try {
  const database = getDatabase(app);
  const config = (await database.ref('config').get()).val();
  if (!config?.ownerUid || !config?.ownerMemberId) throw new Error('No trusted owner configuration found.');
  const reference = database.ref('family/members');
  const check = (profiles) => {
    if (!profiles || profiles[config.ownerMemberId]?.authUid !== config.ownerUid) {
      throw new Error('Owner profile does not match trusted configuration.');
    }
    for (const [id, profile] of Object.entries(profiles)) {
      if (profile.visibility != null && !['family', 'ownerOnly'].includes(profile.visibility)) {
        throw new Error('Unexpected profile visibility; migration aborted.');
      }
      if (id === config.ownerMemberId && profile.visibility === 'ownerOnly') {
        throw new Error('Owner profile cannot be a private connection.');
      }
    }
  };
  const profiles = (await reference.get()).val();
  check(profiles);
  const count = Object.values(profiles).filter((profile) => profile.visibility == null).length;
  console.log(`${count} existing profile(s) need the family visibility default. ${apply ? 'Applying migration.' : 'Dry run only.'}`);
  if (apply && count > 0) {
    const result = await reference.transaction((current) => {
      if (current == null) return current;
      check(current);
      const updated = structuredClone(current);
      for (const profile of Object.values(updated)) profile.visibility ??= 'family';
      return updated;
    }, undefined, false);
    if (!result.committed) throw new Error('Profile migration did not commit.');
  }
  if (apply) {
    const updated = (await reference.get()).val();
    check(updated);
    if (Object.values(updated).some((profile) => profile.visibility == null)) {
      throw new Error('A profile is still missing visibility. Retry before deploying rules.');
    }
    console.log('Profile visibility metadata verified. Locations and device bindings were not modified.');
  }
} finally {
  await deleteApp(app);
}
