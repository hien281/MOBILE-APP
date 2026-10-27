import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api_client.dart';
import 'booking.dart';
import 'home.dart';

const Color colorPrimary = Color(0xFF1E147B);
const Color colorYellow = Color(0xFFFFFC31);
const Color colorMauve = Color(0xFFC86FC9);
const Color colorLavender = Color(0xFFDFDCF9);
const Color colorBackground = Color(0xFFF6F7EB);
const Color colorTextSecondary = Color(0xFF77748E);

class FieldDetailScreen extends StatefulWidget {
  final SportsField field;
  final String? distanceLabel;
  final String accessToken;

  const FieldDetailScreen({
    super.key,
    required this.field,
    this.distanceLabel,
    required this.accessToken,
  });

  @override
  State<FieldDetailScreen> createState() => _FieldDetailScreenState();
}

class _FieldDetailScreenState extends State<FieldDetailScreen> {
  bool _isHoursExpanded = false;

  /// Icon cho từng môn thể thao 
  IconData _sportIcon(String sport) {
    final lower = sport.toLowerCase();
    if (lower.contains('bóng đá') || lower.contains('soccer') || lower.contains('football')) {
      return Icons.sports_soccer_rounded;
    }
    if (lower.contains('cầu lông') || lower.contains('badminton')) {
      return Icons.sports_tennis_rounded;
    }
    if (lower.contains('tennis')) {
      return Icons.sports_tennis_rounded;
    }
    if (lower.contains('bóng rổ') || lower.contains('basketball') || lower.contains('pickleball')) {
      return Icons.sports_basketball_rounded;
    }
    return Icons.sports_rounded;
  }

  /// Chuẩn hóa giờ
  String _formatTime(String time) {
    final trimmed = time.trim();
    final parts = trimmed.split(':');
    if (parts.isEmpty) return trimmed;
    final h = parts[0].padLeft(2, '0');
    final m = parts.length > 1 ? parts[1].padLeft(2, '0') : '00';
    return '$h:$m';
  }

  /// Tính trạng thái mở/đóng cửa theo giờ thiết bị và openTime/closingTime của sân.
  ({bool isOpen, String statusText, Color statusColor, String? fullHours}) _computeOpenStatus() {
    final rawOpen = widget.field.openTime?.trim();
    final rawClose = widget.field.closingTime?.trim();

    if (rawOpen == null || rawOpen.isEmpty || rawClose == null || rawClose.isEmpty) {
      if (rawClose != null && rawClose.isNotEmpty) {
        final closeFormatted = _formatTime(rawClose);
        return (
          isOpen: true,
          statusText: 'Đang mở cửa | Đóng cửa lúc $closeFormatted',
          statusColor: const Color(0xFF1B8A44),
          fullHours: 'Đóng cửa lúc $closeFormatted',
        );
      }
      return (
        isOpen: true,
        statusText: 'Đang mở cửa',
        statusColor: const Color(0xFF1B8A44),
        fullHours: null,
      );
    }

    final openFormatted = _formatTime(rawOpen);
    final closeFormatted = _formatTime(rawClose);

    try {
      final now = DateTime.now();
      final nowMinutes = now.hour * 60 + now.minute;

      int parseMinutes(String time) {
        final parts = time.split(':');
        final h = int.parse(parts[0]);
        final m = parts.length > 1 ? int.parse(parts[1]) : 0;
        return h * 60 + m;
      }

      final openMinutes = parseMinutes(rawOpen);
      final closeMinutes = parseMinutes(rawClose);

      bool isOpen;
      if (closeMinutes > openMinutes) {
        isOpen = nowMinutes >= openMinutes && nowMinutes < closeMinutes;
      } else {
        isOpen = nowMinutes >= openMinutes || nowMinutes < closeMinutes;
      }

      if (isOpen) {
        return (
          isOpen: true,
          statusText: 'Đang mở cửa | Đóng cửa lúc $closeFormatted',
          statusColor: const Color(0xFF1B8A44),
          fullHours: '$openFormatted - $closeFormatted',
        );
      } else {
        return (
          isOpen: false,
          statusText: 'Đang đóng cửa | Mở cửa lúc $openFormatted',
          statusColor: const Color(0xFFD32F2F),
          fullHours: '$openFormatted - $closeFormatted',
        );
      }
    } catch (_) {
      return (
        isOpen: true,
        statusText: 'Đang mở cửa | Đóng cửa lúc $closeFormatted',
        statusColor: const Color(0xFF1B8A44),
        fullHours: '$openFormatted - $closeFormatted',
      );
    }
  }

  /// Mở ứng dụng gọi điện thoại
  Future<void> _makePhoneCall(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'\s+'), '');
    final uri = Uri.parse('tel:$cleaned');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể mở ứng dụng gọi điện')),
      );
    }
  }

  /// Mở liên kết Google Maps của sân
  Future<void> _openGoogleMaps() async {
    final rawUrl = widget.field.googleMapsUrl;
    Uri? uri;

    if (rawUrl != null && rawUrl.trim().isNotEmpty) {
      uri = Uri.tryParse(rawUrl.trim());
    }

    if (uri == null) {
      if (widget.field.latitude != null && widget.field.longitude != null) {
        uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=${widget.field.latitude},${widget.field.longitude}',
        );
      } else {
        uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(widget.field.address)}',
        );
      }
    }

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể mở Google Maps')),
      );
    }
  }

  /// Hiển thị hộp thoại
  void _showPhoneDialog(String phone) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Liên hệ đặt sân',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: colorPrimary,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey, size: 22),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.pop(dialogCtx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: Text(
                    phone,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                      color: colorPrimary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: colorPrimary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: phone));
                        Navigator.pop(dialogCtx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Đã sao chép số: $phone'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 17, color: colorPrimary),
                      label: const Text(
                        'Sao chép',
                        style: TextStyle(
                          color: colorPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: colorPrimary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () {
                        Navigator.pop(dialogCtx);
                        _makePhoneCall(phone);
                      },
                      icon: const Icon(Icons.call, size: 17, color: colorYellow),
                      label: const Text(
                        'Gọi ngay',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Biểu tượng riêng cho từng loại tiện ích
  IconData _facilityIcon(String facility) {
    final lower = facility.toLowerCase();
    if (lower.contains('wifi')) return Icons.wifi;
    if (lower.contains('xe') || lower.contains('đỗ') || lower.contains('parking')) {
      return Icons.local_parking;
    }
    if (lower.contains('vệ sinh') || lower.contains('wc')) return Icons.wc;
    if (lower.contains('camera')) return Icons.videocam_outlined;
    if (lower.contains('thay đồ') || lower.contains('phòng')) return Icons.checkroom;
    if (lower.contains('nước') || lower.contains('uống')) return Icons.local_drink;
    if (lower.contains('thuê') || lower.contains('vợt') || lower.contains('bóng')) {
      return Icons.sports_tennis;
    }
    if (lower.contains('đèn') || lower.contains('sáng')) return Icons.lightbulb_outline;
    if (lower.contains('khán đài') || lower.contains('ghế')) return Icons.chair_outlined;
    return Icons.check_circle_outline;
  }

  String _formatCurrency(int amount) {
    final str = amount.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) {
        buffer.write('.');
      }
      buffer.write(str[i]);
    }
    return '${buffer.toString()}đ';
  }

  @override
  Widget build(BuildContext context) {
    final field = widget.field;
    final status = _computeOpenStatus();
    final hasPhone = field.phone != null && field.phone!.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: colorBackground,
      body: SafeArea(
        top: false, // Để banner tràn full lên mép trên điện thoại
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. ẢNH BANNER PHÍA TRÊN
                    Stack(
                      children: [
                        SizedBox(
                          width: double.infinity,
                          child: AspectRatio(
                            aspectRatio: 16 / 9.5,
                            child: Image.network(
                              field.imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: colorLavender.withValues(alpha: 0.5),
                                child: const Center(
                                  child: Icon(
                                    Icons.sports_soccer,
                                    size: 56,
                                    color: colorPrimary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Nút Back
                        Positioned(
                          top: MediaQuery.of(context).padding.top + 8,
                          left: 12,
                          child: Material(
                            color: Colors.white.withValues(alpha: 0.9),
                            shape: const CircleBorder(),
                            elevation: 3,
                            shadowColor: Colors.black38,
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => Navigator.pop(context),
                              child: const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Icon(
                                  Icons.arrow_back,
                                  color: colorPrimary,
                                  size: 22,
                                ),
                              ),
                            ),
                          ),
                        ),
                        // Tag môn thể thao với Icon riêng từng môn
                        Positioned(
                          bottom: 12,
                          left: 14,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.94),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _sportIcon(field.sport),
                                  color: colorPrimary,
                                  size: 15,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  field.sport,
                                  style: const TextStyle(
                                    color: colorPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    // 2. THÔNG TIN CHÍNH CỦA SÂN
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Tên sân & Rating
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  field.name,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: colorPrimary,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: colorPrimary,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      Icons.star,
                                      color: colorYellow,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      field.rating.toStringAsFixed(1),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),

                          // Địa chỉ
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.location_on_outlined,
                                size: 14,
                                color: colorMauve,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  field.address,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: colorTextSecondary,
                                    height: 1.25,
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),

                          // 3. KHUNG GIỜ HOẠT ĐỘNG
                          InkWell(
                            onTap: status.fullHours != null
                                ? () {
                                    setState(() {
                                      _isHoursExpanded = !_isHoursExpanded;
                                    });
                                  }
                                : null,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: colorLavender),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.access_time_rounded,
                                        size: 16,
                                        color: status.statusColor,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          status.statusText,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: status.statusColor,
                                          ),
                                        ),
                                      ),
                                      if (status.fullHours != null)
                                        Icon(
                                          _isHoursExpanded
                                              ? Icons.keyboard_arrow_up
                                              : Icons.keyboard_arrow_down,
                                          color: colorPrimary,
                                          size: 18,
                                        ),
                                    ],
                                  ),
                                  if (_isHoursExpanded && status.fullHours != null) ...[
                                    const Divider(
                                      height: 14,
                                      color: colorLavender,
                                    ),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Giờ mở cửa cụ thể:',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colorTextSecondary,
                                          ),
                                        ),
                                        Text(
                                          status.fullHours!,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: colorPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // 4. BOX SỐ LƯỢNG SÂN & BOX SỐ ĐIỆN THOẠI
                          Row(
                            children: [
                              // Box Số lượng sân
                              Expanded(
                                child: Container(
                                  height: 56,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: colorLavender),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(7),
                                        decoration: BoxDecoration(
                                          color: colorLavender.withValues(alpha: 0.45),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.sports_score,
                                          color: colorPrimary,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          '${field.courtCount} Sân đấu',
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.bold,
                                            color: colorPrimary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              // Box Số điện thoại
                              Expanded(
                                child: InkWell(
                                  onTap: hasPhone
                                      ? () => _showPhoneDialog(field.phone!)
                                      : null,
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    height: 56,
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: colorLavender),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(7),
                                          decoration: BoxDecoration(
                                            color: colorLavender.withValues(alpha: 0.45),
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.phone_in_talk,
                                            color: colorPrimary,
                                            size: 18,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            hasPhone ? 'Gọi tư vấn' : 'Chưa có SĐT',
                                            style: const TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.bold,
                                              color: colorPrimary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // 5. TIỆN ÍCH SÂN
                          const Text(
                            'Tiện ích sân',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: colorPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (field.facilities.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 10),
                              child: Text(
                                'Sân có đầy đủ tiện ích cơ bản phục vụ người chơi.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorTextSecondary,
                                ),
                              ),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: GridView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: field.facilities.length,
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisExtent: 28,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 6,
                                ),
                                itemBuilder: (context, index) {
                                  final facility = field.facilities[index];
                                  return Row(
                                    children: [
                                      Icon(
                                        _facilityIcon(facility),
                                        color: colorMauve,
                                        size: 17,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          facility,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: colorPrimary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),

                          const SizedBox(height: 16),

                          // 6. KHUNG BẢN ĐỒ
                          const Text(
                            'Vị trí sân',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: colorPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: _openGoogleMaps,
                            borderRadius: BorderRadius.circular(18),
                            child: Container(
                              height: 150,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE5E9F0),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: colorLavender),
                                image: const DecorationImage(
                                  image: NetworkImage(
                                    'https://images.unsplash.com/photo-1524661135-423995f22d0b?auto=format&fit=crop&w=800&q=80',
                                  ),
                                  fit: BoxFit.cover,
                                  opacity: 0.35,
                                ),
                              ),
                              child: Stack(
                                children: [
                                  Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(11),
                                          decoration: BoxDecoration(
                                            color: colorPrimary,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: colorPrimary.withValues(
                                                  alpha: 0.3,
                                                ),
                                                blurRadius: 10,
                                                offset: const Offset(0, 4),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.location_on,
                                            color: colorYellow,
                                            size: 26,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(
                                                  alpha: 0.1,
                                                ),
                                                blurRadius: 6,
                                              ),
                                            ],
                                          ),
                                          child: const Text(
                                            'Chạm để mở trên Google Maps',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: colorPrimary,
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

                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 7. BOTTOM BAR Giá/giờ + Nút Đặt sân ngay
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 14,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatCurrency(field.price),
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: colorPrimary,
                        ),
                      ),
                      const Text(
                        '/ giờ',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorTextSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: ElevatedButton(
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

                        if (!context.mounted) return;
                        if (booked == true) {
                          Navigator.pop(context, true);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Đặt sân ngay',
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
      ),
    );
  }
}
