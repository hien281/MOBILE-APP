import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api_client.dart';
import '../favorite_service.dart';
import 'booking.dart';
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
        final List<dynamic> data = jsonDecode(utf8.decode(res.bodyBytes));
        final all = data.map((json) => SportsField.fromJson(json)).toList();
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
        duration: const Duration(seconds: 2),
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
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primary),
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
                          const SizedBox(height: 8),
                          const Text(
                            'Nhấn vào biểu tượng trái tim ở các sân để lưu lại xem sau nhé!',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: Color(0xFF77748E)),
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
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDFDCF9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
                  child: Image.network(
                    field.imageUrl,
                    height: 150,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      height: 150,
                      color: const Color(0xFFE8EDDF),
                      child: const Center(
                        child: Icon(Icons.sports_rounded, size: 40, color: primary),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    child: IconButton(
                      icon: const Icon(Icons.favorite_rounded, color: Colors.redAccent, size: 20),
                      onPressed: () => _toggleFavorite(field),
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          field.sport,
                          style: const TextStyle(color: primary, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.star_rounded, color: Color(0xFFF4B740), size: 16),
                      const SizedBox(width: 3),
                      Text(
                        field.rating.toStringAsFixed(1),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    field.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primary),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, color: Color(0xFF77748E), size: 14),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          field.address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFF77748E)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_formatPrice(field.price)}đ / giờ',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: primary),
                      ),
                      FilledButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BookingScreen(
                                fieldId: field.id,
                                fieldName: field.name,
                                price: field.price,
                                baseUrl: ApiClient.baseUrl,
                                accessToken: widget.accessToken,
                              ),
                            ),
                          );
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Đặt sân', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
