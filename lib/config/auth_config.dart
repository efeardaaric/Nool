/// Google OAuth + auth deep-link kimlikleri (dart-define ile override edilebilir).
///
/// Google Client Secret uygulamaya konmaz — yalnızca Supabase Dashboard
/// → Authentication → Providers → Google.
///
/// ```
/// flutter run \
///   --dart-define=GOOGLE_WEB_CLIENT_ID=xxx.apps.googleusercontent.com \
///   --dart-define=GOOGLE_IOS_CLIENT_ID=xxx.apps.googleusercontent.com
/// ```
///
/// ## Supabase Dashboard — Google provider
/// Client IDs: Web + iOS (+ isteğe bağlı Android), hepsi aynı alana.
/// Client Secret: yalnızca Web client secret.
///
/// ## Supabase Dashboard — şifre sıfırlama Redirect URLs
///
/// Authentication → URL Configuration:
/// 1. **Redirect URLs** listesine ekle:
///    `com.efeardaaric.nool://auth-callback`
/// 2. (İsteğe bağlı) Site URL aynı kalabilir; mobil reset
///    `resetPasswordForEmail(redirectTo:)` bu scheme’i kullanır.
/// 3. Auth → Email Templates → Reset Password: link’in `{{ .RedirectTo }}`
///    / `{{ .ConfirmationURL }}` kullandığından emin ol.
/// 4. iOS: Info.plist `CFBundleURLSchemes` = `com.efeardaaric.nool` +
///    reversed Google iOS client ID
///    Android: intent-filter scheme+host = `com.efeardaaric.nool` /
///    `auth-callback`
abstract final class AuthConfig {
  /// Google Cloud Console → Web client ID (Supabase Google provider + serverClientId).
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue:
        '936286160448-2lijge7gf7krhb91dkjvgkmrfic402hb.apps.googleusercontent.com',
  );

  /// Google Cloud Console → iOS client ID.
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue:
        '936286160448-pkimuueo2v1dbmvlfbefnnb8tnb6k7s7.apps.googleusercontent.com',
  );

  /// Google Cloud Console → Android client ID (dashboard referansı; native SDK package+SHA ile eşleşir).
  static const googleAndroidClientId = String.fromEnvironment(
    'GOOGLE_ANDROID_CLIENT_ID',
    defaultValue:
        '936286160448-4duccrcaq5t5iufnegn7q88lfjsi65vh.apps.googleusercontent.com',
  );

  static bool get hasGoogleWebClient => googleWebClientId.isNotEmpty;

  /// Custom URL scheme (Info.plist / AndroidManifest ile aynı olmalı).
  static const authUrlScheme = 'com.efeardaaric.nool';

  /// Şifre sıfırlama / OAuth dönüş host’u.
  static const authCallbackHost = 'auth-callback';

  /// Supabase Dashboard → Authentication → URL Configuration → Redirect URLs
  /// listesine eklenmeli: `com.efeardaaric.nool://auth-callback`
  static String get authRedirectUrl => '$authUrlScheme://$authCallbackHost';
}
