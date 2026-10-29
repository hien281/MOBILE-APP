import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
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

  @override
  Widget build(BuildContext context) {
    final minutes =
        _remaining.inMinutes.toString().padLeft(2, '0');
    final seconds =
        (_remaining.inSeconds % 60).toString().padLeft(2, '0');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Thanh toán hội viên'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(
            Icons.card_membership,
            size: 64,
            color: Color(0xFF1E147B),
          ),
          const SizedBox(height: 16),
          Text(
            widget.membershipName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '${_money(widget.totalPrice)} đ',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E147B),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Thời gian thanh toán còn lại: $minutes:$seconds',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          if (_paid)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 48,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Thanh toán thành công!',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    Text('Thẻ hội viên đã được ghi nhận.'),
                  ],
                ),
              ),
            )
          else if (_refund)
            const Text(
              'Giao dịch cần được kiểm tra hoàn tiền. '
              'Vui lòng liên hệ hỗ trợ, không thanh toán lại.',
              textAlign: TextAlign.center,
            )
          else if (_expired)
            const Text(
              'Đã hết thời gian thanh toán. '
              'Nếu bạn vừa chuyển tiền, hãy kiểm tra trạng thái đơn.',
              textAlign: TextAlign.center,
            )
          else ...[
            RadioListTile<String>(
              title: const Text('SePay'),
              value: 'sepay',
              groupValue: _method,
              onChanged: _checkoutStarted
                  ? null
                  : (value) =>
                      setState(() => _method = value!),
            ),
            RadioListTile<String>(
              title: const Text('VNPay'),
              value: 'vnpay',
              groupValue: _method,
              onChanged: _checkoutStarted
                  ? null
                  : (value) =>
                      setState(() => _method = value!),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ||
                      _checking ||
                      _checkoutStarted
                  ? null
                  : _pay,
              child: _loading
                  ? const CircularProgressIndicator()
                  : const Text('Thanh toán ngay'),
            ),
            if (_checkoutStarted)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Đã mở cổng thanh toán. '
                  'Vui lòng không tạo giao dịch thứ hai.',
                  textAlign: TextAlign.center,
                ),
              ),
          ],

          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _checking ? null : _refreshStatus,
            child: const Text('Kiểm tra trạng thái'),
          ),

          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
        ],
      ),
    );
  }
}
