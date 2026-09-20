import 'package:flutter/foundation.dart';
import 'web_storage.dart';

class SupabaseConfig {
  // Default project credentials for 24/7 standalone cloud operation
  static const String defaultUrl = 'https://gwnoadtlpjugpafmkmnn.supabase.co';
  static const String defaultAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imd3bm9hZHRscGp1Z3BhZm1rbW5uIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk4NDEzMTMsImV4cCI6MjEwNTQxNzMxM30.j5Rs33xa4kdJEC5VLDFubqfP9h6Bj7t9ZflgYg0Lrqg';

  static String url = defaultUrl;
  static String anonKey = defaultAnonKey;

  static bool get isConfigured =>
      url.trim().isNotEmpty &&
      anonKey.trim().isNotEmpty &&
      url.startsWith('https://') &&
      !url.contains('YOUR_') &&
      url != 'DEMO_MODE';

  static void initConfig() {
    // 1. Check URL parameters (?supabase_url=...&supabase_key=...)
    try {
      if (kIsWeb) {
        final queryParams = Uri.base.queryParameters;
        final paramUrl = queryParams['supabase_url'] ?? queryParams['sb_url'];
        final paramKey = queryParams['supabase_key'] ?? queryParams['sb_key'];

        if (paramUrl != null && paramKey != null) {
          saveConfig(paramUrl.trim(), paramKey.trim());
          return;
        }
      }
    } catch (_) {}

    // 2. Check persistent storage
    final savedUrl = readWebStorage('splitbet_supabase_url');
    final savedKey = readWebStorage('splitbet_supabase_key');
    if (savedUrl == 'DEMO_MODE') {
      url = '';
      anonKey = '';
      return;
    }
    if (savedUrl != null && savedKey != null && savedUrl.isNotEmpty && savedKey.isNotEmpty) {
      if (!savedUrl.toUpperCase().contains('YOUR_') && savedUrl.startsWith('https://')) {
        url = savedUrl.trim();
        anonKey = savedKey.trim();
      }
    }
  }

  static void saveConfig(String newUrl, String newKey) {
    url = newUrl.trim();
    anonKey = newKey.trim();
    writeWebStorage('splitbet_supabase_url', url);
    writeWebStorage('splitbet_supabase_key', anonKey);
  }

  static void clearConfig() {
    url = '';
    anonKey = '';
    writeWebStorage('splitbet_supabase_url', 'DEMO_MODE');
    writeWebStorage('splitbet_supabase_key', 'DEMO_MODE');
  }

  static void resetToDefaultConfig() {
    url = defaultUrl;
    anonKey = defaultAnonKey;
    writeWebStorage('splitbet_supabase_url', defaultUrl);
    writeWebStorage('splitbet_supabase_key', defaultAnonKey);
  }
}
