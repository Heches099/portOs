import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider({
    bool firebaseEnabled = true,
    String? statusMessage,
  })  : _firebaseEnabled = firebaseEnabled,
        _statusMessage = statusMessage {
    if (_firebaseEnabled) {
      _auth = FirebaseAuth.instance;
      _auth!.authStateChanges().listen((User? user) async {
        _user = user;
        _hasAdminClaim = false;

        if (user != null) {
          try {
            final tokenResult = await user.getIdTokenResult();
            _hasAdminClaim = tokenResult.claims?['admin'] == true;
          } catch (_) {
            _hasAdminClaim = false;
          }
        }

        notifyListeners();
      });
    }
  }

  final bool _firebaseEnabled;
  final String? _statusMessage;
  FirebaseAuth? _auth;
  User? _user;
  bool _hasAdminClaim = false;
  bool _isLoading = false;

  bool get isAuthenticated => _firebaseEnabled && _user != null;
  bool get isFirebaseAvailable => _firebaseEnabled;
  bool get isLoading => _isLoading;
  String? get statusMessage => _statusMessage;
  String? get currentEmail => _user?.email;
  bool get isEmailVerified => _user?.emailVerified ?? false;
  bool get isAdmin {
    if (_firebaseEnabled) {
      return _hasAdminClaim;
    }

    final probe = (currentEmail ?? displayName).toLowerCase();
    return probe.contains('admin') || probe.contains('supervisor');
  }

  String get displayName =>
      _user?.displayName ?? _user?.email?.split('@').first ?? 'Operator';

  Future<bool> signIn({required String email, required String password}) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (!_firebaseEnabled) {
        throw Exception(
          _statusMessage ?? 'Firebase authentication is unavailable.',
        );
      }

      final auth = _auth;
      if (auth == null) {
        throw Exception('Firebase authentication is unavailable.');
      }

      final UserCredential result = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = result.user;
      if (user == null) {
        throw Exception('Firebase did not return an operator account.');
      }

      await user.reload();
      final refreshedUser = auth.currentUser;
      if (refreshedUser == null) {
        throw Exception('Firebase authentication could not be refreshed.');
      }

      _user = refreshedUser;
      final tokenResult = await refreshedUser.getIdTokenResult(true);
      _hasAdminClaim = tokenResult.claims?['admin'] == true;
      return true;
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'user-not-found':
          message = 'No user found with this email.';
          break;
        case 'wrong-password':
          message = 'Wrong password provided.';
          break;
        case 'invalid-email':
          message = 'The email address is badly formatted.';
          break;
        case 'too-many-requests':
          message =
              'Too many sign-in attempts. Please wait a moment and try again.';
          break;
        case 'invalid-credential':
          message =
              'The operator email or access key is incorrect. Check the Firebase Authentication user record and try again.';
          break;
        case 'operation-not-allowed':
          message =
              'Email/password sign-in is disabled for this Firebase project. Enable it in Firebase Console → Authentication → Sign-in method.';
          break;
        case 'network-request-failed':
          message =
              'Firebase could not be reached. Check your internet connection and any API-key domain restrictions.';
          break;
        case 'invalid-api-key':
        case 'api-key-not-valid':
          message =
              'The Firebase web API key is invalid. Update FIREBASE_API_KEY in .env.local.';
          break;
        case 'app-not-authorized':
          message =
              'This localhost address is not authorized for Firebase Authentication. Add localhost in Firebase Console → Authentication → Settings → Authorized domains.';
          break;
        default:
          final detail = e.message?.trim();
          message = detail == null || detail.isEmpty
              ? 'Firebase sign-in failed (${e.code}).'
              : 'Firebase sign-in failed (${e.code}): $detail';
      }
      throw Exception(message);
    } catch (error) {
      if (error is Exception) {
        rethrow;
      }
      throw Exception(
        'An unexpected error occurred.',
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> signUp({required String email, required String password}) async {
    throw Exception(
      'Self-service registration is disabled. Operator accounts are provisioned manually in Firebase.',
    );
  }

  Future<void> sendPasswordResetEmail({required String email}) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty) {
      throw Exception('Enter the registered operator email first.');
    }

    _isLoading = true;
    notifyListeners();

    try {
      if (!_firebaseEnabled) {
        throw Exception(
          _statusMessage ?? 'Firebase authentication is unavailable.',
        );
      }

      final auth = _auth;
      if (auth == null) {
        throw Exception('Firebase authentication is unavailable.');
      }

      await auth.sendPasswordResetEmail(email: normalizedEmail);
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'invalid-email':
          message = 'The email address is badly formatted.';
          break;
        case 'user-not-found':
          message = 'No Firebase operator account exists for this email.';
          break;
        default:
          message = 'Password reset could not be started.';
      }
      throw Exception(message);
    } catch (_) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> getIdToken({bool forceRefresh = false}) async {
    if (!_firebaseEnabled) {
      return null;
    }
    return _user?.getIdToken(forceRefresh);
  }

  Future<void> signOut() async {
    if (_firebaseEnabled) {
      await _auth!.signOut();
      _user = null;
      _hasAdminClaim = false;
    }
    notifyListeners();
  }
}
