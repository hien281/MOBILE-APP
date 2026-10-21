import 'package:flutter/material.dart';
import '../api_client.dart';
import 'booking.dart';

const Color oliveGreen = Color(0xFF1E147B);
const Color pageBackground = Color(0xFFF6F7EB);
const Color textPrimary = Color(0xFF1E147B);
const Color textSecondary = Color(0xFF77748E);

class SportsField {
  final String id;
  final String name;
  final String sport;
  final String address;
  final int price;
  final double rating;
  final String imageUrl;
  final bool isPopular;

  factory SportsField.fromJson(Map<String, dynamic> json) => SportsField(
    id: json['id'].toString(),
    name: json['name'].toString(),
    sport: json['sport'].toString(),
    address: json['address'].toString(),
    price: (json['price'] as num).toInt(),
    rating: (json['rating'] as num).toDouble(),
    imageUrl: json['imageUrl'].toString(),
    isPopular: json['isPopular'] == true,
  );

  const SportsField({
    required this.id,
    required this.name,
    required this.sport,
    required this.address,
    required this.price,
    required this.rating,
    required this.imageUrl,
    this.isPopular = false,
  });
}

class HomeScreen extends StatefulWidget {
  final String accessToken;

  const HomeScreen({
    super.key,
    required this.accessToken,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController =
      TextEditingController();

  String _selectedSport = 'Tất cả';
  String _searchQuery = '';
  int _selectedNavIndex = 0;

  final Set<String> _favoriteIds = {};

  final List<String> _sports = [
    'Tất cả',
    'Bóng đá',
    'Cầu lông',
    'Tennis',
    'Bóng rổ',
  ];

  List<SportsField> _fields = [];
  bool _loadingFields = true;
  String? _fieldsError;

  @override
  void initState() {
    super.initState();
    _loadFields();
  }

  Future<void> _loadFields() async {
    setState(() { _loadingFields = true; _fieldsError = null; });
    try {
      final data = await ApiClient.getFields();
      if (!mounted) return;
      setState(() { _fields = data.map(SportsField.fromJson).toList(); _loadingFields = false; });
    } catch (error) {
      if (!mounted) return;
      setState(() { _fieldsError = error.toString().replaceFirst('Exception: ', ''); _loadingFields = false; });
    }
  }

  List<SportsField> get _filteredFields {
    return _fields.where((field) {
      final matchesSport = _selectedSport == 'Tất cả' ||
          field.sport == _selectedSport;

      final query = _searchQuery.trim().toLowerCase();
      final matchesSearch = query.isEmpty ||
          field.name.toLowerCase().contains(query) ||
          field.address.toLowerCase().contains(query) ||
          field.sport.toLowerCase().contains(query);

      final matchesTab = true;

      return matchesSport && matchesSearch && matchesTab;
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatPrice(int price) {
    final value = price.toString();
    final buffer = StringBuffer();

    for (int i = 0; i < value.length; i++) {
      if (i > 0 && (value.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(value[i]);
    }

    return buffer.toString();
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature sẽ được phát triển ở bước tiếp theo.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: oliveGreen,
      ),
    );
  }

  void _onNavTap(int index) {
    setState(() => _selectedNavIndex = index);
    if (index == 1) _showComingSoon('Bản đồ');
    if (index == 3) _showComingSoon('Lịch của tôi');
    if (index == 4) _showComingSoon('Tài khoản');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBackground,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 700;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: CustomScrollView(
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isWide ? 32 : 20,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 20),
                            _buildHeader(),
                            const SizedBox(height: 24),
                            _buildSearchBar(),
                            const SizedBox(height: 28),
                            _buildSectionTitle(
                              'Khám phá thể thao',
                              subtitle: 'Chọn môn thể thao bạn yêu thích',
                            ),
                            const SizedBox(height: 16),
                            _buildSportCategories(isWide),
                            const SizedBox(height: 28),
                            _buildPromoBanner(),
                            const SizedBox(height: 28),
                            _buildFieldHeading(),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isWide ? 32 : 20,
                      ),
                      sliver: _buildFieldGrid(isWide),
                    ),
                    const SliverToBoxAdapter(
                      child: SizedBox(height: 28),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: _buildBottomNavigation(),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: oliveGreen,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(
            Icons.sports_soccer_rounded,
            color: Colors.white,
            size: 28,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SPORTY',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    color: oliveGreen,
                    size: 15,
                  ),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      'TP. Hồ Chí Minh',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Thông báo',
          onPressed: () => _showComingSoon('Thông báo'),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            fixedSize: const Size(46, 46),
          ),
          icon: const Icon(
            Icons.notifications_none_rounded,
            color: textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: const Color(0xFFDFDCF9)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.search_rounded,
            color: oliveGreen,
            size: 25,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
              decoration: const InputDecoration(
                hintText: 'Tìm sân, môn thể thao...',
                hintStyle: TextStyle(
                  color: textSecondary,
                  fontSize: 14,
                ),
                border: InputBorder.none,
                isCollapsed: true,
              ),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            IconButton(
              tooltip: 'Xóa tìm kiếm',
              onPressed: () {
                _searchController.clear();
                setState(() => _searchQuery = '');
              },
              icon: const Icon(Icons.close_rounded, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(
    String title, {
    String? subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: textPrimary,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: const TextStyle(
              color: textSecondary,
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSportCategories(bool isWide) {
    final icons = <String, IconData>{
      'Tất cả': Icons.grid_view_rounded,
      'Bóng đá': Icons.sports_soccer_rounded,
      'Cầu lông': Icons.sports_tennis_rounded,
      'Tennis': Icons.sports_tennis_rounded,
      'Bóng rổ': Icons.sports_basketball_rounded,
    };

    if (isWide) {
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: _sports.map((sport) {
          return SizedBox(
            width: 125,
            child: _sportItem(sport, icons[sport]!),
          );
        }).toList(),
      );
    }

    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _sports.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final sport = _sports[index];
          return SizedBox(
            width: 82,
            child: _sportItem(sport, icons[sport]!),
          );
        },
      ),
    );
  }

  Widget _sportItem(String sport, IconData icon) {
    final isSelected = _selectedSport == sport;

    return Material(
      color: isSelected ? oliveGreen : Colors.white,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: () {
          setState(() => _selectedSport = sport);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: 14,
            horizontal: 8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: isSelected
                  ? oliveGreen
                  : const Color(0xFFDFDCF9),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 25,
                color: isSelected ? Colors.white : oliveGreen,
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  sport,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPromoBanner() {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 155),
      decoration: BoxDecoration(
        color: oliveGreen,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -25,
            top: -30,
            child: Container(
              width: 155,
              height: 155,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha:0.08),
              ),
            ),
          ),
          Positioned(
            right: 18,
            bottom: -38,
            child: Icon(
              Icons.sports_tennis_rounded,
              size: 140,
              color: Colors.white.withValues(alpha:0.14),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha:0.18),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'SPORTY MEMBER',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Sẵn sàng ra sân?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Tìm sân phù hợp và bắt đầu trận đấu!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _selectedSport = 'Tất cả';
                      _selectedNavIndex = 0;
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: oliveGreen,
                    backgroundColor: Colors.white,
                    side: BorderSide.none,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Khám phá ngay',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldHeading() {
    final title = _selectedSport == 'Tất cả' ? 'Sân nổi bật' : 'Sân $_selectedSport';

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: textPrimary,
            ),
          ),
        ),
        Text(
          '${_filteredFields.length} sân',
          style: const TextStyle(
            fontSize: 12,
            color: textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildFieldGrid(bool isWide) {
    if (_loadingFields) {
      return const SliverToBoxAdapter(child: Padding(
        padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()),
      ));
    }
    if (_fieldsError != null) {
      return SliverToBoxAdapter(child: Column(children: [
        Text(_fieldsError!, textAlign: TextAlign.center),
        TextButton(onPressed: _loadFields, child: const Text('Thử lại')),
      ]));
    }
    final fields = _filteredFields;

    if (fields.isEmpty) {
      return SliverToBoxAdapter(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 45),
          alignment: Alignment.center,
          child: Column(
            children: [
              Icon(
                _selectedNavIndex == 1
                    ? Icons.favorite_border_rounded
                    : Icons.search_off_rounded,
                size: 48,
                color: textSecondary,
              ),
              const SizedBox(height: 12),
              const Text(
                'Chưa tìm thấy sân phù hợp',
                style: TextStyle(
                  color: textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Thử đổi từ khóa hoặc danh mục nhé.',
                style: TextStyle(
                  color: textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final columns = width >= 800 ? 3 : width >= 520 ? 2 : 1;
        const spacing = 16.0;
        final cardWidth =
            (width - spacing * (columns - 1)) / columns;

        return SliverList(
          delegate: SliverChildListDelegate(
            [
              Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: fields.map((field) {
                  return SizedBox(
                    width: cardWidth,
                    child: _buildFieldCard(field),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFieldCard(SportsField field) {
    final isFavorite = _favoriteIds.contains(field.id);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDFDCF9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha:0.025),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(21),
            ),
            child: Stack(
              children: [
                SizedBox(
                  height: 175,
                  width: double.infinity,
                  child: Image.network(
                    field.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: const Color(0xFFE8EDDF),
                        child: const Center(
                          child: Icon(
                            Icons.sports_rounded,
                            size: 48,
                            color: oliveGreen,
                          ),
                        ),
                      );
                    },
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;

                      return Container(
                        color: const Color(0xFFF0F2EB),
                        alignment: Alignment.center,
                        child: const CircularProgressIndicator(
                          color: oliveGreen,
                          strokeWidth: 2,
                        ),
                      );
                    },
                  ),
                ),
                if (field.isPopular)
                  Positioned(
                    left: 12,
                    top: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.local_fire_department_rounded,
                            size: 15,
                            color: Color(0xFFE78A36),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Nổi bật',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  right: 12,
                  top: 12,
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: isFavorite
                          ? 'Bỏ yêu thích'
                          : 'Thêm vào yêu thích',
                      constraints: const BoxConstraints(
                        minWidth: 38,
                        minHeight: 38,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: () {
                        setState(() {
                          if (isFavorite) {
                            _favoriteIds.remove(field.id);
                          } else {
                            _favoriteIds.add(field.id);
                          }
                        });
                      },
                      icon: Icon(
                        isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: isFavorite
                            ? Colors.redAccent
                            : textPrimary,
                        size: 21,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: oliveGreen.withValues(alpha:0.09),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        field.sport,
                        style: const TextStyle(
                          color: oliveGreen,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.star_rounded,
                      color: Color(0xFFF4B740),
                      size: 18,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      field.rating.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 11),
                Text(
                  field.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: textSecondary,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        field.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                const Divider(height: 1, color: Color(0xFFF0F1EC)),
                const SizedBox(height: 13),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_formatPrice(field.price)}đ',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w900,
                              color: oliveGreen,
                            ),
                          ),
                          const Text(
                            '/ giờ',
                            style: TextStyle(
                              fontSize: 11,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton(
                      onPressed: () async {
                        final booked = await Navigator.push<bool>(
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

                        if (!mounted) return;

                        if (booked == true) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Đặt sân thành công!'),
                            ),
                          );
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: oliveGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Đặt sân',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
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

  Widget _buildBottomNavigation() {
    const items = [
      (icon: Icons.home_rounded, label: 'Trang chủ'),
      (icon: Icons.map_outlined, label: 'Bản đồ'),
      (icon: Icons.explore_outlined, label: 'Khám phá'),
      (icon: Icons.calendar_month_outlined, label: 'Lịch của tôi'),
      (icon: Icons.person_outline_rounded, label: 'Tài khoản'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFDFDCF9))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final selected = _selectedNavIndex == index;
              final center = index == 2;
              return Expanded(
                child: InkWell(
                  onTap: () => _onNavTap(index),
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: center ? 48 : 38,
                        height: center ? 48 : 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected ? const Color(0xFF1E147B)
                              : center ? const Color(0xFFDFDCF9) : Colors.transparent,
                        ),
                        child: Icon(item.icon, size: center ? 27 : 23,
                          color: selected ? const Color(0xFFFFFC31)
                              : const Color(0xFF85839A)),
                      ),
                      const SizedBox(height: 3),
                      Text(item.label, maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 9,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? oliveGreen : textSecondary)),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
