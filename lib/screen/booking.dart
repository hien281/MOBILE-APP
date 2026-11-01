import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'fixed_booking.dart';
import 'payment_screen.dart';

class BookingScreen extends StatefulWidget {
  final String fieldId;
  final String fieldName;
  final int price;
  final String baseUrl;
  final String accessToken;

  const BookingScreen({
    super.key,
    required this.fieldId,
    required this.fieldName,
    required this.price,
    required this.baseUrl,
    required this.accessToken,
  });

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  static const primary = Color.fromARGB(255, 54, 27, 145);
  static const double rowHeight = 60;
  static const double timeWidth = 57;
  List<String> courts = [];
  List<int> hours = [];
  String _openingTime = '';
  String _closingTime = '';

  final Set<String> _selected = {};
  final Map<String, Set<String>> _busy = {};
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  DateTime _now = DateTime.now();
  Timer? _clock;
  Timer? _availabilityTimer;
  bool _pollingAvailability = false;
  bool _loading = false;
  bool _submitting = false;
  String? _error;
  int _request = 0;
  List<Map<String, dynamic>> _membershipCards = [];
  String? _selectedMembershipId;
  bool _useMembership = false;

  Map<String, dynamic>? get _chosenMembership {
    for (final m in _membershipCards) {
      if (m['id']?.toString() == _selectedMembershipId) return m;
    }
    return null;
  }

  Future<void> _loadMembershipCards() async {
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) return;
      final response = await http.get(
        Uri.parse('${widget.baseUrl}/my-memberships'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return;
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (!mounted || data is! Map || data['memberships'] is! List) return;
      final list = (data['memberships'] as List)
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .where((m) => m['fieldId']?.toString() == widget.fieldId &&
              m['status'] == 'active' &&
              (num.tryParse(m['remainingSlots']?.toString() ?? '0') ?? 0) > 0)
          .toList();

      // Thẻ đã mua chỉ chứa membershipId; điều kiện sử dụng nằm ở gói gốc.
      // Lấy đúng dữ liệu Firestore thay vì hiển thị điều kiện giả định.
      await Future.wait(list.map((card) async {
        final packageId = card['membershipId']?.toString();
        if (packageId == null || packageId.isEmpty) return;
        try {
          final snapshot = await FirebaseFirestore.instance
              .collection('memberships').doc(packageId).get();
          final package = snapshot.data();
          if (package != null) {
            card['packageApplyTime'] = package['applyTime'];
            card['packageAllowedWeekdays'] = package['allowedWeekdays'];
          }
        } catch (error) {
          debugPrint('Không tải được điều kiện thẻ $packageId: $error');
        }
      }));
      if (!mounted) return;
      setState(() {
        _membershipCards = list;
        if (!list.any((m) => m['id']?.toString() == _selectedMembershipId)) {
          _selectedMembershipId = null;
          _useMembership = false;
        }
      });
    } catch (_) {
      // Thanh toán thường vẫn khả dụng nếu API thẻ không phản hồi.
    }
  }

  String _membershipHours(Map<String, dynamic> card) {
    final rule = (card['packageApplyTime'] ?? card['applyTime'])?.toString().trim() ?? '';
    final weekdays = card['packageAllowedWeekdays'];
    if (rule.isEmpty) return 'Chưa có thông tin giờ áp dụng';

    // applyTime thường đã bao gồm cả giờ và thứ, ví dụ:
    // "06:00 - 16:00 (Thứ 2 - Thứ 6)".
    if (RegExp(r'thứ|t2|t3|t4|t5|t6|t7|cn|chủ nhật', caseSensitive: false)
        .hasMatch(rule)) return rule;

    if (weekdays is List && weekdays.isNotEmpty) {
      final days = weekdays.map((day) {
        final number = int.tryParse(day.toString());
        if (number == 7 || number == 0) return 'CN';
        if (number != null && number >= 1 && number <= 6) {
          return 'Thứ ${number + 1}';
        }
        return null;
      }).whereType<String>().toList();
      if (days.isNotEmpty) return '$rule · ${days.join(', ')}';
    }
    return rule;
  }

  Widget _membershipOption() {
    if (_selected.isEmpty || _membershipCards.isEmpty) return const SizedBox.shrink();
    final card = _chosenMembership ?? _membershipCards.first;
    final chosen = _useMembership && _selectedMembershipId == card['id']?.toString();
    final remaining = card['remainingSlots']?.toString() ?? '0';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 5, 16, 7),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F3FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD9CDFB)),
      ),
      child: Row(children: [
        Container(width: 36, height: 36, alignment: Alignment.center,
          decoration: BoxDecoration(color: const Color(0xFFE7DEFF), borderRadius: BorderRadius.circular(9)),
          child: const Icon(Icons.card_membership_rounded, color: primary, size: 19)),
        const SizedBox(width: 9),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text((card['membershipName'] ?? 'Thẻ hội viên').toString(),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: primary)),
          const SizedBox(height: 3),
          const Text('Sử dụng 1 lượt', style: TextStyle(fontSize: 11, color: Color(0xFF77748E))),
          Text(_membershipHours(card), maxLines: 2,
            style: const TextStyle(fontSize: 11, color: Color(0xFF77748E))),
        ])),
        const SizedBox(width: 7),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFE9E1FF), borderRadius: BorderRadius.circular(18)),
            child: Text('Còn $remaining lượt', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: primary))),
          const SizedBox(height: 7),
          SizedBox(height: 30, child: OutlinedButton(
            onPressed: _submitting ? null : () async {
              if (chosen) { setState(() => _useMembership = false); return; }
              Map<String, dynamic>? picked = card;
              if (_membershipCards.length > 1) {
                picked = await showModalBottomSheet<Map<String, dynamic>>(
                  context: context, backgroundColor: Colors.white,
                  showDragHandle: true,
                  builder: (ctx) => SafeArea(child: ListView(shrinkWrap: true,
                    children: [
                      const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                        child: Text('Chọn thẻ hội viên', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                      for (final m in _membershipCards) ListTile(
                        title: Text((m['membershipName'] ?? 'Thẻ hội viên').toString(), style: const TextStyle(fontSize: 12)),
                        subtitle: Text('Còn ${m['remainingSlots']} lượt · ${_membershipHours(m)}', style: const TextStyle(fontSize: 11)),
                        onTap: () => Navigator.pop(ctx, m)),
                    ])),
                );
              }
              if (picked != null && mounted) setState(() {
                _selectedMembershipId = picked!['id']?.toString();
                _useMembership = true;
              });
            },
            style: OutlinedButton.styleFrom(
              backgroundColor: chosen ? primary : Colors.white,
              foregroundColor: chosen ? Colors.white : primary,
              side: const BorderSide(color: primary),
              padding: const EdgeInsets.symmetric(horizontal: 9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9))),
            child: Text(chosen ? 'Đã chọn' : 'Dùng thẻ', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)))),
        ]),
      ]),
    );
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _time(int h) => '${h.toString().padLeft(2, '0')}:00';
  String _money(int v) => v.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  String _key(String court, String time) => '$court|$time';
  bool get _isToday => DateUtils.isSameDay(_date, _now);
  bool _past(int h) =>
      !DateTime(_date.year, _date.month, _date.day, h).isAfter(_now);

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _load();
    _loadMembershipCards();
    _availabilityTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && !_loading && !_submitting) _refreshAvailability();
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _availabilityTimer?.cancel();
    _request++;
    super.dispose();
  }

  Future<void> _load() async {
    final id = ++_request;

    setState(() {
      _loading = true;
      _error = null;
      _selected.clear();
      _busy.clear();
    });

    try {
      final uri = Uri.parse(
        '${widget.baseUrl}/fields/${Uri.encodeComponent(widget.fieldId)}/availability',
      ).replace(queryParameters: {'date': _dateKey(_date)});

      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      final data = jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode != 200 ||
          data is! Map ||
          data['success'] != true) {
        throw Exception(
          data is Map
              ? data['message']?.toString() ?? 'Lỗi tải lịch'
              : 'Lỗi dữ liệu',
        );
      }

      if (data['courts'] is! List) {
        throw Exception('Backend chưa trả về danh sách sân.');
      }

      final nextCourts = <String>[];
      final nextHours = <int>[];
      final busy = <String, Set<String>>{};

      final courtData = data['courts'] as List;

      for (final court in courtData) {
        if (court is! Map || court['slots'] is! List) {
          throw Exception('Dữ liệu lịch sân không hợp lệ.');
        }

        final courtId = court['courtId'].toString();
        nextCourts.add(courtId);

        busy[courtId] = (court['slots'] as List)
            .where((slot) => slot['available'] != true)
            .map<String>((slot) => slot['startTime'].toString())
            .toSet();
      }

      if (courtData.isNotEmpty) {
        final slots = (courtData.first as Map)['slots'] as List;

        for (final slot in slots) {
          final startTime = slot['startTime'].toString();
          final hour = int.tryParse(startTime.split(':').first);

          if (hour == null) {
            throw Exception('Giờ đặt sân không hợp lệ.');
          }

          nextHours.add(hour);
        }
      }

      if (!mounted || id != _request) return;

      setState(() {
        courts = nextCourts;
        hours = nextHours;

        _openingTime = data['openingTime']?.toString() ?? '';
        _closingTime = data['closingTime']?.toString() ?? '';

        _busy
          ..clear()
          ..addAll(busy);
      });
    } catch (e) {
      if (!mounted || id != _request) return;

      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted && id == _request) {
        setState(() => _loading = false);
      }
    }
  }


  // Chỉ cập nhật tình trạng chỗ trống, không xóa khung giờ đang chọn.
  // Backend vẫn kiểm tra transaction khi đặt để chống 2 tài khoản đặt trùng.
  Future<void> _refreshAvailability() async {
    if (_pollingAvailability || _loading || _submitting) return;
    _pollingAvailability = true;
    final date = _dateKey(_date);
    try {
      final response = await http.get(
        Uri.parse('${widget.baseUrl}/fields/${Uri.encodeComponent(widget.fieldId)}/availability')
            .replace(queryParameters: {'date': date}),
        headers: {'Cache-Control': 'no-cache'},
      ).timeout(const Duration(seconds: 12));
      if (!mounted || date != _dateKey(_date) || response.statusCode != 200) return;
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! Map || json['success'] != true || json['courts'] is! List) return;
      final nextBusy = <String, Set<String>>{};
      for (final court in (json['courts'] as List)) {
        if (court is! Map || court['slots'] is! List) continue;
        final id = court['courtId'].toString();
        nextBusy[id] = (court['slots'] as List)
            .where((slot) => slot is Map && slot['available'] != true)
            .map<String>((slot) => slot['startTime'].toString()).toSet();
      }
      if (!mounted || date != _dateKey(_date)) return;
      setState(() {
        _busy..clear()..addAll(nextBusy);
        _selected.removeWhere((key) {
          final parts = key.split('|');
          return parts.length == 2 && (_busy[parts[0]]?.contains(parts[1]) ?? false);
        });
      });
    } catch (error) {
      // Không xóa lịch đang hiển thị khi mạng yếu.
      debugPrint('Refresh availability: $error');
    } finally {
      _pollingAvailability = false;
    }
  }

  void _changeDate(int offset) {
    final next = _date.add(Duration(days: offset));
    if (next.isBefore(DateUtils.dateOnly(DateTime.now()))) return;
    setState(() => _date = next);
    _load();
  }

  Future<void> _book() async {
    if (_useMembership && _selectedMembershipId != null) {
      await _bookWithMembership();
      return;
    }
    if (_selected.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) throw Exception('Bạn cần đăng nhập lại.');
      final selections = _selected.map((key) {
        final parts = key.split('|');
        return {
          'date': _dateKey(_date),
          'courtId': parts[0],
          'startTime': parts[1],
        };
      }).toList();
      final response = await http
          .post(
            Uri.parse('${widget.baseUrl}/bookings'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'fieldId': widget.fieldId,
              'selections': selections,
            }),
          )
          .timeout(const Duration(seconds: 30));
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (!mounted) return;
      if (response.statusCode == 201 &&
          data is Map &&
          data['success'] == true) {
        final booking = data['booking'];
        final expiresAt = DateTime.tryParse(
          (data['expiresAt'] ??
                  (booking is Map ? booking['expiresAt'] : null) ??
                  '')
              .toString(),
        );
        final bookingId = data['bookingId']?.toString();
        if (bookingId == null || bookingId.isEmpty || expiresAt == null) {
          throw Exception('Backend chưa trả về bookingId hoặc expiresAt.');
        }
        final totalPrice = booking is Map && booking['totalPrice'] is num
            ? (booking['totalPrice'] as num).toInt()
            : widget.price * selections.length;
        final selectedDetails =
            selections.map((s) => Map<String, String>.from(s)).toList()
              ..sort((a, b) {
                final byTime = a['startTime']!.compareTo(b['startTime']!);
                return byTime != 0
                    ? byTime
                    : a['courtId']!.compareTo(b['courtId']!);
              });
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PaymentScreen(
              bookingId: bookingId,
              fieldName: widget.fieldName,
              totalPrice: totalPrice,
              expiresAt: expiresAt,
              baseUrl: widget.baseUrl,
              selections: selectedDetails,
            ),
          ),
        );
        if (mounted) await _load();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            data is Map
                ? (data['message']?.toString() ?? 'Đặt thất bại')
                : 'Đặt thất bại',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }


  Future<void> _bookWithMembership() async {
    if (_submitting || _selected.isEmpty || !_useMembership || _selectedMembershipId == null) return;
    final chosen = _selected.map((key) {
      final parts = key.split('|');
      return {'date': _dateKey(_date), 'courtId': parts[0], 'startTime': parts[1]};
    }).toList();
    if (chosen.length > 3 || chosen.map((s) => s['courtId']).toSet().length != 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:
        Text('Hội viên chỉ được đặt tối đa 3 giờ liên tiếp trên cùng một sân.')));
      return;
    }
    final times = chosen.map((s) => s['startTime']!).toList()..sort();
    for (var i = 1; i < times.length; i++) {
      if (int.parse(times[i].substring(0, 2)) != int.parse(times[i - 1].substring(0, 2)) + 1) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hãy chọn các giờ liên tiếp.')));
        return;
      }
    }
    setState(() => _submitting = true);
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) throw Exception('Vui lòng đăng nhập lại.');
      final response = await http.post(
        Uri.parse('${widget.baseUrl}/membership-bookings'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode({'membershipCardId': _selectedMembershipId,
          'fieldId': widget.fieldId, 'selections': chosen}),
      ).timeout(const Duration(seconds: 30));
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 201 || data is! Map || data['success'] != true) {
        throw Exception(data is Map ? data['message'] : 'Không đặt được sân');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:
        Text('Đặt sân hội viên thành công! Còn ${data['remainingSlots']} lượt.')));
      setState(() { _useMembership = false; _selectedMembershipId = null; });
      await _loadMembershipCards();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Không thể dùng thẻ: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _schedule() {
    final todayMinutes = _now.hour * 60 + _now.minute + _now.second / 60;
    final currentY = hours.isEmpty
        ? -1.0
        : (todayMinutes - hours.first * 60) / 60 * rowHeight;
    final showNow =
        _isToday && currentY >= 0 && currentY <= hours.length * rowHeight;

    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: timeWidth, child: Text('Giờ')),
            for (var i = 0; i < courts.length; i++)
              Expanded(
                child: Center(
                  child: Text(
                    'Sân ${i + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            return SizedBox(
              height: rowHeight * hours.length + 18,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Each timestamp is a boundary. The booking cell occupies the
                  // space between this boundary and the next hour's boundary.
                  for (var i = 0; i <= hours.length; i++)
                    Positioned(
                      top: i * rowHeight,
                      left: 0,
                      width: timeWidth - 3,
                      child: Text(
                        _time(hours.isEmpty ? 0 : hours.first + i),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF54566B),
                        ),
                      ),
                    ),
                  for (var i = 0; i < hours.length; i++)
                    Positioned(
                      top: i * rowHeight + 13,
                      left: timeWidth,
                      right: 0,
                      height: rowHeight - 6,
                      child: Row(
                        children: [
                          for (final court in courts)
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                child: Builder(
                                  builder: (context) {
                                    final time = _time(hours[i]);
                                    final key = _key(court, time);
                                    final booked =
                                        _busy[court]?.contains(time) ?? false;
                                    final disabled = booked || _past(hours[i]);
                                    final selected = _selected.contains(key);
                                    return Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(9),
                                        onTap: disabled
                                            ? null
                                            : () => setState(() {
                                                if (selected) {
                                                  _selected.remove(key);
                                                } else {
                                                  _selected.add(key);
                                                }
                                              }),
                                        child: Container(
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: disabled
                                                ? Colors.grey.shade200
                                                : selected
                                                ? const Color(0xFFE5E0FF)
                                                : const Color(0xFFF7F8FC),
                                            borderRadius: BorderRadius.circular(
                                              9,
                                            ),
                                            border: Border.all(
                                              color: selected
                                                  ? primary
                                                  : Colors.grey.shade300,
                                              width: selected ? 2 : 1,
                                            ),
                                          ),
                                          child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [Text(
                                            booked
                                                ? 'Hết chỗ'
                                                : _past(hours[i])
                                                ? 'Đã qua'
                                                : '${_money(widget.price)}đ',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: disabled
                                                  ? Colors.grey
                                                  : primary,
                                            ),
                                          ),
                                          if (selected) const Padding(padding: EdgeInsets.only(top: 3), child: CircleAvatar(radius: 9, backgroundColor: primary, child: Icon(Icons.check_rounded, color: Colors.white, size: 12))),
                                          ]),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  if (showNow)
                    Positioned(
                      top: currentY,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: Row(
                          children: [
                            SizedBox(
                              width: timeWidth - 7,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDC4665),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: Color(0xFFDC4665),
                                shape: BoxShape.circle,
                              ),
                            ),
                            Expanded(
                              child: Container(
                                height: 1.5,
                                color: const Color(0xFFDC4665),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _summary() {
    final selections = _selected.toList()
      ..sort((a, b) {
        final pa = a.split('|');
        final pb = b.split('|');
        final byTime = pa[1].compareTo(pb[1]);
        return byTime != 0 ? byTime : pa[0].compareTo(pb[0]);
      });
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_selected.length} khung giờ đã chọn',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  _useMembership && _selectedMembershipId != null ? '0đ' : '${_money(_selected.length * widget.price)}đ',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: primary,
                  ),
                ),
              ],
            ),
            if (selections.isNotEmpty) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Ngày ${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 110),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: selections.length,
                  itemBuilder: (context, index) {
                    final parts = selections[index].split('|');
                    final courtNumber = courts.indexOf(parts[0]) + 1;
                    final startHour = int.parse(parts[1].substring(0, 2));
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Sân $courtNumber · ${_time(startHour)}–${_time(startHour + 1)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Text(
                            '${_money(widget.price)}đ',
                            style: const TextStyle(fontSize: 12),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => setState(
                              () => _selected.remove(selections[index]),
                            ),
                            child: const Icon(Icons.close, size: 17),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(fixedSize: const Size.fromHeight(45), minimumSize: const Size.fromHeight(45), padding: EdgeInsets.zero, textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    onPressed: () async {
                      if (_selected.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Hãy chọn sân và khung giờ trước khi đặt cố định.',
                            ),
                          ),
                        );
                        return;
                      }
                      final selectedHours = <String, Set<int>>{};
                      for (final key in _selected) {
                        final parts = key.split('|');
                        selectedHours
                            .putIfAbsent(parts[0], () => <int>{})
                            .add(int.parse(parts[1].split(':').first));
                      }
                      final allHours = selectedHours.values
                          .expand((s) => s)
                          .toSet();
                      final minHour = allHours.reduce((a, b) => a < b ? a : b);
                      final maxHour = allHours.reduce((a, b) => a > b ? a : b);
                      final contiguous = selectedHours.values.every(
                        (hours) =>
                            hours.length == maxHour - minHour + 1 &&
                            List.generate(
                              maxHour - minHour + 1,
                              (i) => minHour + i,
                            ).every(hours.contains),
                      );
                      if (!contiguous) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Đặt cố định cần cùng một dải giờ liên tục trên các sân. Hãy chọn lại các khung giờ liền nhau.',
                            ),
                          ),
                        );
                        return;
                      }
                      final initialSelections = _selected.map((key) {
                        final parts = key.split('|');
                        return <String, String>{
                          'date': _dateKey(_date),
                          'courtId': parts[0],
                          'startTime': parts[1],
                        };
                      }).toList();
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FixedBookingScreen(
                            fieldId: widget.fieldId,
                            fieldName: widget.fieldName,
                            price: widget.price,
                            baseUrl: widget.baseUrl,
                            initialDate: _date,
                            initialSelections: initialSelections,
                          ),
                        ),
                      );
                      if (mounted) await _load();
                    },
                    child: const Text('Đặt cố định'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: primary, fixedSize: const Size.fromHeight(45), minimumSize: const Size.fromHeight(45), padding: EdgeInsets.zero, textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    onPressed: _selected.isNotEmpty && !_submitting
                        ? () {
                            if (_useMembership && _selectedMembershipId != null) {
                              _bookWithMembership();
                            } else {
                              _book();
                            }
                          }
                        : null,
                    child: Text(_submitting ? 'Đang đặt...' : 'Tiếp tục'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: const Color(0xFFF9F8F2),
        toolbarHeight: 48,
        iconTheme: const IconThemeData(color: primary, size: 20),
        leading: IconButton(tooltip: 'Quay lại', icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF55278D), size: 20), onPressed: () => Navigator.maybePop(context)),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Đặt sân',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: primary),
        ),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFE9DEFF), Color(0xFFF3F0F5), Color(0xFFF8F6EA)], stops: [0, 0.55, 1])),
        child: Theme(data: Theme.of(context).copyWith(cardTheme: CardThemeData(elevation: 0, color: Colors.white.withValues(alpha: 0.50), surfaceTintColor: Colors.transparent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: primary.withValues(alpha: 0.4), width: 0.7)))), child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.fieldName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${_money(widget.price)}đ / giờ',
                          style: const TextStyle(color: primary),
                        ),
                        if (_openingTime.isNotEmpty && _closingTime.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Giờ hoạt động: $_openingTime – $_closingTime · ${courts.length} sân',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            IconButton(
                              onPressed:
                                  _date.isAfter(
                                    DateUtils.dateOnly(DateTime.now()),
                                  )
                                  ? () => _changeDate(-1)
                                  : null,
                              icon: const Icon(Icons.chevron_left),
                            ),
                            Expanded(
                              child: Center(
                                child: Text(
                                  '${_date.day}/${_date.month}/${_date.year}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => _changeDate(1),
                              icon: const Icon(Icons.chevron_right),
                            ),
                          ],
                        ),
                        if (_loading) const LinearProgressIndicator(),
                        if (_error != null)
                          Column(
                            children: [
                              Text(
                                _error!,
                                style: const TextStyle(color: Colors.red),
                              ),
                              TextButton(
                                onPressed: _load,
                                child: const Text('Thử lại'),
                              ),
                            ],
                          ),
                        if (!_loading && _error == null) _schedule(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
           _membershipOption(),
          _summary(),
        ],
      )),
            ),
    );
  }
}
