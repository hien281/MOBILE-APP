
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class ApiClient {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://mobile-app-nine-lac.vercel.app/api',
  );

  // Lấy danh sách sân
  static Future<List<Map<String, dynamic>>> getFields() async {
    final response = await http.get(
      Uri.parse('$baseUrl/fields'),
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Không tải được danh sách sân');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));

    return (data['fields'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  // Tạo đơn giữ sân 10 phút
  static Future<Map<String, dynamic>> createBooking({
    required String fieldId,
    required List<Map<String, String>> selections,
  }) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      throw Exception('Bạn cần đăng nhập để đặt sân.');
    }

    final token = await user.getIdToken();

    if (token == null || token.isEmpty) {
      throw Exception('Không lấy được phiên đăng nhập.');
    }

    final response = await http.post(
      Uri.parse('$baseUrl/bookings'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'fieldId': fieldId,
        'selections': selections,
      }),
    ).timeout(const Duration(seconds: 20));

    final data = jsonDecode(utf8.decode(response.bodyBytes));

    if (response.statusCode != 201) {
      throw Exception(
        data['message'] ?? 'Không thể tạo đơn đặt sân.',
      );
    }

    return Map<String, dynamic>.from(data);
  }
}
