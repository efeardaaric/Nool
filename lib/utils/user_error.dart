import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_strings.dart';

/// Kullanıcıya gösterilecek kısa, lokalize hata metni.
/// Ham Postgrest / Auth / stack trace asla UI’ye çıkmaz.
String userFacingError(Object error, [AppStrings? strings]) {
  final s = strings ?? AppStrings.fromSettings();
  if (error is AuthException) {
    return _authMessage(error.message, s);
  }
  final raw = error.toString();
  final lower = raw.toLowerCase();

  if (lower.contains('nonce')) {
    return s.errorGoogleNonce;
  }
  if (lower.contains('network') ||
      lower.contains('socket') ||
      lower.contains('failed host lookup') ||
      lower.contains('connection')) {
    return s.errorNetwork;
  }
  if (lower.contains('invalid login') ||
      lower.contains('invalid_credentials') ||
      lower.contains('wrong password') ||
      lower.contains('email not confirmed')) {
    return s.errorInvalidCredentials;
  }
  if (lower.contains('user already') || lower.contains('already registered')) {
    return s.errorEmailTaken;
  }
  if (lower.contains('rate limit') || lower.contains('too many')) {
    return s.errorRateLimited;
  }
  if (lower.contains('permission') ||
      lower.contains('row-level security') ||
      lower.contains('42501') ||
      lower.contains('not authorized')) {
    return s.errorPermission;
  }
  if (lower.contains('pgrst') ||
      lower.contains('postgrest') ||
      lower.contains('could not find the function') ||
      lower.contains('schema cache')) {
    return s.errorServerConfig;
  }
  if (lower.contains('storage') || lower.contains('bucket')) {
    return s.errorUpload;
  }
  if (lower.contains('iptal') ||
      lower.contains('cancel') ||
      lower.contains('canceled')) {
    return s.errorCancelled;
  }

  // AuthException message already short & localized sometimes.
  if (error is AuthException && error.message.trim().isNotEmpty) {
    return error.message.trim();
  }

  return s.errorGeneric;
}

String _authMessage(String message, AppStrings s) {
  final lower = message.toLowerCase();
  if (lower.contains('nonce') || lower.contains('skip nonce')) {
    return s.errorGoogleNonce;
  }
  if (lower.contains('invalid login') ||
      lower.contains('invalid_credentials')) {
    return s.errorInvalidCredentials;
  }
  if (lower.contains('already') || lower.contains('registered')) {
    return s.errorEmailTaken;
  }
  if (lower.contains('iptal') || lower.contains('cancel')) {
    return s.errorCancelled;
  }
  if (message.trim().isNotEmpty &&
      !message.contains('Exception') &&
      !message.contains('Error:') &&
      message.length < 160) {
    return message.trim();
  }
  return s.errorGeneric;
}
