import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AppAuthController extends ChangeNotifier {
  AppAuthController({
    FirebaseAuth? firebaseAuth,
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  }) : _auth = firebaseAuth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance {
    unawaited(_loadPendingEmailPasswordSetup());
    unawaited(_loadLocalProfilePhotoPath());
  }

  AppAuthController.offline()
    : _auth = null,
      _firestore = null,
      _storage = null,
      _hasLoadedPendingEmailPasswordSetup = true;

  static const String _pendingEmailPasswordSetupUidKey =
      'pendingEmailPasswordSetupUid';
  static const String _pendingEmailPasswordSetupEmailKey =
      'pendingEmailPasswordSetupEmail';
  static const String _pendingEmailPasswordSetupTempPasswordKey =
      'pendingEmailPasswordSetupTempPassword';
  static const String _localProfilePhotoPathPrefix = 'localProfilePhotoPath.';

  final FirebaseAuth? _auth;
  final FirebaseFirestore? _firestore;
  final FirebaseStorage? _storage;

  bool _isBusy = false;
  String? _verificationId;
  int? _forceResendingToken;
  String? _lastPhoneNumber;
  bool _prefersCreateEmailFlow = false;
  String? _pendingEmailPasswordSetupUid;
  String? _pendingEmailPasswordSetupEmail;
  String? _pendingEmailPasswordSetupTempPassword;
  bool _hasLoadedPendingEmailPasswordSetup = false;
  String? _localProfilePhotoPath;

  bool get isBusy => _isBusy;
  bool get hasPendingPhoneCode => _verificationId != null;
  User? get currentUser => _auth?.currentUser;
  String? get localProfilePhotoPath => _localProfilePhotoPath;
  Stream<User?> get authStateChanges =>
      _auth?.authStateChanges() ?? Stream<User?>.value(null);
  bool get prefersCreateEmailFlow => _prefersCreateEmailFlow;
  bool get hasLoadedPendingEmailPasswordSetup =>
      _hasLoadedPendingEmailPasswordSetup;
  bool get needsEmailPasswordSetup {
    final user = _auth?.currentUser;
    return user != null && user.uid == _pendingEmailPasswordSetupUid;
  }

  bool get needsEmailVerification {
    final user = _auth?.currentUser;
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

  void preferCreateEmailFlow() {
    if (_prefersCreateEmailFlow) {
      return;
    }
    _prefersCreateEmailFlow = true;
    notifyListeners();
  }

  void clearCreateEmailFlowPreference() {
    if (!_prefersCreateEmailFlow) {
      return;
    }
    _prefersCreateEmailFlow = false;
    notifyListeners();
  }

  Future<void> sendPhoneCode(String phoneNumber) async {
    final normalizedPhone = phoneNumber.trim();
    if (normalizedPhone.isEmpty) {
      throw const AuthFlowException('Please enter your phone number first.');
    }

    _setBusy(true);

    try {
      final auth = _auth!;
      final completer = Completer<void>();

      await auth.verifyPhoneNumber(
        phoneNumber: normalizedPhone,
        forceResendingToken: _forceResendingToken,
        verificationCompleted: (credential) async {
          try {
            await auth.signInWithCredential(credential);
            await _upsertUserProfile(
              provider: 'phone',
              phoneNumber: credential.smsCode == null
                  ? normalizedPhone
                  : auth.currentUser?.phoneNumber ?? normalizedPhone,
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
      final auth = _auth!;
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: trimmedCode,
      );
      await auth.signInWithCredential(credential);
      await _upsertUserProfile(
        provider: 'phone',
        phoneNumber: auth.currentUser?.phoneNumber ?? _lastPhoneNumber,
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

      final userCredential = await _auth!.signInWithCredential(oauthCredential);
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
      await _auth!.signInWithEmailAndPassword(
        email: normalizedEmail,
        password: password,
      );
      clearCreateEmailFlowPreference();
      await _clearPendingEmailPasswordSetup();
      await _upsertUserProfile(provider: 'email');
    } catch (error) {
      throw _mapError(error);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    final normalizedEmail = email.trim();
    if (normalizedEmail.isEmpty) {
      throw const AuthFlowException('Please enter your email first.');
    }

    _setBusy(true);
    try {
      await _auth!.sendPasswordResetEmail(email: normalizedEmail);
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

    preferCreateEmailFlow();

    final currentUser = _auth!.currentUser;
    if (currentUser != null && currentUser.email == normalizedEmail) {
      _setBusy(true);
      try {
        if (!currentUser.emailVerified) {
          await currentUser.sendEmailVerification();
        } else {
          await _setPendingEmailPasswordSetup(currentUser.uid);
          notifyListeners();
        }
      } catch (error) {
        throw _mapError(error);
      } finally {
        _setBusy(false);
      }
      return;
    }

    _setBusy(true);
    try {
      final auth = _auth;
      final tempPassword = '${_randomNonce(28)}Aa1!';
      final credential = await auth.createUserWithEmailAndPassword(
        email: normalizedEmail,
        password: tempPassword,
      );
      await credential.user?.sendEmailVerification();
      await _setPendingEmailPasswordSetup(
        credential.user?.uid,
        email: normalizedEmail,
        tempPassword: tempPassword,
      );
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
      final auth = _auth!;
      final user = auth.currentUser;
      if (user == null) {
        throw const AuthFlowException(
          'Send the verification email before continuing.',
        );
      }

      await user.reload();
      final refreshedUser = auth.currentUser;
      if (refreshedUser == null || !refreshedUser.emailVerified) {
        throw const AuthFlowException(
          'Please open the verification email first, then try again.',
        );
      }
      await _setPendingEmailPasswordSetup(
        refreshedUser.uid,
        email: refreshedUser.email,
        tempPassword: _pendingEmailPasswordSetupTempPassword,
      );
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
      final user = _auth!.currentUser;
      if (user == null || !user.emailVerified) {
        throw const AuthFlowException(
          'Verify your email before creating your password.',
        );
      }

      await user.updatePassword(password);
      await user.reload();
      clearCreateEmailFlowPreference();
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
      await _auth!.signOut();
      _verificationId = null;
      _forceResendingToken = null;
      _lastPhoneNumber = null;
      clearCreateEmailFlowPreference();
      await _clearPendingEmailPasswordSetup();
      notifyListeners();
    } catch (error) {
      throw _mapError(error);
    } finally {
      _setBusy(false);
    }
  }

  Future<void> updateProfilePhoto(File imageFile) async {
    final user = _auth!.currentUser;
    if (user == null) {
      throw const AuthFlowException('Sign in before updating your profile.');
    }

    _setBusy(true);
    try {
      await _saveLocalProfilePhotoPath(user.uid, imageFile.path);

      String? downloadUrl;
      try {
        final extension = _fileExtension(imageFile.path);
        final ref = _storage!.ref(
          'profile_images/${user.uid}/avatar$extension',
        );
        final metadata = SettableMetadata(
          contentType: _contentTypeForExtension(extension),
          customMetadata: {'uid': user.uid},
        );
        await ref.putFile(imageFile, metadata);
        downloadUrl = await ref.getDownloadURL();
        await user.updatePhotoURL(downloadUrl);
      } on FirebaseException {
        // Firebase Storage is intentionally unavailable on the Spark plan.
        // The local path keeps the app-side picker flow usable until Storage is enabled.
      }

      await _firestore!.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'photoUrl': downloadUrl ?? user.photoURL,
        'hasLocalProfilePhoto': downloadUrl == null,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await user.reload();
      notifyListeners();
    } catch (error) {
      if (error is AuthFlowException) {
        rethrow;
      }
      throw const AuthFlowException(
        'Could not update your profile photo. Please try again.',
      );
    } finally {
      _setBusy(false);
    }
  }

  Future<void> _upsertUserProfile({
    required String provider,
    String? displayName,
    String? phoneNumber,
  }) async {
    final user = _auth!.currentUser;
    if (user == null) {
      return;
    }

    final resolvedDisplayName = displayName?.trim();
    if (resolvedDisplayName != null && resolvedDisplayName.isNotEmpty) {
      await user.updateDisplayName(resolvedDisplayName);
    }

    final now = FieldValue.serverTimestamp();
    await _firestore!.collection('users').doc(user.uid).set({
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
    await _loadLocalProfilePhotoPath();
  }

  AuthFlowException _mapError(Object error) {
    if (error is AuthFlowException) {
      return error;
    }
    if (error is FirebaseAuthException) {
      return AuthFlowException(_messageForAuthCode(error), code: error.code);
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

  Future<void> _loadLocalProfilePhotoPath() async {
    final user = _auth?.currentUser;
    if (user == null) {
      return;
    }

    try {
      final preferences = await SharedPreferences.getInstance();
      _localProfilePhotoPath = preferences.getString(
        '$_localProfilePhotoPathPrefix${user.uid}',
      );
      notifyListeners();
    } catch (_) {
      // Profile photos can still load from Firebase Auth or Firestore.
    }
  }

  Future<void> _saveLocalProfilePhotoPath(String uid, String path) async {
    _localProfilePhotoPath = path;
    notifyListeners();
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('$_localProfilePhotoPathPrefix$uid', path);
    } catch (_) {
      // The picked image still works for the current run even without preferences.
    }
  }

  String _fileExtension(String path) {
    final extension = path.split('.').last.toLowerCase();
    switch (extension) {
      case 'png':
        return '.png';
      case 'webp':
        return '.webp';
      case 'heic':
        return '.heic';
      case 'jpg':
      case 'jpeg':
      default:
        return '.jpg';
    }
  }

  String _contentTypeForExtension(String extension) {
    switch (extension) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  Future<void> _loadPendingEmailPasswordSetup() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      _pendingEmailPasswordSetupUid = preferences.getString(
        _pendingEmailPasswordSetupUidKey,
      );
      _pendingEmailPasswordSetupEmail = preferences.getString(
        _pendingEmailPasswordSetupEmailKey,
      );
      _pendingEmailPasswordSetupTempPassword = preferences.getString(
        _pendingEmailPasswordSetupTempPasswordKey,
      );
    } catch (_) {
      // Keep the in-memory default if preferences are unavailable in tests.
    } finally {
      _hasLoadedPendingEmailPasswordSetup = true;
      notifyListeners();
    }
  }

  Future<void> _setPendingEmailPasswordSetup(
    String? uid, {
    String? email,
    String? tempPassword,
  }) async {
    if (uid == null) {
      return;
    }
    _pendingEmailPasswordSetupUid = uid;
    _pendingEmailPasswordSetupEmail = email ?? _pendingEmailPasswordSetupEmail;
    _pendingEmailPasswordSetupTempPassword =
        tempPassword ?? _pendingEmailPasswordSetupTempPassword;
    notifyListeners();
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_pendingEmailPasswordSetupUidKey, uid);
      if (_pendingEmailPasswordSetupEmail != null) {
        await preferences.setString(
          _pendingEmailPasswordSetupEmailKey,
          _pendingEmailPasswordSetupEmail!,
        );
      }
      if (_pendingEmailPasswordSetupTempPassword != null) {
        await preferences.setString(
          _pendingEmailPasswordSetupTempPasswordKey,
          _pendingEmailPasswordSetupTempPassword!,
        );
      }
    } catch (_) {
      // The in-memory flag still protects the current session.
    }
  }

  Future<void> _clearPendingEmailPasswordSetup() async {
    _pendingEmailPasswordSetupUid = null;
    _pendingEmailPasswordSetupEmail = null;
    _pendingEmailPasswordSetupTempPassword = null;
    notifyListeners();
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(_pendingEmailPasswordSetupUidKey);
      await preferences.remove(_pendingEmailPasswordSetupEmailKey);
      await preferences.remove(_pendingEmailPasswordSetupTempPasswordKey);
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
  const AuthFlowException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}
