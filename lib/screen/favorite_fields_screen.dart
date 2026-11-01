import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api_client.dart';
import '../favorite_service.dart';
import 'field_detail.dart';
import 'home.dart';

class FavoriteFieldsScreen extends StatefulWidget {
  final String accessToken;
  const FavoriteFieldsScreen({super.key, required this.accessToken});

  @override
  State<FavoriteFieldsScreen> createState() => _FavoriteFieldsScreenState();
}

class _FavoriteFieldsScreenState extends State<FavoriteFieldsScreen> {
  static const Color primary = Color(0xFF1E147B);
  static const Color background = Color(0xFFF6F7EB);

  bool _loading = true;
  String? _error;
  List<SportsField> _favoriteFields = [];
  Set<String> _favoriteIds = {};

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final favIds = await FavoriteService.getFavorites();
      _favoriteIds = favIds;

      final res = await http.get(Uri.parse('${ApiClient.baseUrl}/fields'));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        List<dynamic> listData = [];
        if (decoded is List) {
          listData = decoded;
        } else if (decoded is Map && decoded['fields'] is List) {
          listData = decoded['fields'];
        }
        final all = listData
            .whereType<Map>()
            .map((item) => SportsField.fromJson(Map<String, dynamic>.from(item)))
            .toList();
        final favList = all.where((f) => favIds.contains(f.id)).toList();
        if (mounted) {
          setState(() {
            _favoriteFields = favList;
            _loading = false;
          });
        }
      } else {
        throw Exception('Không tải được danh sách sân.');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggleFavorite(SportsField field) async {
    await FavoriteService.toggleFavorite(field.id);
    if (!mounted) return;
    setState(() {
      _favoriteFields.removeWhere((f) => f.id == field.id);
      _favoriteIds.remove(field.id);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã bỏ yêu thích ${field.name}'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _formatPrice(int price) {
    final s = price.toString();
    final buffer = StringBuffer();
    int count = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      buffer.write(s[i]);
      count++;
      if (count % 3 == 0 && i != 0) buffer.write('.');
    }
    return buffer.toString().split('').reversed.join('');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: primary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Sân yêu thích',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primary),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: primary))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _loadFavorites,
                        style: ElevatedButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white),
                        child: const Text('Thử lại'),
                      ),
                    ],
                  ),
                )
              : _favoriteFields.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: const Color(0xFFDFDCF9).withValues(alpha: 0.4),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.favorite_border_rounded, size: 36, color: primary),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Chưa có sân yêu thích',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primary),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _favoriteFields.length,
                      itemBuilder: (context, index) {
                        final field = _favoriteFields[index];
                        return _buildCard(field);
                      },
                    ),
    );
  }

  Widget _buildCard(SportsField field) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      height: 104,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDFDCF9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FieldDetailScreen(
                  field: field,
                  accessToken: widget.accessToken,
                ),
              ),
            );
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(17)),
                child: SizedBox(
                  width: 104,
                  height: 104,
                  child: Image.network(
                    field.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: const Color(0xFFE8EDDF),
                      child: const Center(
                        child: Icon(Icons.sports_rounded, color: primary, size: 28),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Badge môn, sao & icon tim bỏ yêu thích
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color.fromARGB(255, 53, 22, 127),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              field.sport,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(Icons.star_rounded, color: Color(0xFFF4B740), size: 14),
                          const SizedBox(width: 2),
                          Text(
                            field.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: primary,
                            ),
                          ),
                          const Spacer(),
                          InkWell(
                            onTap: () => _toggleFavorite(field),
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(Icons.favorite_rounded, color: Colors.redAccent, size: 18),
                            ),
                          ),
                        ],
                      ),

                      // Tên sân
                      Text(
                        field.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: primary,
                        ),
                      ),

                      // Địa chỉ
                      Text(
                        field.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 8.5,
                          color: Color(0xFF77748E),
                        ),
                      ),

                      // Giá
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_formatPrice(field.price)}đ / giờ',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
