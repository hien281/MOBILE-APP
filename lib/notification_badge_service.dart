import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';

class SportyNotificationBadge {
  SportyNotificationBadge._();
  static final instance = SportyNotificationBadge._();

  final ValueNotifier<int> unread = ValueNotifier<int>(0);
  Timer? _timer;
  StreamSubscription<User?>? _auth;
  bool _busy = false;

  void start() {
    if (_timer != null) return;
    _auth ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        unread.value = 0;
      } else {
        refresh();
      }
    });
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => refresh());
  }

  Future<void> refresh() async {
    if (_busy) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      unread.value = 0;
      return;
    }
    _busy = true;
    try {
      final jwt = await user.getIdToken();
      if (jwt == null || jwt.isEmpty) return;
      final response = await http.get(
        Uri.parse('${ApiClient.baseUrl}/notifications'),
        headers: {'Authorization': 'Bearer $jwt', 'Cache-Control': 'no-cache'},
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return;
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is! Map || body['success'] != true || body['notifications'] is! List) return;
      if (FirebaseAuth.instance.currentUser?.uid != user.uid) return;
      unread.value = (body['notifications'] as List)
          .where((item) => item is Map && item['read'] != true)
          .length;
    } catch (error) {
      debugPrint('SPORTY unread badge refresh: $error');
    } finally {
      _busy = false;
    }
  }
}
