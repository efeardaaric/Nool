import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../icons/nool_icons.dart';
import '../config/app_info.dart';
import '../utils/external_links.dart';
import '../l10n/app_strings.dart';
import '../services/auth_service.dart';
import '../services/curiosity_teaser_service.dart';
import '../services/profile_service.dart';
import '../services/settings_service.dart';
import '../theme/colors.dart';
import '../utils/user_error.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_legal_consent.dart';
import 'change_password_screen.dart';
import 'splash_screen.dart';

/// Dil, oynatma ve hesap ayarları.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static Route<void> route() {
    return noolRoute<void>(page: const SettingsScreen());
  }

  Future<void> _signOut(BuildContext context) async {
    try {
      await AuthService().signOut();
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 420),
          pageBuilder: (_, __, ___) => const SplashScreen(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
        (_) => false,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NoolColors.tangerine,
          content: Text(
            userFacingError(e, context.s),
            style: GoogleFonts.syne(color: NoolColors.ink),
          ),
        ),
      );
    }
  }

  Future<void> _sendResetEmail(BuildContext context) async {
    final s = context.s;
    final auth = AuthService();
    if (!auth.hasEmailIdentity) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NoolColors.tangerine,
          content: Text(
            s.sendResetEmailNoEmail,
            style: GoogleFonts.syne(
              color: NoolColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      return;
    }

    try {
      await auth.resetPasswordForCurrentUser();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NoolColors.acid,
          content: Text(
            s.sendResetEmailDone,
            style: GoogleFonts.syne(
              color: NoolColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NoolColors.tangerine,
          content: Text(
            userFacingError(e, context.s),
            style: GoogleFonts.syne(color: NoolColors.ink),
          ),
        ),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final s = context.s;
    if (!AuthService().isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NoolColors.acid,
          content: Text(
            s.deleteAccountNoSession,
            style: GoogleFonts.syne(
              color: NoolColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NoolColors.night,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: NoolColors.acid, width: 3),
        ),
        title: Text(
          s.deleteAccountWarnTitle,
          style: GoogleFonts.syne(
            color: NoolColors.acid,
            fontWeight: FontWeight.w800,
            fontSize: 22,
          ),
        ),
        content: Text(
          s.deleteAccountWarnBody,
          style: GoogleFonts.syne(
            color: NoolColors.white,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              s.cancel,
              style: GoogleFonts.syne(
                color: NoolColors.lavender,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Material(
            color: NoolColors.tangerine,
            child: InkWell(
              onTap: () => Navigator.pop(ctx, true),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: NoolColors.ink, width: 3),
                ),
                child: Text(
                  s.deleteConfirm,
                  style: GoogleFonts.syne(
                    color: NoolColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await ProfileService().deleteAccount();
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 420),
          pageBuilder: (_, __, ___) => const SplashScreen(),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
        (_) => false,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NoolColors.tangerine,
          content: Text(
            userFacingError(e, context.s),
            style: GoogleFonts.syne(color: NoolColors.ink),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        final str = context.s;
        return Scaffold(
          backgroundColor: NoolColors.night,
          body: NoolAtmosphere(
            accent: AtmosphereAccent.lavender,
            intensity: 0.8,
            child: SafeArea(
              child: ListView(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 28 + bottom),
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const NoolIcon(
                          NoolIconData.back,
                          color: NoolColors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        str.settingsTitle,
                        style: GoogleFonts.syne(
                          color: NoolColors.acid,
                          fontWeight: FontWeight.w800,
                          fontSize: 24,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    str.settingsSubtitle,
                    style: GoogleFonts.syne(
                      color: NoolColors.lavender,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _SectionLabel(str.sectionLanguage),
                  const SizedBox(height: 8),
                  _LanguageCard(
                    selected: settings.languageCode,
                    onSelect: (code) => settings.setLocale(Locale(code)),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    str.languageHint,
                    style: GoogleFonts.syne(
                      color: NoolColors.lavender,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _SectionLabel(str.sectionPlayback),
                  const SizedBox(height: 8),
                  _SettingsTile(
                    title: str.feedSound,
                    subtitle: str.feedSoundHint,
                    trailing: Switch(
                      value: settings.feedSoundOn,
                      activeThumbColor: NoolColors.ink,
                      activeTrackColor: NoolColors.acid,
                      inactiveThumbColor: NoolColors.lavender,
                      inactiveTrackColor: Colors.white24,
                      onChanged: settings.setFeedSoundOn,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SettingsTile(
                    title: str.haptics,
                    subtitle: str.hapticsHint,
                    trailing: Switch(
                      value: settings.hapticsOn,
                      activeThumbColor: NoolColors.ink,
                      activeTrackColor: NoolColors.acid,
                      inactiveThumbColor: NoolColors.lavender,
                      inactiveTrackColor: Colors.white24,
                      onChanged: settings.setHapticsOn,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SettingsTile(
                    title: str.reduceMotion,
                    subtitle: str.reduceMotionHint,
                    trailing: Switch(
                      value: settings.reduceMotion,
                      activeThumbColor: NoolColors.ink,
                      activeTrackColor: NoolColors.acid,
                      inactiveThumbColor: NoolColors.lavender,
                      inactiveTrackColor: Colors.white24,
                      onChanged: settings.setReduceMotion,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _SectionLabel(str.sectionAlerts),
                  const SizedBox(height: 8),
                  _SettingsTile(
                    title: str.curiosityPush,
                    subtitle: str.curiosityPushHint,
                    trailing: Switch(
                      value: settings.curiosityPushOn,
                      activeThumbColor: NoolColors.ink,
                      activeTrackColor: NoolColors.acid,
                      inactiveThumbColor: NoolColors.lavender,
                      inactiveTrackColor: Colors.white24,
                      onChanged: (v) async {
                        await settings.setCuriosityPushOn(v);
                        await CuriosityTeaserService.instance
                            .onCuriosityPrefChanged(v);
                      },
                    ),
                  ),
                  const SizedBox(height: 22),
                  _SectionLabel(str.sectionLegal),
                  const SizedBox(height: 8),
                  _SettingsTile(
                    title: str.termsAndPermissions,
                    subtitle: str.privacyNote,
                    onTap: () => NoolLegalConsent.showTermsSheet(context),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: NoolColors.lavender,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _SettingsTile(
                    title: str.support,
                    subtitle: AppInfo.supportEmail,
                    onTap: () => openExternalLink(
                        context, 'mailto:${AppInfo.supportEmail}'),
                    trailing: const Icon(Icons.mail_outline,
                        color: NoolColors.lavender),
                  ),
                  const SizedBox(height: 8),
                  _SettingsTile(
                    title: str.website,
                    subtitle: AppInfo.websiteUrl,
                    onTap: () => openExternalLink(context, AppInfo.websiteUrl),
                    trailing: const Icon(Icons.open_in_new,
                        color: NoolColors.lavender),
                  ),
                  const SizedBox(height: 8),
                  _SettingsTile(
                    title: str.privacyPolicy,
                    onTap: () => openExternalLink(context, AppInfo.privacyUrl),
                    trailing: const Icon(Icons.open_in_new,
                        color: NoolColors.lavender),
                  ),
                  const SizedBox(height: 22),
                  if (AuthService().isSignedIn) ...[
                    _SectionLabel(str.sectionPassword),
                    const SizedBox(height: 8),
                    if (!AuthService().hasEmailIdentity)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          str.passwordSocialOnlyHint,
                          style: GoogleFonts.syne(
                            color: NoolColors.lavender,
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ),
                    _SettingsTile(
                      title: str.changePassword,
                      subtitle: str.changePasswordHint,
                      onTap: () => Navigator.of(context).push<void>(
                        ChangePasswordScreen.route(),
                      ),
                      trailing: const Icon(
                        Icons.lock_outline_rounded,
                        color: NoolColors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SettingsTile(
                      title: str.sendResetEmail,
                      subtitle: AuthService().hasEmailIdentity
                          ? str.sendResetEmailHint
                          : str.sendResetEmailNoEmail,
                      onTap: AuthService().hasEmailIdentity
                          ? () => _sendResetEmail(context)
                          : null,
                      trailing: Icon(
                        Icons.mark_email_unread_outlined,
                        color: AuthService().hasEmailIdentity
                            ? NoolColors.white
                            : NoolColors.lavender.withValues(alpha: 0.5),
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],
                  _SectionLabel(str.sectionAccount),
                  const SizedBox(height: 8),
                  if (AuthService().isSignedIn) ...[
                    _SettingsTile(
                      title: str.signOut,
                      onTap: () => _signOut(context),
                      trailing: const Icon(
                        Icons.logout_rounded,
                        color: NoolColors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SettingsTile(
                      title: str.deleteAccount,
                      destructive: true,
                      onTap: () => _confirmDelete(context),
                      trailing: const Icon(
                        Icons.delete_outline_rounded,
                        color: NoolColors.tangerine,
                        size: 20,
                      ),
                    ),
                  ] else
                    Text(
                      str.loginRequired,
                      style: GoogleFonts.syne(
                        color: NoolColors.lavender,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const SizedBox(height: 28),
                  Text(
                    '${str.versionLabel} 1.0.0',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.syne(
                      color: NoolColors.lavender.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.syne(
        color: NoolColors.acid,
        fontWeight: FontWeight.w800,
        fontSize: 12,
        letterSpacing: 1.1,
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({
    required this.selected,
    required this.onSelect,
  });

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    return Row(
      children: [
        Expanded(
          child: _LangChip(
            label: s.languageTurkish,
            selected: selected == 'tr',
            onTap: () => onSelect('tr'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _LangChip(
            label: s.languageEnglish,
            selected: selected == 'en',
            onTap: () => onSelect('en'),
          ),
        ),
      ],
    );
  }
}

class _LangChip extends StatelessWidget {
  const _LangChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected ? NoolColors.acid : NoolColors.night,
            border: Border.all(
              color: selected ? NoolColors.white : NoolColors.lavender,
              width: 3,
            ),
            boxShadow: const [
              BoxShadow(
                color: NoolColors.ink,
                offset: Offset(3, 3),
                blurRadius: 0,
              ),
            ],
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.syne(
                color: selected ? NoolColors.night : NoolColors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NoolColors.night,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          decoration: BoxDecoration(
            border: Border.all(color: NoolColors.ink, width: 3),
            boxShadow: const [
              BoxShadow(
                color: NoolColors.ink,
                offset: Offset(3, 3),
                blurRadius: 0,
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.syne(
                        color: destructive
                            ? NoolColors.tangerine
                            : NoolColors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        style: GoogleFonts.syne(
                          color: NoolColors.lavender,
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}
