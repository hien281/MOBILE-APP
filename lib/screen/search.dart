import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../api_client.dart';
import 'booking.dart';
import 'field_detail.dart';
import 'filter.dart';
import 'home.dart';

class SearchScreen extends StatefulWidget {
  final List<SportsField> allFields;
  final String initialSport;
  final bool autoFocus;
  final bool openFilterImmediately;
  final Position? currentPosition;
  final String accessToken;
  final Set<String> favoriteIds;
  final void Function(String fieldId)? onToggleFavorite;

  const SearchScreen({
    super.key,
    required this.allFields,
    this.initialSport = 'Tất cả',
    this.autoFocus = true,
    this.openFilterImmediately = false,
    this.currentPosition,
    required this.accessToken,
    this.favoriteIds = const {},
    this.onToggleFavorite,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  // Bộ nhớ lịch sử tìm kiếm tĩnh
  static final List<String> _recentSearchesHistory = [];

  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;

  late String _selectedSport;
  String _searchQuery = '';
  SearchFilterOptions _filterOptions = const SearchFilterOptions();
  late Set<String> _favoriteIds;

  // 4 môn thể thao + Tất cả
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
    _selectedSport = widget.initialSport;
    _favoriteIds = Set.from(widget.favoriteIds);
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();

    // Lắng nghe trạng thái focus
    _searchFocusNode.addListener(() {
      if (mounted) setState(() {});
    });

    if (widget.openFilterImmediately) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openFilterBottomSheet();
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _saveRecentSearch(String keyword) {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _recentSearchesHistory.remove(trimmed);
      _recentSearchesHistory.insert(0, trimmed);
      if (_recentSearchesHistory.length > 8) {
        _recentSearchesHistory.removeLast();
      }
    });
  }

  void _removeRecentSearch(String keyword) {
    setState(() {
      _recentSearchesHistory.remove(keyword);
    });
  }

  void _clearAllRecentSearches() {
    setState(() {
      _recentSearchesHistory.clear();
    });
  }

  List<String> get _availableDistricts {
    final set = <String>{};
    final regex = RegExp(r'(Quận \d+|Quận [^,]+|Huyện [^,]+|Thành phố Thủ Đức|Thủ Đức)');
    for (final f in widget.allFields) {
      final m = regex.firstMatch(f.address);
      if (m != null) set.add(m.group(0)!.trim());
    }
    final list = set.toList()..sort();
    return list;
  }

  double? _distanceKm(SportsField field) {
    final position = widget.currentPosition;
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
    final result = widget.allFields.where((field) {
      // 1. Môn thể thao (Hỗ trợ Pickleball, Bóng đá, Cầu lông, Tennis)
      final matchesSport = _selectedSport == 'Tất cả' ||
          field.sport.toLowerCase() == _selectedSport.toLowerCase();

      // 2. Từ khóa tìm kiếm real-time
      final query = _searchQuery.trim().toLowerCase();
      final matchesSearch = query.isEmpty ||
          field.name.toLowerCase().contains(query) ||
          field.address.toLowerCase().contains(query) ||
          field.sport.toLowerCase().contains(query);

      // 3. Khu vực quận/huyện
      bool matchesDistrict = true;
      if (_filterOptions.districts.isNotEmpty) {
        final addr = field.address.toLowerCase();
        matchesDistrict = _filterOptions.districts.any(
          (d) => addr.contains(d.toLowerCase()),
        );
      }

      // 4. Mức giá
      bool matchesPrice = true;
      final price = field.price;
      switch (_filterOptions.priceRange) {
        case 'under_100':
          matchesPrice = price < 100000;
          break;
        case '100_200':
          matchesPrice = price >= 100000 && price <= 200000;
          break;
        case '200_300':
          matchesPrice = price > 200000 && price <= 300000;
          break;
        case 'above_300':
          matchesPrice = price > 300000;
          break;
        default:
          matchesPrice = true;
      }

      // 5. Khoảng cách
      bool matchesDistance = true;
      if (_filterOptions.maxDistanceKm != null) {
        final dist = _distanceKm(field);
        matchesDistance = dist != null && dist <= _filterOptions.maxDistanceKm!;
      }

      return matchesSport && matchesSearch && matchesDistrict && matchesPrice && matchesDistance;
    }).toList();

    // Sắp xếp
    if (_filterOptions.sortBy == 'distance') {
      result.sort((a, b) {
        final da = _distanceKm(a);
        final db = _distanceKm(b);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });
    } else if (_filterOptions.sortBy == 'price_asc') {
      result.sort((a, b) => a.price.compareTo(b.price));
    } else if (_filterOptions.sortBy == 'price_desc') {
      result.sort((a, b) => b.price.compareTo(a.price));
    } else if (_filterOptions.sortBy == 'rating') {
      result.sort((a, b) => b.rating.compareTo(a.rating));
    }

    return result;
  }

  void _openFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FilterBottomSheet(
        initialOptions: _filterOptions,
        availableDistricts: _availableDistricts,
        onApply: (newOptions) {
          setState(() {
            _filterOptions = newOptions;
          });
        },
        onReset: () {
          setState(() {
            _filterOptions = const SearchFilterOptions();
          });
        },
      ),
    );
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
    final filtered = _filteredFields;
    final hasActiveFilter = !_filterOptions.isDefault;
    final showRecentPanel = _searchFocusNode.hasFocus &&
        _searchQuery.isEmpty &&
        _recentSearchesHistory.isNotEmpty;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Tô nền
      value: const SystemUiOverlayStyle(
        statusBarColor: pageBackground,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: GestureDetector(
        // Chạm ra ngoài sẽ ẩn bàn phím và đóng Recent search
        onTap: () {
          if (_searchFocusNode.hasFocus) {
            _searchFocusNode.unfocus();
          }
        },
        behavior: HitTestBehavior.translucent,
        child: Scaffold(
          backgroundColor: pageBackground,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. TOP HEADER
                _buildTopHeader(hasActiveFilter),

                // 2. KHỐI TÌM KIẾM GẦN ĐÂY
                if (showRecentPanel) _buildRecentSearchesSection(),

                // 3. DANH SÁCH KẾT QUẢ TÌM KIẾM
                Expanded(
                  child: _buildSearchResultsSection(filtered),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader(bool hasActiveFilter) {
    return Container(
      color: pageBackground, 
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          // Tiêu đề "Tìm sân"
          SizedBox(
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: IconButton(
                      tooltip: 'Quay lại',
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: oliveGreen,
                        size: 20,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
                const Text(
                  'Tìm sân',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                  ),
                ),
              ],
            ),
          ),

          // Khung tìm kiếm & Nút Bộ lọc
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: _searchFocusNode.hasFocus ? oliveGreen : const Color(0xFFDFDCF9),
                        width: _searchFocusNode.hasFocus ? 1.5 : 1.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.search_rounded,
                          color: Color(0xFF85839A),
                          size: 21,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocusNode,
                            autofocus: widget.autoFocus,
                            enableSuggestions: true,
                            autocorrect: false,
                            keyboardType: TextInputType.text,
                            textInputAction: TextInputAction.search,
                            onChanged: (value) {
                              setState(() {
                                _searchQuery = value;
                              });
                            },
                            onSubmitted: (value) {
                              _saveRecentSearch(value);
                              _searchFocusNode.unfocus();
                            },
                            style: const TextStyle(
                              fontSize: 14,
                              color: textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Tìm sân, địa chỉ, môn thể thao...',
                              hintStyle: TextStyle(
                                color: Color(0xFFA09EB0),
                                fontSize: 13.5,
                                fontWeight: FontWeight.normal,
                              ),
                              border: InputBorder.none,
                              isCollapsed: true,
                            ),
                          ),
                        ),
                        if (_searchQuery.isNotEmpty)
                          IconButton(
                            tooltip: 'Xóa',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.cancel_rounded, size: 18, color: Colors.grey),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchQuery = '';
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),

                // Nút mở Bộ lọc
                InkWell(
                  onTap: _openFilterBottomSheet,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(
                      color: hasActiveFilter ? oliveGreen : Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: hasActiveFilter ? oliveGreen : const Color(0xFFDFDCF9),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.tune_rounded,
                          color: hasActiveFilter ? Colors.white : oliveGreen,
                          size: 22,
                        ),
                        if (hasActiveFilter)
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF3B30),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.5),
                              ),
                            ),
                          ),
                      ],
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

  Widget _buildRecentSearchesSection() {
    return Container(
      color: pageBackground,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Tìm kiếm gần đây',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
              TextButton(
                onPressed: _clearAllRecentSearches,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Xóa tất cả',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF85839A),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _recentSearchesHistory.map((item) {
              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    _searchController.text = item;
                    _searchController.selection = TextSelection.fromPosition(
                      TextPosition(offset: item.length),
                    );
                    setState(() {
                      _searchQuery = item;
                    });
                    _searchFocusNode.unfocus();
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFDFDCF9)),
                    ),
                    padding: const EdgeInsets.only(left: 10, right: 6, top: 5, bottom: 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.history_rounded, size: 14, color: Color(0xFF85839A)),
                        const SizedBox(width: 4),
                        Text(
                          item,
                          style: const TextStyle(
                            fontSize: 12,
                            color: textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 3),
                        InkWell(
                          onTap: () => _removeRecentSearch(item),
                          borderRadius: BorderRadius.circular(10),
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(Icons.close_rounded, size: 13, color: Color(0xFFA09EB0)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultsSection(List<SportsField> fields) {
    const colorYellow = Color(0xFFFFFC31); // Màu vàng chuẩn của app

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Thanh chọn Môn Thể thao
        Container(
          color: oliveGreen,
          height: 52,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            scrollDirection: Axis.horizontal,
            itemCount: _sports.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final sport = _sports[index];
              final isSelected = _selectedSport.toLowerCase() == sport.toLowerCase();
              return Material(
                color: isSelected ? colorYellow : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    setState(() {
                      _selectedSport = sport;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
                    alignment: Alignment.center,
                    child: Text(
                      sport,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected ? oliveGreen : Colors.white, // Text trong box #1E147B khi chọn
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        // Thanh tóm tắt số kết quả và các chip bộ lọc đang áp dụng
        _buildActiveFiltersBar(fields.length),

        // Danh sách sân kết quả
        Expanded(
          child: fields.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  itemCount: fields.length,
                  itemBuilder: (context, index) {
                    return _buildSearchResultCard(fields[index]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildActiveFiltersBar(int count) {
    final chips = <Widget>[];

    if (_filterOptions.districts.isNotEmpty) {
      chips.add(_buildActiveFilterChip(
        label: _filterOptions.districts.length == 1
            ? _filterOptions.districts.first
            : '${_filterOptions.districts.length} quận',
        onRemove: () => setState(() {
          _filterOptions = _filterOptions.copyWith(districts: const {});
        }),
      ));
    }

    if (_filterOptions.priceRange != 'all') {
      String label = '';
      if (_filterOptions.priceRange == 'under_100') label = 'Dưới 100k';
      if (_filterOptions.priceRange == '100_200') label = '100k - 200k';
      if (_filterOptions.priceRange == '200_300') label = '200k - 300k';
      if (_filterOptions.priceRange == 'above_300') label = 'Trên 300k';

      chips.add(_buildActiveFilterChip(
        label: label,
        onRemove: () => setState(() {
          _filterOptions = _filterOptions.copyWith(priceRange: 'all');
        }),
      ));
    }

    if (_filterOptions.maxDistanceKm != null) {
      chips.add(_buildActiveFilterChip(
        label: 'Trong ${_filterOptions.maxDistanceKm!.toInt()}km',
        onRemove: () => setState(() {
          _filterOptions = _filterOptions.copyWith(clearMaxDistance: true);
        }),
      ));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            'Tìm thấy $count sân',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: chips),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFilterChip({required String label, required VoidCallback onRemove}) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.only(left: 8, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFDFDCF9).withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDFDCF9)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: oliveGreen,
            ),
          ),
          const SizedBox(width: 3),
          InkWell(
            onTap: onRemove,
            child: const Icon(Icons.close_rounded, size: 14, color: oliveGreen),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultCard(SportsField field) {
    final isFavorite = _favoriteIds.contains(field.id);
    final distance = _distanceKm(field);

    // Tính trạng thái mở/đóng cửa
    bool isOpen = true;
    String statusText = 'Đang mở cửa';
    if (field.openTime != null && field.closingTime != null) {
      final now = TimeOfDay.now();
      final nowMinutes = now.hour * 60 + now.minute;
      int parseMinutes(String t) {
        final parts = t.split(':');
        if (parts.length >= 2) {
          final h = int.tryParse(parts[0]) ?? 0;
          final m = int.tryParse(parts[1]) ?? 0;
          return h * 60 + m;
        }
        return 0;
      }
      final openMin = parseMinutes(field.openTime!);
      final closeMin = parseMinutes(field.closingTime!);
      if (openMin < closeMin) {
        isOpen = nowMinutes >= openMin && nowMinutes < closeMin;
      } else {
        isOpen = nowMinutes >= openMin || nowMinutes < closeMin;
      }
      statusText = isOpen
          ? 'Đang mở cửa | Đóng cửa lúc ${field.closingTime}'
          : 'Đang đóng cửa | Mở cửa lúc ${field.openTime}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDFDCF9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ảnh sân + Favorite button + Tag nổi bật
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
            child: Stack(
              children: [
                GestureDetector(
                  onTap: () => _openFieldDetail(field),
                  child: SizedBox(
                    height: 155,
                    width: double.infinity,
                    child: Image.network(
                      field.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: const Color(0xFFE8EDDF),
                        child: const Center(
                          child: Icon(Icons.sports_rounded, size: 44, color: oliveGreen),
                        ),
                      ),
                    ),
                  ),
                ),
                if (field.isPopular)
                  Positioned(
                    left: 10,
                    top: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.local_fire_department_rounded, size: 14, color: Color(0xFFE78A36)),
                          SizedBox(width: 3),
                          Text(
                            'Nổi bật',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  right: 10,
                  top: 10,
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    child: IconButton(
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: isFavorite ? Colors.redAccent : textPrimary,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          if (isFavorite) {
                            _favoriteIds.remove(field.id);
                          } else {
                            _favoriteIds.add(field.id);
                          }
                        });
                        widget.onToggleFavorite?.call(field.id);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Nội dung thông tin sân
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
                        color: oliveGreen.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
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
                    const Icon(Icons.star_rounded, color: Color(0xFFF4B740), size: 17),
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
                const SizedBox(height: 8),

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
                const SizedBox(height: 6),

                Row(
                  children: [
                    const Icon(Icons.location_on_outlined, color: textSecondary, size: 15),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        field.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5, color: textSecondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // Giờ đóng / mở cửa & Khoảng cách
                Row(
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: 14,
                      color: isOpen ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        statusText,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isOpen ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                        ),
                      ),
                    ),
                    if (distance != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '· ${_distanceLabel(distance)}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),

                const Divider(height: 18, color: Color(0xFFECEEF6)),

                // Giá và Nút Đặt sân (Hiển thị giá/giờ đồng bộ với Trang chủ)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_formatPrice(field.price)}đ',
                          style: const TextStyle(
                            fontSize: 16,
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
                            const SnackBar(content: Text('Đặt sân thành công!')),
                          );
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: oliveGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Đặt sân',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
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

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        // Cuộn an toàn khi bàn phím mở lên, ngăn chặn hoàn toàn lỗi overflow
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: const Color(0xFFDFDCF9).withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_off_rounded,
                size: 38,
                color: oliveGreen,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Không tìm thấy sân phù hợp',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Hãy thử thay đổi từ khóa tìm kiếm hoặc điều chỉnh lại bộ lọc khu vực/mức giá nhé.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 18, color: oliveGreen),
              label: const Text(
                'Đặt lại bộ lọc',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: oliveGreen,
                ),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: oliveGreen),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                setState(() {
                  _searchController.clear();
                  _searchQuery = '';
                  _selectedSport = 'Tất cả';
                  _filterOptions = const SearchFilterOptions();
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
