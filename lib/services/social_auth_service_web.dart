import 'dart:async';
import 'dart:convert';
import 'dart:js' as js;

Future<Map<String, dynamic>?> webGoogleSignIn() async {
  try {
    int attempts = 0;
    while (!js.context.hasProperty('hagzySignInWithGoogleCallback') && attempts < 25) {
      await Future.delayed(const Duration(milliseconds: 200));
      attempts++;
    }

    if (js.context.hasProperty('hagzySignInWithGoogleCallback')) {
      final completer = Completer<Map<String, dynamic>?>();
      js.context.callMethod('hagzySignInWithGoogleCallback', [
        js.allowInterop((result) {
          try {
            if (result != null) {
              if (result is String) {
                completer.complete(jsonDecode(result) as Map<String, dynamic>);
              } else {
                final str = js.context['JSON'].callMethod('stringify', [result]);
                completer.complete(jsonDecode(str as String) as Map<String, dynamic>);
              }
            } else {
              completer.complete(null);
            }
          } catch (e) {
            completer.complete({'error': e.toString()});
          }
        }),
        js.allowInterop((error) {
          completer.complete({'error': error?.toString() ?? 'Authentication error'});
        }),
      ]);
      return await completer.future;
    } else {
      return {'error': 'Firebase Auth is still initializing. Please tap again.'};
    }
  } catch (e) {
    return {'error': e.toString()};
  }
}

Future<Map<String, dynamic>?> webAppleSignIn() async {
  try {
    int attempts = 0;
    while (!js.context.hasProperty('hagzySignInWithAppleCallback') && attempts < 25) {
      await Future.delayed(const Duration(milliseconds: 200));
      attempts++;
    }

    if (js.context.hasProperty('hagzySignInWithAppleCallback')) {
      final completer = Completer<Map<String, dynamic>?>();
      js.context.callMethod('hagzySignInWithAppleCallback', [
        js.allowInterop((result) {
          try {
            if (result != null) {
              if (result is String) {
                completer.complete(jsonDecode(result) as Map<String, dynamic>);
              } else {
                final str = js.context['JSON'].callMethod('stringify', [result]);
                completer.complete(jsonDecode(str as String) as Map<String, dynamic>);
              }
            } else {
              completer.complete(null);
            }
          } catch (e) {
            completer.complete({'error': e.toString()});
          }
        }),
        js.allowInterop((error) {
          completer.complete({'error': error?.toString() ?? 'Authentication error'});
        }),
      ]);
      return await completer.future;
    } else {
      return {'error': 'Firebase Auth is still initializing. Please tap again.'};
    }
  } catch (e) {
    return {'error': e.toString()};
  }
}

Future<Map<String, dynamic>?> webSendPhoneOtp(String phone) async {
  return null;
}

Future<Map<String, dynamic>?> webVerifyPhoneOtp(String code) async {
  return null;
}

Map<String, dynamic>? webGetRedirectUser() {
  try {
    if (js.context.hasProperty('hagzyRedirectUser')) {
      final user = js.context['hagzyRedirectUser'];
      if (user != null && user is String && user.isNotEmpty) {
        return jsonDecode(user) as Map<String, dynamic>;
      }
    }
  } catch (_) {}
  return null;
}

void webSignOut() {
  try {
    if (js.context.hasProperty('hagzySignOut')) {
      js.context.callMethod('hagzySignOut');
    }
  } catch (_) {}
}

void webRegisterSignOutListener(void Function() onSignOut) {
  try {
    if (js.context.hasProperty('registerHagzySignOutCallback')) {
      js.context.callMethod('registerHagzySignOutCallback', [
        js.allowInterop(() {
          onSignOut();
        }),
      ]);
    }
  } catch (_) {}
}

void webRegisterRedirectAuthListener(
    void Function(Map<String, dynamic>) onRedirectUser) {
  try {
    if (js.context.hasProperty('registerHagzyRedirectAuthCallback')) {
      js.context.callMethod('registerHagzyRedirectAuthCallback', [
        js.allowInterop((dynamic rawJson) {
          try {
            if (rawJson is String && rawJson.isNotEmpty) {
              final decoded = jsonDecode(rawJson);
              if (decoded is Map) {
                onRedirectUser(Map<String, dynamic>.from(decoded));
              }
            }
          } catch (_) {}
        }),
      ]);
    }
  } catch (_) {}
}

Future<void> webSignInWithCustomToken(String token) async {
  try {
    if (js.context.hasProperty('hagzySignInWithCustomTokenCallback')) {
      final completer = Completer<void>();
      js.context.callMethod('hagzySignInWithCustomTokenCallback', [
        token,
        js.allowInterop((result) {
          if (!completer.isCompleted) completer.complete();
        }),
        js.allowInterop((err) {
          print('Firebase custom token error: $err');
          if (!completer.isCompleted) completer.complete();
        }),
      ]);
      await completer.future.timeout(const Duration(seconds: 8), onTimeout: () {});
      return;
    }
    if (js.context.hasProperty('hagzySignInWithCustomToken')) {
      js.context.callMethod('hagzySignInWithCustomToken', [token]);
    }
  } catch (e) {
    print('Custom token error: $e');
  }
}

void webRegisterVenuesListener(void Function(List<Map<String, dynamic>>) onVenues) {
  try {
    if (js.context.hasProperty('registerHagzyVenuesListener')) {
      js.context.callMethod('registerHagzyVenuesListener', [
        js.allowInterop((dynamic rawJson) {
          try {
            if (rawJson is String && rawJson.isNotEmpty) {
              final decoded = jsonDecode(rawJson);
              if (decoded is List) {
                final list = decoded
                    .whereType<Map>()
                    .map((m) => Map<String, dynamic>.from(m))
                    .toList();
                onVenues(list);
              }
            }
          } catch (_) {}
        }),
      ]);
    }
  } catch (_) {}
}

void webSaveVenueToFirestore(Map<String, dynamic> venueJson) {
  try {
    if (js.context.hasProperty('hagzySaveVenueToFirestore')) {
      js.context.callMethod('hagzySaveVenueToFirestore', [jsonEncode(venueJson)]);
    }
  } catch (_) {}
}

void webDeleteVenueFromFirestore(String venueId) {
  try {
    if (js.context.hasProperty('hagzyDeleteVenueFromFirestore')) {
      js.context.callMethod('hagzyDeleteVenueFromFirestore', [venueId]);
    }
  } catch (_) {}
}

void webSyncUserToFirestore(Map<String, dynamic> userJson) {
  try {
    if (js.context.hasProperty('hagzySyncUserToFirestore')) {
      js.context.callMethod('hagzySyncUserToFirestore', [jsonEncode(userJson)]);
    }
  } catch (_) {}
}

void webSyncBookingToFirestore(
    Map<String, dynamic> bookingJson, Map<String, dynamic> userJson) {
  try {
    if (js.context.hasProperty('hagzySyncBookingToFirestore')) {
      js.context.callMethod('hagzySyncBookingToFirestore', [
        jsonEncode(bookingJson),
        jsonEncode(userJson),
      ]);
    }
  } catch (_) {}
}
