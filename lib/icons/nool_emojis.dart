import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/colors.dart';

/// Neubrutalism emoji set
/// ([Figma — Neubrutalism Icons Set](https://www.figma.com/design/s1Yp3KIweiUzgXdmMApAQR/Neubrutalism-Icons-Set--Community-?node-id=412-41)).
///
/// Kalın ink stroke + `currentColor` dolgu. Metinde [token] ile taşınır.
enum NoolEmojiData {
  cool('😎', 'cool', NoolColors.acid),
  fire('🔥', 'fire', NoolColors.tangerine),
  heart('❤', 'heart', Color(0xFFFF2D55)),
  laugh('😂', 'laugh', NoolColors.acid),
  wow('😮', 'wow', NoolColors.lavender),
  dead('😵', 'dead', NoolColors.tangerine),
  party('⭐', 'party', NoolColors.acid),
  bolt('⚡', 'bolt', NoolColors.acid),
  skull('💀', 'skull', NoolColors.lavender),
  cry('😭', 'cry', Color(0xFF6EC8FF));

  const NoolEmojiData(this.token, this.assetName, this.tint);

  /// Yorum / reaksiyon metninde saklanan unicode anahtar.
  final String token;
  final String assetName;
  final Color tint;

  String get assetPath => 'assets/emojis/$assetName.svg';

  static NoolEmojiData? fromToken(String token) {
    for (final e in NoolEmojiData.values) {
      if (e.token == token) return e;
    }
    return null;
  }

  /// Composer / reaction bar için sabit sıra.
  static const picker = <NoolEmojiData>[
    NoolEmojiData.cool,
    NoolEmojiData.fire,
    NoolEmojiData.heart,
    NoolEmojiData.laugh,
    NoolEmojiData.wow,
    NoolEmojiData.dead,
    NoolEmojiData.party,
    NoolEmojiData.bolt,
    NoolEmojiData.skull,
    NoolEmojiData.cry,
  ];
}

/// Tek neo-brutal emoji.
class NoolEmoji extends StatelessWidget {
  const NoolEmoji(
    this.emoji, {
    super.key,
    this.size = 28,
    this.color,
    this.withBrutalShadow = false,
  });

  final NoolEmojiData emoji;
  final double size;
  final Color? color;
  final bool withBrutalShadow;

  @override
  Widget build(BuildContext context) {
    final tint = color ?? emoji.tint;
    final picture = SvgPicture.asset(
      emoji.assetPath,
      width: size,
      height: size,
      theme: SvgTheme(currentColor: tint),
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
            emoji.assetPath,
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

/// Yatay emoji picker — yorum / reaction.
class NoolEmojiPicker extends StatelessWidget {
  const NoolEmojiPicker({
    super.key,
    required this.onSelected,
    this.size = 32,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
  });

  final ValueChanged<NoolEmojiData> onSelected;
  final double size;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: size + 20,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: NoolEmojiData.picker.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final emoji = NoolEmojiData.picker[index];
          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onSelected(emoji);
            },
            child: Container(
              width: size + 10,
              height: size + 10,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: NoolColors.night,
                border: Border.all(color: NoolColors.ink, width: 2.5),
                boxShadow: const [
                  BoxShadow(
                    color: NoolColors.ink,
                    offset: Offset(2, 2),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: NoolEmoji(emoji, size: size),
            ),
          );
        },
      ),
    );
  }
}

/// Metindeki emoji token’larını SVG ile çizen rich satır.
class NoolEmojiText extends StatelessWidget {
  const NoolEmojiText(
    this.text, {
    super.key,
    this.style,
    this.emojiSize = 18,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.textAlign,
  });

  final String text;
  final TextStyle? style;
  final double emojiSize;
  final int? maxLines;
  final TextOverflow overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final pattern = RegExp(
      NoolEmojiData.values.map((e) => RegExp.escape(e.token)).join('|'),
    );
    final spans = <InlineSpan>[];
    var start = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > start) {
        spans.add(
            TextSpan(text: text.substring(start, match.start), style: style));
      }
      final emoji = NoolEmojiData.fromToken(match.group(0)!);
      if (emoji != null) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: NoolEmoji(emoji, size: emojiSize),
            ),
          ),
        );
      } else {
        spans.add(TextSpan(text: match.group(0), style: style));
      }
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: style));
    }

    return Text.rich(
      TextSpan(
        children: spans.isEmpty ? [TextSpan(text: text, style: style)] : spans,
      ),
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign ?? TextAlign.start,
    );
  }
}

/// DB `reaction_type` keys for feed reactions.
abstract final class NoolReactionTypes {
  static const laugh = 'laugh';
  static const pepper = 'pepper';
  static const smile = 'smile';
  static const angry = 'angry';
  static const star = 'star';

  static const all = <String>[laugh, pepper, smile, angry, star];

  /// Visual mapping onto existing neo-brutal emoji assets.
  static NoolEmojiData emojiFor(String type) {
    switch (type) {
      case pepper:
        return NoolEmojiData.fire;
      case smile:
        return NoolEmojiData.cool;
      case angry:
        return NoolEmojiData.dead;
      case star:
        return NoolEmojiData.party;
      case laugh:
      default:
        return NoolEmojiData.laugh;
    }
  }
}

/// Quick reaction chip strip (feed).
class NoolReactionBar extends StatelessWidget {
  const NoolReactionBar({
    super.key,
    required this.selected,
    required this.counts,
    required this.onReact,
  });

  /// Currently selected `reaction_type` key (or null).
  final String? selected;

  /// Counts keyed by `reaction_type` (laugh / pepper / smile / angry / star).
  final Map<String, int> counts;
  final ValueChanged<String> onReact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final type in NoolReactionTypes.all) ...[
          _ReactionChip(
            emoji: NoolReactionTypes.emojiFor(type),
            count: counts[type] ?? 0,
            selected: selected == type,
            onTap: () => onReact(type),
          ),
          const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.emoji,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final NoolEmojiData emoji;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color:
              selected ? NoolColors.acid : Colors.black.withValues(alpha: 0.45),
          border: Border.all(color: NoolColors.ink, width: 2),
          boxShadow: selected
              ? const [
                  BoxShadow(
                    color: NoolColors.ink,
                    offset: Offset(2, 2),
                    blurRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            NoolEmoji(
              emoji,
              size: 18,
              color: selected ? NoolColors.ink : emoji.tint,
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  color: selected ? NoolColors.ink : NoolColors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
