import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'firebase_options.dart';

class AppBootstrapState {
  const AppBootstrapState({
    required this.isFirebaseAvailable,
    this.statusMessage,
  });

  final bool isFirebaseAvailable;
  final String? statusMessage;
}

class AppBootstrap {
  static Future<AppBootstrapState> initialize() async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      return const AppBootstrapState(
        isFirebaseAvailable: true,
      );
    } catch (error, stackTrace) {
      debugPrint('Firebase initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      return AppBootstrapState(
        isFirebaseAvailable: false,
        statusMessage: kIsWeb
            ? 'Firebase could not initialize on web. Live data is unavailable.'
            : 'Firebase could not initialize on this device. Live data is unavailable.',
      );
    }
  }
}