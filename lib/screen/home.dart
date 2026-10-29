import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:async';
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
import 'explore.dart';
import 'my_schedule.dart';
import 'account_screen.dart';
import '../widgets/bottom_nav.dart';

const Color oliveGreen = Color(0xFF35167F);
const Color pageBackground = Color.fromARGB(255, 254, 255, 247);
const Color textPrimary = Color(0xFF35167F);
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
  bool _mapWasOpened = false;
  final PageController _bannerController = PageController();
  Timer? _bannerTimer;
  int _bannerIndex = 0;
  static const _bannerData = [
    ('KHÁM PHÁ', 'Sân đẹp đang chờ bạn!', 'Tìm sân phù hợp cho trận đấu tiếp theo.', 'assets/images/banner_1.jpg'),
    ('ĐẶT SÂN', 'Lên lịch chơi, SPORTY lo!', 'Chọn ngày, chọn giờ và đặt sân nhanh chóng.', 'assets/images/banner_2.jpg'),
    ('KẾT NỐI', 'Rủ hội bạn, ra sân thôi!', 'Cùng bạn bè tạo nên những trận đấu đáng nhớ.', 'assets/images/banner_3.jpg'),
  ];

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
    _bannerTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_bannerController.hasClients) return;
      final next = (_bannerIndex + 1) % _bannerData.length;
      _bannerController.animateToPage(next, duration: const Duration(milliseconds: 450), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerController.dispose();
    super.dispose();
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
      setState(() => _selectedNavIndex = 4);
      return;
    }
    if (index == 1) {
      setState(() { _mapWasOpened = true; _selectedNavIndex = 1; });
      return;
    }
    if (index == 2) {
    setState(() => _selectedNavIndex = 2);
    return;
    }
    if (index == 3) setState(() => _selectedNavIndex = 3);
    if (index == 0) setState(() => _selectedNavIndex = 0);
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
        body: IndexedStack(
          index: _selectedNavIndex,
          children: [
            SafeArea(
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
                            const SizedBox(height: 30),
                            _buildHeader(),
                            const SizedBox(height: 17),
                            _buildSearchBar(),
                            const SizedBox(height: 18),
                            _buildPromoBanner(),
                            const SizedBox(height: 22),
                            _buildSectionTitle(
                              'Khám phá thể thao',
                              subtitle: 'Chọn môn thể thao bạn yêu thích',
                            ),
                            const SizedBox(height: 12),
                            _buildSportCategories(isWide),
                            const SizedBox(height: 23),
                            _buildFieldHeading(),
                            const SizedBox(height: 12),
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
            if (_selectedNavIndex == 1 || _mapWasOpened)
              MapScreen(
                allFields: _fields,
                currentPosition: _currentPosition,
                accessToken: widget.accessToken,
                favoriteIds: _favoriteIds,
                onToggleFavorite: (id) {
                  setState(() {
                    if (!_favoriteIds.add(id)) _favoriteIds.remove(id);
                  });
                },
              )
            else
              const SizedBox.shrink(),
            ExploreScreen(
            accessToken: widget.accessToken,
          ),
          const MyScheduleScreen(isActive: _selectedNavIndex == 3),
          const AccountScreen(),
          ],
        ),
      bottomNavigationBar: SportyBottomNav(
        selectedIndex: _selectedNavIndex,
        onTap: _onNavTap,
      ),
    ),
    );
  }

  Widget _buildHeader() {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName?.trim().isNotEmpty == true
        ? user!.displayName!.trim()
        : (user?.email?.split('@').first ?? 'bạn');
    final photo = user?.photoURL;
    return Row(
      children: [
        CircleAvatar(
          radius: 21,
          backgroundColor: const Color(0xFFEDE7FA),
          backgroundImage: photo != null && photo.isNotEmpty ? NetworkImage(photo) : null,
          child: photo == null || photo.isEmpty
              ? const Icon(Icons.person_rounded, color: oliveGreen, size: 25)
              : null,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Chào mừng trở lại!', style: TextStyle(fontSize: 11, color: textSecondary)),
              const SizedBox(height: 2),
              Text('Xin chào, $name!', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary)),
              const SizedBox(height: 3),
              InkWell(
                onTap: _loadingLocation ? null : _loadLocation,
                child: Row(children: [
                  const Icon(Icons.location_on_outlined, color: oliveGreen, size: 13),
                  const SizedBox(width: 3),
                  Flexible(child: Text(_locationLabel, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: textSecondary))),
                  if (_loadingLocation) ...[
                    const SizedBox(width: 5),
                    const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
                  ],
                ]),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: 'Thông báo',
          onPressed: () => _showComingSoon('Thông báo'),
          style: IconButton.styleFrom(backgroundColor: const Color(0xFFF7F6FB), fixedSize: const Size(40, 40)),
          icon: const Icon(Icons.notifications_none_rounded, color: oliveGreen, size: 22),
        ),
      ],
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
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: const Color(0xFFE8E1F5),
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
                    fontSize: 12,
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
            fontSize: 17,
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
              fontSize: 11,
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
      'Tennis': Icons.sports_baseball_rounded,
      'Pickleball': Icons.sports_tennis_rounded,
    };
    if (isWide) {
      return Wrap(spacing: 15, runSpacing: 12,
        children: _sports.map((sport) => _sportItem(sport, icons[sport]!)).toList());
    }
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _sports.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final sport = _sports[index];
          return _sportItem(sport, icons[sport]!);
        },
      ),
    );
  }

  Widget _sportItem(String sport, IconData icon) {
    final selected = _selectedSport == sport;
    return SizedBox(
      width: 66,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() => _selectedSport = sport),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 49, height: 49,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? oliveGreen : const Color(0xFFF0ECFA),
              ),
              child: (sport == 'Tennis' || sport == 'Pickleball')
                  ? Padding(
                      padding: const EdgeInsets.all(11),
                      child: Image.asset(
                        sport == 'Tennis'
                            ? 'assets/images/icon_tennis.png'
                            : 'assets/images/icon_pickleball.png',
                        color: selected ? Colors.white : const Color(0xFF35167F),
                        errorBuilder: (_, __, ___) => Icon(icon, size: 23,
                          color: selected ? Colors.white : oliveGreen),
                      ),
                    )
                  : Icon(icon, size: 23, color: selected ? Colors.white : oliveGreen),
            ),
            const SizedBox(height: 6),
            Text(sport, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? oliveGreen : textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildPromoBanner() {
    return Column(
      children: [
        SizedBox(
          height: 154,
          child: PageView.builder(
            controller: _bannerController,
            itemCount: _bannerData.length,
            onPageChanged: (index) => setState(() => _bannerIndex = index),
            itemBuilder: (context, index) {
              final banner = _bannerData[index];
              return ClipRRect(
                borderRadius: BorderRadius.circular(17),
                child: Stack(fit: StackFit.expand, children: [
                  Image.asset(banner.$4, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [Color(0xFF35167F), Color(0xFF9A7CD5)])),
                      child: const Align(alignment: Alignment.centerRight,
                        child: Padding(padding: EdgeInsets.only(right: 16),
                          child: Icon(Icons.sports_tennis_rounded, size: 96, color: Color(0x55FFFFFF)))),
                    ),
                  ),
                  const DecoratedBox(decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight,
                      colors: [Color(0xD9000000), Color(0x77000000), Color(0x00000000)],
                      stops: [0, 0.65, 1]),
                  )),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(banner.$1, style: const TextStyle(fontSize: 9, letterSpacing: 1.2,
                        color: Color(0xFFE9DFFF), fontWeight: FontWeight.w800)),
                      const SizedBox(height: 9),
                      SizedBox(width: 210, child: Text(banner.$2,
                        style: const TextStyle(fontSize: 19, height: 1.13,
                          color: Colors.white, fontWeight: FontWeight.w800))),
                      const SizedBox(height: 6),
                      SizedBox(width: 220, child: Text(banner.$3,
                        style: const TextStyle(fontSize: 10.5, height: 1.35, color: Colors.white))),
                    ]),
                  ),
                ]),
              );
            },
          ),
        ),
        const SizedBox(height: 9),
        Row(mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_bannerData.length, (index) => AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: index == _bannerIndex ? 17 : 6, height: 6,
            decoration: BoxDecoration(
              color: index == _bannerIndex ? oliveGreen : const Color(0xFFE2DDEE),
              borderRadius: BorderRadius.circular(10)),
          )),
        ),
      ],
    );
  }

  Widget _buildFieldHeading() {
    final title = _selectedSport == 'Tất cả' ? 'Sân nổi bật' : 'Sân $_selectedSport';
    return Row(children: [
      Expanded(child: Text(title, style: const TextStyle(
        fontSize: 17, fontWeight: FontWeight.w800, color: textPrimary))),
      if (_currentPosition != null)
        TextButton.icon(
          onPressed: () => setState(() => _sortByDistance = !_sortByDistance),
          icon: Icon(_sortByDistance ? Icons.check_circle_outline_rounded : Icons.near_me_outlined, size: 15),
          label: const Text('Gần nhất'),
          style: TextButton.styleFrom(foregroundColor: oliveGreen,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 7),
            textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        ),
    ]);
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEAE5F3)),
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
              top: Radius.circular(15),
            ),
            child: Stack(
              children: [
                GestureDetector(
                  onTap: () => _openFieldDetail(field),
                  child: SizedBox(
                  height: 145,
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
            padding: const EdgeInsets.all(12),
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
                              fontSize: 15,
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

}
