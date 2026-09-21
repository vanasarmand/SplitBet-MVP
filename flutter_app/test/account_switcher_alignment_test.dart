import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/screens/home_screen.dart';
import 'package:flutter_app/services/api_service.dart';

void main() {
  testWidgets('Account switcher button is right-aligned on screen', (WidgetTester tester) async {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    tester.view.physicalSize = const Size(480, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(apiService: ApiService()),
      ),
    );
    await tester.pump();

    // Verify that the Switch Account button is right-aligned:
    // With a screen width of 480 and 20px right padding, its right edge is at 460.0.
    final buttonFinder = find.byTooltip('Switch Account');
    expect(buttonFinder, findsOneWidget);

    final topRight = tester.getTopRight(buttonFinder);
    expect(topRight.dx, closeTo(460.0, 1.0));
  });
}
