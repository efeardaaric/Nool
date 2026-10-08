import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_strings.dart';
import '../services/auth_service.dart';
import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../utils/user_error.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_legal_consent.dart';
import '../widgets/nool_logo.dart';
import 'layout_manager.dart';
import 'sign_in_screen.dart';

/// Neo-brutalist Kayıt Ol — Google / Apple / e-posta.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({
    super.key,
    this.popOnSuccess = false,
  });

  final bool popOnSuccess;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late final AnimationController _enter;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  bool _busyGoogle = false;
  bool _busyApple = false;
  bool _busyEmail = false;
  bool _obscure = true;
  bool _legalAccepted = false;
  String? _error;

  bool get _busy => _busyGoogle || _busyApple || _busyEmail;

  bool _ensureLegalAccepted() {
    if (_legalAccepted) return true;
    setState(() {
      _error = context.s.legalMustAccept;
    });
    return false;
  }

  Future<void> _persistLegalAcceptance() async {
    await OnboardingService.acceptLegalTerms();
  }

  @override
  void initState() {
    super.initState();
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
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _goHome() async {
    if (widget.popOnSuccess) {
      if (!mounted) return;
      Navigator.of(context).pop(true);
      return;
    }

    final username = AuthService().displayName ??
        await OnboardingService.getUsername() ??
        AppStrings.fromSettings().anonymousHandle;
    if (!mounted) return;
    await Navigator.of(context).pushAndRemoveUntil(
      noolRoute<void>(
        page: LayoutManager(username: username),
        duration: const Duration(milliseconds: 480),
      ),
      (_) => false,
    );
  }

  Future<void> _runSocial(
    Future<void> Function() action, {
    required bool google,
  }) async {
    if (!_ensureLegalAccepted()) return;
    setState(() {
      _error = null;
      if (google) {
        _busyGoogle = true;
      } else {
        _busyApple = true;
      }
    });
    try {
      await _persistLegalAcceptance();
      await action();
      await _goHome();
    } catch (e) {
      if (mounted) setState(() => _error = userFacingError(e, context.s));
    } finally {
      if (mounted) {
        setState(() {
          _busyGoogle = false;
          _busyApple = false;
        });
      }
    }
  }

  Future<void> _signUpEmail() async {
    if (!_ensureLegalAccepted()) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busyEmail = true;
      _error = null;
    });
    try {
      await _persistLegalAcceptance();
      final res = await AuthService().signUpWithEmail(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
      );
      if (res.session == null && res.user != null) {
        if (!mounted) return;
        setState(() {
          _error = context.s.verifyEmailHint;
        });
        return;
      }
      await _goHome();
    } catch (e) {
      if (mounted) setState(() => _error = userFacingError(e, context.s));
    } finally {
      if (mounted) setState(() => _busyEmail = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  padding: EdgeInsets.fromLTRB(24, 20, 24, 28 + bottomInset),
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
                        const NoolLogoMark(
                            size: 72, border: true, shadow: true),
                        const SizedBox(height: 18),
                        Text(
                          'NOOL',
                          style: GoogleFonts.syne(
                            fontSize: 48,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1.8,
                            color: NoolColors.acid,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          context.s.signUp,
                          style: GoogleFonts.syne(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: NoolColors.white,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.s.signUpSubtitle,
                          style: GoogleFonts.syne(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: NoolColors.lavender,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 22),
                        NoolLegalConsent(
                          accepted: _legalAccepted,
                          onChanged: (v) => setState(() {
                            _legalAccepted = v;
                            if (v) _error = null;
                          }),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () =>
                                NoolLegalConsent.showTermsSheet(context),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              context.s.readFullTerms,
                              style: GoogleFonts.syne(
                                color: NoolColors.acid,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                decoration: TextDecoration.underline,
                                decorationColor: NoolColors.acid,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        AuthSocialButton(
                          label: context.s.continueWithGoogle,
                          background: NoolColors.acid,
                          foreground: NoolColors.ink,
                          icon: Icons.g_mobiledata_rounded,
                          loading: _busyGoogle,
                          onPressed: _busy
                              ? null
                              : () => _runSocial(
                                    () async {
                                      await AuthService().signInWithGoogle();
                                    },
                                    google: true,
                                  ),
                        ),
                        const SizedBox(height: 28),
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 3,
                                color: NoolColors.lavender,
                              ),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                context.s.orEmailDivider,
                                style: GoogleFonts.syne(
                                  color: NoolColors.lavender,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Container(
                                height: 3,
                                color: NoolColors.lavender,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        AuthBrutalField(
                          controller: _emailCtrl,
                          label: context.s.emailLabel,
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) {
                            final s = context.s;
                            if (v == null || v.trim().isEmpty) {
                              return s.forgotPasswordNeedEmail;
                            }
                            if (!v.contains('@')) {
                              return s.forgotPasswordInvalidEmail;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        AuthBrutalField(
                          controller: _passwordCtrl,
                          label: context.s.passwordLabel,
                          obscureText: _obscure,
                          suffix: IconButton(
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: NoolColors.lavender,
                            ),
                          ),
                          validator: (v) {
                            if (v == null || v.length < 6) {
                              return context.s.resetPasswordTooShort;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        AuthBrutalField(
                          controller: _confirmCtrl,
                          label: context.s.passwordConfirmLabel,
                          obscureText: _obscure,
                          validator: (v) {
                            if (v != _passwordCtrl.text) {
                              return context.s.resetPasswordMismatch;
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
                        const SizedBox(height: 16),
                        BrutalShadow(
                          offset: const Offset(5, 5),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _busy ? null : _signUpEmail,
                              child: _busyEmail
                                  ? const AuthAcidLoader()
                                  : Text(
                                      _legalAccepted
                                          ? context.s.signUpCta
                                          : context.s.signUpCtaNeedConsent,
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute<void>(
                                builder: (_) => SignInScreen(
                                  popOnSuccess: widget.popOnSuccess,
                                ),
                              ),
                            );
                          },
                          child: Text.rich(
                            TextSpan(
                              style: GoogleFonts.syne(
                                color: NoolColors.lavender,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                              children: [
                                const TextSpan(text: 'Zaten hesabın var mı? '),
                                TextSpan(
                                  text: 'Giriş Yap',
                                  style: GoogleFonts.syne(
                                    color: NoolColors.acid,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
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
