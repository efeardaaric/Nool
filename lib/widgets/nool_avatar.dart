import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../icons/nool_icons.dart';
import '../theme/colors.dart';

/// Dairesel profil fotoğrafı — her zaman [BoxFit.cover] ile daireyi doldurur.
///
/// Dikdörtgen görseller letterbox yapmaz; taşan kısım ClipOval ile kesilir.
class NoolAvatar extends StatelessWidget {
  const NoolAvatar({
    super.key,
    required this.size,
    this.imageUrl,
    this.localFile,
    this.borderWidth = 2.5,
    this.borderColor = NoolColors.acid,
    this.showShadow = false,
    this.fallbackInitial,
    this.fallbackIconSize,
    this.backgroundColor,
  });

  final double size;
  final String? imageUrl;
  final File? localFile;
  final double borderWidth;
  final Color borderColor;
  final bool showShadow;

  /// Varsa harf fallback (feed / arama); yoksa person ikonu.
  final String? fallbackInitial;
  final double? fallbackIconSize;
  final Color? backgroundColor;

  bool get _hasImage {
    if (localFile != null) return true;
    final url = imageUrl;
    return url != null && url.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final inner = (size - borderWidth * 2).clamp(1.0, size);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: borderWidth),
        boxShadow: showShadow
            ? const [
                BoxShadow(
                  color: NoolColors.ink,
                  offset: Offset(3, 3),
                  blurRadius: 0,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: ClipOval(
        child: SizedBox(
          width: inner,
          height: inner,
          child: _hasImage ? _buildPhoto(inner) : _buildFallback(inner),
        ),
      ),
    );
  }

  Widget _buildPhoto(double inner) {
    final file = localFile;
    if (file != null) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        width: inner,
        height: inner,
        alignment: Alignment.center,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => _buildFallback(inner),
      );
    }

    return Image.network(
      imageUrl!.trim(),
      fit: BoxFit.cover,
      width: inner,
      height: inner,
      alignment: Alignment.center,
      gaplessPlayback: true,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => _buildFallback(inner),
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return ColoredBox(
          color: backgroundColor ?? NoolColors.night,
          child: Center(
            child: SizedBox(
              width: inner * 0.28,
              height: inner * 0.28,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: NoolColors.acid.withValues(alpha: 0.7),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFallback(double inner) {
    final initial = fallbackInitial?.trim();
    if (initial != null && initial.isNotEmpty) {
      final cleaned = initial.replaceFirst('@', '');
      final letter =
          cleaned.isEmpty ? '?' : cleaned.substring(0, 1).toUpperCase();
      return ColoredBox(
        color: backgroundColor ?? NoolColors.acid,
        child: Center(
          child: Text(
            letter,
            style: GoogleFonts.syne(
              color: NoolColors.ink,
              fontWeight: FontWeight.w800,
              fontSize: inner * 0.42,
              height: 1,
            ),
          ),
        ),
      );
    }

    final iconSize = fallbackIconSize ?? (inner * 0.45);
    return ColoredBox(
      color: (backgroundColor ?? NoolColors.acid).withValues(alpha: 0.22),
      child: Center(
        child: NoolIcon(
          NoolIconData.person,
          color: NoolColors.acid,
          size: iconSize,
        ),
      ),
    );
  }
}
