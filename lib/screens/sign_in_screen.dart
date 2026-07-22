import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';
import '../theme/colors.dart';
import '../widgets/nool_chrome.dart';
import '../widgets/nool_logo.dart';
import '../widgets/nool_lottie.dart';
import 'layout_manager.dart';
import 'sign_up_screen.dart';

/// Neo-brutalist Giriş Yap — Google / Apple / e-posta.
class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    this.popOnSuccess = false,
  });

  /// Shell içinden açıldıysa true — LayoutManager'a replace etmez, pop eder.
  final bool popOnSuccess;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen>
    with SingleTickerProviderStateMixin {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
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
    super.dispose();
  }

  Future<void> _goHome() async {
    if (widget.popOnSuccess) {
      if (!mounted) return;
      Navigator.of(context).pop(true);
      return;
    }

    final username =
        AuthService().displayName ??
        await OnboardingService.getUsername() ??
        '@anon_kayip_kaos';
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      noolRoute<void>(
        page: LayoutManager(username: username),
        duration: const Duration(milliseconds: 480),
      ),
    );
  }

  Future<void> _runSocial(Future<void> Function() action, {required bool google}) async {
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

  Future<void> _signInEmail() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busyEmail = true;
      _error = null;
    });
    try {
      await AuthService().signInWithEmail(
        email: _emailCtrl.text,
        password: _passwordCtrl.text,
      );
      await _goHome();
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busyEmail = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Şifre sıfırlamak için önce e-postanı yaz.');
      return;
    }
    try {
      await AuthService().resetPassword(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: NoolColors.acid,
          content: Text(
            'Sıfırlama linki yolda — mailini check et.',
            style: GoogleFonts.syne(
              color: NoolColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
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
          const _AuthAtmosphere(),
          SafeArea(
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(24, 28, 24, 28 + bottomInset),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
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
                          'Giriş Yap',
                          style: GoogleFonts.syne(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: NoolColors.white,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tek tıkla kampüse bağlan. FaceID veya Google — form doldurma yok.',
                          style: GoogleFonts.syne(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: NoolColors.lavender,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 28),
                        AuthSocialButton(
                          label: 'Google ile devam et',
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
                          label: 'Apple ile devam et',
                          background: NoolColors.white,
                          foreground: NoolColors.ink,
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
                        const _AuthDivider(label: 'veya e-posta'),
                        const SizedBox(height: 20),
                        AuthBrutalField(
                          controller: _emailCtrl,
                          label: 'E-posta',
                          keyboardType: TextInputType.emailAddress,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'E-posta lazım';
                            }
                            if (!v.contains('@')) return 'Geçerli bir e-posta yaz';
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
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _forgotPassword,
                            child: Text(
                              'Şifremi unuttum',
                              style: GoogleFonts.syne(
                                color: NoolColors.lavender,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            _error!,
                            style: GoogleFonts.syne(
                              color: NoolColors.tangerine,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                        BrutalShadow(
                          offset: const Offset(5, 5),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _busyEmail || _busyGoogle || _busyApple
                                  ? null
                                  : _signInEmail,
                              child: _busyEmail
                                  ? const AuthAcidLoader()
                                  : const Text('GİRİŞ YAP'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextButton(
                          onPressed: () async {
                            final ok = await Navigator.of(context).push<bool>(
                              MaterialPageRoute<bool>(
                                builder: (_) => SignUpScreen(
                                  popOnSuccess: widget.popOnSuccess,
                                ),
                              ),
                            );
                            if (!mounted) return;
                            if (ok == true && widget.popOnSuccess) {
                              Navigator.of(this.context).pop(true);
                            }
                          },
                          child: Text.rich(
                            TextSpan(
                              style: GoogleFonts.syne(
                                color: NoolColors.lavender,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                              children: [
                                const TextSpan(text: 'Hesabın yok mu? '),
                                TextSpan(
                                  text: 'Hemen Kayıt Ol',
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

/// Kozmik night zemin + asit / tangerine glow.
class _AuthAtmosphere extends StatelessWidget {
  const _AuthAtmosphere();

  @override
  Widget build(BuildContext context) {
    return const NoolAtmosphere(
      accent: AtmosphereAccent.acid,
      child: NoolScanLines(opacity: 0.03),
    );
  }
}

class _AuthDivider extends StatelessWidget {
  const _AuthDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Container(height: 3, color: NoolColors.ink)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: GoogleFonts.syne(
              color: NoolColors.lavender,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
        Expanded(child: Container(height: 3, color: NoolColors.ink)),
      ],
    );
  }
}

/// Kalın siyah çerçeve + sert gölge sosyal CTA.
class AuthSocialButton extends StatelessWidget {
  const AuthSocialButton({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    required this.icon,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return BrutalShadow(
      offset: const Offset(5, 5),
      child: Material(
        color: background,
        child: InkWell(
          onTap: loading ? null : onPressed,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            decoration: BoxDecoration(
              border: Border.all(color: NoolColors.ink, width: 3),
            ),
            child: loading
                ? const Center(child: AuthAcidLoader())
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: foreground, size: 28),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          label,
                          style: GoogleFonts.syne(
                            color: foreground,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Glass tint + ink border TextField.
class AuthBrutalField extends StatelessWidget {
  const AuthBrutalField({
    super.key,
    required this.controller,
    required this.label,
    this.obscureText = false,
    this.keyboardType,
    this.validator,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return BrutalShadow(
      offset: const Offset(4, 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: TextFormField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            validator: validator,
            style: GoogleFonts.syne(
              color: NoolColors.white,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              labelText: label,
              labelStyle: GoogleFonts.syne(color: NoolColors.lavender),
              filled: true,
              fillColor: NoolColors.lavender.withOpacity(0.12),
              suffixIcon: suffix,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(2),
                borderSide: const BorderSide(color: NoolColors.ink, width: 3),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(2),
                borderSide: const BorderSide(color: NoolColors.acid, width: 3),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(2),
                borderSide: const BorderSide(
                  color: NoolColors.tangerine,
                  width: 3,
                ),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(2),
                borderSide: const BorderSide(
                  color: NoolColors.tangerine,
                  width: 3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Asimetrik asit yeşili yükleniyor — Lottie neon loader.
class AuthAcidLoader extends StatelessWidget {
  const AuthAcidLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return const NoolLottieView.loading(width: 36, height: 36, compact: true);
  }
}
