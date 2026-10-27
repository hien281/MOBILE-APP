import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api_client.dart';
import '../location_service.dart';
import 'booking.dart';
import 'field_detail.dart';
import 'search.dart';
import 'map_screen.dart';

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
  final double? latitude;
  final double? longitude;
  final String? openTime;
  final String? closingTime;
  final String? phone;
  final int courtCount;
  final List<String> facilities;
  final String? googleMapsUrl;

  static double? _coordinate(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  factory SportsField.fromJson(Map<String, dynamic> json) => SportsField(
    id: json['id'].toString(),
    name: json['name'].toString(),
    sport: json['sport'].toString(),
    address: json['address'].toString(),
    price: (json['price'] as num).toInt(),
    rating: (json['rating'] as num).toDouble(),
    imageUrl: json['imageUrl'].toString(),
    isPopular: json['isPopular'] == true,
    latitude: _coordinate(json['latitude']),
    longitude: _coordinate(json['longitude']),
    openTime: (json['openTime'] ?? json['openingTime'])?.toString(),
    closingTime: (json['closingTime'] ?? json['closeTime'])?.toString(),
    phone: json['phone']?.toString(),
    courtCount: (json['courtCount'] as num?)?.toInt() ?? 1,
    facilities: (json['facilities'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        const [],
    googleMapsUrl: json['googleMapsUrl']?.toString(),
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
    this.latitude,
    this.longitude,
    this.openTime,
    this.closingTime,
    this.phone,
    this.courtCount = 1,
    this.facilities = const [],
    this.googleMapsUrl,
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
  String _selectedSport = 'Tất cả';
  int _selectedNavIndex = 0;

  final Set<String> _favoriteIds = {};

  final List<String> _sports = [
    'Tất cả',
    'Bóng đá',
    'Cầu lông',
    'Tennis',
    'Pickleball',
  ];

  List<SportsField> _fields = [];
  bool _loadingFields = true;
  String? _fieldsError;

  String _locationLabel = 'Đang lấy vị trí...';
  bool _loadingLocation = false;
  Position? _currentPosition;
  bool _sortByDistance = false;

  @override
  void initState() {
    super.initState();
    _loadFields();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    if (_loadingLocation) return;
    setState(() {
      _loadingLocation = true;
      _locationLabel = 'Đang lấy vị trí...';
    });

    try {
      final position = await LocationService.getCurrentLocation();
      if (!mounted) return;

      final coordinates =
          '${position.latitude.toStringAsFixed(5)}, '
          '${position.longitude.toStringAsFixed(5)}';

      // Lưu GPS ngay để tính khoảng cách, không cần chờ reverse geocoding.
      setState(() {
        _currentPosition = position;
        _locationLabel = coordinates;
      });

      String label = coordinates;
      try {
        final uri = Uri.parse('${ApiClient.baseUrl}/location/reverse').replace(
          queryParameters: {
            'lat': position.latitude.toString(),
            'lon': position.longitude.toString(),
          },
        );
        final response = await http.get(uri).timeout(const Duration(seconds: 12));
        if (response.statusCode == 200) {
          final decoded = jsonDecode(utf8.decode(response.bodyBytes));
          if (decoded is Map<String, dynamic> && decoded['success'] == true) {
            final name = decoded['name'];
            if (name is String && name.trim().isNotEmpty) {
              label = name.trim();
            }
          }
        }
      } catch (error) {
        // Reverse geocoding is optional; retain the GPS coordinates on failure.
        debugPrint('Reverse geocoding unavailable: $error');
      }

      if (!mounted) return;
      setState(() {
        _locationLabel = label;
        _loadingLocation = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingLocation = false;
        _currentPosition = null;
        _locationLabel = 'Chạm để thử lại vị trí';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _loadFields() async {
    setState(() { _loadingFields = true; _fieldsError = null; });
    try {
      // Fetch directly from the active API to avoid stale getFields() URLs.
      final uri = Uri.parse('${ApiClient.baseUrl}/fields').replace(
        queryParameters: {'_fresh': DateTime.now().millisecondsSinceEpoch.toString()},
      );
      debugPrint('SPORTY fields API: $uri');
      final response = await http.get(
        uri,
        headers: {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('Không tải được danh sách sân (HTTP ${response.statusCode}).');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['fields'] is! List) {
        throw Exception('Dữ liệu sân từ API không hợp lệ.');
      }
      for (final item in decoded['fields'] as List) {
        if (item is Map) {
          debugPrint('SPORTY FIELD ${item['id']}: lat=${item['latitude']} lon=${item['longitude']}');
        }
      }
      final fields = (decoded['fields'] as List).map((item) {
        if (item is! Map) throw const FormatException('Dữ liệu sân lỗi');
        return SportsField.fromJson(Map<String, dynamic>.from(item));
      }).toList();
      if (!mounted) return;
      setState(() { _fields = fields; _loadingFields = false; });
    } catch (error) {
      if (!mounted) return;
      setState(() { _fieldsError = error.toString().replaceFirst('Exception: ', ''); _loadingFields = false; });
    }
  }

  double? _distanceKm(SportsField field) {
    final position = _currentPosition;
    final lat = field.latitude;
    final lon = field.longitude;
    if (position == null || lat == null || lon == null ||
        !lat.isFinite || !lon.isFinite ||
        lat < -90 || lat > 90 || lon < -180 || lon > 180) {
      return null;
    }
    return Geolocator.distanceBetween(
      position.latitude, position.longitude, lat, lon,
    ) / 1000;
  }

  String _distanceLabel(double km) {
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  List<SportsField> get _filteredFields {
    final result = _fields.where((field) {
      return _selectedSport == 'Tất cả' ||
          field.sport.toLowerCase() == _selectedSport.toLowerCase();
    }).toList();

    if (_sortByDistance) {
      result.sort((a, b) {
        final da = _distanceKm(a);
        final db = _distanceKm(b);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });
    }

    return result;
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
    if (index == 4) {
      _showAccountDialog();
      return;
    }
    setState(() => _selectedNavIndex = index);
    if (index == 1) {
      _openMapScreen();
      return;
    }
    if (index == 2) _showComingSoon('Khám phá');
    if (index == 3) _showComingSoon('Lịch của tôi');
  }

  Future<void> _showAccountDialog() async {
    final user = FirebaseAuth.instance.currentUser;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tài khoản SPORTY'),
        content: Text(user?.email ?? 'Chưa có email'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Đóng')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await FirebaseAuth.instance.signOut();
            },
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: pageBackground,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
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
    ),
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
              Text(
                'Xin chào, ${FirebaseAuth.instance.currentUser?.displayName?.trim().isNotEmpty == true ? FirebaseAuth.instance.currentUser!.displayName!.trim() : (FirebaseAuth.instance.currentUser?.email?.split('@').first ?? 'bạn')}!',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              InkWell(
                onTap: _loadingLocation ? null : _loadLocation,
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: oliveGreen,
                      size: 15,
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        _locationLabel,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (_loadingLocation) ...[
                      const SizedBox(width: 6),
                      const SizedBox(
                        width: 11,
                        height: 11,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                    ],
                  ],
                ),
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

  void _openMapScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapScreen(
          allFields: _fields,
          currentPosition: _currentPosition,
          accessToken: widget.accessToken,
          favoriteIds: _favoriteIds,
          onToggleFavorite: (id) {
            setState(() {
              if (_favoriteIds.contains(id)) {
                _favoriteIds.remove(id);
              } else {
                _favoriteIds.add(id);
              }
            });
          },
        ),
      ),
    );
  }

  void _openSearchScreen({bool autoFocus = true, bool openFilter = false}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchScreen(
          allFields: _fields,
          initialSport: _selectedSport,
          autoFocus: autoFocus,
          openFilterImmediately: openFilter,
          currentPosition: _currentPosition,
          accessToken: widget.accessToken,
          favoriteIds: _favoriteIds,
          onToggleFavorite: (id) {
            setState(() {
              if (_favoriteIds.contains(id)) {
                _favoriteIds.remove(id);
              } else {
                _favoriteIds.add(id);
              }
            });
          },
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFDFDCF9),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.search_rounded,
            color: oliveGreen,
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              onTap: () => _openSearchScreen(autoFocus: true),
              child: Container(
                alignment: Alignment.centerLeft,
                child: const Text(
                  'Tìm sân, môn thể thao, khu vực...',
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
          Container(
            height: 24,
            width: 1,
            color: const Color(0xFFDFDCF9),
            margin: const EdgeInsets.symmetric(horizontal: 4),
          ),
          IconButton(
            tooltip: 'Bộ lọc tìm kiếm',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _openSearchScreen(autoFocus: false, openFilter: true),
            icon: const Icon(
              Icons.tune_rounded,
              color: oliveGreen,
              size: 22,
            ),
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
      'Pickleball': Icons.sports_baseball_rounded,
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
        if (_currentPosition != null) ...[
          TextButton.icon(
            onPressed: () => setState(() => _sortByDistance = !_sortByDistance),
            icon: Icon(_sortByDistance ? Icons.check_circle : Icons.near_me_outlined, size: 16),
            label: Text(_sortByDistance ? 'Gần nhất ✓' : 'Gần nhất'),
            style: TextButton.styleFrom(
              foregroundColor: oliveGreen,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
          ),
        ],
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


  void _openFieldDetail(SportsField field) {
    final distance = _distanceKm(field);
    final distanceLabel = distance != null ? 'Cách bạn ' : null;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FieldDetailScreen(
          field: field,
          distanceLabel: distanceLabel,
          accessToken: widget.accessToken,
        ),
      ),
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
                GestureDetector(
                  onTap: () => _openFieldDetail(field),
                  child: SizedBox(
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
                GestureDetector(
                  onTap: () => _openFieldDetail(field),
                  child: Text(
                    field.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: textPrimary,
                    ),
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
                const SizedBox(height: 7),
                Builder(builder: (context) {
                  final distance = _distanceKm(field);
                  final hasCoordinates = field.latitude != null && field.longitude != null;
                  final message = distance != null
                      ? 'Cách bạn ${_distanceLabel(distance)}'
                      : _loadingLocation
                          ? 'Đang xác định khoảng cách...'
                          : _currentPosition == null
                              ? 'Chưa có vị trí của bạn · Chạm vị trí phía trên để thử lại'
                              : !hasCoordinates
                                  ? 'Sân chưa có tọa độ từ API'
                                  : 'Tọa độ sân không hợp lệ';
                  return Row(children: [
                    Icon(Icons.near_me_outlined, size: 15,
                      color: distance == null ? textSecondary : oliveGreen),
                    const SizedBox(width: 5),
                    Expanded(child: Text(message,
                      maxLines: 2,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                        color: distance == null ? textSecondary : oliveGreen))),
                  ]);
                }),
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
