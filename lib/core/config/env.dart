/// Build-time configuration, supplied with `--dart-define` (or
/// `--dart-define-from-file=env.json`). Nothing secret lives here: the
/// publishable key only lets the client call the public RPC layer.
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
