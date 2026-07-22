import 'package:flutter_test/flutter_test.dart';
import 'package:nool/services/profanity_filter.dart';

void main() {
  group('ProfanityFilter', () {
    test('temiz metni geçer', () {
      expect(
        ProfanityFilter.containsBlocked('bu drop efsane kampüs vibe'),
        isFalse,
      );
    });

    test('yasaklı kökü yakalar', () {
      expect(ProfanityFilter.containsBlocked('sen salak mısın'), isTrue);
      expect(ProfanityFilter.containsBlocked('AMK ne bu'), isTrue);
    });

    test('bypass boşluk/nokta denemesini yakalar', () {
      expect(ProfanityFilter.containsBlocked('s a l a k'), isTrue);
    });
  });
}
