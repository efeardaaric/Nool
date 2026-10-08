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

/// Recovery deep link sonrası yeni şifre — `AuthService.updatePassword`.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  late final AnimationController _enter;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  bool _busy = false;
  bool _done = false;
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
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService().updatePassword(_passwordCtrl.text);
      if (!mounted) return;
      setState(() => _done = true);
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
            accent: AtmosphereAccent.acid,
            child: NoolScanLines(opacity: 0.03),
          ),
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
                          _done
                              ? s.resetPasswordSuccessTitle
                              : s.resetPasswordTitle,
                          style: GoogleFonts.syne(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: NoolColors.white,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _done
                              ? s.resetPasswordSuccess
                              : s.resetPasswordSubtitle,
                          style: GoogleFonts.syne(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: NoolColors.lavender,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 28),
                        if (_done) ...[
                          BrutalShadow(
                            offset: const Offset(5, 5),
                            child: SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                                child: Text(s.resetPasswordDoneCta),
                              ),
                            ),
                          ),
                        ] else ...[
                          AuthBrutalField(
                            controller: _passwordCtrl,
                            label: s.resetPasswordLabel,
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
                                return s.resetPasswordTooShort;
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          AuthBrutalField(
                            controller: _confirmCtrl,
                            label: s.resetPasswordConfirmLabel,
                            obscureText: _obscure,
                            validator: (v) {
                              if (v != _passwordCtrl.text) {
                                return s.resetPasswordMismatch;
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
                                    : Text(s.resetPasswordCta),
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
