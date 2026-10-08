import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_strings.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../utils/user_error.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_logo.dart';
import 'sign_in_screen.dart';

/// Neo-brutalist şifre sıfırlama — e-posta → Supabase reset maili.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late final AnimationController _enter;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final seed = widget.initialEmail?.trim();
    if (seed != null && seed.isNotEmpty) {
      _emailCtrl.text = seed;
    }
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    )..forward();
    _fade = CurvedAnimation(parent: _enter, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _enter.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService().resetPassword(_emailCtrl.text);
      if (!mounted) return;
      setState(() => _sent = true);
    } catch (e) {
      if (mounted) setState(() => _error = userFacingError(e, context.s));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const NoolAtmosphere(
            accent: AtmosphereAccent.tangerine,
            child: NoolScanLines(opacity: 0.03),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(24, 16, 24, 28 + bottomInset),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: IconButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(
                              Icons.arrow_back,
                              color: NoolColors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const NoolLogoMark(
                            size: 64, border: true, shadow: true),
                        const SizedBox(height: 18),
                        Text(
                          'NOOL',
                          style: GoogleFonts.syne(
                            fontSize: 42,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.6,
                            color: NoolColors.acid,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _sent
                              ? s.forgotPasswordSuccessTitle
                              : s.forgotPasswordTitle,
                          style: GoogleFonts.syne(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: NoolColors.white,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _sent
                              ? s.forgotPasswordSuccessBody
                              : s.forgotPasswordSubtitle,
                          style: GoogleFonts.syne(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: NoolColors.lavender,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 28),
                        if (_sent) ...[
                          BrutalShadow(
                            offset: const Offset(5, 5),
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: NoolColors.acid,
                                border: Border.all(
                                  color: NoolColors.ink,
                                  width: 3,
                                ),
                              ),
                              child: Text(
                                _emailCtrl.text.trim(),
                                style: GoogleFonts.syne(
                                  color: NoolColors.ink,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          BrutalShadow(
                            offset: const Offset(5, 5),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                                child: Text(s.forgotPasswordBackToSignIn),
                              ),
                            ),
                          ),
                        ] else ...[
                          AuthBrutalField(
                            controller: _emailCtrl,
                            label: s.forgotPasswordEmailHint,
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return s.forgotPasswordNeedEmail;
                              }
                              if (!v.contains('@')) {
                                return s.forgotPasswordInvalidEmail;
                              }
                              return null;
                            },
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: GoogleFonts.syne(
                                color: NoolColors.tangerine,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          BrutalShadow(
                            offset: const Offset(5, 5),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _busy ? null : _submit,
                                child: _busy
                                    ? const AuthAcidLoader()
                                    : Text(s.forgotPasswordCta),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
