// File generated manually from android/app/google-services.json.
// Re-generate with `flutterfire configure` if Firebase project settings change.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) throw UnsupportedError('Web is not configured.');
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyABB3tS_rTRP-MysWo8jRK-HIBe4zqEASY',
    appId: '1:136324676353:android:274f14d488b7c63780f900',
    messagingSenderId: '136324676353',
    projectId: 'algo-stockara',
    storageBucket: 'algo-stockara.firebasestorage.app',
  );
}
