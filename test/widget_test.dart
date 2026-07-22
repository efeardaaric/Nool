import 'package:flutter_test/flutter_test.dart';
import 'package:nool/main.dart';

void main() {
  testWidgets('NoolApp builds splash with NOOL brand', (WidgetTester tester) async {
    await tester.pumpWidget(const NoolApp());
    await tester.pump();

    expect(find.text('NOOL'), findsOneWidget);
  });
}
