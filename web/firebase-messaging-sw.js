// SPORTY: Firebase Messaging service worker (public Firebase web config only).
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyC6SeOH9Y4Fmm7RU_e9T68JVK4uzHbjZ4U',
  authDomain: 'sport-app-b6ba9.firebaseapp.com',
  projectId: 'sport-app-b6ba9',
  storageBucket: 'sport-app-b6ba9.firebasestorage.app',
  messagingSenderId: '499981685398',
  appId: '1:499981685398:web:532fafbd96ef0abee628b7',
});
const messaging = firebase.messaging();
// Firebase tự hiển thị notification payload cho background messages.
// Không gọi showNotification lần nữa để tránh thông báo lặp.
