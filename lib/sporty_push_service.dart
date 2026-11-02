import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'sporty_notification_navigation.dart';

class SportyPushService {
  SportyPushService._();
  static final instance = SportyPushService._();
  static const _vapidKey = String.fromEnvironment('SPORTY_VAPID_KEY');
  static const _channel = AndroidNotificationChannel(
    'sporty_booking_reminders', 'Nhắc lịch đặt sân',
    description: 'Thông báo nhắc trước giờ chơi',
    importance: Importance.max,
    playSound: true,
  );
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _tapSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;

  Future<void> _configureAndroid() async {
    await _local.initialize(
      const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null) return;
        try {
          final data = Map<String,dynamic>.from(jsonDecode(payload) as Map);
          openSportyBookingFromPush(data);
        } catch (error) {
          debugPrint('SPORTY local push tap error: $error');
        }
      },
    );
    await _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);
    final details = await _local.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true) {
      final payload = details?.notificationResponse?.payload;
      if (payload != null) {
        try { openSportyBookingFromPush(Map<String,dynamic>.from(jsonDecode(payload) as Map)); }
        catch (error) { debugPrint('SPORTY initial local notification: $error'); }
      }
    }
  }

  Future<void> start() async {
    if (_authSubscription != null) return;
    final messaging = FirebaseMessaging.instance;
    try {
      if (!kIsWeb) {
        if (defaultTargetPlatform == TargetPlatform.android) await _configureAndroid();
        final permission = await messaging.requestPermission(alert:true,badge:true,sound:true);
        debugPrint('SPORTY push permission: ${permission.authorizationStatus}');
        await messaging.setForegroundNotificationPresentationOptions(alert:true,badge:true,sound:true);
      }
      _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null && !kIsWeb) registerCurrentToken();
      });
      _tokenSubscription = messaging.onTokenRefresh.listen((_) => registerCurrentToken());
      _tapSubscription = FirebaseMessaging.onMessageOpenedApp.listen((message) {
        openSportyBookingFromPush(message.data);
      });
      _foregroundSubscription = FirebaseMessaging.onMessage.listen((message) async {
        if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
        final notification = message.notification;
        if (notification == null) return;
        try {
          await _local.show(
            message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch.remainder(100000),
            notification.title, notification.body,
            const NotificationDetails(android: AndroidNotificationDetails(
              'sporty_booking_reminders','Nhắc lịch đặt sân',
              channelDescription:'Thông báo nhắc trước giờ chơi',
              importance: Importance.max, priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            )),
            payload: jsonEncode(message.data),
          );
        } catch (error) { debugPrint('SPORTY local notification error: $error'); }
      });
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) openSportyBookingFromPush(initialMessage.data);
      if (!kIsWeb && FirebaseAuth.instance.currentUser != null) await registerCurrentToken();
    } catch (error) {
      debugPrint('SPORTY push initialization: $error');
    }
  }

  Future<bool> enableNotifications() async {
    if (FirebaseAuth.instance.currentUser == null) return false;
    if (kIsWeb) {
      if (_vapidKey.isEmpty) return false;
      return registerCurrentToken();
    }
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(alert:true,badge:true,sound:true);
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) return false;
      return registerCurrentToken();
    } catch(error) { debugPrint('SPORTY FCM permission: $error'); return false; }
  }

  Future<bool> registerCurrentToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if(user == null) return false;
      if(kIsWeb && _vapidKey.isEmpty) return false;
      final token = await FirebaseMessaging.instance.getToken(vapidKey:kIsWeb?_vapidKey:null);
      if(token == null || token.isEmpty) return false;
      final jwt = await user.getIdToken();
      final response = await http.post(Uri.parse('${ApiClient.baseUrl}/push/register'),
        headers:{'Authorization':'Bearer $jwt','Content-Type':'application/json'},
        body:jsonEncode({'token':token}),
      ).timeout(const Duration(seconds:15));
      debugPrint('SPORTY FCM registration HTTP ${response.statusCode}');
      return response.statusCode == 200;
    } catch(error) {debugPrint('SPORTY FCM registration error: $error'); return false;}
  }
}
