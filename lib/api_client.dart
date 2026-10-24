import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  static const String baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://mobile-app-nine-lac.vercel.app/api',
);

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
}
