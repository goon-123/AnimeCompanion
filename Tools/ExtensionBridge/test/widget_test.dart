import 'package:companion_extensions/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('headless startup does not start Java or contact a source', (
    tester,
  ) async {
    var starts = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('anymex_extension_bridge/embedded_jvm'),
          (call) async {
            starts++;
            return null;
          },
        );
    app.main();
    await tester.pumpAndSettle();
    expect(starts, 0);
    expect(app.player.value, isNull);
    expect(find.byType(MaterialApp), findsOneWidget);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('anymex_extension_bridge/embedded_jvm'),
          null,
        );
  });
}
