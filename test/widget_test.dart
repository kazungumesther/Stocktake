import 'package:flutter_test/flutter_test.dart';
import 'package:stocktake/core/config.dart';

// Replaces the counter-app test that `flutter create` generates.
void main() {
  test('runs in local-only mode when no Supabase settings are given', () {
    expect(AppConfig.hasSupabase, isFalse);
  });
}
