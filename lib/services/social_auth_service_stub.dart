import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

bool _googleInitialized = false;

Future<void> _ensureGoogleSignInInitialized() async {
  if (_googleInitialized) return;
  try {
    await GoogleSignIn.instance.initialize();
    _googleInitialized = true;
  } catch (e) {
    debugPrint('GoogleSignIn.initialize note: $e');
  }
}

Future<Map<String, dynamic>?> webGoogleSignIn() async {
  try {
    await _ensureGoogleSignInInitialized();
    final account = await GoogleSignIn.instance.authenticate();
    final idToken = account.authentication.idToken;
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
    debugPrint('Google Sign-In native error: $e');
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
    final fullName = [credential.givenName, credential.familyName]
        .where((s) => s != null && s.trim().isNotEmpty)
        .join(' ')
        .trim();
    return {
      'name': fullName.isEmpty ? 'Apple Member' : fullName,
      'email': credential.email ?? '',
      'token': credential.identityToken ?? '',
      'providerId': credential.userIdentifier ?? '',
    };
  } catch (e) {
    debugPrint('Apple Sign-In native error: $e');
    return {'error': e.toString()};
  }
}

Future<Map<String, dynamic>?> webSendPhoneOtp(String phone) async => null;
Future<Map<String, dynamic>?> webVerifyPhoneOtp(String code) async => null;
Map<String, dynamic>? webGetRedirectUser() => null;
Future<void> webSignInWithCustomToken(String token) async {}
void webSignOut() {
  try {
    GoogleSignIn.instance.signOut();
  } catch (_) {}
}
void webRegisterSignOutListener(void Function() onSignOut) {}
void webRegisterRedirectAuthListener(
    void Function(Map<String, dynamic>) onRedirectUser) {}
void webRegisterVenuesListener(
    void Function(List<Map<String, dynamic>>) onVenues) {}
void webRegisterUsersListener(
    void Function(List<Map<String, dynamic>>) onUsers) {}
void webSaveVenueToFirestore(Map<String, dynamic> venueJson) {}
void webDeleteVenueFromFirestore(String venueId) {}
void webSyncUserToFirestore(Map<String, dynamic> userJson) {}
void webSyncBookingToFirestore(
    Map<String, dynamic> bookingJson, Map<String, dynamic> userJson) {}
