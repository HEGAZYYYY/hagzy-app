import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String kSupabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://qgimngblsrfgzavuxpde.supabase.co',
);

const String kSupabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'sb_publishable_6cjcbaaKHRIFih4XOlXa1Q_IXqpSMMK',
);

const String kDefaultEdgeApiUrl =
    '$kSupabaseUrl/functions/v1/hagzy-api';

bool _supabaseReady = false;

/// Initializes Supabase once at app startup. Safe to call in unit tests.
Future<void> initHagzySupabase() async {
  if (_supabaseReady) return;
  try {
    await Supabase.initialize(
      url: kSupabaseUrl,
      publishableKey: kSupabaseAnonKey,
    );
    _supabaseReady = true;
  } catch (e) {
    if (kDebugMode) debugPrint('Supabase init notice: $e');
  }
}

/// Returns the active SupabaseClient when initialized, or null in widget tests / preview mode.
SupabaseClient? get supabaseClientOrNull {
  if (!_supabaseReady) return null;
  try {
    return Supabase.instance.client;
  } catch (_) {
    return null;
  }
}
