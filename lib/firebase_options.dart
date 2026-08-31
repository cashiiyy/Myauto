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
    apiKey: 'AIzaSyA9T_5yIYmP2-6RL-G3ybqKv7lBLkXzKm0',
    appId: '1:422292813866:android:9c117b1becb53352aceb53',
    messagingSenderId: '422292813866',
    projectId: 'myauto-dd21e',
    storageBucket: 'myauto-dd21e.firebasestorage.app',
    databaseURL: 'https://myauto-dd21e-default-rtdb.asia-southeast1.firebasedatabase.app',
  );

  // Web config — Firebase Console > Project Settings > Web Apps
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyA9T_5yIYmP2-6RL-G3ybqKv7lBLkXzKm0',
    appId: '1:422292813866:web:ee90dd6579d65a6d42b7b2',
    messagingSenderId: '422292813866',
    projectId: 'myauto-dd21e',
    storageBucket: 'myauto-dd21e.firebasestorage.app',
    authDomain: 'myauto-dd21e.firebaseapp.com',
    databaseURL: 'https://myauto-dd21e-default-rtdb.asia-southeast1.firebasedatabase.app',
  );
}
