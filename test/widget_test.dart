// Basic smoke test. The full app needs Firebase, which isn't available in
// widget tests, so this only verifies that the app theme builds correctly.

import 'package:flutter_test/flutter_test.dart';

import 'package:interviewpro/core/theme/app_theme.dart';

void main() {
  test('App theme builds', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final theme = AppTheme.light;
    expect(theme.useMaterial3, isTrue);
  });
}
