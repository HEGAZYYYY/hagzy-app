Future<Map<String, dynamic>?> webGoogleSignIn() async => null;
Future<Map<String, dynamic>?> webAppleSignIn() async => null;
Future<Map<String, dynamic>?> webSendPhoneOtp(String phone) async => null;
Future<Map<String, dynamic>?> webVerifyPhoneOtp(String code) async => null;
Map<String, dynamic>? webGetRedirectUser() => null;
Future<void> webSignInWithCustomToken(String token) async {}
void webSignOut() {}
void webRegisterSignOutListener(void Function() onSignOut) {}
void webRegisterRedirectAuthListener(void Function(Map<String, dynamic>) onRedirectUser) {}
void webRegisterVenuesListener(void Function(List<Map<String, dynamic>>) onVenues) {}
void webRegisterUsersListener(void Function(List<Map<String, dynamic>>) onUsers) {}
void webSaveVenueToFirestore(Map<String, dynamic> venueJson) {}
void webDeleteVenueFromFirestore(String venueId) {}
void webSyncUserToFirestore(Map<String, dynamic> userJson) {}
void webSyncBookingToFirestore(
    Map<String, dynamic> bookingJson, Map<String, dynamic> userJson) {}
