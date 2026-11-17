import 'social_auth_service_stub.dart'
    if (dart.library.html) 'social_auth_service_web.dart';

class SocialAuthService {
  static Future<Map<String, dynamic>?> signInWithGoogle() => webGoogleSignIn();
  static Future<Map<String, dynamic>?> signInWithApple() => webAppleSignIn();
  static void signOut() => webSignOut();
  static void signOutWeb() => webSignOut();
}
