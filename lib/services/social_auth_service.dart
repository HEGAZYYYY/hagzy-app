import 'social_auth_service_stub.dart'
    if (dart.library.html) 'social_auth_service_web.dart';

class SocialAuthService {
  static Future<Map<String, dynamic>?> signInWithGoogle() => webGoogleSignIn();
  static Future<Map<String, dynamic>?> signInWithApple() => webAppleSignIn();
  static Future<Map<String, dynamic>?> sendPhoneOtp(String phone) => webSendPhoneOtp(phone);
  static Future<Map<String, dynamic>?> verifyPhoneOtp(String code) => webVerifyPhoneOtp(code);
  static Future<void> signInWithCustomToken(String token) => webSignInWithCustomToken(token);
  static Map<String, dynamic>? getRedirectUser() => webGetRedirectUser();
  static void signOutWeb() => webSignOut();
}
