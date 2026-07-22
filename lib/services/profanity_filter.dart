/// Yerel siber zorbalık / küfür filtresi.
///
/// Yasaklı kökler noktalamasız normalize edilip kelime sınırıyla aranır.
abstract final class ProfanityFilter {
  static final List<RegExp> _patterns = _buildPatterns(_blockedRoots);

  /// Türkçe kampüs bağlamında yaygın hakaret / zorbalık kökleri.
  static const _blockedRoots = [
    'amk',
    'aq',
    'a q',
    'siktir',
    'sikerim',
    'sikeyim',
    'amına',
    'amina',
    'orospu',
    'orosbu',
    'piç',
    'pic',
    'göt',
    'got',
    'yarrak',
    'yarrrak',
    'daşşak',
    'dassak',
    'kahpe',
    'pezevenk',
    'ibne',
    'ibine',
    'salak',
    'gerizekali',
    'gerizekâlı',
    'aptal',
    'dangalak',
    'öküz',
    'okuz',
    'köpek',
    'kopek',
    'sikik',
    'amcik',
    'amcık',
    'götveren',
    'gotveren',
    'sürtük',
    'surtuk',
    'fahişe',
    'fahise',
    'kill yourself',
    'kys',
    'intihar et',
    'öl git',
    'ol git',
    'gebersin',
    'gebertirim',
    'ezik',
    'eziksin',
    'kıro',
    'kiro',
    'yobaz',
    'geri zekalı',
  ];

  static List<RegExp> _buildPatterns(List<String> roots) {
    return roots.map((root) {
      final escaped = RegExp.escape(root.toLowerCase());
      return RegExp(
        '(?:^|[^a-zçğıöşü0-9])$escaped(?:[^a-zçğıöşü0-9]|\$)',
        caseSensitive: false,
        unicode: true,
      );
    }).toList(growable: false);
  }

  static String normalize(String input) {
    var s = input.toLowerCase().trim();
    const map = {
      'ı': 'i',
      'İ': 'i',
      'ş': 's',
      'ğ': 'g',
      'ü': 'u',
      'ö': 'o',
      'ç': 'c',
      'â': 'a',
      'î': 'i',
      'û': 'u',
    };
    map.forEach((k, v) => s = s.replaceAll(k, v));
    // "s.i.k.t.i.r" tarzı bypass
    s = s.replaceAll(RegExp(r'[\s._*\-]+'), ' ');
    s = s.replaceAll(RegExp(r'(.)\1{2,}'), r'$1$1');
    return s;
  }

  /// Yasaklı içerik var mı?
  static bool containsBlocked(String raw) {
    final text = normalize(raw);
    if (text.isEmpty) return false;
    final padded = ' $text ';
    for (final pattern in _patterns) {
      if (pattern.hasMatch(padded)) return true;
    }
    // "s a l a k" gibi harf-arası boşluk bypass
    final compact = text.replaceAll(RegExp(r'\s+'), '');
    for (final root in _blockedRoots) {
      final needle = normalize(root).replaceAll(RegExp(r'\s+'), '');
      if (needle.length < 3) continue;
      if (compact.contains(needle)) return true;
    }
    return false;
  }

  static const blockedMessage =
      'Hey, burası pozitif bir kampüs alanı! Lütfen diline dikkat et.';
}
