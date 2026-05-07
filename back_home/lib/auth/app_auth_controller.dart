import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AppAuthController extends ChangeNotifier {
  AppAuthController({FirebaseAuth? firebaseAuth, FirebaseFirestore? firestore})
    : _auth = firebaseAuth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance {
    unawaited(_loadPendingEmailPasswordSetup());
  }

  static const String _pendingEmailPasswordSetupUidKey =
      'pendingEmailPasswordSetupUid';

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  bool _isBusy = false;
  String? _verificationId;
  int? _forceResendingToken;
  String? _lastPhoneNumber;
  String? _pendingEmailPasswordSetupUid;

  bool get isBusy => _isBusy;
  bool get hasPendingPhoneCode => _verificationId != null;
  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();
  bool get needsEmailPasswordSetup {
    final user = _auth.currentUser;
    return user != null && user.uid == _pendingEmailPasswordSetupUid;
  }

  bool get needsEmailVerification {
    final user = _auth.currentUser;
    if (user == null || user.email == null || user.emailVerified) {
      return false;
    }

    return user.providerData.any(
      (provider) => provider.providerId == 'password',
    );
  }

  bool get supportsAppleSignIn {
    if (kIsWeb) {
      return false;
    }

    return Platform.isIOS || Platform.isMacOS;
  }

  Future<void> sendPhoneCode(String phoneNumber) async {
    final normalizedPhone = phoneNumber.trim();
    if (normalizedPhone.isEmpty) {
      throw const AuthFlowException('Please enter your phone number first.');
    }

    _setBusy(true);

    try {
      final completer = Completer<void>();

      await _auth.verifyPhoneNumber(
        phoneNumber: normalizedPhone,
        forceResendingToken: _forceResendingToken,
        verificationCompleted: (credential) async {
          try {
            await _auth.signInWithCredential(credential);
            await _upsertUserProfile(
              provider: 'phone',
              phoneNumber: credential.smsCode == null
                  ? normalizedPhone
                  : _auth.currentUser?.phoneNumber ?? normalizedPhone,
            );
            _verificationId = null;
            _forceResendingToken = null;
            _lastPhoneNumber = normalizedPhone;
            if (!completer.isCompleted) {
              completer.complete();
            }
            notifyListeners();
          } catch (error) {
            if (!completer.isCompleted) {
              completer.completeError(_mapError(error));
            }
          }
        },
        verificationFailed: (error) {
          if (!completer.isCompleted) {
            completer.completeError(_mapError(error));
          }
        },
        codeSent: (verificationId, forceResendingToken) {
          _verificationId = verificationId;
          _forceResendingToken = forceResendingToken;
          _lastPhoneNumber = normalizedPhone;
          notifyListeners();
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
        codeAutoRetrievalTimeout: (verificationId) {
          _verificationId = verificationId;
          notifyListeners();
        },
      );

      await completer.future;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> verifySmsCode(String smsCode) async {
    final trimmedCode = smsCode.trim();
    if (trimmedCode.isEmpty) {
      throw const AuthFlowException('Please enter the 6-digit code.');
    }
    if (_verificationId == null) {
      throw const AuthFlowException('Send a phone code before confirming it.');
    }

    _setBusy(true);
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: trimmedCode,
      );
      await _auth.signInWithCredential(credential);
      await _upsertUserProfile(
        provider: 'phone',
        phoneNumber: _auth.currentUser?.phoneNumber ?? _lastPhoneNumber,
      );
      _verificationId = null;
      notifyListeners();
    } catch (error) {
      throw _mapError(error);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> signInWithApple() async {
    if (!supportsAppleSignIn) {
      throw const AuthFlowException(
        'Apple sign in is only available on Apple devices.',
      );
    }

    _setBusy(true);
    try {
      final rawNonce = _randomNonce();
      final nonce = _sha256OfString(rawNonce);
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      final oauthCredential = OAuthProvider(
        'apple.com',
      ).credential(idToken: credential.identityToken, rawNonce: rawNonce);

      final userCredential = await _auth.signInWithCredential(oauthCredential);
      await _upsertUserProfile(
        provider: 'apple',
        displayName: _joinAppleName(
          credential.givenName,
          credential.familyName,
          fallback: userCredential.user?.displayName,
        ),
      );
    } catch (error) {
      throw _mapError(error);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty) {
      throw const AuthFlowException('Please enter your email first.');
    }
    if (password.isEmpty) {
      throw const AuthFlowException('Please enter your password.');
    }

    _setBusy(true);
    try {
      await _auth.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      await _clearPendingEmailPasswordSetup();
      await _upsertUserProfile(provider: 'email');
    } catch (error) {
      throw _mapError(error);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> sendEmailCreationVerification(String email) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty) {
      throw const AuthFlowException('Please enter your email first.');
    }

    final currentUser = _auth.currentUser;
    if (currentUser != null &&
        currentUser.email == normalizedEmail &&
        !currentUser.emailVerified) {
      _setBusy(true);
      try {
        await currentUser.sendEmailVerification();
      } catch (error) {
        throw _mapError(error);
      } finally {
        _setBusy(false);
      }
      return;
    }

    _setBusy(true);
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: '${_randomNonce(28)}Aa1!',
      );
      await credential.user?.sendEmailVerification();
      await _setPendingEmailPasswordSetup(credential.user?.uid);
      await _upsertUserProfile(provider: 'email_pending');
    } catch (error) {
      throw _mapError(error);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> confirmEmailCreationVerification() async {
    _setBusy(true);
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw const AuthFlowException(
          'Send the verification email before continuing.',
        );
      }

      await user.reload();
      final refreshedUser = _auth.currentUser;
      if (refreshedUser == null || !refreshedUser.emailVerified) {
        throw const AuthFlowException(
          'Please open the verification email first, then try again.',
        );
      }
      await _setPendingEmailPasswordSetup(refreshedUser.uid);
      notifyListeners();
    } catch (error) {
      throw _mapError(error);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> finishVerifiedEmailAccount({required String password}) async {
    if (password.length < 6) {
      throw const AuthFlowException(
        'Please use a password with at least 6 characters.',
      );
    }

    _setBusy(true);
    try {
      final user = _auth.currentUser;
      if (user == null || !user.emailVerified) {
        throw const AuthFlowException(
          'Verify your email before creating your password.',
        );
      }

      await user.updatePassword(password);
      await user.reload();
      await _upsertUserProfile(provider: 'email');
      await _clearPendingEmailPasswordSetup();
      notifyListeners();
    } catch (error) {
      throw _mapError(error);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> signOut() async {
    _setBusy(true);
    try {
      await _auth.signOut();
      _verificationId = null;
      _forceResendingToken = null;
      _lastPhoneNumber = null;
      await _clearPendingEmailPasswordSetup();
      notifyListeners();
    } catch (error) {
      throw _mapError(error);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _upsertUserProfile({
    required String provider,
    String? displayName,
    String? phoneNumber,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      return;
    }

    final resolvedDisplayName = displayName?.trim();
    if (resolvedDisplayName != null && resolvedDisplayName.isNotEmpty) {
      await user.updateDisplayName(resolvedDisplayName);
    }

    final now = FieldValue.serverTimestamp();
    await _firestore.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'displayName': (resolvedDisplayName?.isNotEmpty ?? false)
          ? resolvedDisplayName
          : user.displayName,
      'phoneNumber': phoneNumber ?? user.phoneNumber,
      'email': user.email,
      'photoUrl': user.photoURL,
      'provider': provider,
      'lastLoginAt': now,
      'createdAt': now,
    }, SetOptions(merge: true));
  }

  AuthFlowException _mapError(Object error) {
    if (error is AuthFlowException) {
      return error;
    }
    if (error is FirebaseAuthException) {
      return AuthFlowException(_messageForAuthCode(error));
    }
    if (error is SignInWithAppleAuthorizationException &&
        error.code == AuthorizationErrorCode.canceled) {
      return const AuthFlowException('Apple sign in was cancelled.');
    }

    return const AuthFlowException(
      'Something went wrong while signing in. Please try again.',
    );
  }

  String _messageForAuthCode(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-phone-number':
        return 'Please enter a valid phone number with country code, like +1 555...';
      case 'too-many-requests':
        return 'Too many attempts right now. Please wait a bit and try again.';
      case 'invalid-verification-code':
        return 'That code does not look right. Please try again.';
      case 'session-expired':
        return 'That code expired. Please send a new one.';
      case 'account-exists-with-different-credential':
        return 'That account already exists with another login method.';
      case 'email-already-in-use':
        return 'That email already has an account. Try signing in instead.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'The email or password is incorrect.';
      case 'weak-password':
        return 'Please use a stronger password.';
      case 'missing-or-invalid-nonce':
        return 'Apple sign in could not be verified. Please try again.';
      case 'network-request-failed':
        return 'Network connection failed. Please check your internet and try again.';
      default:
        return error.message ??
            'Authentication failed. Please try again in a moment.';
    }
  }

  void _setBusy(bool value) {
    if (_isBusy == value) {
      return;
    }

    _isBusy = value;
    notifyListeners();
  }

  Future<void> _loadPendingEmailPasswordSetup() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _pendingEmailPasswordSetupUid = preferences.getString(
        _pendingEmailPasswordSetupUidKey,
      );
      notifyListeners();
    } catch (_) {
      // Keep the in-memory default if preferences are unavailable in tests.
    }
  }

  Future<void> _setPendingEmailPasswordSetup(String? uid) async {
    if (uid == null) {
      return;
    }
    _pendingEmailPasswordSetupUid = uid;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_pendingEmailPasswordSetupUidKey, uid);
    } catch (_) {
      // The in-memory flag still protects the current session.
    }
  }

  Future<void> _clearPendingEmailPasswordSetup() async {
    _pendingEmailPasswordSetupUid = null;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_pendingEmailPasswordSetupUidKey);
    } catch (_) {
      // The in-memory flag was already cleared.
    }
  }

  String _randomNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List<String>.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  String _sha256OfString(String input) {
    final bytes = utf8.encode(input);
    return sha256.convert(bytes).toString();
  }

  String? _joinAppleName(
    String? givenName,
    String? familyName, {
    String? fallback,
  }) {
    final parts = [givenName, familyName]
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return fallback;
    }
    return parts.join(' ');
  }
}

class AuthFlowException implements Exception {
  const AuthFlowException(this.message);

  final String message;

  @override
  String toString() => message;
}
