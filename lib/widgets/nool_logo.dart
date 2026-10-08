import 'package:flutter/material.dart';

/// Nool marka logosu — asit zemin + deal-with-it smiley.
abstract final class NoolBrand {
  static const logoAsset = 'assets/brand/nool_logo.png';
}

/// Uygulama logosu — splash / hero / header.
class NoolLogoMark extends StatelessWidget {
  const NoolLogoMark({
    super.key,
    this.size = 120,
    this.border = true,
    this.shadow = true,
  });

  final double size;
  final bool border;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      NoolBrand.logoAsset,
      width: size,
      height: size,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.medium,
    );

    Widget child = image;
    if (border) {
      child = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black, width: size >= 80 ? 4 : 3),
        ),
        child: image,
      );
    }

    if (!shadow) return child;

    return Container(
      decoration: const BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black,
            offset: Offset(5, 5),
            blurRadius: 0,
          ),
        ],
      ),
      child: child,
    );
  }
}
