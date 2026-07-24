import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_logo.dart';
import 'location_gate_screen.dart';
import 'sign_in_screen.dart';

/// Neo-brutalist Kayıt Ol — Google / Apple / e-posta.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({
    super.key,
    this.popOnSuccess = false,
    this.gateMode = false,
  });

  final bool popOnSuccess;
  final bool gateMode;

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
  String? _error;

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

    if (!mounted) return;
    await Navigator.of(context).pushAndRemoveUntil(
      noolRoute<void>(
        page: const LocationGateScreen(),
        duration: const Duration(milliseconds: 480),
      ),
      (_) => false,
    );
  }

  Future<void> _runSocial(
    Future<void> Function() action, {
    required bool google,
  }) async {
    setState(() {
      _error = null;
      if (google) {
        _busyGoogle = true;
      } else {
        _busyApple = true;
      }
    });
    try {
      await action();
      await _goHome();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
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
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busyEmail = true;
      _error = null;
    });
    try {
      final res = await AuthService().signUpWithEmail(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
      );
      if (res.session == null && res.user != null) {
        if (!mounted) return;
        setState(() {
          _error =
              'Mailini doğrula — sonra Giriş Yap ile içeri sız. '
              '(Supabase e-posta onayı açıksa)';
        });
        return;
      }
      await _goHome();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busyEmail = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return PopScope(
      canPop: !widget.gateMode,
      child: Scaffold(
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
                        const NoolLogoMark(size: 72, border: true, shadow: true),
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
                          'Kayıt Ol',
                          style: GoogleFonts.syne(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: NoolColors.white,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Hesabını güvenceye al — kaos kalıcı olsun.',
                          style: GoogleFonts.syne(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: NoolColors.lavender,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 28),
                        AuthSocialButton(
                          label: 'Google ile kayıt ol',
                          background: NoolColors.acid,
                          foreground: NoolColors.ink,
                          icon: Icons.g_mobiledata_rounded,
                          loading: _busyGoogle,
                          onPressed: (_busyGoogle || _busyApple || _busyEmail)
                              ? null
                              : () => _runSocial(
                                    () async {
                                      await AuthService().signInWithGoogle();
                                    },
                                    google: true,
                                  ),
                        ),
                        const SizedBox(height: 12),
                        AuthSocialButton(
                          label: 'Apple ile kayıt ol',
                          background: NoolColors.ink,
                          foreground: NoolColors.white,
                          icon: Icons.apple,
                          loading: _busyApple,
                          onPressed: (_busyGoogle || _busyApple || _busyEmail)
                              ? null
                              : () => _runSocial(
                                    () async {
                                      await AuthService().signInWithApple();
                                    },
                                    google: false,
                                  ),
                        ),
                        const SizedBox(height: 28),
                        Row(
                          children: [
                            Expanded(
                              child: Container(height: 3, color: NoolColors.ink),
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'veya e-posta',
                                style: GoogleFonts.syne(
                                  color: NoolColors.lavender,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Container(height: 3, color: NoolColors.ink),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        AuthBrutalField(
                          controller: _emailCtrl,
                          label: 'E-posta',
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'E-posta lazım';
                            }
                            if (!v.contains('@')) {
                              return 'Geçerli bir e-posta yaz';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        AuthBrutalField(
                          controller: _passwordCtrl,
                          label: 'Şifre',
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
                              return 'En az 6 karakter';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        AuthBrutalField(
                          controller: _confirmCtrl,
                          label: 'Şifre tekrar',
                          obscureText: _obscure,
                          validator: (v) {
                            if (v != _passwordCtrl.text) {
                              return 'Şifreler uyuşmuyor';
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
                              onPressed: _busyEmail || _busyGoogle || _busyApple
                                  ? null
                                  : _signUpEmail,
                              child: _busyEmail
                                  ? const AuthAcidLoader()
                                  : const Text('KAYIT OL'),
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
                                  gateMode: widget.gateMode,
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
    ),
    );
  }
}
