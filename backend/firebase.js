const fs = require('fs');

const {
  initializeApp,
  getApps,
  cert,
} = require('firebase-admin/app');

const { getFirestore } = require('firebase-admin/firestore');

function loadServiceAccount() {
  const json = process.env.FIREBASE_SERVICE_ACCOUNT;

  if (json) {
    return JSON.parse(json);
  }

  const filePath = process.env.FIREBASE_SERVICE_ACCOUNT_PATH;

  if (filePath) {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  }

  throw new Error(
    'Missing FIREBASE_SERVICE_ACCOUNT or FIREBASE_SERVICE_ACCOUNT_PATH'
  );
}

if (getApps().length === 0) {
  initializeApp({
    credential: cert(loadServiceAccount()),
  });
}

const db = getFirestore();

module.exports = { db };