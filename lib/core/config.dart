/// Build-time settings. Pass them with `--dart-define-from-file=env.json`.
/// With no Supabase values the app runs in local-only mode (no sign-in, no sync).
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_KEY');

  static bool get hasSupabase => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;

  /// Items at or below this quantity count as "low stock".
  static const lowStockThreshold = 5;
}
