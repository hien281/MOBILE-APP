import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class PaymentScreen extends StatefulWidget {
  final String bookingId;
  final String fieldName;
  final int totalPrice;
  final DateTime expiresAt;
  final String baseUrl;

  const PaymentScreen({
    super.key,
    required this.bookingId,
    required this.fieldName,
    required this.totalPrice,
    required this.expiresAt,
    required this.baseUrl,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  static const Color primary = Color(0xFF1E147B);

  Timer? _timer;
  Duration _remaining = Duration.zero;

  String _status = 'pending_payment';
  bool _checking = false;
  bool _cancelling = false;
  bool _allowPop = false;

  String? _error;

  String _money(int amount) {
    return amount.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
  }

  @override
  void initState() {
    super.initState();

    _tick();

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tick(),
    );

    _refreshStatus();
  }

  void _tick() {
    if (!mounted) return;

    final difference =
        widget.expiresAt.difference(DateTime.now());

    setState(() {
      _remaining = difference.isNegative
          ? Duration.zero
          : difference;
    });
  }

  Future<bool> _refreshStatus() async {
    if (_checking) return false;

    setState(() {
      _checking = true;
      _error = null;
    });

    try {
      final token =
          await FirebaseAuth.instance.currentUser?.getIdToken();

      if (token == null) {
        throw Exception('Bạn cần đăng nhập lại.');
      }

      final uri = Uri.parse(
        '${widget.baseUrl}/bookings/'
        '${Uri.encodeComponent(widget.bookingId)}/status',
      );

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(
        utf8.decode(response.bodyBytes),
      );

      if (response.statusCode != 200 ||
          data is! Map ||
          data['success'] != true) {
        throw Exception(
          data is Map
              ? data['message']?.toString() ??
                  'Không kiểm tra được đơn.'
              : 'Dữ liệu không hợp lệ.',
        );
      }

      if (!mounted) return false;

      setState(() {
        _status = data['status']?.toString() ?? _status;
      });

      return true;
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }

      return false;
    } finally {
      if (mounted) {
        setState(() {
          _checking = false;
        });
      }
    }
  }

  Future<bool> _cancelBooking() async {
    if (_cancelling) return false;

    setState(() {
      _cancelling = true;
      _error = null;
    });

    try {
      final token =
          await FirebaseAuth.instance.currentUser?.getIdToken();

      if (token == null) {
        throw Exception('Bạn cần đăng nhập lại.');
      }

      final uri = Uri.parse(
        '${widget.baseUrl}/bookings/'
        '${Uri.encodeComponent(widget.bookingId)}/cancel',
      );

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 20));

      final data = jsonDecode(
        utf8.decode(response.bodyBytes),
      );

      if (response.statusCode != 200 ||
          data is! Map ||
          data['success'] != true) {
        throw Exception(
          data is Map
              ? data['message']?.toString() ??
                  'Không hủy được đơn.'
              : 'Không hủy được đơn.',
        );
      }

      if (!mounted) return false;

      setState(() {
        _status = 'cancelled';
      });

      return true;
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Hủy thất bại: $e';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hủy thất bại: $e'),
          ),
        );
      }

      return false;
    } finally {
      if (mounted) {
        setState(() {
          _cancelling = false;
        });
      }
    }
  }

  Future<bool> _onBack() async {
    if (_allowPop) return true;

    if (_cancelling || _checking) {
      return false;
    }

    // Kiểm tra trạng thái mới nhất từ backend.
    final checked = await _refreshStatus();

    if (!mounted) return false;

    if (!checked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Không kiểm tra được trạng thái đơn. '
            'Vui lòng thử lại.',
          ),
        ),
      );

      return false;
    }

    // Đơn đã hoàn tất hoặc không còn giữ sân.
    if (_status != 'pending_payment') {
      _allowPop = true;
      return true;
    }

    final cancel = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Hủy giữ sân?'),
          content: const Text(
            'Nếu quay lại, đơn chờ thanh toán sẽ bị hủy '
            'và các khung giờ được mở lại ngay.\n\n'
            'Bạn có muốn hủy giữ sân không?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Tiếp tục thanh toán'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: primary,
              ),
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Hủy giữ sân'),
            ),
          ],
        );
      },
    );

    if (cancel != true || !mounted) {
      return false;
    }

    final success = await _cancelBooking();

    if (success) {
      _allowPop = true;
      return true;
    }

    return false;
  }

  Future<void> _handleBackButton() async {
    final canLeave = await _onBack();

    if (!mounted || !canLeave) return;

    Navigator.of(context).pop(true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = _remaining.inSeconds;

    final countdown =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:'
        '${(seconds % 60).toString().padLeft(2, '0')}';

    final expired = _remaining == Duration.zero;
    final confirmed = _status == 'confirmed';

    final cancelled =
        _status == 'expired' || _status == 'cancelled';

    return WillPopScope(
      onWillPop: _onBack,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FC),
        appBar: AppBar(
          title: const Text('Thanh toán đặt sân'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _cancelling || _checking
                ? null
                : _handleBackButton,
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ĐỒNG HỒ GIỮ SÂN
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Icon(
                      Icons.timer_outlined,
                      size: 42,
                      color: primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      confirmed
                          ? 'Đã xác nhận'
                          : cancelled || expired
                              ? 'Đã hết thời gian giữ sân'
                              : 'Thời gian giữ sân còn lại',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      confirmed ? 'Hoàn tất' : countdown,
                      style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.bold,
                        color: expired
                            ? Colors.red
                            : primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Trạng thái đơn: $_status',
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // THÔNG TIN ĐƠN
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.fieldName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Mã đơn: ${widget.bookingId}',
                    ),
                    const Divider(height: 28),
                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Tổng tiền',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_money(widget.totalPrice)}đ',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: primary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // PHƯƠNG THỨC THANH TOÁN
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Phương thức thanh toán',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 12),
                    ListTile(
                      leading: Icon(
                        Icons.account_balance_wallet_outlined,
                      ),
                      title: Text('MoMo'),
                      subtitle: Text(
                        'Chưa kết nối cổng thanh toán',
                      ),
                      enabled: false,
                    ),
                    ListTile(
                      leading: Icon(Icons.credit_card),
                      title: Text('VNPay'),
                      subtitle: Text(
                        'Chưa kết nối cổng thanh toán',
                      ),
                      enabled: false,
                    ),
                    ListTile(
                      leading: Icon(Icons.qr_code),
                      title: Text('QR chuyển khoản'),
                      subtitle: Text(
                        'Chưa có xác minh thanh toán tự động',
                      ),
                      enabled: false,
                    ),
                  ],
                ),
              ),
            ),

            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.red,
                  ),
                ),
              ),

            const SizedBox(height: 12),

            // KIỂM TRA TRẠNG THÁI
            FilledButton.icon(
              onPressed: _checking || _cancelling
                  ? null
                  : () {
                      _refreshStatus();
                    },
              icon: const Icon(Icons.refresh),
              label: Text(
                _checking
                    ? 'Đang kiểm tra...'
                    : _cancelling
                        ? 'Đang hủy...'
                        : 'Kiểm tra trạng thái đơn',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: primary,
                padding: const EdgeInsets.all(16),
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              'Đây là màn hình chờ thanh toán. '
              'Đơn chưa được xác nhận cho đến khi backend '
              'xác minh giao dịch thành công. '
              'Hết 10 phút, thời gian giữ sân '
              'không còn hiệu lực.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
