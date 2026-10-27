import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'field_detail.dart';
import 'home.dart';

class MapScreen extends StatefulWidget {
  final List<SportsField> allFields;
  final Position? currentPosition;
  final String accessToken;
  final Set<String> favoriteIds;
  final void Function(String fieldId)? onToggleFavorite;

  const MapScreen({
    super.key,
    required this.allFields,
    this.currentPosition,
    required this.accessToken,
    this.favoriteIds = const {},
    this.onToggleFavorite,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late final MapController _mapController;

  String _selectedDistrict = 'Tất cả';
  String _selectedSport = 'Tất cả';
  String? _openFilter;
  SportsField? _selectedField;

  final List<String> _sports = [
    'Tất cả',
    'Bóng đá',
    'Cầu lông',
    'Tennis',
    'Pickleball',
  ];

  @override
  void initState() {
    super.initState();
    _mapController = MapController();

    // Mặc định chọn sân đầu tiên có tọa độ hợp lệ để xem trước
    final validFields = widget.allFields.where(_hasValidCoords).toList();
    if (validFields.isNotEmpty) {
      _selectedField = validFields.first;
    }
  }

  bool _hasValidCoords(SportsField f) {
    final lat = f.latitude;
    final lon = f.longitude;
    return lat != null &&
        lon != null &&
        lat.isFinite &&
        lon.isFinite &&
        lat >= -90 &&
        lat <= 90 &&
        lon >= -180 &&
        lon <= 180;
  }

  List<String> get _availableDistricts {
    final set = <String>{};
    final regex = RegExp(r'(Quận \d+|Quận [^,]+|Huyện [^,]+|Thành phố Thủ Đức|Thủ Đức)');
    for (final f in widget.allFields) {
      final m = regex.firstMatch(f.address);
      if (m != null) set.add(m.group(0)!.trim());
    }
    final list = set.toList()..sort();
    return ['Tất cả', ...list];
  }

  List<SportsField> get _filteredFields {
    return widget.allFields.where((field) {
      if (!_hasValidCoords(field)) return false;

      final matchesSport = _selectedSport == 'Tất cả' ||
          field.sport.toLowerCase() == _selectedSport.toLowerCase();

      bool matchesDistrict = true;
      if (_selectedDistrict != 'Tất cả') {
        matchesDistrict = field.address.toLowerCase().contains(_selectedDistrict.toLowerCase());
      }

      return matchesSport && matchesDistrict;
    }).toList();
  }

  double? _distanceKm(SportsField field) {
    final position = widget.currentPosition;
    final lat = field.latitude;
    final lon = field.longitude;
    if (position == null || lat == null || lon == null || !_hasValidCoords(field)) {
      return null;
    }
    return Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      lat,
      lon,
    ) / 1000;
  }

  String _distanceLabel(double km) {
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
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

  Color _getSportColor(String sport) {
    switch (sport.toLowerCase()) {
      case 'bóng đá':
        return const Color(0xFF1E147B);
      case 'cầu lông':
        return const Color(0xFFC86FC9);
      case 'tennis':
        return const Color(0xFF2E20A8);
      case 'pickleball':
        return const Color(0xFFFFFC31);
      default:
        return const Color(0xFF1E147B);
    }
  }

  Color _getSportIconColor(String sport) {
    if (sport.toLowerCase() == 'pickleball') {
      return const Color(0xFF1E147B);
    }
    return Colors.white; 
  }

  IconData _getSportIcon(String sport) {
    switch (sport.toLowerCase()) {
      case 'bóng đá':
        return Icons.sports_soccer_rounded;
      case 'cầu lông':
        return Icons.sports_tennis_rounded;
      case 'tennis':
        return Icons.sports_tennis_rounded;
      case 'pickleball':
        return Icons.sports_baseball_rounded;
      default:
        return Icons.sports_rounded;
    }
  }

  void _openFieldDetail(SportsField field) {
    final distance = _distanceKm(field);
    final distanceLabel = distance != null ? _distanceLabel(distance) : null;
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

  void _recenterToUser() {
    final pos = widget.currentPosition;
    if (pos != null) {
      _mapController.move(LatLng(pos.latitude, pos.longitude), 14.5);
    } else {
      _mapController.move(const LatLng(10.7769, 106.7009), 13.5);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredFields;
    final userPos = widget.currentPosition != null
        ? LatLng(widget.currentPosition!.latitude, widget.currentPosition!.longitude)
        : const LatLng(10.7769, 106.7009);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: pageBackground,
        body: Stack(
          children: [
            // 1. BẢN ĐỒ TƯƠNG TÁC
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: userPos,
                initialZoom: 13.5,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                  subdomains: const ['0', '1', '2', '3'],
                  userAgentPackageName: 'com.example.mobile_app',
                ),

                // Marker vị trí GPS người dùng
                if (widget.currentPosition != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: userPos,
                        width: 26,
                        height: 26,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.blue.shade600,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.withValues(alpha: 0.4),
                                blurRadius: 10,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),

                // Marker các sân
                MarkerLayer(
                  markers: filtered.map((field) {
                    final isSelected = _selectedField?.id == field.id;
                    final sportColor = _getSportColor(field.sport);
                    final iconColor = _getSportIconColor(field.sport);
                    final sportIcon = _getSportIcon(field.sport);

                    return Marker(
                      point: LatLng(field.latitude!, field.longitude!),
                      width: isSelected ? 44 : 36,
                      height: isSelected ? 52 : 44,
                      alignment: Alignment.topCenter,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedField = field;
                          });
                          _mapController.move(
                            LatLng(field.latitude!, field.longitude!),
                            _mapController.camera.zoom,
                          );
                        },
                        child: _buildPointyPinMarker(
                          color: sportColor,
                          iconColor: iconColor,
                          icon: sportIcon,
                          isSelected: isSelected,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),

            // Chạm ngoài danh sách để đóng, không kéo bản đồ khi đang chọn.
            if (_openFilter != null)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _openFilter = null),
                ),
              ),

            // 2. THANH LỌC TRÊN CÙNG
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              left: 16,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildFilterButton(
                          filter: 'district',
                          label: _selectedDistrict == 'Tất cả'
                              ? 'Địa điểm'
                              : _selectedDistrict,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildFilterButton(
                          filter: 'sport',
                          label: _selectedSport == 'Tất cả'
                              ? 'Bộ môn'
                              : _selectedSport,
                        ),
                      ),
                    ],
                  ),
                  if (_openFilter != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _openFilter == 'district'
                              ? _buildFilterMenu(
                                  items: _availableDistricts,
                                  selected: _selectedDistrict,
                                  onSelected: (value) {
                                    setState(() {
                                      _selectedDistrict = value;
                                      _openFilter = null;
                                    });
                                  },
                                )
                              : const SizedBox.shrink(),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _openFilter == 'sport'
                              ? _buildFilterMenu(
                                  items: _sports,
                                  selected: _selectedSport,
                                  onSelected: (value) {
                                    setState(() {
                                      _selectedSport = value;
                                      _openFilter = null;
                                    });
                                  },
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // 3. GPS Button
            Positioned(
              right: 16,
              bottom: _selectedField != null ? 140 : 20,
              child: FloatingActionButton(
                heroTag: 'map_gps_btn',
                mini: true,
                backgroundColor: Colors.white,
                foregroundColor: oliveGreen,
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onPressed: _recenterToUser,
                child: const Icon(Icons.my_location_rounded, size: 20),
              ),
            ),

            // 4. THẺ XEM TRƯỚC SÂN
            if (_selectedField != null)
              Positioned(
                left: 14,
                right: 14,
                bottom: 12,
                child: _buildBottomFieldCard(_selectedField!),
              ),
          ],
        ),
        bottomNavigationBar: _buildBottomNavigation(),
      ),
    );
  }

  Widget _buildFilterButton({
    required String filter,
    required String label,
  }) {
    final isOpen = _openFilter == filter;
    return Material(
      color: const Color(0xFF1E147B),
      elevation: 4,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _openFilter = isOpen ? null : filter),
        child: SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  isOpen
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterMenu({
    required List<String> items,
    required String selected,
    required ValueChanged<String> onSelected,
  }) {
    return Material(
      color: const Color(0xFFF6F7EB),
      elevation: 6,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 200),
        child: Scrollbar(
          child: ListView.builder(
            primary: false,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemExtent: 50,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final isSelected = item == selected;
              return Material(
                color: isSelected
                    ? const Color(0xFFFFFC31)
                    : const Color(0xFFF6F7EB),
                child: InkWell(
                  onTap: () => onSelected(item),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                              color: const Color(0xFF1E147B),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.check_rounded,
                            color: Color(0xFF1E147B),
                            size: 18,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
  // Marker Địa Điểm
  Widget _buildPointyPinMarker({
    required Color color,
    required Color iconColor,
    required IconData icon,
    required bool isSelected,
  }) {
    final double headSize = isSelected ? 38 : 30;
    final double iconSize = isSelected ? 20 : 16;
    final double pointerHeight = isSelected ? 8 : 6;
    final double pointerWidth = isSelected ? 12 : 9;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Đầu ghim tròn
        Container(
          width: headSize,
          height: headSize,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? const Color(0xFFFFFC31) : Colors.white,
              width: isSelected ? 3 : 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: isSelected ? 8 : 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            icon,
            color: iconColor,
            size: iconSize,
          ),
        ),
        // Mũi nhọn chỉ xuống địa điểm
        ClipPath(
          clipper: _TriangleClipper(),
          child: Container(
            width: pointerWidth,
            height: pointerHeight,
            color: isSelected ? const Color(0xFFFFFC31) : color,
          ),
        ),
      ],
    );
  }

  // Thẻ preview sân
  Widget _buildBottomFieldCard(SportsField field) {
    final distance = _distanceKm(field);
    final sportColor = _getSportColor(field.sport);
    final sportTextColor = _getSportIconColor(field.sport);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openFieldDetail(field),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 104,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFDFDCF9)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
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
                        child: Icon(Icons.sports_rounded, color: oliveGreen, size: 28),
                      ),
                    ),
                  ),
                ),
              ),

              // Thông tin sân
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Badge môn & Đánh giá sao & Nút đóng
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: sportColor,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              field.sport,
                              style: TextStyle(
                                color: sportTextColor,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const Spacer(),
                          const Icon(Icons.star_rounded, color: Color(0xFFF4B740), size: 14),
                          const SizedBox(width: 2),
                          Text(
                            field.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => setState(() => _selectedField = null),
                            child: const Icon(Icons.close_rounded, size: 16, color: Colors.grey),
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
                          color: textPrimary,
                        ),
                      ),

                      // Địa chỉ
                      Text(
                        field.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 8,
                          color: textSecondary,
                        ),
                      ),

                      // Giá và Khoảng cách
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_formatPrice(field.price)}đ / giờ',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              color: oliveGreen,
                            ),
                          ),
                          if (distance != null)
                            Text(
                              '~${_distanceLabel(distance)}',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: textSecondary,
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

  Widget _buildBottomNavigation() {
    const items = [
      (icon: Icons.home_rounded, label: 'Trang chủ'),
      (icon: Icons.map_rounded, label: 'Bản đồ'),
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
              final selected = index == 1; // Tab Bản đồ đang được chọn
              final center = index == 2;
              return Expanded(
                child: InkWell(
                  onTap: () {
                    if (index == 0) {
                      Navigator.pop(context); // Quay lại Trang chủ
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: center ? 48 : 38,
                        height: center ? 48 : 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected
                              ? const Color(0xFF1E147B)
                              : center
                                  ? const Color(0xFFDFDCF9)
                                  : Colors.transparent,
                        ),
                        child: Icon(
                          item.icon,
                          size: center ? 27 : 23,
                          color: selected ? const Color(0xFFFFFC31) : const Color(0xFF85839A),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? oliveGreen : textSecondary,
                        ),
                      ),
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

// Clipper tạo hình tam giác nhọn cho chân Marker
class _TriangleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width / 2, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
