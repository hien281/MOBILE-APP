const {
  initializeApp,
  getApps,
  cert,
} = require('firebase-admin/app');

const {
  getFirestore,
} = require('firebase-admin/firestore');

const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT;

if (!serviceAccountJson) {
  throw new Error('Missing FIREBASE_SERVICE_ACCOUNT');
}

const serviceAccount = JSON.parse(serviceAccountJson);

if (getApps().length === 0) {
  initializeApp({
    credential: cert(serviceAccount),
  });
}

const db = getFirestore();

module.exports = { db };
