class LumenoteBackendConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );
  static const aiGatewayUrl = String.fromEnvironment(
    'LUMENOTE_AI_URL',
    defaultValue: 'http://localhost:8787',
  );
  static const transcriptionFunction = 'process-transcription';
  static const generationFunction = 'generate-study-material';
}
