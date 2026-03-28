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
  String? _demoEmail;
  bool _isLoading = false;

  bool get isAuthenticated =>
      _firebaseEnabled ? _user != null : _demoEmail != null;
  bool get isLoading => _isLoading;
  bool get isDemoMode => !_firebaseEnabled;
  String? get statusMessage => _statusMessage;
  String? get currentEmail => _firebaseEnabled ? _user?.email : _demoEmail;
  bool get isAdmin {
    if (_firebaseEnabled) {
      return _hasAdminClaim;
    }

    final probe = (currentEmail ?? displayName).toLowerCase();
    return probe.contains('admin') || probe.contains('supervisor');
  }

  String get displayName => _firebaseEnabled
      ? _user?.displayName ?? _user?.email?.split('@').first ?? 'User'
      : _demoEmail?.split('@').first ?? 'Operator';

  Future<bool> signIn({required String email, required String password}) async {
    _isLoading = true;
    notifyListeners();

    try {
      if (!_firebaseEnabled) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        _demoEmail = email;
        return true;
      }

      final auth = _auth;
      if (auth == null) {
        throw Exception('Firebase authentication is unavailable.');
      }

      final UserCredential result = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      _user = result.user;
      final tokenResult = await result.user?.getIdTokenResult();
      _hasAdminClaim = tokenResult?.claims?['admin'] == true;
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
        default:
          message = 'Sign in failed. Please try again.';
      }
      throw Exception(message);
    } catch (_) {
      throw Exception(
        _firebaseEnabled
            ? 'An unexpected error occurred.'
            : 'Demo sign in failed.',
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
        await Future<void>.delayed(const Duration(milliseconds: 250));
        throw Exception(
          'Password reset email is unavailable in demo mode.',
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
    } else {
      _demoEmail = null;
    }
    notifyListeners();
  }
}
