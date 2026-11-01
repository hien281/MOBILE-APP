import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';

class SportyPushService {
  SportyPushService._();
  static final instance = SportyPushService._();
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _tapSubscription;

  Future<void> start() async {
    if (kIsWeb || _authSubscription != null) return;
    final messaging = FirebaseMessaging.instance;
    try {
      await messaging.requestPermission(alert:true,badge:true,sound:true);
      await messaging.setForegroundNotificationPresentationOptions(alert:true,badge:true,sound:true);
      _authSubscription=FirebaseAuth.instance.authStateChanges().listen((user) {
        if(user!=null) { registerCurrentToken(); }
      });
      _tokenSubscription=messaging.onTokenRefresh.listen((_) { registerCurrentToken(); });
      _tapSubscription=FirebaseMessaging.onMessageOpenedApp.listen((message) {
        debugPrint('SPORTY reminder tapped: ${message.data}');
        // Mở app; có thể nối điều hướng đến Chi tiết đặt sân ở bước sau.
      });
      final initial=await messaging.getInitialMessage();
      if(initial!=null) debugPrint('SPORTY launched by reminder: ${initial.data}');
      if(FirebaseAuth.instance.currentUser!=null) await registerCurrentToken();
    }catch(error){
      debugPrint('SPORTY notification setup failed: $error');
    }
  }

  Future<void> registerCurrentToken() async {
    try {
      final user=FirebaseAuth.instance.currentUser;
      if(user==null) return;
      final deviceToken=await FirebaseMessaging.instance.getToken();
      if(deviceToken==null || deviceToken.isEmpty) return;
      final jwt=await user.getIdToken();
      final response=await http.post(
        Uri.parse('${ApiClient.baseUrl}/push/register'),
        headers:{'Authorization':'Bearer $jwt','Content-Type':'application/json'},
        body:jsonEncode({'token':deviceToken}),
      ).timeout(const Duration(seconds:15));
      if(response.statusCode!=200) debugPrint('FCM register failed: ${response.statusCode}');
    }catch(error){
      debugPrint('FCM register error: $error');
    }
  }
}
