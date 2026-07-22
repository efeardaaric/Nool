/// Google OAuth istemci kimlikleri (dart-define).
///
/// ```
/// flutter run \
///   --dart-define=GOOGLE_WEB_CLIENT_ID=xxx.apps.googleusercontent.com \
///   --dart-define=GOOGLE_IOS_CLIENT_ID=xxx.apps.googleusercontent.com
/// ```
abstract final class AuthConfig {
  /// Google Cloud Console → Web client ID (Supabase Google provider + Android).
  static const googleWebClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  /// Google Cloud Console → iOS client ID.
  static const googleIosClientId = String.fromEnvironment(
    'GOOGLE_IOS_CLIENT_ID',
    defaultValue: '',
  );

  static bool get hasGoogleWebClient => googleWebClientId.isNotEmpty;
}
