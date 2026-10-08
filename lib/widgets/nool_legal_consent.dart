import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_strings.dart';
import '../config/app_info.dart';
import '../utils/external_links.dart';
import '../theme/colors.dart';

/// Kayıt sırasında zorunlu hukuki / izin onayı.
class NoolLegalConsent extends StatelessWidget {
  const NoolLegalConsent({
    super.key,
    required this.accepted,
    required this.onChanged,
  });

  final bool accepted;
  final ValueChanged<bool> onChanged;

  static Future<void> showTermsSheet(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _LegalTermsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.s;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Checkbox(
              value: accepted,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: NoolColors.acid,
              checkColor: NoolColors.ink,
              side: const BorderSide(color: NoolColors.lavender, width: 2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(!accepted),
              child: Text.rich(
                TextSpan(
                  style: GoogleFonts.syne(
                    color: NoolColors.lavender,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    height: 1.35,
                  ),
                  children: [
                    TextSpan(text: s.legalCheckboxPrefix),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: GestureDetector(
                        onTap: () => showTermsSheet(context),
                        child: Text(
                          s.legalRead,
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
                    TextSpan(text: s.legalAnd),
                    TextSpan(
                      text: s.legalApproved,
                      style: GoogleFonts.syne(
                        color: NoolColors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalTermsSheet extends StatelessWidget {
  const _LegalTermsSheet();

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final bottom = MediaQuery.paddingOf(context).bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: NoolColors.night,
            border: Border.all(color: NoolColors.ink, width: 3),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                color: NoolColors.lavender,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    s.termsTitle,
                    style: GoogleFonts.syne(
                      color: NoolColors.acid,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + bottom),
                  children: [
                    Text(
                      s.termsIntro,
                      style: GoogleFonts.syne(
                        color: NoolColors.lavender,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () =>
                          openExternalLink(context, AppInfo.privacyUrl),
                      child: Text(s.privacyPolicy),
                    ),
                    TextButton(
                      onPressed: () =>
                          openExternalLink(context, AppInfo.termsUrl),
                      child: Text(s.termsTitle),
                    ),
                    for (final section in s.legalSections) ...[
                      Text(
                        section.title,
                        style: GoogleFonts.syne(
                          color: NoolColors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        section.body,
                        style: GoogleFonts.syne(
                          color: NoolColors.lavender,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Material(
                      color: NoolColors.acid,
                      child: InkWell(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border.all(color: NoolColors.ink, width: 3),
                          ),
                          child: Text(
                            s.understood,
                            style: GoogleFonts.syne(
                              color: NoolColors.ink,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
