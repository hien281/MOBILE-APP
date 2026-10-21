import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  static const String baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://mobile-app-nine-lac.vercel.app/api',
);

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    final dynamic decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Dữ liệu trả về từ máy chủ không hợp lệ.');
    }
    if (response.statusCode >= 200 && response.statusCode < 300) return decoded;
    throw Exception(decoded['message'] ?? 'Đăng nhập thất bại.');
  }
  static Future<List<Map<String, dynamic>>> getFields() async {
  final response = await http
      .get(Uri.parse('$baseUrl/fields'))
      .timeout(const Duration(seconds: 15));

  if (response.statusCode != 200) {
    throw Exception(
      'Không tải được danh sách sân (HTTP ${response.statusCode})',
    );
  }

  final decoded = jsonDecode(utf8.decode(response.bodyBytes));

  if (decoded is! Map || decoded['fields'] is! List) {
    throw Exception('Dữ liệu sân không hợp lệ');
  }

  return (decoded['fields'] as List)
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();
  }
}
