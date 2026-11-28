import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_config.dart';

bool _googleInitialized = false;

Future<void> _ensureGoogleSignInInitialized() async {
  if (_googleInitialized) return;
  try {
    await GoogleSignIn.instance.initialize();
    _googleInitialized = true;
  } catch (e) {
    if (kDebugMode) debugPrint('GoogleSignIn.initialize note: $e');
  }
}

Future<Map<String, dynamic>?> webGoogleSignIn() async {
  try {
    await _ensureGoogleSignInInitialized();
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
    if (idToken != null && idToken.isNotEmpty) {
      final client = supabaseClientOrNull;
      if (client != null) {
        try {
          await client.auth.signInWithIdToken(
            provider: OAuthProvider.google,
            idToken: idToken,
          );
        } catch (_) {}
      }
    }
    return {
      'name': account.displayName ?? 'Hagzy Member',
      'email': account.email,
      'avatar': account.photoUrl ?? '',
      'token': idToken ?? '',
      'providerId': account.id,
    };
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled) {
      return null;
    }
    return {'error': e.description ?? e.code.name};
  } catch (e) {
    if (kDebugMode) debugPrint('Google Sign-In native error: $e');
    return {'error': e.toString()};
  }
}

Future<Map<String, dynamic>?> webAppleSignIn() async {
  try {
    final credential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );
    final idToken = credential.identityToken;
    if (idToken != null && idToken.isNotEmpty) {
      final client = supabaseClientOrNull;
      if (client != null) {
        try {
          await client.auth.signInWithIdToken(
            provider: OAuthProvider.apple,
            idToken: idToken,
          );
        } catch (_) {}
      }
    }
    final fullName = [credential.givenName, credential.familyName]
        .where((s) => s != null && s.trim().isNotEmpty)
        .join(' ')
        .trim();
    return {
      'name': fullName.isEmpty ? 'Apple Member' : fullName,
      'email': credential.email ?? '',
      'token': idToken ?? '',
      'providerId': credential.userIdentifier ?? '',
    };
  } on SignInWithAppleAuthorizationException catch (e) {
    if (e.code == AuthorizationErrorCode.canceled) {
      return null;
    }
    if (kDebugMode) {
      debugPrint(
          'Apple Sign-In authorization error: ${e.message} (code: ${e.code})');
    }
    return {'error': e.message};
  } catch (e) {
    if (kDebugMode) debugPrint('Apple Sign-In native error: $e');
    return {'error': e.toString()};
  }
}

void webSignOut() {
  try {
    GoogleSignIn.instance.signOut();
  } catch (_) {}
  try {
    supabaseClientOrNull?.auth.signOut();
  } catch (_) {}
}
