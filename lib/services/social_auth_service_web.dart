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
