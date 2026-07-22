import 'package:flutter_test/flutter_test.dart';
import 'package:nool/models/vibe_post.dart';
import 'package:nool/services/supabase_service.dart';

void main() {
  group('SupabaseService TTL + skor', () {
    test('isWithinTtl 24 saat penceresini doğrular', () {
      final service = SupabaseService.instance;
      final now = DateTime.utc(2026, 7, 22, 12);

      expect(
        service.isWithinTtl(now.subtract(const Duration(hours: 23)), now: now),
        isTrue,
      );
      expect(
        service.isWithinTtl(now.subtract(const Duration(hours: 25)), now: now),
        isFalse,
      );
    });

    test('filterFreshVideos eski kayıtları eker', () {
      final now = DateTime.utc(2026, 7, 22, 12);
      final posts = [
        VibePost(
          id: 'fresh',
          videoUrl: 'https://example.com/a.mp4',
          username: '@anon_a',
          caption: 'x',
          distanceLabel: '10m',
          subtitle: '',
          trackLabel: '',
          vibeCountLabel: '1',
          commentCountLabel: '0',
          createdAt: now.subtract(const Duration(hours: 2)),
        ),
        VibePost(
          id: 'stale',
          videoUrl: 'https://example.com/b.mp4',
          username: '@anon_b',
          caption: 'y',
          distanceLabel: '10m',
          subtitle: '',
          trackLabel: '',
          vibeCountLabel: '1',
          commentCountLabel: '0',
          createdAt: now.subtract(const Duration(hours: 30)),
        ),
      ];

      final filtered =
          SupabaseService.instance.filterFreshVideos(posts, now: now);

      expect(filtered.map((p) => p.id), ['fresh']);
    });

    test('computeScore vibe/(mesafe×zaman) formülünü uygular', () {
      final score = SupabaseService.computeScore(
        vibeCount: 100,
        distanceMeters: 50,
        age: const Duration(hours: 2),
      );
      // 100 / (50 * 2) = 1
      expect(score, closeTo(1.0, 0.001));
    });
  });
}
