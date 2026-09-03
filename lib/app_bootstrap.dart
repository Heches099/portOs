import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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
      await FirebaseRuntimeConfig.loadLocalAsset();
      final runtimeOptions = FirebaseRuntimeConfig.currentPlatformOptions;

      if (runtimeOptions != null) {
        await Firebase.initializeApp(options: runtimeOptions);
      } else if (kIsWeb) {
        return AppBootstrapState(
          isFirebaseAvailable: false,
          statusMessage: FirebaseRuntimeConfig.hasAnyRuntimeConfig
              ? 'Firebase web configuration is incomplete. Live data is unavailable.'
              : 'Firebase web configuration is missing. Live data is unavailable.',
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
            ? 'Firebase could not initialize on web. Live data is unavailable.'
            : 'Firebase could not initialize on this device. Live data is unavailable.',
      );
    }
  }
}

class FirebaseRuntimeConfig {
  static Map<String, String> _localValues = const {};

  static Future<void> loadLocalAsset() async {
    try {
      final content = await rootBundle.loadString('.env.local');
      final values = <String, String>{};
      for (final rawLine in content.split(RegExp(r'\r?\n'))) {
        final line = rawLine.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        final separator = line.indexOf('=');
        if (separator <= 0) continue;
        final key = line.substring(0, separator).trim();
        final value = line.substring(separator + 1).trim();
        if (key.isNotEmpty && value.isNotEmpty) values[key] = value;
      }
      _localValues = values;
    } catch (_) {
      // Dart defines remain available for CI and production builds.
    }
  }

  static String _value(String compileTimeValue, String name) =>
      compileTimeValue.isNotEmpty ? compileTimeValue : (_localValues[name] ?? '');

  static String get _apiKey => _value(const String.fromEnvironment('FIREBASE_API_KEY'), 'FIREBASE_API_KEY');
  static String get _projectId => _value(const String.fromEnvironment('FIREBASE_PROJECT_ID'), 'FIREBASE_PROJECT_ID');
  static String get _messagingSenderId => _value(const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID'), 'FIREBASE_MESSAGING_SENDER_ID');
  static String get _storageBucket => _value(const String.fromEnvironment('FIREBASE_STORAGE_BUCKET'), 'FIREBASE_STORAGE_BUCKET');
  static String get _authDomain => _value(const String.fromEnvironment('FIREBASE_AUTH_DOMAIN'), 'FIREBASE_AUTH_DOMAIN');
  static String get _measurementId => _value(const String.fromEnvironment('FIREBASE_MEASUREMENT_ID'), 'FIREBASE_MEASUREMENT_ID');
  static String get _databaseUrl => _value(const String.fromEnvironment('FIREBASE_DATABASE_URL'), 'FIREBASE_DATABASE_URL');
  static String get _webAppId => _value(const String.fromEnvironment('FIREBASE_WEB_APP_ID'), 'FIREBASE_WEB_APP_ID');
  static String get _androidAppId => _value(const String.fromEnvironment('FIREBASE_ANDROID_APP_ID'), 'FIREBASE_ANDROID_APP_ID');
  static String get _iosAppId => _value(const String.fromEnvironment('FIREBASE_IOS_APP_ID'), 'FIREBASE_IOS_APP_ID');
  static String get _macosAppId => _value(const String.fromEnvironment('FIREBASE_MACOS_APP_ID'), 'FIREBASE_MACOS_APP_ID');

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
