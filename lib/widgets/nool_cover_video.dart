import 'package:cached_video_player_plus/cached_video_player_plus.dart';
import 'package:flutter/material.dart';

import '../theme/colors.dart';

/// TikTok-style full-bleed video — [BoxFit.cover] the viewport.
///
/// Uses FittedBox (not OverflowBox) for stable iOS Impeller sizing;
/// overlays sit on top separately and do not shrink this plane.
class NoolCoverVideo extends StatelessWidget {
  const NoolCoverVideo({
    super.key,
    required this.controller,
  });

  final CachedVideoPlayerPlusController controller;

  @override
  Widget build(BuildContext context) {
    final size = controller.value.size;
    if (!controller.value.isInitialized ||
        size.width <= 0 ||
        size.height <= 0) {
      return const ColoredBox(color: NoolColors.night);
    }

    return ColoredBox(
      color: NoolColors.night,
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: CachedVideoPlayerPlus(controller),
          ),
        ),
      ),
    );
  }
}
