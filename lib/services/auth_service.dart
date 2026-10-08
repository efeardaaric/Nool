import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/auth_config.dart';
import 'curiosity_teaser_service.dart';
import 'notification_service.dart';
import 'settings_service.dart';
import 'social_notification_service.dart';
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

  /// E-posta kimliği var mı (şifre / reset maili için).
  bool get hasEmailIdentity {
    final user = currentUser;
    if (user == null) return false;
    if ((user.email ?? '').trim().isNotEmpty) return true;
    return user.identities?.any((i) => i.provider == 'email') ?? false;
  }

  /// Oturum açıkken `updateUser(password:)` ile şifre değişebilir.
  bool get canUpdatePassword => isSignedIn;

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

      final response = await _auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );
      _onSignedIn();
      return response;
    } on AuthException catch (e) {
      // Native Google id_token often contains a nonce that google_sign_in
      // does not expose — Supabase must skip nonce checks for Google.
      final msg = e.message;
      if (msg.contains('nonce') || msg.contains('Nonce')) {
        throw const AuthException(
          'Google girişi: Supabase’te Google sağlayıcısında '
          '“Skip nonce checks” açık olmalı '
          '(Authentication → Providers → Google).',
        );
      }
      rethrow;
    } catch (e, st) {
      debugPrint('AuthService.signInWithGoogle: $e\n$st');
      final text = e.toString();
      if (text.contains('nonce') || text.contains('Nonce')) {
        throw const AuthException(
          'Google girişi: Supabase’te Google sağlayıcısında '
          '“Skip nonce checks” açık olmalı '
          '(Authentication → Providers → Google).',
        );
      }
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

      _onSignedIn();
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
      final response = await _auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      _onSignedIn();
      return response;
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
      final response = await _auth.signUp(
        email: email.trim(),
        password: password,
      );
      if (response.session != null) {
        _onSignedIn();
      }
      return response;
    } on AuthException {
      rethrow;
    } catch (e, st) {
      debugPrint('AuthService.signUpWithEmail: $e\n$st');
      throw AuthException('Kayıt başarısız: $e');
    }
  }

  /// E-posta ile şifre sıfırlama linki gönderir.
  ///
  /// [redirectTo] varsayılanı [AuthConfig.authRedirectUrl] — uygulama
  /// deep link’i. Supabase Dashboard’da Redirect URLs’e eklenmeli:
  /// `com.efeardaaric.nool://auth-callback`
  Future<void> resetPassword(String email, {String? redirectTo}) async {
    _assertReady();
    final trimmed = email.trim();
    if (trimmed.isEmpty || !trimmed.contains('@')) {
      throw const AuthException('Geçerli bir e-posta gerekli.');
    }
    try {
      await _auth.resetPasswordForEmail(
        trimmed,
        redirectTo: redirectTo ?? AuthConfig.authRedirectUrl,
      );
    } on AuthException {
      rethrow;
    } catch (e, st) {
      debugPrint('AuthService.resetPassword: $e\n$st');
      throw AuthException('Şifre sıfırlama maili gönderilemedi: $e');
    }
  }

  /// Giriş yapmış kullanıcının hesabına sıfırlama maili gönder.
  Future<void> resetPasswordForCurrentUser({String? redirectTo}) async {
    final mail = email?.trim();
    if (mail == null || mail.isEmpty) {
      throw const AuthException(
        'Hesabında e-posta yok. Sıfırlama maili gönderilemez.',
      );
    }
    await resetPassword(mail, redirectTo: redirectTo);
  }

  /// Recovery deep link sonrası veya ayarlardan yeni şifre kaydet.
  Future<UserResponse> updatePassword(String newPassword) async {
    _assertReady();
    if (newPassword.length < 6) {
      throw const AuthException('Şifre en az 6 karakter olmalı.');
    }
    try {
      final response = await _auth.updateUser(
        UserAttributes(password: newPassword),
      );
      return response;
    } on AuthException {
      rethrow;
    } catch (e, st) {
      debugPrint('AuthService.updatePassword: $e\n$st');
      throw AuthException('Şifre güncellenemedi: $e');
    }
  }

  /// `PASSWORD_RECOVERY` olaylarını dinler (deep link → in-app reset ekranı).
  StreamSubscription<AuthState> listenPasswordRecovery(
    void Function() onRecovery,
  ) {
    return _auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        onRecovery();
      }
    });
  }

  /// Fresh Apple authorization is required before deleting an Apple-linked account.
  Future<void> authorizeAppleAccountDeletion() async {
    _assertReady();
    if (!(currentUser?.identities?.any((i) => i.provider == 'apple') ??
        false)) {
      return;
    }
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: const [AppleIDAuthorizationScopes.email],
    );
    final response = await _supabase.functions.invoke(
      'apple-revoke',
      body: {'authorization_code': credential.authorizationCode},
    );
    if (response.status != 200 ||
        response.data is! Map ||
        response.data['revoked'] != true) {
      throw const AuthException(
          'Apple hesap silme yetkilendirmesi tamamlanamadı.');
    }
  }

  Future<void> signOut() async {
    if (!SupabaseService.instance.isReady) return;
    try {
      final googleSignIn = GoogleSignIn(
        clientId: AuthConfig.googleIosClientId.isEmpty
            ? null
            : AuthConfig.googleIosClientId,
        serverClientId:
            AuthConfig.hasGoogleWebClient ? AuthConfig.googleWebClientId : null,
      );
      await googleSignIn.signOut();
    } catch (e) {
      debugPrint('AuthService.signOut google: $e');
    }
    try {
      await SocialNotificationService.instance.stopWatching();
    } catch (e) {
      debugPrint('AuthService.signOut notifications: $e');
    }
    try {
      await CuriosityTeaserService.instance.cancelScheduled();
    } catch (e) {
      debugPrint('AuthService.signOut curiosity: $e');
    }
    try {
      await _auth.signOut();
    } catch (e, st) {
      debugPrint('AuthService.signOut: $e\n$st');
      throw AuthException('Oturum kapatılamadı: $e');
    }
  }

  /// Push token'ı profiles'a yaz (Firebase hazır + izin varsa).
  void _onSignedIn() {
    unawaited(NotificationService.instance.registerToken());
    unawaited(SocialNotificationService.instance.startWatching());
    unawaited(CuriosityTeaserService.instance.onAppBecameActive());
    unawaited(
      CuriosityTeaserService.instance.syncCuriosityPref(
        SettingsService.instance.curiosityPushOn,
      ),
    );
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
