import 'package:shared_preferences/shared_preferences.dart';

class FavoriteService {
  static const String _prefKey = 'user_favorite_field_ids';

  /// Lấy danh sách ID sân yêu thích từ SharedPreferences
  static Future<Set<String>> getFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefKey) ?? [];
      return list.toSet();
    } catch (_) {
      return {};
    }
  }

  /// Bật/tắt trạng thái yêu thích của một sân
  static Future<bool> toggleFavorite(String fieldId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = (prefs.getStringList(_prefKey) ?? []).toSet();
      bool isFav;
      if (list.contains(fieldId)) {
        list.remove(fieldId);
        isFav = false;
      } else {
        list.add(fieldId);
        isFav = true;
      }
      await prefs.setStringList(_prefKey, list.toList());
      return isFav;
    } catch (_) {
      return false;
    }
  }

  /// Kiểm tra 1 sân có được yêu thích không
  static Future<bool> isFavorite(String fieldId) async {
    final favs = await getFavorites();
    return favs.contains(fieldId);
  }
}
