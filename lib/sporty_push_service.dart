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
  static const _vapidKey = String.fromEnvironment('SPORTY_VAPID_KEY');

  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _tapSubscription;

  Future<void> start() async {
    if (_authSubscription != null) return;
    final messaging = FirebaseMessaging.instance;
    try {
      if (!kIsWeb) {
        await messaging.requestPermission(alert: true, badge: true, sound: true);
        await messaging.setForegroundNotificationPresentationOptions(
          alert: true, badge: true, sound: true,
        );
      }
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null && !kIsWeb) registerCurrentToken();
      });
      _tokenSubscription = messaging.onTokenRefresh.listen((_) => registerCurrentToken());
      _tapSubscription = FirebaseMessaging.onMessageOpenedApp.listen((message) {
        debugPrint('SPORTY reminder opened: ${message.data}');
      });
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('SPORTY opened from reminder: ${initialMessage.data}');
      }
      if (!kIsWeb && FirebaseAuth.instance.currentUser != null) await registerCurrentToken();
    } catch (error) {
      debugPrint('SPORTY push initialization: $error');
    }
  }

  // Trên Web: gọi từ hành động người dùng (ví dụ nút Bật thông báo).
  // Trên Web tránh requestPermission() của firebase_messaging_web vì
  // phiên bản hiện tại có thể ném "Null check operator used on a null value".
  // Người dùng cần cấp quyền site trước khi bấm nút này.
  Future<bool> enableNotifications() async {
    if (FirebaseAuth.instance.currentUser == null) {
      debugPrint('SPORTY FCM: hãy đăng nhập trước.');
      return false;
    }
    if (kIsWeb) {
      if (_vapidKey.isEmpty) {
        debugPrint('SPORTY FCM: thiếu SPORTY_VAPID_KEY.');
        return false;
      }
      debugPrint('SPORTY FCM Web: bắt đầu lấy token, không gọi requestPermission().');
      return registerCurrentToken();
    }

    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true, badge: true, sound: true,
      );
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        debugPrint('SPORTY FCM: người dùng chưa cấp quyền.');
        return false;
      }
      return registerCurrentToken();
    } catch (error) {
      debugPrint('SPORTY FCM permission error: $error');
      return false;
    }
  }

  Future<bool> registerCurrentToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) { debugPrint('FCM: chưa đăng nhập'); return false; }
      if (kIsWeb && _vapidKey.isEmpty) { debugPrint('FCM: thiếu VAPID key'); return false; }
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb ? _vapidKey : null,
      );
      if (token == null || token.isEmpty) { debugPrint('FCM: getToken trả về rỗng'); return false; }
      final jwt = await user.getIdToken();
      final response = await http.post(
        Uri.parse('${ApiClient.baseUrl}/push/register'),
        headers: {'Authorization': 'Bearer $jwt', 'Content-Type': 'application/json'},
        body: jsonEncode({'token': token}),
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        debugPrint('SPORTY FCM registration failed: ${response.statusCode} ${response.body}');
      } else {
        debugPrint('SPORTY FCM token registered successfully');
      }
      return response.statusCode == 200;
    } catch (error) {
      debugPrint('SPORTY FCM registration error: $error');
      return false;
    }
  }
}
