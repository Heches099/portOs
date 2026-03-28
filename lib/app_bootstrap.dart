import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

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
      final runtimeOptions = FirebaseRuntimeConfig.currentPlatformOptions;

      if (runtimeOptions != null) {
        await Firebase.initializeApp(options: runtimeOptions);
      } else if (kIsWeb) {
        return AppBootstrapState(
          isFirebaseAvailable: false,
          statusMessage: FirebaseRuntimeConfig.hasAnyRuntimeConfig
              ? 'Firebase web config is incomplete, so the app is running in demo mode.'
              : 'Firebase web config is missing, so the app is running in demo mode.',
        );
      } else {
        await Firebase.initializeApp();
      }

      return const AppBootstrapState(isFirebaseAvailable: true);
    } catch (error, stackTrace) {
      debugPrint('Firebase initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      return const AppBootstrapState(
        isFirebaseAvailable: false,
        statusMessage: kIsWeb
            ? 'Firebase could not initialize on web, so the app is running in demo mode.'
            : 'Firebase could not initialize on this device, so the app is running in demo mode.',
      );
    }
  }
}

class FirebaseRuntimeConfig {
  static const String _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String _projectId =
      String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String _messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const String _storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );
  static const String _authDomain = String.fromEnvironment(
    'FIREBASE_AUTH_DOMAIN',
  );
  static const String _measurementId = String.fromEnvironment(
    'FIREBASE_MEASUREMENT_ID',
  );
  static const String _databaseUrl = String.fromEnvironment(
    'FIREBASE_DATABASE_URL',
  );

  static const String _webAppId = String.fromEnvironment('FIREBASE_WEB_APP_ID');
  static const String _androidAppId = String.fromEnvironment(
    'FIREBASE_ANDROID_APP_ID',
  );
  static const String _iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
  static const String _macosAppId = String.fromEnvironment(
    'FIREBASE_MACOS_APP_ID',
  );

  static bool get hasAnyRuntimeConfig =>
      _apiKey.isNotEmpty ||
      _projectId.isNotEmpty ||
      _messagingSenderId.isNotEmpty ||
      _webAppId.isNotEmpty ||
      _androidAppId.isNotEmpty ||
      _iosAppId.isNotEmpty ||
      _macosAppId.isNotEmpty;

  static FirebaseOptions? get currentPlatformOptions {
    if (!_sharedConfigIsComplete) {
      return null;
    }

    if (kIsWeb) {
      if (_webAppId.isEmpty) {
        return null;
      }
      return _buildOptions(appId: _webAppId, authDomain: _authDomain);
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return _androidAppId.isEmpty
            ? null
            : _buildOptions(appId: _androidAppId);
      case TargetPlatform.iOS:
        return _iosAppId.isEmpty ? null : _buildOptions(appId: _iosAppId);
      case TargetPlatform.macOS:
        return _macosAppId.isEmpty ? null : _buildOptions(appId: _macosAppId);
      case TargetPlatform.linux:
      case TargetPlatform.windows:
      case TargetPlatform.fuchsia:
        return null;
    }
  }

  static bool get _sharedConfigIsComplete =>
      _apiKey.isNotEmpty &&
      _projectId.isNotEmpty &&
      _messagingSenderId.isNotEmpty;

  static FirebaseOptions _buildOptions({
    required String appId,
    String? authDomain,
  }) {
    return FirebaseOptions(
      apiKey: _apiKey,
      appId: appId,
      messagingSenderId: _messagingSenderId,
      projectId: _projectId,
      authDomain: authDomain?.isEmpty ?? true ? null : authDomain,
      storageBucket: _storageBucket.isEmpty ? null : _storageBucket,
      measurementId: _measurementId.isEmpty ? null : _measurementId,
      databaseURL: _databaseUrl.isEmpty ? null : _databaseUrl,
    );
  }
}
