import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/colors.dart';
import 'nool_chrome.dart';

/// Neo-brutal chat input bar.
///
/// Pair with [Scaffold.resizeToAvoidBottomInset] `true` and do **not** also
/// pad with [MediaQuery.viewInsets] — Scaffold already shrinks the body.
class NoolChatComposer extends StatelessWidget {
  const NoolChatComposer({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onSend,
    this.sending = false,
    this.trailing = const [],
  });

  final TextEditingController controller;
  final String hintText;
  final VoidCallback? onSend;
  final bool sending;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    // When keyboard is open, Scaffold has already lifted the body; bottom
    // padding is typically 0. When closed, keep home-indicator clearance.
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return Padding(
      // Extra 4px bottom/right so BrutalPressable ink shadows aren't clipped.
      padding: EdgeInsets.fromLTRB(12, 8, 12, safeBottom + 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: ClipRRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  decoration: BoxDecoration(
                    color: NoolColors.night.withValues(alpha: 0.65),
                    border: Border.all(color: NoolColors.ink, width: 3),
                  ),
                  child: TextField(
                    controller: controller,
                    maxLines: 4,
                    minLines: 1,
                    style: GoogleFonts.syne(
                      color: NoolColors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      height: 1.25,
                    ),
                    cursorColor: NoolColors.acid,
                    // Keep caret visible without fighting Scaffold resize.
                    scrollPadding: const EdgeInsets.only(bottom: 80),
                    decoration: InputDecoration(
                      hintText: hintText,
                      hintStyle: GoogleFonts.syne(
                        color: NoolColors.lavender,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend?.call(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          BrutalPressable(
            offset: const Offset(2, 2),
            onTap: sending ? null : onSend,
            enabled: !sending,
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: NoolColors.acid,
                border: Border.all(color: NoolColors.ink, width: 3),
              ),
              child: const Icon(
                Icons.send,
                color: NoolColors.ink,
                size: 20,
              ),
            ),
          ),
          for (final action in trailing) ...[
            const SizedBox(width: 8),
            action,
          ],
        ],
      ),
    );
  }
}
