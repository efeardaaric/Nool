// Privacy-safe curiosity / re-engagement copy (TR + EN).

class CuriosityTeaserCopy {
  const CuriosityTeaserCopy({
    required this.kind,
    required this.titleTr,
    required this.bodyTr,
    required this.titleEn,
    required this.bodyEn,
  });

  final String kind;
  final String titleTr;
  final String bodyTr;
  final String titleEn;
  final String bodyEn;

  String title(bool english) => english ? titleEn : titleTr;
  String body(bool english) => english ? bodyEn : bodyTr;
}

const kCuriosityTeasers = <CuriosityTeaserCopy>[
  CuriosityTeaserCopy(
    kind: 'nearby',
    titleTr: 'Kampüsünde hareket var',
    bodyTr: 'Radar ısındı. Bakmadan bilmezsin.',
    titleEn: "Something's up on campus",
    bodyEn: "Radar's warm. You won't know until you look.",
  ),
  CuriosityTeaserCopy(
    kind: 'radar',
    titleTr: "Radar'da hareket var",
    bodyTr: "Yakında drop'lar var. Spoiler yok.",
    titleEn: 'Movement on the radar',
    bodyEn: 'Nearby drops are live. No spoilers.',
  ),
  CuriosityTeaserCopy(
    kind: 'streak',
    titleTr: 'Ateş sönmek üzere',
    bodyTr: 'Kadronun ateşi zayıflıyor. Bir göz at.',
    titleEn: 'Fire about to die',
    bodyEn: "Your circle fire is fading. Don't miss it.",
  ),
  CuriosityTeaserCopy(
    kind: 'unseen',
    titleTr: 'Görmediğin drop’lar birikiyor',
    bodyTr: 'Akışta seni bekleyen videolar var.',
    titleEn: 'Unseen drops stacking up',
    bodyEn: 'There are videos waiting in your feed.',
  ),
  CuriosityTeaserCopy(
    kind: 'friends',
    titleTr: 'Kadro kıpırdadı',
    bodyTr: 'Kanka tarafında hareket var. Detay yok, sadece sinyal.',
    titleEn: 'Your circle stirred',
    bodyEn: 'Buddy-side activity. Signal only, no spoilers.',
  ),
  CuriosityTeaserCopy(
    kind: 'night',
    titleTr: 'Gece de açık',
    bodyTr: 'Kampüs uyanık. Sen?',
    titleEn: 'Still up tonight',
    bodyEn: 'Campus is awake. Are you?',
  ),
];

CuriosityTeaserCopy curiosityTeaserForDay(DateTime day) {
  final i = day.difference(DateTime.utc(2024)).inDays.abs() %
      kCuriosityTeasers.length;
  return kCuriosityTeasers[i];
}

CuriosityTeaserCopy randomCuriosityTeaser([int? seed]) {
  final s = seed ?? DateTime.now().millisecondsSinceEpoch;
  return kCuriosityTeasers[s.abs() % kCuriosityTeasers.length];
}
