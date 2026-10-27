import 'package:flutter/material.dart';

const Color colorPrimary = Color(0xFF1E147B);
const Color colorActive = Color(0xFFC86FC9);
const Color colorLavender = Color(0xFFDFDCF9);
const Color colorTextSecondary = Color(0xFF77748E);

/// Dữ liệu bộ lọc tìm kiếm
class SearchFilterOptions {
  final String sortBy; // 'default', 'distance', 'price_asc', 'price_desc', 'rating'
  final Set<String> districts; // Tập hợp các quận được chọn, rỗng = tất cả
  final String priceRange; // 'all', 'duoi_100', '100_200', '200_300', 'above_300'
  final double? maxDistanceKm; // null, 3.0, 5.0, 10.0

  const SearchFilterOptions({
    this.sortBy = 'default',
    this.districts = const {},
    this.priceRange = 'all',
    this.maxDistanceKm,
  });

  bool get isDefault =>
      sortBy == 'default' &&
      districts.isEmpty &&
      priceRange == 'all' &&
      maxDistanceKm == null;

  SearchFilterOptions copyWith({
    String? sortBy,
    Set<String>? districts,
    String? priceRange,
    double? maxDistanceKm,
    bool clearMaxDistance = false,
  }) {
    return SearchFilterOptions(
      sortBy: sortBy ?? this.sortBy,
      districts: districts ?? this.districts,
      priceRange: priceRange ?? this.priceRange,
      maxDistanceKm: clearMaxDistance ? null : (maxDistanceKm ?? this.maxDistanceKm),
    );
  }
}
/// Bottom Sheet hiển thị bộ lọc tìm kiếm
class FilterBottomSheet extends StatefulWidget {
  final SearchFilterOptions initialOptions;
  final List<String> availableDistricts;
  final ValueChanged<SearchFilterOptions> onApply;
  final VoidCallback onReset;

  const FilterBottomSheet({
    super.key,
    required this.initialOptions,
    required this.availableDistricts,
    required this.onApply,
    required this.onReset,
  });

  @override
  State<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  late String _sortBy;
  late Set<String> _districts;
  late String _priceRange;
  late double? _maxDistanceKm;

  // Mặc định thu gọn tất cả
  bool _expandSort = false;
  bool _expandDistrict = true; // Mặc định mở phần khu vực
  bool _expandPrice = false;
  bool _expandDistance = false;

  @override
  void initState() {
    super.initState();
    _sortBy = widget.initialOptions.sortBy;
    _districts = Set.from(widget.initialOptions.districts);
    _priceRange = widget.initialOptions.priceRange;
    _maxDistanceKm = widget.initialOptions.maxDistanceKm;
  }

  void _handleReset() {
    widget.onReset();
    Navigator.pop(context);
  }

  Widget _buildSectionHeader({
    required String title,
    required String currentSummary,
    required bool isExpanded,
    required VoidCallback onTap,
  }) {
    const colorMauve = Color(0xFFC86FC9);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colorPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (currentSummary.isNotEmpty)
                    Flexible(
                      child: Text(
                        '($currentSummary)',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: colorMauve,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: colorPrimary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isSelected ? colorPrimary : const Color(0xFFF7F8FC),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? colorPrimary : const Color(0xFFE2E4F0),
              width: 1.2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected ? Colors.white : colorPrimary,
            ),
          ),
        ),
      ),
    );
  }

  String _getSortLabel(String key) {
    switch (key) {
      case 'distance':
        return 'Gần nhất';
      case 'price_asc':
        return 'Giá thấp';
      case 'price_desc':
        return 'Giá cao';
      case 'rating':
        return 'Đánh giá cao';
      default:
        return 'Mặc định';
    }
  }

  String _getPriceLabel(String key) {
    switch (key) {
      case 'under_100':
        return 'Dưới 100k';
      case '100_200':
        return '100k - 200k';
      case '200_300':
        return '200k - 300k';
      case 'above_300':
        return 'Trên 300k';
      default:
        return 'Tất cả';
    }
  }

  @override
  Widget build(BuildContext context) {
    final districtSummary = _districts.isEmpty
        ? 'Tất cả quận'
        : _districts.length == 1
            ? _districts.first
            : '${_districts.length} quận';

    final distanceSummary =
        _maxDistanceKm == null ? 'Mọi khoảng cách' : 'Trong ${_maxDistanceKm!.toInt()}km';

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Bộ lọc tìm sân',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: colorPrimary,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.black87, size: 22),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Color(0xFFECEEF6)),

          // Danh sách các tiêu chí
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. VỊ TRÍ
                  _buildSectionHeader(
                    title: 'Khu vực (TP.HCM)',
                    currentSummary: districtSummary,
                    isExpanded: _expandDistrict,
                    onTap: () => setState(() => _expandDistrict = !_expandDistrict),
                  ),
                  if (_expandDistrict) ...[
                    Container(
                      constraints: const BoxConstraints(maxHeight: 220),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFD),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE2E4F0)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Scrollbar(
                          thumbVisibility: true,
                          child: ListView(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            children: [
                              CheckboxListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                activeColor: colorPrimary,
                                checkColor: Colors.white,
                                title: const Text(
                                  'Tất cả quận',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: colorPrimary,
                                  ),
                                ),
                                value: _districts.isEmpty,
                                onChanged: (val) {
                                  setState(() {
                                    _districts.clear();
                                  });
                                },
                                controlAffinity: ListTileControlAffinity.leading,
                              ),
                              const Divider(height: 1, color: Color(0xFFE2E4F0)),
                              ...widget.availableDistricts.map((d) {
                                final isSelected = _districts.contains(d);
                                return CheckboxListTile(
                                  dense: true,
                                  visualDensity: VisualDensity.compact,
                                  activeColor: colorPrimary,
                                  checkColor: Colors.white,
                                  title: Text(
                                    d,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                      color: isSelected ? colorPrimary : Colors.black87,
                                    ),
                                  ),
                                  value: isSelected,
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _districts.add(d);
                                      } else {
                                        _districts.remove(d);
                                      }
                                    });
                                  },
                                  controlAffinity: ListTileControlAffinity.leading,
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],

                  const Divider(height: 1, color: Color(0xFFECEEF6)),

                  // 2. MỨC GIÁ MỖI GIỜ
                  _buildSectionHeader(
                    title: 'Mức giá mỗi giờ',
                    currentSummary: _getPriceLabel(_priceRange),
                    isExpanded: _expandPrice,
                    onTap: () => setState(() => _expandPrice = !_expandPrice),
                  ),
                  if (_expandPrice) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildChip(
                          label: 'Tất cả mức giá',
                          isSelected: _priceRange == 'all',
                          onTap: () => setState(() => _priceRange = 'all'),
                        ),
                        _buildChip(
                          label: 'Dưới 100k',
                          isSelected: _priceRange == 'under_100',
                          onTap: () => setState(() => _priceRange = 'under_100'),
                        ),
                        _buildChip(
                          label: '100k - 200k',
                          isSelected: _priceRange == '100_200',
                          onTap: () => setState(() => _priceRange = '100_200'),
                        ),
                        _buildChip(
                          label: '200k - 300k',
                          isSelected: _priceRange == '200_300',
                          onTap: () => setState(() => _priceRange = '200_300'),
                        ),
                        _buildChip(
                          label: 'Trên 300k',
                          isSelected: _priceRange == 'above_300',
                          onTap: () => setState(() => _priceRange = 'above_300'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],

                  const Divider(height: 1, color: Color(0xFFECEEF6)),

                  // 3. SẮP XẾP THEO
                  _buildSectionHeader(
                    title: 'Sắp xếp theo',
                    currentSummary: _getSortLabel(_sortBy),
                    isExpanded: _expandSort,
                    onTap: () => setState(() => _expandSort = !_expandSort),
                  ),
                  if (_expandSort) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildChip(
                          label: 'Mặc định',
                          isSelected: _sortBy == 'default',
                          onTap: () => setState(() => _sortBy = 'default'),
                        ),
                        _buildChip(
                          label: 'Gần nhất',
                          isSelected: _sortBy == 'distance',
                          onTap: () => setState(() => _sortBy = 'distance'),
                        ),
                        _buildChip(
                          label: 'Giá thấp đến cao',
                          isSelected: _sortBy == 'price_asc',
                          onTap: () => setState(() => _sortBy = 'price_asc'),
                        ),
                        _buildChip(
                          label: 'Giá cao đến thấp',
                          isSelected: _sortBy == 'price_desc',
                          onTap: () => setState(() => _sortBy = 'price_desc'),
                        ),
                        _buildChip(
                          label: 'Đánh giá cao',
                          isSelected: _sortBy == 'rating',
                          onTap: () => setState(() => _sortBy = 'rating'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],

                  const Divider(height: 1, color: Color(0xFFECEEF6)),

                  // 4. KHOẢNG CÁCH TỐI ĐA
                  _buildSectionHeader(
                    title: 'Khoảng cách tối đa',
                    currentSummary: distanceSummary,
                    isExpanded: _expandDistance,
                    onTap: () => setState(() => _expandDistance = !_expandDistance),
                  ),
                  if (_expandDistance) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildChip(
                          label: 'Mọi khoảng cách',
                          isSelected: _maxDistanceKm == null,
                          onTap: () => setState(() => _maxDistanceKm = null),
                        ),
                        _buildChip(
                          label: 'Trong 3 km',
                          isSelected: _maxDistanceKm == 3.0,
                          onTap: () => setState(() => _maxDistanceKm = 3.0),
                        ),
                        _buildChip(
                          label: 'Trong 5 km',
                          isSelected: _maxDistanceKm == 5.0,
                          onTap: () => setState(() => _maxDistanceKm = 5.0),
                        ),
                        _buildChip(
                          label: 'Trong 10 km',
                          isSelected: _maxDistanceKm == 10.0,
                          onTap: () => setState(() => _maxDistanceKm = 10.0),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),

          // Bottom Actions
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFECEEF6))),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      side: const BorderSide(color: colorPrimary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _handleReset,
                    child: const Text(
                      'Xóa bộ lọc',
                      style: TextStyle(
                        color: colorPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorPrimary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    onPressed: () {
                      final options = SearchFilterOptions(
                        sortBy: _sortBy,
                        districts: _districts,
                        priceRange: _priceRange,
                        maxDistanceKm: _maxDistanceKm,
                      );
                      widget.onApply(options);
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'Xem kết quả',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
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
}
