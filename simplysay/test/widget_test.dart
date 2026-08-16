import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simplysay/features/home/presentation/home_screen.dart';
import 'package:simplysay/main.dart';

void main() {
  testWidgets('SimplySay App Smoke Test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: SimplySayApp(),
      ),
    );

    expect(find.text('SimplySay'), findsAtLeastNWidgets(1));
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('HomeScreen Smoke Test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: SimplySayApp(homeScreen: HomeScreen()),
      ),
    );

    expect(find.text('SimplySay'), findsOneWidget);
    expect(find.text('Alex Johnson'), findsOneWidget);
    expect(find.text('Jordan Smith'), findsOneWidget);
    expect(find.text('Recent'), findsAtLeastNWidgets(1));
  });
}
