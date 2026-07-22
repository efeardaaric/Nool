import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/auth_config.dart';
import 'supabase_service.dart';

/// Supabase native sosyal + e-posta kimlik doğrulama (singleton).
class AuthService {
  AuthService._internal();

  static final AuthService _instance = AuthService._internal();

  factory AuthService() => _instance;

  SupabaseClient get _supabase => SupabaseService.instance.client;

  GoTrueClient get _auth => _supabase.auth;

  User? get currentUser =>
      SupabaseService.instance.isReady ? _auth.currentUser : null;

  bool get isSignedIn => currentUser != null;

  String? get displayName {
    final user = currentUser;
    if (user == null) return null;
    final meta = user.userMetadata ?? {};
    final full = meta['full_name'] as String?;
    if (full != null && full.trim().isNotEmpty) return full.trim();
    final name = meta['name'] as String?;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    final given = meta['given_name'] as String?;
    final family = meta['family_name'] as String?;
    final parts = <String>[
      if (given != null && given.isNotEmpty) given,
      if (family != null && family.isNotEmpty) family,
    ];
    if (parts.isNotEmpty) return parts.join(' ');
    return user.email;
  }

  String? get email => currentUser?.email;

  String? get avatarUrl {
    final user = currentUser;
    if (user == null) return null;
    final meta = user.userMetadata ?? {};
    final avatar = meta['avatar_url'] as String? ?? meta['picture'] as String?;
    if (avatar != null && avatar.isNotEmpty) return avatar;
    return null;
  }

  /// Native Google → Supabase `signInWithIdToken`.
  Future<AuthResponse> signInWithGoogle() async {
    _assertReady();

    if (!AuthConfig.hasGoogleWebClient) {
      throw const AuthException(
        'GOOGLE_WEB_CLIENT_ID tanımlı değil. '
        '--dart-define=GOOGLE_WEB_CLIENT_ID=... ile çalıştır.',
      );
    }

    try {
      final googleSignIn = GoogleSignIn(
        clientId: AuthConfig.googleIosClientId.isEmpty
            ? null
            : AuthConfig.googleIosClientId,
        serverClientId: AuthConfig.googleWebClientId,
        scopes: const ['email', 'profile'],
      );

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        throw const AuthException('Google girişi iptal edildi.');
      }

      final googleAuth = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (accessToken == null) {
        throw const AuthException('Google access token alınamadı.');
      }
      if (idToken == null) {
        throw const AuthException('Google id token alınamadı.');
      }

      return await _auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
    } on AuthException {
      rethrow;
    } catch (e, st) {
      debugPrint('AuthService.signInWithGoogle: $e\n$st');
      throw AuthException('Google ile giriş başarısız: $e');
    }
  }

  /// Native Apple → hashed nonce + Supabase `signInWithIdToken`.
  Future<AuthResponse> signInWithApple() async {
    _assertReady();

    try {
      final rawNonce = _generateRawNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        throw const AuthException('Apple identity token alınamadı.');
      }

      final response = await _auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );

      // Apple adını yalnızca ilk girişte verir — metadata'ya yaz.
      final given = credential.givenName;
      final family = credential.familyName;
      if (given != null || family != null) {
        final parts = <String>[
          if (given != null && given.isNotEmpty) given,
          if (family != null && family.isNotEmpty) family,
        ];
        if (parts.isNotEmpty) {
          await _auth.updateUser(
            UserAttributes(
              data: {
                'full_name': parts.join(' '),
                'given_name': given,
                'family_name': family,
              },
            ),
          );
        }
      }

      return response;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const AuthException('Apple girişi iptal edildi.');
      }
      throw AuthException('Apple ile giriş başarısız: ${e.message}');
    } on AuthException {
      rethrow;
    } catch (e, st) {
      debugPrint('AuthService.signInWithApple: $e\n$st');
      throw AuthException('Apple ile giriş başarısız: $e');
    }
  }

  Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) async {
    _assertReady();
    try {
      return await _auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } on AuthException {
      rethrow;
    } catch (e, st) {
      debugPrint('AuthService.signInWithEmail: $e\n$st');
      throw AuthException('E-posta ile giriş başarısız: $e');
    }
  }

  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
  }) async {
    _assertReady();
    try {
      return await _auth.signUp(
        email: email.trim(),
        password: password,
      );
    } on AuthException {
      rethrow;
    } catch (e, st) {
      debugPrint('AuthService.signUpWithEmail: $e\n$st');
      throw AuthException('Kayıt başarısız: $e');
    }
  }

  Future<void> resetPassword(String email) async {
    _assertReady();
    try {
      await _auth.resetPasswordForEmail(email.trim());
    } on AuthException {
      rethrow;
    } catch (e, st) {
      debugPrint('AuthService.resetPassword: $e\n$st');
      throw AuthException('Şifre sıfırlama maili gönderilemedi: $e');
    }
  }

  Future<void> signOut() async {
    if (!SupabaseService.instance.isReady) return;
    try {
      final googleSignIn = GoogleSignIn(
        clientId: AuthConfig.googleIosClientId.isEmpty
            ? null
            : AuthConfig.googleIosClientId,
        serverClientId: AuthConfig.hasGoogleWebClient
            ? AuthConfig.googleWebClientId
            : null,
      );
      await googleSignIn.signOut();
    } catch (e) {
      debugPrint('AuthService.signOut google: $e');
    }
    try {
      await _auth.signOut();
    } catch (e, st) {
      debugPrint('AuthService.signOut: $e\n$st');
      throw AuthException('Oturum kapatılamadı: $e');
    }
  }

  void _assertReady() {
    if (!SupabaseService.instance.isReady) {
      throw const AuthException(
        'Supabase henüz hazır değil. SUPABASE_URL / SUPABASE_ANON_KEY gerekir.',
      );
    }
  }

  String _generateRawNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }
}
