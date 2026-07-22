import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/colors.dart';

/// Neubrutalism tarzı ikon seti
/// ([Figma Community — Neubrutalism Icons Set](https://www.figma.com/design/s1Yp3KIweiUzgXdmMApAQR/Neubrutalism-Icons-Set--Community-)).
///
/// Kalın siyah stroke + `currentColor` dolgu; [color] yalnızca dolguyu boyar.
enum NoolIconData {
  home,
  homeOutline,
  camera,
  cameraOutline,
  fire,
  fireOutline,
  heart,
  heartOutline,
  comment,
  send,
  person,
  personOutline,
  search,
  flag,
  close,
  add,
  play,
  flash,
  flashOff,
  flipCamera,
  back,
  music,
  more,
  stop,
  record,
}

extension NoolIconDataX on NoolIconData {
  String get assetPath {
    const root = 'assets/icons';
    switch (this) {
      case NoolIconData.home:
        return '$root/home.svg';
      case NoolIconData.homeOutline:
        return '$root/home_outline.svg';
      case NoolIconData.camera:
        return '$root/camera.svg';
      case NoolIconData.cameraOutline:
        return '$root/camera_outline.svg';
      case NoolIconData.fire:
        return '$root/fire.svg';
      case NoolIconData.fireOutline:
        return '$root/fire_outline.svg';
      case NoolIconData.heart:
        return '$root/heart.svg';
      case NoolIconData.heartOutline:
        return '$root/heart_outline.svg';
      case NoolIconData.comment:
        return '$root/comment.svg';
      case NoolIconData.send:
        return '$root/send.svg';
      case NoolIconData.person:
        return '$root/person.svg';
      case NoolIconData.personOutline:
        return '$root/person_outline.svg';
      case NoolIconData.search:
        return '$root/search.svg';
      case NoolIconData.flag:
        return '$root/flag.svg';
      case NoolIconData.close:
        return '$root/close.svg';
      case NoolIconData.add:
        return '$root/add.svg';
      case NoolIconData.play:
        return '$root/play.svg';
      case NoolIconData.flash:
        return '$root/flash.svg';
      case NoolIconData.flashOff:
        return '$root/flash_off.svg';
      case NoolIconData.flipCamera:
        return '$root/flip_camera.svg';
      case NoolIconData.back:
        return '$root/back.svg';
      case NoolIconData.music:
        return '$root/music.svg';
      case NoolIconData.more:
        return '$root/more.svg';
      case NoolIconData.stop:
        return '$root/stop.svg';
      case NoolIconData.record:
        return '$root/record.svg';
    }
  }
}

/// Neo-brutal SVG ikon — asimetrik gölge opsiyonel.
class NoolIcon extends StatelessWidget {
  const NoolIcon(
    this.icon, {
    super.key,
    this.size = 24,
    this.color = NoolColors.acid,
    this.strokeOnly = false,
    this.withBrutalShadow = false,
  });

  final NoolIconData icon;
  final double size;
  final Color color;

  /// Outline ikonlarda dolgu yok; [color] stroke yerine kullanılmaz
  /// (siyah stroke sabit). Bu bayrak yalnızca anlamsal.
  final bool strokeOnly;

  /// Neubrutalism offset gölge (ink).
  final bool withBrutalShadow;

  @override
  Widget build(BuildContext context) {
    final picture = SvgPicture.asset(
      icon.assetPath,
      width: size,
      height: size,
      theme: SvgTheme(currentColor: color),
      fit: BoxFit.contain,
    );

    if (!withBrutalShadow) return picture;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 2,
          top: 2,
          child: SvgPicture.asset(
            icon.assetPath,
            width: size,
            height: size,
            theme: const SvgTheme(currentColor: NoolColors.ink),
            fit: BoxFit.contain,
          ),
        ),
        picture,
      ],
    );
  }
}
