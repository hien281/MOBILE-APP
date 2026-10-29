import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'dart:convert';

import '../api_client.dart';
import 'membership_payment_screen.dart';

class ExploreScreen extends StatefulWidget {
  final String accessToken;

  const ExploreScreen({super.key, required this.accessToken});

  @override
  State<ExploreScreen> createState() => ExploreScreenState();
}

class ExploreScreenState extends State<ExploreScreen> {
  // Chuẩn hóa bộ màu chuẩn của SPORTY đồng bộ với Trang chủ & Bản đồ
  static const Color primary = Color(0xFF1E147B);
  static const Color background = Color(0xFFF6F7EB);
  static const Color textSecondary = Color(0xFF77748E);

  // 3 Banner phân khu cố định theo môn thể thao
  final Map<String, String> _sportBanners = {
    'Pickleball': 'https://static.foxnews.com/foxnews.com/content/uploads/2024/07/pickleball-paddle-court.jpg',
    'Cầu lông': 'https://cdn2.fptshop.com.vn/unsafe/1920x0/filters:format(webp):quality(75)/Cau_long_tieng_Anh_la_gi_cover_ce00312387.png',
    'Bóng đá': 'https://encrypted-tbn0.gstatic.com/images?q=tbn:ANd9GcSadgiHiVWw2W7RLErXymZJ9B4V9mAz68Pr-y8VaKxU9I8HDVyzNYeZtueS&s=10',
  };

  String _selectedCategory = 'Tất cả';
  bool _loading = false;
  List<Map<String, dynamic>> _items = [];

  final List<String> _categories = ['Tất cả', 'Sự kiện', 'Gói hội viên'];

  @override
  void initState() {
    super.initState();
    _fetchExploreData();
  }

  Future<void> _fetchExploreData() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final membershipSnapshot = await FirebaseFirestore.instance
          .collection('memberships')
          .get();
      final memberships = membershipSnapshot.docs.map((doc) {
        return <String, dynamic>{
          ...doc.data(),
          'id': doc.id,
          'category': 'Gói hội viên',
        };
      }).toList();

      final eventSnapshot = await FirebaseFirestore.instance
          .collection('event')
          .get();
      final events = eventSnapshot.docs.map((doc) {
        return <String, dynamic>{
          ...doc.data(),
          'id': doc.id,
          'category': 'Sự kiện',
        };
      }).toList();

      if (mounted && (memberships.isNotEmpty || events.isNotEmpty)) {
        setState(() {
          _items = [...memberships, ...events];
          _loading = false;
        });
        return;
      }
      _useMockData();
    } catch (e) {
      debugPrint('Lỗi kết nối Firebase Firestore: $e');
      _useMockData();
    }
  }

  void _useMockData() {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _items = [
        {
          'id': 'mem_01',
          'category': 'Gói hội viên',
          'venue': 'Swin Pickleball',
          'distance': '1.5km',
          'address': '218A Thành Thái, Quận 10, Thành phố Hồ Chí Minh',
          'postTime': '08:00 28/10/2026',
          'tag': '#uudaigoihoivien',
          'cardName': 'Thẻ Hội Viên Swin Pass Sáng & Trưa',
          'openSale': '01/11/2026 - 31/12/2026',
          'applyTime': '06:00 - 16:00 (Thứ 2 - Thứ 6)',
          'duration': '1 Tháng',
          'freeSlots': '30',
          'sport': 'Pickleball',
          'logoUrl': 'https://images.unsplash.com/photo-1626224583764-f87db24ac4ea?auto=format&fit=crop&w=150&q=80',
          'price': 850000,
          'description': 'Gói tập tự do khung giờ sáng và trưa tại Swin Pickleball dành cho hội viên.',
          'policy': 'Thẻ có hiệu lực 30 ngày kể từ ngày kích hoạt.',
          'benefits': 'Miễn phí mượn bóng và vợt tập.',
        },
      ];
    });
  }

  List<Map<String, dynamic>> get _filteredItems {
    if (_selectedCategory == 'Tất cả') return _items;
    return _items.where((e) {
      final cat = (e['category'] ?? '').toString().trim().toLowerCase();
      final selected = _selectedCategory.trim().toLowerCase();
      return cat == selected;
    }).toList();
  }

  String _formatMoney(int amount) {
    return amount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            // Filter Chips (Tất cả, Sự kiện, Gói hội viên)
            SizedBox(
              height: 40,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final isSelected = cat == _selectedCategory;
                  return GestureDetect(
                    onTap: () => setState(() => _selectedCategory = cat),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected ? primary : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected ? primary : const Color(0xFFE5E7EB),
                        ),
                      ),
                      child: Text(
                        cat,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            // Danh sách hiển thị
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: primary),
                    )
                  : RefreshIndicator(
                      onRefresh: _fetchExploreData,
                      child: _selectedCategory == 'Tất cả'
                          ? _buildAllGroupedBySportList()
                          : _buildSingleCategoryList(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // Giao diện tab "Tất cả": Gom nhóm bài viết theo môn & chỉ hiện đúng 3 Banner cố định
  Widget _buildAllGroupedBySportList() {
    final List<String> sportsOrder = ['Pickleball', 'Cầu lông', 'Bóng đá'];
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: sportsOrder.length + 1,
      itemBuilder: (context, sportIndex) {
        // Hiển thị cả những bài viết có môn thể thao chưa được phân nhóm.
        if (sportIndex == sportsOrder.length) {
          final ungrouped = _items.where((item) {
            final sport = (item['sport'] ?? '').toString().trim().toLowerCase();
            return !sportsOrder.any((name) => name.toLowerCase() == sport);
          }).toList();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: ungrouped.map((item) {
              final category = (item['category'] ?? '').toString().trim().toLowerCase();
              return category == 'sự kiện' || category == 'event'
                  ? _buildEventNewsCard(item)
                  : _buildMembershipCard(item);
            }).toList(),
          );
        }
        final sportName = sportsOrder[sportIndex];
        final bannerUrl = _sportBanners[sportName];

        final sportItems = _items.where((e) {
          final s = (e['sport'] ?? '').toString().trim().toLowerCase();
          return s == sportName.toLowerCase();
        }).toList();

        if (sportItems.isEmpty && bannerUrl == null) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (bannerUrl != null) ...[
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 14),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 16 / 5.5,
                    child: Image.network(
                      bannerUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ],
            ...sportItems.map((item) {
              final cat = (item['category'] ?? '')
                  .toString()
                  .trim()
                  .toLowerCase();
              if (cat == 'sự kiện' || cat == 'event') {
                return _buildEventNewsCard(item);
              }
              return _buildMembershipCard(item);
            }),
          ],
        );
      },
    );
  }

  // Giao diện khi chọn riêng từng tab "Sự kiện" hoặc "Gói hội viên"
  Widget _buildSingleCategoryList() {
    final list = _filteredItems;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final item = list[index];
        final cat = (item['category'] ?? '').toString().trim().toLowerCase();
        if (cat == 'sự kiện' || cat == 'event') {
          return _buildEventNewsCard(item);
        }
        return _buildMembershipCard(item);
      },
    );
  }

  // Thẻ Tin Tức / Sự Kiện Giải Đấu
  Widget _buildEventNewsCard(Map<String, dynamic> item) {
    return GestureDetector(
      onTap: () => _showEventDetail(context, item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.campaign_rounded, color: primary, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    item['venue'] ?? 'SPORTY News',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  (item['postTime'] ?? '').toString(),
                  style: const TextStyle(fontSize: 11, color: textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  (item['imageUrl'] ?? '').toString(),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: const Color(0xFFF3F0FF),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.sports_score, color: primary, size: 36),
                        SizedBox(height: 4),
                        Text(
                          'Thông tin giải đấu',
                          style: TextStyle(color: primary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              (item['title'] ?? '').toString(),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: primary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              (item['content'] ?? '').toString(),
              style: const TextStyle(
                fontSize: 12,
                color: textSecondary,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
                onPressed: () => _showEventDetail(context, item),
                icon: const Text(
                  'Xem chi tiết',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                label: const Icon(Icons.chevron_right, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Modal hiển thị chi tiết bài viết Sự kiện / Giải đấu
  void _showEventDetail(BuildContext parentContext, Map<String, dynamic> item) {
    showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: const BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios,
                        color: Colors.white,
                        size: 18,
                      ),
                      onPressed: () => Navigator.of(modalCtx).pop(),
                    ),
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Chi tiết tin tức & sự kiện',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const Icon(Icons.share, color: Colors.white, size: 20),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Image.network(
                          (item['imageUrl'] ?? '').toString(),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                color: const Color(0xFFF3F0FF),
                                child: const Icon(
                                  Icons.sports_score,
                                  color: primary,
                                  size: 48,
                                ),
                              ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F0FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            item['venue'] ?? 'SPORTY News',
                            style: const TextStyle(
                              color: primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          (item['postTime'] ?? '').toString(),
                          style: const TextStyle(
                            fontSize: 12,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      (item['title'] ?? '').toString(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: primary,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: Color(0xFFE5E7EB)),
                    const SizedBox(height: 12),
                    Text(
                      (item['content'] ?? '').toString(),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Thẻ Gói Hội Viên
  Widget _buildMembershipCard(Map<String, dynamic> item) {
    final String sport = (item['sport'] ?? 'Pickleball').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: Image.network(
                    (item['logoUrl'] ?? '').toString(),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) =>
                        const CircleAvatar(
                          radius: 19,
                          backgroundColor: primary,
                          child: Icon(
                            Icons.sports_tennis,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (item['venue'] ?? '').toString(),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: primary,
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          '(${item['distance'] ?? ''}) ',
                          style: const TextStyle(
                            fontSize: 11,
                            color: primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            (item['address'] ?? '').toString(),
                            style: const TextStyle(
                              fontSize: 11,
                              color: textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            (item['postTime'] ?? '').toString(),
            style: const TextStyle(fontSize: 10, color: textSecondary),
          ),
          const SizedBox(height: 8),
          const Text(
            'Ưu đãi gói hội viên mới',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          Text(
            (item['tag'] ?? '#uudaigoihoivien').toString(),
            style: const TextStyle(
              color: primary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F0FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFDDD6FE)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '1 Thẻ hội viên',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  (item['cardName'] ?? '').toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Mở bán : ${item['openSale'] ?? ''}',
                  style: const TextStyle(fontSize: 11, color: textSecondary),
                ),
                Text(
                  'Giờ áp dụng: ${item['applyTime'] ?? ''}',
                  style: const TextStyle(fontSize: 11, color: textSecondary),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildMiniFeature(
                      Icons.access_time,
                      'Thời hạn',
                      (item['duration'] ?? '').toString(),
                      primary,
                    ),
                    _buildMiniFeature(
                      Icons.check_circle_outline,
                      'Lượt miễn phí',
                      (item['freeSlots'] ?? '').toString(),
                      primary,
                    ),
                    _buildMiniFeature(
                      Icons.sports_golf,
                      'Loại sân',
                      sport,
                      primary,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_formatMoney((item['price'] is num) ? (item['price'] as num).toInt() : int.tryParse(item['price']?.toString() ?? '') ?? 0)} đ',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: primary,
                      ),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      onPressed: () => _showMembershipDetail(context, item),
                      icon: const Text(
                        'Đăng ký',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      label: const Icon(Icons.chevron_right, size: 16),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniFeature(
    IconData icon,
    String label,
    String val,
    Color color,
  ) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 3),
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            val,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>> _createMembershipOrder(
    String membershipId,
  ) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();

    if (token == null || token.isEmpty) {
      throw Exception('Vui lòng đăng nhập để mua thẻ.');
    }

    final response = await http
        .post(
          Uri.parse('${ApiClient.baseUrl}/membership-orders'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'membershipId': membershipId}),
        )
        .timeout(const Duration(seconds: 20));

    final data = jsonDecode(utf8.decode(response.bodyBytes));

    if (data is! Map || data['success'] != true) {
      throw Exception(
        data is Map
            ? (data['message'] ?? 'Không thể tạo đơn hội viên.')
            : 'Phản hồi backend không hợp lệ.',
      );
    }

    return Map<String, dynamic>.from(data);
  }

  // Modal Chi Tiết Thẻ Hội Viên & Thanh Toán
  void _showMembershipDetail(
    BuildContext parentContext,
    Map<String, dynamic> item,
  ) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final nameController = TextEditingController(
      text: currentUser?.displayName ?? '',
    );
    final phoneController = TextEditingController(
      text: currentUser?.phoneNumber ?? '',
    );

    showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF4F5F0),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Header Modal
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: const BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.arrow_back_ios,
                        color: Colors.white,
                        size: 18,
                      ),
                      onPressed: () => Navigator.of(modalCtx).pop(),
                    ),
                    const Expanded(
                      child: Center(
                        child: Text(
                          'Chi tiết Thẻ hội viên',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const Icon(Icons.share, color: Colors.white, size: 20),
                  ],
                ),
              ),

              // Nội dung Modal
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: primary,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (item['venue'] ?? '').toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            (item['cardName'] ?? '').toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _buildMiniFeature(
                                Icons.access_time,
                                'Thời hạn',
                                (item['duration'] ?? '').toString(),
                                Colors.amber.shade300,
                              ),
                              _buildMiniFeature(
                                Icons.check_circle_outline,
                                'Lượt miễn phí',
                                (item['freeSlots'] ?? '').toString(),
                                Colors.amber.shade300,
                              ),
                              _buildMiniFeature(
                                Icons.sports_golf,
                                'Loại sân',
                                (item['sport'] ?? '').toString(),
                                Colors.amber.shade300,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    _buildSectionBox(
                      'Thông tin chương trình',
                      (item['description'] ?? '').toString(),
                    ),
                    _buildSectionBox(
                      'Chính sách chương trình',
                      (item['policy'] ?? '').toString(),
                    ),
                    _buildSectionBox(
                      'Quyền lợi đi kèm',
                      (item['benefits'] ?? '').toString(),
                    ),
                    const SizedBox(height: 12),

                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Thông tin khách hàng',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: nameController,
                            decoration: const InputDecoration(
                              labelText: 'Họ và tên *',
                              hintText: 'Nhập họ và tên người đăng ký',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Số điện thoại *',
                              hintText: 'Nhập số điện thoại liên hệ',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom Bar Thanh Toán
              Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Tổng tiền',
                          style: TextStyle(fontSize: 11, color: textSecondary),
                        ),
                        Text(
                          '${_formatMoney((item['price'] is num) ? (item['price'] as num).toInt() : int.tryParse(item['price']?.toString() ?? '') ?? 0)} đ',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: primary,
                          ),
                        ),
                      ],
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () async {
                        try {
                          final membershipId = item['id']?.toString() ?? '';

                          if (membershipId.isEmpty) {
                            throw Exception('Không tìm thấy mã gói hội viên.');
                          }

                          final order = await _createMembershipOrder(
                            membershipId,
                          );

                          final orderId = order['orderId']?.toString();
                          final totalPrice = (order['totalPrice'] as num?)
                              ?.toInt();
                          final expiresAt = DateTime.tryParse(
                            order['expiresAt']?.toString() ?? '',
                          );

                          if (orderId == null ||
                              orderId.isEmpty ||
                              totalPrice == null ||
                              expiresAt == null) {
                            throw Exception(
                              'Dữ liệu đơn hội viên không hợp lệ.',
                            );
                          }

                          if (modalCtx.mounted) {
                            Navigator.of(modalCtx).pop();
                          }
                          if (parentContext.mounted) {
                          Navigator.of(parentContext, rootNavigator: true).push(
                            MaterialPageRoute(
                              builder: (_) => MembershipPaymentScreen(
                                orderId: orderId,
                                membershipName:
                                    order['membershipName']?.toString() ??
                                    item['cardName']?.toString() ??
                                    'Thẻ hội viên',
                                totalPrice: totalPrice,
                                expiresAt: expiresAt,
                                baseUrl: ApiClient.baseUrl,
                              ),
                            ),
                          );
                        }

                        } catch (e) {
                          if (parentContext.mounted) {
                            ScaffoldMessenger.of(parentContext).showSnackBar(
                              SnackBar(content: Text('Không thể tạo đơn: $e')),
                            );
                          }
                        }
                      },
                      child: const Text(
                        'Thanh toán ngay',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionBox(String title, String content) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: primary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            content,
            style: const TextStyle(
              fontSize: 12,
              color: textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class GestureDetect extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;

  const GestureDetect({super.key, required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }
}
