import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_strings.dart';
import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../theme/colors.dart';

/// Neo-brutal sheet: öğrenci e-postasını bağla → campus domain üyeliği.
Future<UserProfile?> showClaimStudentEmailSheet(BuildContext context) {
  return showModalBottomSheet<UserProfile>(
    context: context,
    isScrollControlled: true,
    backgroundColor: NoolColors.night,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(0)),
    ),
    builder: (ctx) => const _ClaimStudentEmailSheet(),
  );
}

class _ClaimStudentEmailSheet extends StatefulWidget {
  const _ClaimStudentEmailSheet();

  @override
  State<_ClaimStudentEmailSheet> createState() =>
      _ClaimStudentEmailSheetState();
}

class _ClaimStudentEmailSheetState extends State<_ClaimStudentEmailSheet> {
  late final TextEditingController _emailCtrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final authEmail = AuthService().email?.trim() ?? '';
    _emailCtrl = TextEditingController(text: authEmail);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = context.s;
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      setState(() => _error = s.campusEmailInvalid);
      return;
    }
    if (!AuthService().isSignedIn) {
      setState(() => _error = s.campusEmailSignInRequired);
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final profile = await ProfileService().claimStudentEmail(email);
      if (!mounted) return;
      Navigator.of(context).pop(profile);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = s.campusEmailClaimFailed;
      });
      debugPrint('claimStudentEmail sheet: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: NoolColors.lavender.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Nool',
            style: GoogleFonts.syne(
              color: NoolColors.acid,
              fontWeight: FontWeight.w800,
              fontSize: 28,
              height: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.campusClaimTitle,
            style: GoogleFonts.syne(
              color: NoolColors.white,
              fontWeight: FontWeight.w800,
              fontSize: 22,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            s.campusClaimBody,
            style: GoogleFonts.syne(
              color: NoolColors.lavender,
              fontWeight: FontWeight.w500,
              fontSize: 14,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            decoration: BoxDecoration(
              color: NoolColors.night,
              border: Border.all(color: NoolColors.ink, width: 3),
              boxShadow: const [
                BoxShadow(
                  color: NoolColors.ink,
                  offset: Offset(3, 3),
                  blurRadius: 0,
                ),
              ],
            ),
            child: TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              enabled: !_saving,
              style: GoogleFonts.syne(
                color: NoolColors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
              cursorColor: NoolColors.acid,
              decoration: InputDecoration(
                hintText: s.campusEmailHint,
                hintStyle: GoogleFonts.syne(
                  color: NoolColors.lavender,
                  fontWeight: FontWeight.w500,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: GoogleFonts.syne(
                color: NoolColors.tangerine,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            s.campusEmailVerifyNote,
            style: GoogleFonts.syne(
              color: NoolColors.lavender.withValues(alpha: 0.85),
              fontWeight: FontWeight.w500,
              fontSize: 12,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: NoolColors.white,
                    side: const BorderSide(color: NoolColors.ink, width: 3),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    s.cancel,
                    style: GoogleFonts.syne(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Container(
                  decoration: const BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: NoolColors.ink,
                        offset: Offset(4, 4),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                  child: Material(
                    color: NoolColors.acid,
                    child: InkWell(
                      onTap: _saving ? null : _submit,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: NoolColors.ink,
                            width: 3.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: NoolColors.ink,
                                ),
                              )
                            : Text(
                                s.campusClaimCta,
                                style: GoogleFonts.syne(
                                  color: NoolColors.ink,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
