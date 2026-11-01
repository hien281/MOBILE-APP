import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'sepay_checkout_screen.dart';
import 'sepay_web_stub.dart'
    if (dart.library.html) 'sepay_web.dart' as sepayWeb;

class MembershipPaymentScreen extends StatefulWidget {
  final String orderId;
  final String membershipName;
  final int totalPrice;
  final DateTime expiresAt;
  final String baseUrl;

  const MembershipPaymentScreen({
    super.key,
    required this.orderId,
    required this.membershipName,
    required this.totalPrice,
    required this.expiresAt,
    required this.baseUrl,
  });

  @override
  State<MembershipPaymentScreen> createState() =>
      _MembershipPaymentScreenState();
}

class _MembershipPaymentScreenState
    extends State<MembershipPaymentScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  Timer? _pollTimer;

  Duration _remaining = Duration.zero;
  String _status = 'pending_payment';
  String _paymentStatus = 'pending';
  String _method = 'sepay';

  bool _loading = false;
  bool _checking = false;
  bool _checkoutStarted = false;
  String? _error;
  String? _membershipImageUrl;
  String? _membershipVenue;
  String? _membershipDuration;
  String? _membershipSlots;
  String? _membershipSport;
  String? _membershipApplyTime;

  String get _api =>
      widget.baseUrl.replaceFirst(RegExp(r'/$'), '');

  bool get _paid =>
      _status == 'confirmed' && _paymentStatus == 'paid';

  bool get _refund =>
      _paymentStatus == 'refund_required';

  bool get _expired => _remaining == Duration.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tick();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tick(),
    );
    _pollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshStatus(),
    );
    _refreshStatus();
    _loadMembershipDetails();
  }

  Future<void> _loadMembershipDetails() async {
    try {
      final result = await FirebaseFirestore.instance.collection('memberships').get();
      final target = widget.membershipName.trim().toLowerCase();
      for (final doc in result.docs) {
        final m = doc.data();
        final name = (m['cardName'] ?? m['name'] ?? m['title'] ?? '').toString().trim().toLowerCase();
        if (name != target) continue;
        final image = (m['imageUrl'] ?? m['coverUrl'] ?? m['bannerUrl'] ?? m['logoUrl'])?.toString();
        if (!mounted) return;
        setState(() {
          _membershipImageUrl = image != null && Uri.tryParse(image)?.scheme == 'https' ? image : null;
          _membershipVenue = (m['venue'] ?? '').toString();
          _membershipDuration = (m['duration'] ?? '').toString();
          _membershipSlots = (m['freeSlots'] ?? '').toString();
          _membershipSport = (m['sport'] ?? '').toString();
          _membershipApplyTime = (m['applyTime'] ?? m['applicableHours'] ?? m['timeRange'] ?? '').toString();
        });
        break;
      }
    } catch (_) {
      // Không để lỗi tải ảnh/thông tin làm gián đoạn thanh toán.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _tick() {
    if (!mounted) return;
    final diff = widget.expiresAt.difference(DateTime.now());
    setState(() {
      _remaining = diff.isNegative ? Duration.zero : diff;
    });
  }

  Future<String> _token() async {
    final token =
        await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) {
      throw Exception('Vui lòng đăng nhập lại.');
    }
    return token;
  }

  Future<void> _refreshStatus() async {
    if (!mounted || _checking || _paid || _refund) return;

    setState(() => _checking = true);

    try {
      final token = await _token();

      final response = await http.get(
        Uri.parse(
          '$_api/membership-orders/'
          '${Uri.encodeComponent(widget.orderId)}/status',
        ),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode != 200 ||
          data is! Map ||
          data['success'] != true) {
        throw Exception(
          data is Map
              ? data['message'] ?? 'Không kiểm tra được đơn.'
              : 'Phản hồi không hợp lệ.',
        );
      }

      if (!mounted) return;

      setState(() {
        _status = data['status']?.toString() ?? _status;
        _paymentStatus =
            data['paymentStatus']?.toString() ?? _paymentStatus;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Kiểm tra trạng thái: $e');
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _pay() async {
    if (_loading ||
        _checking ||
        _paid ||
        _refund ||
        _expired ||
        _checkoutStarted) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final token = await _token();
      final isSePay = _method == 'sepay';

      final endpoint = isSePay
          ? '/payments/sepay/membership/create'
          : '/payments/vnpay/membership/create';

      final response = await http.post(
        Uri.parse('$_api$endpoint'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'orderId': widget.orderId}),
      ).timeout(const Duration(seconds: 20));

      final data = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode != 200 ||
          data is! Map ||
          data['success'] != true) {
        throw Exception(
          data is Map
              ? data['message'] ?? 'Không tạo được thanh toán.'
              : 'Phản hồi không hợp lệ.',
        );
      }

      if (isSePay) {
        final checkoutUrl =
            data['checkoutUrl']?.toString() ?? '';
        final rawFields = data['fields'];

        if (rawFields is! Map) {
          throw Exception('Thiếu dữ liệu SePay Checkout.');
        }

        final uri = Uri.tryParse(checkoutUrl);
        if (uri == null ||
            uri.scheme != 'https' ||
            uri.host != 'pay-sandbox.sepay.vn' ||
            uri.path != '/v1/checkout/init') {
          throw Exception('URL SePay Sandbox không hợp lệ.');
        }

        final fields = rawFields.map<String, dynamic>(
          (key, value) => MapEntry(key.toString(), value),
        );

        if (!mounted) return;
        setState(() => _checkoutStarted = true);

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
      } else {
        final url = Uri.tryParse(
          data['paymentUrl']?.toString() ?? '',
        );

        if (url == null ||
            url.scheme != 'https' ||
            url.host != 'sandbox.vnpayment.vn') {
          throw Exception('URL VNPay Sandbox không hợp lệ.');
        }

        final opened = await launchUrl(
          url,
          mode: LaunchMode.externalApplication,
        );

        if (!opened) {
          throw Exception('Không mở được VNPay.');
        }

        if (mounted) {
          setState(() => _checkoutStarted = true);
        }
      }

      await _refreshStatus();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _money(int value) => value.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );

  static const Color _primary = Color.fromARGB(255, 54, 26, 148);
  static const Color _background = Color.fromARGB(255, 255, 254, 247);

  Widget _card(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.74),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _primary.withValues(alpha: 0.35), width: 0.7),
    ),
    child: child,
  );

  Widget _detail(String label, String value, {bool highlight = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF77788A))),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: highlight ? _primary : const Color(0xFF202039),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _membershipPreview() => Container(
    width: 54,
    height: 54,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: const Color(0xFFF0EEE5),
      borderRadius: BorderRadius.circular(12),
    ),
    child: _membershipImageUrl == null
        ? const Center(child: Icon(Icons.card_membership_rounded, size: 26, color: _primary))
        : Image.network(
            _membershipImageUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.card_membership_rounded, size: 26, color: _primary),
            ),
          ),
  );

  @override
  Widget build(BuildContext context) {
    final seconds = _remaining.inSeconds;
    final countdown =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';
    final closed = _status == 'cancelled' || _status == 'expired';
    final finished = _paid || _refund || _expired || closed;
    final canPay = !finished && !_loading && !_checking && !_checkoutStarted;
    final subtitle = _paid
        ? 'Thẻ hội viên đã được ghi nhận. Cảm ơn bạn!'
        : _refund
            ? 'Vui lòng liên hệ hỗ trợ để kiểm tra hoàn tiền, không thanh toán lại.'
            : closed || _expired
                ? 'Đã hết thời gian thanh toán. Vui lòng kiểm tra trạng thái đơn.'
                : _checkoutStarted
                    ? 'SPORTY sẽ tự động kiểm tra trạng thái thanh toán.'
                    : 'Vui lòng thanh toán trước khi hết thời gian giữ đơn.';

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: const Color(0xFFF9F8F2),
        toolbarHeight: 48,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        title: Text(
          _paid ? 'Xác nhận hội viên' : 'Thanh toán hội viên',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _primary),
        ),
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: _primary),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  _card(
                    _paid
                        ? Row(
                            children: [
                              const CircleAvatar(
                                radius: 13,
                                backgroundColor: Color(0xFF159E65),
                                child: Icon(Icons.check_rounded, color: Colors.white, size: 17),
                              ),
                              const SizedBox(width: 10),
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Đăng ký hội viên thành công!',
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _primary)),
                                  const SizedBox(height: 3),
                                  Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF6B6B80))),
                                ],
                              )),
                            ],
                          )
                        : Column(
                            children: [
                              Text(subtitle, textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _primary)),
                              if (!finished) ...[
                                const SizedBox(height: 7),
                                const Text('Thời gian thanh toán còn lại',
                                    style: TextStyle(fontSize: 12, color: Color(0xFF6B6B80))),
                                const SizedBox(height: 2),
                                Text(countdown,
                                    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: _primary)),
                              ],
                            ],
                          ),
                  ),
                  const SizedBox(height: 11),
                  _card(Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        _membershipPreview(),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.membershipName,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _primary)),
                            const SizedBox(height: 6),
                            Text('${_money(widget.totalPrice)}đ',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _primary)),
                          ],
                        )),
                      ]),
                      const Divider(height: 25),
                      const Text('Thông tin thẻ hội viên',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 5),
                      _detail('Mã đơn', widget.orderId),
                      if (_membershipVenue?.isNotEmpty == true)
                        _detail('Địa điểm', _membershipVenue!),
                      if (_membershipDuration?.isNotEmpty == true)
                        _detail('Thời hạn thẻ', _membershipDuration!),
                      if (_membershipSlots?.isNotEmpty == true)
                        _detail('Lượt miễn phí', _membershipSlots!),
                      if (_membershipApplyTime?.isNotEmpty == true)
                        _detail('Khung giờ áp dụng', _membershipApplyTime!),
                      if (_membershipSport?.isNotEmpty == true)
                        _detail('Bộ môn', _membershipSport!),
                      const Divider(height: 25),
                      _detail('Tổng thanh toán', '${_money(widget.totalPrice)}đ', highlight: true),
                      _detail('Trạng thái', _paid ? 'Đã thanh toán' : _refund
                          ? 'Cần kiểm tra hoàn tiền' : closed || _expired
                          ? 'Đã hết hạn' : 'Chờ thanh toán'),
                    ],
                  )),
                  const SizedBox(height: 14),
                  if (!finished)
                    _card(Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Phương thức thanh toán',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        RadioListTile<String>(
                          value: 'vnpay',
                          groupValue: _method,
                          onChanged: _checkoutStarted ? null : (value) => setState(() => _method = value!),
                          contentPadding: EdgeInsets.zero,
                          activeColor: _primary,
                          title: const Text('VNPay', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          subtitle: const Text('Thanh toán trực tuyến', style: TextStyle(fontSize: 12)),
                          secondary: const Icon(Icons.account_balance_rounded, color: _primary),
                        ),
                        const Divider(),
                        RadioListTile<String>(
                          value: 'sepay',
                          groupValue: _method,
                          onChanged: _checkoutStarted ? null : (value) => setState(() => _method = value!),
                          contentPadding: EdgeInsets.zero,
                          activeColor: _primary,
                          title: const Text('SePay QR', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          subtitle: const Text('Quét mã chuyển khoản ngân hàng', style: TextStyle(fontSize: 12)),
                          secondary: const Icon(Icons.qr_code, color: _primary),
                        ),
                      ],
                    )),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                    ),
                  if (_checkoutStarted && !finished)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(children: [
                        const Text('Đã mở cổng thanh toán. Vui lòng không tạo giao dịch thứ hai.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: Color(0xFF77788A))),
                        TextButton.icon(
                          onPressed: _checking ? null : _refreshStatus,
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Kiểm tra trạng thái'),
                        ),
                      ]),
                    ),
                  if (finished && !_paid)
                    Align(
                      child: TextButton.icon(
                        onPressed: _checking ? null : _refreshStatus,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Kiểm tra trạng thái'),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 45,
                child: _paid
                    ? FilledButton(
                        onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                        style: FilledButton.styleFrom(backgroundColor: _primary),
                        child: const Text('Về trang chủ'),
                      )
                    : finished
                        ? FilledButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            style: FilledButton.styleFrom(backgroundColor: _primary),
                            child: const Text('Quay lại'),
                          )
                        : _checkoutStarted
                            ? const Center(child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(width: 17, height: 17,
                                      child: CircularProgressIndicator(strokeWidth: 2)),
                                  SizedBox(width: 10),
                                  Text('Đang tự động xác minh thanh toán'),
                                ],
                              ))
                            : FilledButton(
                                onPressed: canPay ? _pay : null,
                                style: FilledButton.styleFrom(backgroundColor: _primary),
                                child: Text(_loading ? 'Đang mở thanh toán...' : 'Thanh toán'),
                              ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
