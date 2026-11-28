import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

Future<Map<String, dynamic>?> webGoogleSignIn() async {
  final client = supabaseClientOrNull;
  if (client == null) {
    return {'error': 'Supabase Auth is still initializing. Please tap again.'};
  }
  try {
    await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: Uri.base.origin,
      queryParams: const {'prompt': 'select_account'},
    );
    return {'redirecting': true};
  } catch (e) {
    if (kDebugMode) debugPrint('Supabase Google OAuth error: $e');
    return {'error': e.toString()};
  }
}

Future<Map<String, dynamic>?> webAppleSignIn() async {
  final client = supabaseClientOrNull;
  if (client == null) {
    return {'error': 'Supabase Auth is still initializing. Please tap again.'};
  }
  try {
    await client.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: Uri.base.origin,
    );
    return {'redirecting': true};
  } catch (e) {
    if (kDebugMode) debugPrint('Supabase Apple OAuth error: $e');
    return {'error': e.toString()};
  }
}

void webSignOut() {
  try {
    supabaseClientOrNull?.auth.signOut();
  } catch (_) {}
}
