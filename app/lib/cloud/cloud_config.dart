/// Supabase connection, passed at build time: `--dart-define-from-file=cloud_config.json`.
const kSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
const kSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

bool get isCloudConfigured => kSupabaseUrl.isNotEmpty && kSupabaseAnonKey.isNotEmpty;
