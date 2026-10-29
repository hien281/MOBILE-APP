import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'sepay_checkout_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'sepay_web_stub.dart'
    if (dart.library.html) 'sepay_web.dart'
    as sepayWeb;

class PaymentScreen extends StatefulWidget {
  final String bookingId;
  final String fieldName;
  final int totalPrice;
  final DateTime expiresAt;
  final String baseUrl;
  final List<Map<String, String>> selections;
  final String? fieldImageUrl;

  const PaymentScreen({
    super.key,
    required this.bookingId,
    required this.fieldName,
    required this.totalPrice,
    required this.expiresAt,
    required this.baseUrl,
    required this.selections,
    this.fieldImageUrl,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen>
    with WidgetsBindingObserver {
  static const primary = Color.fromARGB(255, 54, 26, 148);
  static const background = Color.fromARGB(255, 255, 254, 247);
  Timer? _countdown;
  Timer? _poll;
  Duration _remaining = Duration.zero;
  String _status = 'pending_payment';
  String _paymentStatus = 'pending';
  String? _error;
  bool _checking = false;
  bool _paying = false;
  bool _cancelling = false;
  bool _openedVNPay = false;
  String _selectedPaymentMethod = 'vnpay';
  bool _allowPop = false;
  String? _resolvedImageUrl;
  String? _sportName;

  String get _api => widget.baseUrl.replaceFirst(RegExp(r'/$'), '');
  bool get _success => _status == 'confirmed' && _paymentStatus == 'paid';
  bool get _closed => _status == 'cancelled' || _status == 'expired';
  bool get _refund => _paymentStatus == 'refund_required';
  bool get _expired => _remaining == Duration.zero;
  bool get _canPay =>
      !_success &&
      !_closed &&
      !_refund &&
      !_expired &&
      !_openedVNPay &&
      !_paying &&
      !_checking &&
      !_cancelling;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tick();
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_success && !_closed && !_refund) _refresh();
    });
    _refresh();
    _loadFieldDetails();
  }

  Future<void> _loadFieldDetails() async {
    try {
      final response = await http
          .get(Uri.parse('$_api/fields'))
          .timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return;
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['fields'] is! List) return;
      for (final item in decoded['fields'] as List) {
        if (item is! Map) continue;
        if (item['name']?.toString().trim().toLowerCase() !=
            widget.fieldName.trim().toLowerCase())
          continue;
        final image = item['imageUrl']?.toString();
        if (!mounted) return;
        setState(() {
          _resolvedImageUrl =
              image != null &&
                  Uri.tryParse(image)?.hasAbsolutePath == true &&
                  image.startsWith('https://')
              ? image
              : null;
          _sportName = item['sport']?.toString();
        });
        break;
      }
    } catch (_) {
      // Keep the payment screen usable if venue details are temporarily unavailable.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdown?.cancel();
    _poll?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final d = widget.expiresAt.difference(DateTime.now());
    setState(() => _remaining = d.isNegative ? Duration.zero : d);
  }

  String _money(int v) => v.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  String _date(String raw) {
    final d = DateTime.tryParse(raw);
    if (d == null) return raw;
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  String _court(String raw) {
    final match = RegExp(r'court_(\d+)').firstMatch(raw);
    return match == null ? raw : 'Sân ${match.group(1)}';
  }

  String _endTime(String raw) {
    final parts = raw.split(':');
    final hour = int.tryParse(parts.first);
    if (hour == null) return raw;
    return '${(hour + 1).toString().padLeft(2, '0')}:00';
  }

  Future<String> _token() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty)
      throw Exception('Vui lòng đăng nhập lại.');
    return token;
  }

  Future<bool> _refresh() async {
    if (_checking || !mounted) return false;
    setState(() => _checking = true);
    try {
      final token = await _token();
      final response = await http
          .get(
            Uri.parse(
              '$_api/bookings/${Uri.encodeComponent(widget.bookingId)}/status',
            ),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200 ||
          data is! Map ||
          data['success'] != true) {
        throw Exception(
          data is Map
              ? (data['message'] ?? 'Không lấy được trạng thái')
              : 'Dữ liệu lỗi',
        );
      }
      if (!mounted) return false;
      setState(() {
        _status = data['status']?.toString() ?? _status;
        _paymentStatus = data['paymentStatus']?.toString() ?? _paymentStatus;
        _error = null;
      });
      return true;
    } catch (e) {
      if (mounted && _openedVNPay)
        setState(() => _error = 'Chưa cập nhật được kết quả: $e');
      return false;
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _payVNPay() async {
    if (!_canPay) return;
    setState(() {
      _paying = true;
      _error = null;
    });
    try {
      final token = await _token();
      final response = await http
          .post(
            Uri.parse('$_api/payments/vnpay/create'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'bookingId': widget.bookingId}),
          )
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200 ||
          data is! Map ||
          data['success'] != true) {
        throw Exception(
          data is Map
              ? (data['message'] ?? 'Không tạo được giao dịch')
              : 'Phản hồi không hợp lệ',
        );
      }
      final url = Uri.tryParse(data['paymentUrl']?.toString() ?? '');
      if (url == null ||
          url.scheme != 'https' ||
          url.host != 'sandbox.vnpayment.vn') {
        throw Exception('Địa chỉ thanh toán Sandbox không hợp lệ.');
      }
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (!opened) throw Exception('Không mở được trình duyệt thanh toán.');
      if (mounted) setState(() => _openedVNPay = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Không mở được VNPay: $e');
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  
Future<void> _paySePay() async {
  if (!_canPay) return;

  setState(() {
    _paying = true;
    _error = null;
  });

  try {
    final token = await _token();

    final response = await http
        .post(
          Uri.parse('$_api/payments/sepay/create'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'bookingId': widget.bookingId,
          }),
        )
        .timeout(const Duration(seconds: 20));

    final data = jsonDecode(utf8.decode(response.bodyBytes));

    if (response.statusCode != 200 ||
        data is! Map ||
        data['success'] != true) {
      throw Exception(
        data is Map
            ? (data['message'] ?? 'Không tạo được thanh toán SePay')
            : 'Phản hồi không hợp lệ',
      );
    }

    final checkoutUrl = data['checkoutUrl']?.toString() ?? '';
    final rawFields = data['fields'];

    if (rawFields is! Map) {
      throw Exception('Thiếu dữ liệu SePay Checkout.');
    }

    final fields = rawFields.map<String, dynamic>(
      (key, value) => MapEntry(key.toString(), value),
    );

    if (!mounted) return;

    // Đánh dấu đã bắt đầu phiên thanh toán.
    setState(() => _openedVNPay = true);

    if (kIsWeb) {
    sepayWeb.openSePayWeb(checkoutUrl, fields);
  } else {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SePayCheckoutScreen(
          checkoutUrl: checkoutUrl,
          fields: fields,
        ),
      ),
    );
}

    if (mounted) {
      await _refresh();
    }
  } catch (e) {
    if (mounted) {
      setState(() {
        _error = 'Không mở được SePay: $e';
      });
    }
  } finally {
    if (mounted) {
      setState(() => _paying = false);
    }
  }
}

  Future<bool> _cancel() async {
    if (_cancelling) return false;
    setState(() => _cancelling = true);
    try {
      final token = await _token();
      final response = await http
          .post(
            Uri.parse(
              '$_api/bookings/${Uri.encodeComponent(widget.bookingId)}/cancel',
            ),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200 ||
          data is! Map ||
          data['success'] != true) {
        throw Exception(
          data is Map
              ? (data['message'] ?? 'Không hủy được đơn')
              : 'Không hủy được đơn',
        );
      }
      if (mounted)
        setState(() {
          _status = 'cancelled';
          _paymentStatus = 'cancelled';
        });
      return true;
    } catch (e) {
      if (mounted) setState(() => _error = 'Hủy đơn thất bại: $e');
      return false;
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  Future<bool> _onBack() async {
    if (_allowPop) return true;
    if (_checking || _paying || _cancelling) return false;
    final checked = await _refresh();
    if (!mounted) return false;
    if (!checked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chưa xác minh được trạng thái đơn. Vui lòng thử lại.'),
        ),
      );
      return false;
    }
    if (_success || _closed || _refund || _status != 'pending_payment') {
      _allowPop = true;
      return true;
    }
    // Rời màn hình không hủy đơn: giữ sân đến expiresAt để thanh toán lại.
    _allowPop = true;
    return true;
  }

  Future<void> _back() async {
    if (await _onBack() && mounted) Navigator.pop(context, true);
  }

  Widget _card(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.74),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: primary.withValues(alpha: 0.35), width: 0.7),
    ),
    child: child,
  );

  Widget _fieldPreview() {
    final imageUrl = widget.fieldImageUrl ?? _resolvedImageUrl;
    return Container(
      width: 98,
      height: 80,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFF0EEE5),
        borderRadius: BorderRadius.circular(11),
      ),
      child: imageUrl != null && imageUrl.isNotEmpty
          ? Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Center(
                child: Icon(Icons.image_outlined, color: Color(0xFF9B98A0)),
              ),
            )
          : const Center(
              child: Icon(Icons.image_outlined, color: Color(0xFF9B98A0)),
            ),
    );
  }

  Widget _detail(String label, String value, {bool highlight = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 12, color: Color(0xFF77788A)),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: highlight ? primary : const Color(0xFF202039),
                ),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final seconds = _remaining.inSeconds;
    final countdown =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
    final finished = _success || _closed || _refund || _expired;
    final stateSubtitle = _success
        ? 'Thanh toán đã được xác nhận. Hẹn gặp bạn tại sân!'
        : _refund
        ? 'Vui lòng liên hệ đơn vị vận hành để kiểm tra giao dịch.'
        : finished
        ? 'Bạn có thể quay lại chọn lịch khác.'
        : _openedVNPay
        ? 'SPORTY tự kiểm tra trạng thái sau khi bạn trở lại ứng dụng.'
        : 'Vui lòng thanh toán trước khi hết thời gian giữ sân.';

    return WillPopScope(
      onWillPop: _onBack,
      child: Scaffold(
        backgroundColor: background,
        appBar: AppBar(
          backgroundColor: const Color(0xFFF9F8F2),
          toolbarHeight: 48,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          title: Text(
            _success ? 'Xác nhận đặt sân' : 'Thanh toán đặt sân',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: primary,
            ),
          ),
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 20,
              color: primary,
            ),
            onPressed: () {
              if (Navigator.of(context, rootNavigator: true).canPop()) {
                 Navigator.of(context, rootNavigator: true).pop();
              } else {
                 Navigator.pop(context);
              }
},
          ),
        ),
        body: Container(
          color: background,
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(14),
                    children: [
                      _card(
                        _success
                            ? Row(
                                children: [
                                  const CircleAvatar(
                                    radius: 13,
                                    backgroundColor: Color(0xFF159E65),
                                    child: Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 17,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Đặt sân thành công!',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: primary,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          stateSubtitle,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF6B6B80),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : Column(
                                children: [
                                  Text(
                                    stateSubtitle,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: primary,
                                    ),
                                  ),
                                  if (!finished) ...[
                                    const SizedBox(height: 7),
                                    const Text(
                                      'Thời gian giữ sân còn lại',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF6B6B80),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      countdown,
                                      style: const TextStyle(
                                        fontSize: 21,
                                        fontWeight: FontWeight.w700,
                                        color: primary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                      ),
                      const SizedBox(height: 11),
                      _card(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                _fieldPreview(),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.fieldName,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: primary,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${_money(widget.totalPrice)}đ',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 25),
                            const Text(
                              'Thông tin đặt sân',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            if (widget.selections.isNotEmpty) ...[
                              _detail(
                                'Ngày đặt',
                                (widget.selections
                                        .map((e) => e['date'] ?? '')
                                        .toSet()
                                        .toList()
                                      ..sort())
                                    .map(_date)
                                    .join(', '),
                              ),
                              for (final entry in widget.selections)
                                _detail(
                                  _court(entry['courtId'] ?? ''),
                                  '${entry['startTime'] ?? ''} – ${_endTime(entry['startTime'] ?? '')}',
                                ),
                            ],
                            _detail(
                              'Bộ môn',
                              (_sportName == null || _sportName!.isEmpty)
                                  ? 'Đang cập nhật'
                                  : _sportName!,
                            ),
                            const Divider(height: 25),
                            _detail(
                              'Tổng thanh toán',
                              '${_money(widget.totalPrice)}đ',
                              highlight: true,
                            ),
                            _detail(
                              'Trạng thái',
                              _success
                                  ? 'Đã thanh toán'
                                  : _closed
                                  ? 'Đã đóng'
                                  : 'Chờ thanh toán',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (!finished)
                        _card(
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Phương thức thanh toán',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              RadioListTile<String>(
                                value: 'vnpay',
                                groupValue: _selectedPaymentMethod,
                                onChanged: _openedVNPay
                                    ? null
                                    : (value) {
                                        setState(() => _selectedPaymentMethod = value!);
                                      },
                                contentPadding: EdgeInsets.zero,
                                activeColor: primary,
                                title: const Text(
                                  'VNPay',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: const Text(
                                  'Thanh toán trực tuyến',
                                  style: TextStyle(fontSize: 11),
                                ),
                                secondary: const Icon(
                                  Icons.account_balance_rounded,
                                  color: primary,
                                ),
                              ),

                              const Divider(),

                              RadioListTile<String>(
                                value: 'sepay',
                                groupValue: _selectedPaymentMethod,
                                onChanged: _openedVNPay
                                    ? null
                                    : (value) {
                                        setState(() => _selectedPaymentMethod = value!);
                                      },
                                contentPadding: EdgeInsets.zero,
                                activeColor: primary,
                                title: const Text(
                                  'SePay QR',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: const Text(
                                  'Quét mã chuyển khoản ngân hàng',
                                  style: TextStyle(fontSize: 11),
                                ),
                                secondary: const Icon(
                                  Icons.qr_code,
                                  color: primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      if (_openedVNPay && !finished)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Nếu đã thanh toán, đừng tạo giao dịch mới. '
                            'Kết quả sẽ được cập nhật tự động khi backend nhận xác nhận VNPay.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF77788A),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 45,
                    child: _success
                        ? FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: primary,
                              textStyle: const TextStyle(fontSize: 15),
                            ),
                            onPressed: () =>
                                Navigator.of(context)
                                    .popUntil((route) => route.isFirst),
                            child: const Text('Về trang chủ'),
                          )
                        : finished
                        ? FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: primary,
                              textStyle: const TextStyle(fontSize: 15),
                            ),
                            onPressed: _back,
                            child: const Text('Quay lại đặt sân'),
                          )
                        : _openedVNPay
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 17,
                                  height: 17,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text('Đang tự động xác minh thanh toán'),
                              ],
                            ),
                          )
                        : FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: primary,
                              textStyle: const TextStyle(fontSize: 15),
                            ),
                            onPressed: _canPay
                            ? (_selectedPaymentMethod == 'sepay'
                                ? _paySePay
                                : _payVNPay)
                            : null,
                            child: Text(
                              _paying ? 'Đang mở thanh toán...' : 'Thanh toán',
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
