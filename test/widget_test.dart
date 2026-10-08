import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nool/main.dart';

void main() {
  testWidgets('Startup renders while initialization is pending',
      (tester) async {
    final pending = Completer<void>();
    await tester.pumpWidget(NoolBootstrap(initialize: () => pending.future));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete();
  });

  testWidgets('Startup failure offers a working retry', (tester) async {
    var attempts = 0;
    final retry = Completer<void>();
    await tester.pumpWidget(NoolBootstrap(initialize: () {
      attempts++;
      return attempts == 1
          ? Future<void>.error(StateError('offline'))
          : retry.future;
    }));
    await tester.pump();
    expect(find.text('Yeniden dene / Retry'), findsOneWidget);
    await tester.tap(find.text('Yeniden dene / Retry'));
    await tester.pump();
    expect(attempts, 2);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    retry.complete();
  });
}
