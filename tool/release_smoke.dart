import 'dart:io';
import 'package:nool/services/profanity_filter.dart';
import 'package:nool/utils/storage_media_reference.dart';

void main() {
  var passed = 0;
  void check(String name, bool condition) {
    if (!condition) throw StateError('FAIL: $name');
    passed++;
    stdout.writeln('PASS: $name');
  }

  check('clean text',
      !ProfanityFilter.containsBlocked('bu drop efsane kampüs vibe'));
  check('blocked word', ProfanityFilter.containsBlocked('sen salak mısın'));
  check('uppercase profanity', ProfanityFilter.containsBlocked('AMK ne bu'));
  check('spaced bypass', ProfanityFilter.containsBlocked('s a l a k'));
  const project = 'https://project.supabase.co';
  StorageMediaReference? parse(String value) =>
      StorageMediaReference.parse(value, projectUrl: project);
  final media = parse('$project/storage/v1/object/public/campus-drops/u/a.mp4');
  check('media bucket', media?.bucket == 'campus-drops');
  check('media object path', media?.path == 'u/a.mp4');
  check('group media',
      parse('$project/storage/v1/object/public/group-drops/g/a.mp4') != null);
  check(
      'different project rejected',
      parse('https://other.supabase.co/storage/v1/object/public/campus-drops/u/a.mp4') ==
          null);
  check(
      'insecure origin rejected',
      parse('http://project.supabase.co/storage/v1/object/public/campus-drops/u/a.mp4') ==
          null);
  check('unrelated bucket rejected',
      parse('$project/storage/v1/object/public/secrets/u/a.mp4') == null);
  check(
      'encoded path separator rejected',
      parse('$project/storage/v1/object/public/campus-drops/u%2Fa.mp4') ==
          null);
  check('empty object rejected',
      parse('$project/storage/v1/object/public/campus-drops/') == null);
  check(
      'existing signed URL not re-signed',
      parse('$project/storage/v1/object/sign/campus-drops/u/a.mp4?token=x') ==
          null);
  stdout.writeln('$passed smoke checks passed.');
}
