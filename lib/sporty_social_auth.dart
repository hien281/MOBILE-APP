import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

class SportySocialAuth {
  static Future<UserCredential> signIn(AuthProvider provider) async {
    if (kIsWeb) {
      return FirebaseAuth.instance.signInWithPopup(provider);
    }
    if (provider is GoogleAuthProvider) {
      await GoogleSignIn.instance.initialize(serverClientId: '499981685398-81d3cakehm586r74rd568tiiir1lq7v9.apps.googleusercontent.com');
      final account = await GoogleSignIn.instance.authenticate();
      final auth = account.authentication;
      if (auth.idToken == null) {
        throw FirebaseAuthException(code: 'missing-google-id-token', message: 'Khong nhan duoc Google ID token. Kiem tra SHA-1 / google-services.json.');
      }
      return FirebaseAuth.instance.signInWithCredential(
        GoogleAuthProvider.credential(idToken: auth.idToken),
      );
    }
    if (provider is FacebookAuthProvider) {
      final result = await FacebookAuth.instance.login(permissions: ['public_profile', 'email']);
      if (result.status != LoginStatus.success || result.accessToken == null) {
        throw FirebaseAuthException(code: 'facebook-login-failed', message: result.message ?? 'Facebook login was cancelled or failed.');
      }
      return FirebaseAuth.instance.signInWithCredential(
        FacebookAuthProvider.credential(result.accessToken!.tokenString),
      );
    }
    throw FirebaseAuthException(code: 'unsupported-provider', message: 'Unsupported login provider.');
  }
}
