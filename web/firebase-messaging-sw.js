importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDNiGouhzzZSJ0q2gKgJ2mK2brSSuRxfKk',
  authDomain: 'oncovault-8cbbc.firebaseapp.com',
  projectId: 'oncovault-8cbbc',
  storageBucket: 'oncovault-8cbbc.firebasestorage.app',
  messagingSenderId: '552811546534',
  appId: '1:552811546534:web:b1273e155d12dee633b167'
});

const messaging = firebase.messaging();
