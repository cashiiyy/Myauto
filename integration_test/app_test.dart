import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:my_auto/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('end-to-end test', () {
    testWidgets('tap on destination search bar and select destination',
        (tester) async {
      app.main();
      await tester.pumpAndSettle();

      // Find the search bar
      final Finder searchBar = find.text('Where to?');
      expect(searchBar, findsOneWidget);
    });
  });
}
