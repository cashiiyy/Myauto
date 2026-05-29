import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with [Firebase.initializeApp].
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for ios.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyByT0Lo7tgsNnoPoEhzjG4e0xeKMIO8e5s',
    appId: '1:252031920183:android:5409accead9fa6a742b7b2',
    messagingSenderId: '252031920183',
    projectId: 'myauto-493fc',
    storageBucket: 'myauto-493fc.firebasestorage.app',
    databaseURL: 'https://myauto-493fc-default-rtdb.firebaseio.com',
  );

  // Web config — Firebase Console > Project Settings > Web Apps
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyByT0Lo7tgsNnoPoEhzjG4e0xeKMIO8e5s',
    appId: '1:252031920183:web:ee90dd6579d65a6d42b7b2',
    messagingSenderId: '252031920183',
    projectId: 'myauto-493fc',
    storageBucket: 'myauto-493fc.firebasestorage.app',
    authDomain: 'myauto-493fc.firebaseapp.com',
    databaseURL: 'https://myauto-493fc-default-rtdb.firebaseio.com',
  );
}
