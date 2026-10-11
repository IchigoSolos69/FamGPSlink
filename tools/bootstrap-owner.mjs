import { applicationDefault, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getDatabase } from 'firebase-admin/database';
import { createRequire } from 'node:module';

const cliMode = process.argv.includes('--cli');
const [projectId, databaseURL, ownerEmail, ownerName = 'Owner'] = process.argv.slice(2).filter((argument) => argument !== '--cli');
if (!projectId || !databaseURL || !ownerEmail) {
  console.error('Usage: npm run owner:bootstrap -- [--cli] PROJECT_ID DATABASE_URL EXISTING_OWNER_EMAIL [NAME]');
  process.exit(1);
}
if (ownerName.length > 40 || ownerName.trim().length === 0) throw new Error('Name must have 1–40 characters');
// Uses local application-default credentials / GOOGLE_APPLICATION_CREDENTIALS.
// Create the email/password user in the Firebase console first. No password or
// privileged credential is written to the app or repository.
let credential;
if (cliMode) {
  // Uses the pinned Firebase CLI's local session in memory. Never export its
  // refresh token into app configuration, source files, CI secrets or logs.
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
} else {
  credential = applicationDefault();
}
initializeApp({ credential, projectId, databaseURL });
const user = await getAuth().getUserByEmail(ownerEmail);
const root = getDatabase().ref();
const config = await root.child('config').get();
if (config.exists()) throw new Error('Owner already configured; refusing to replace an existing family.');
await root.update({
  config: { ownerUid: user.uid, ownerMemberId: 'owner' },
  [`family/bindings/${user.uid}`]: 'owner',
  'family/members/owner': { name: ownerName.trim(), authUid: user.uid, installationId: 'owner', active: true },
  'family/states/owner': { control: { sharingEnabled: false, overrideActive: false, revision: 0 } },
});
console.log('Owner configured. Deploy locked database rules and sign in with the owner account.');
process.exit(0);
