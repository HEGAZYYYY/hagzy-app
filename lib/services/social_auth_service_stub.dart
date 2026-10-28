Future<Map<String, dynamic>?> webGoogleSignIn() async => null;
Future<Map<String, dynamic>?> webAppleSignIn() async => null;
Future<Map<String, dynamic>?> webSendPhoneOtp(String phone) async => null;
Future<Map<String, dynamic>?> webVerifyPhoneOtp(String code) async => null;
Map<String, dynamic>? webGetRedirectUser() => null;
Future<void> webSignInWithCustomToken(String token) async {}
void webSignOut() {}
void webRegisterSignOutListener(void Function() onSignOut) {}
void webRegisterVenuesListener(void Function(List<Map<String, dynamic>>) onVenues) {}
void webSaveVenueToFirestore(Map<String, dynamic> venueJson) {}
void webDeleteVenueFromFirestore(String venueId) {}
