import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiClient {
  // Android Emulator dùng 10.0.2.2 để truy cập localhost của máy tính.
  // Chrome chạy trên cùng máy tính dùng localhost.
  static String get baseUrl {
    if (kIsWeb) {
      return 'http://localhost:3000/api';
    }

    return 'http://10.0.2.2:3000/api';
  }

import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  // Địa chỉ API đã deploy lên Vercel
  static const String baseUrl = 'https://mobile-app-nine-lac.vercel.app/api';

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );

    final data = jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return data;
    }

    throw Exception(data['message'] ?? 'Đăng nhập thất bại.');
  }
}
}
