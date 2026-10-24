import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

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
  static const _blue = Color(0xFF1E147B);
  static const _red = Color(0xFFE53935);
  static const double _timeWidth = 62;
  static const double _rowHeight = 76;
  static const int _daysPerPage = 3;
  static const int _startHour = 6;
  static const int _endHour = 22; // Khung cuối: 21:00–22:00

  late DateTime _today;
  late DateTime _pageStart;
  late DateTime _now;
  Timer? _clockTimer;

  // Key: yyyy-MM-dd, value: tập hợp giờ đã đặt.
  Map<String, Set<String>> _booked = {};
  DateTime? _selectedDate;
  String? _selectedTime;
  bool _loading = false;
  bool _submitting = false;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _today = _dateOnly(_now);
    _pageStart = _today;
    _loadPage();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _now = now;
        _today = _dateOnly(now);
        if (_selectedDate != null &&
            _isPast(_selectedDate!, _selectedTime ?? '00:00')) {
          _selectedDate = null;
          _selectedTime = null;
        }
      });
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _requestId++;
    super.dispose();
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _displayDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  String _time(int hour) => '${hour.toString().padLeft(2, '0')}:00';

  String _money(int value) => value.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => '.',
      );

  bool _isPast(DateTime date, String startTime) {
    final hour = int.tryParse(startTime.split(':').first) ?? 0;
    final start = DateTime(date.year, date.month, date.day, hour);
    // Không cho bắt đầu khung giờ đã qua hoặc đang diễn ra.
    return !start.isAfter(_now);
  }

  List<DateTime> get _pageDays => List.generate(
        _daysPerPage,
        (i) => _pageStart.add(Duration(days: i)),
      );

  Future<void> _loadPage() async {
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
      _booked = {};
      _selectedDate = null;
      _selectedTime = null;
    });

    try {
      final days = _pageDays;
      final responses = await Future.wait(days.map((day) async {
        final uri = Uri.parse(
          '${widget.baseUrl}/fields/${Uri.encodeComponent(widget.fieldId)}/availability',
        ).replace(queryParameters: {'date': _dateKey(day)});
        final response = await http.get(uri).timeout(const Duration(seconds: 15));
        final dynamic data = jsonDecode(utf8.decode(response.bodyBytes));
        if (response.statusCode != 200 || data is! Map || data['success'] != true) {
          throw Exception(data is Map ? (data['message'] ?? 'Không tải được lịch') : 'Phản hồi không hợp lệ');
        }
        final rawSlots = data['slots'];
        if (rawSlots is! List) throw Exception('Danh sách khung giờ không hợp lệ');
        final bookedTimes = <String>{};
        for (final slot in rawSlots) {
          if (slot is Map && slot['available'] != true) {
            bookedTimes.add(slot['startTime'].toString());
          }
        }
        return MapEntry(_dateKey(day), bookedTimes);
      }));

      if (!mounted || requestId != _requestId) return;
      setState(() => _booked = Map.fromEntries(responses));
    } catch (e) {
      if (!mounted || requestId != _requestId) return;
      setState(() => _error = 'Không tải được lịch sân: $e');
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _loading = false);
      }
    }
  }

  void _changePage(int direction) {
    final candidate = _pageStart.add(Duration(days: direction * _daysPerPage));
    if (candidate.isBefore(_today)) return;
    setState(() => _pageStart = candidate);
    _loadPage();
  }

  Future<void> _book() async {
    if (_submitting || _selectedDate == null || _selectedTime == null) return;
    if (_isPast(_selectedDate!, _selectedTime!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Khung giờ này đã qua. Hãy chọn giờ khác.')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null || token.isEmpty) {
        throw Exception('Vui lòng đăng nhập lại để đặt sân.');
      }
      final response = await http.post(
        Uri.parse('${widget.baseUrl}/bookings'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'fieldId': widget.fieldId,
          'date': _dateKey(_selectedDate!),
          'startTime': _selectedTime,
        }),
      ).timeout(const Duration(seconds: 20));
      final dynamic data = jsonDecode(utf8.decode(response.bodyBytes));
      if (!mounted) return;
      if (response.statusCode == 201 && data is Map && data['success'] == true) {
        Navigator.pop(context, true);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(data is Map ? (data['message']?.toString() ?? 'Đặt sân thất bại') : 'Đặt sân thất bại'),
      ));
      await _loadPage();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi kết nối: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showRecurringInfo() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đặt sân cố định theo tuần'),
        content: const Text(
          'Tính năng đặt cùng ngày và giờ mỗi tuần đang được phát triển. '
          'Cần bổ sung API đặt nhiều tuần bằng một Firestore transaction '
          'để tránh đặt thành công một phần.'
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Đóng')),
        ],
      ),
    );
  }

  Widget _timeLabel(int hour) {
    return SizedBox(
      width: _timeWidth,
      child: Text(
        _time(hour),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: Color(0xFF616779), fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _slotCell(DateTime date, int hour) {
    final time = _time(hour);
    final booked = _booked[_dateKey(date)]?.contains(time) ?? false;
    final past = _isPast(date, time);
    final disabled = booked || past || _loading || _error != null;
    final selected = _selectedDate == date && _selectedTime == time;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 9),
        child: Material(
          color: disabled
              ? const Color(0xFFF0F1F4)
              : selected
                  ? const Color(0xFFE8E6FF)
                  : const Color(0xFFF7F8FC),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: disabled
                ? null
                : () => setState(() {
                      if (selected) {
                        _selectedDate = null;
                        _selectedTime = null;
                      } else {
                        _selectedDate = date;
                        _selectedTime = time;
                      }
                    }),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? _blue : const Color(0xFFE5E6EC),
                  width: selected ? 2 : 1,
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selected) const Icon(Icons.check_circle, size: 15, color: _blue),
                    Text(
                      booked ? 'Hết chỗ' : past ? 'Đã qua' : '${_money(widget.price ~/ 1000)}k',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: disabled ? Colors.grey : _blue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Vẽ đường ngang ở vị trí chính xác theo phút trong khoảng giờ hiện tại.
  Widget _currentTimeLine() {
    final minutes = _now.hour * 60 + _now.minute + _now.second / 60;
    final top = (minutes - _startHour * 60) / 60 * _rowHeight;
    if (top < 0 || top > (_endHour - _startHour) * _rowHeight) {
      return const SizedBox.shrink();
    }
    final todayIndex = _pageDays.indexWhere((d) => d == _today);
    if (todayIndex == -1) return const SizedBox.shrink();

    return Positioned(
      left: 0,
      right: 0,
      top: top - 10,
      child: IgnorePointer(
        child: SizedBox(
          height: 20,
          child: Row(
            children: [
              const SizedBox(
                width: _timeWidth,
                child: Text('Bây giờ', style: TextStyle(color: _red, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              Expanded(
                child: Row(
                  children: [
                    const Icon(Icons.circle, color: _red, size: 8),
                    Expanded(child: Container(height: 2, color: _red)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalendar() {
    final days = _pageDays;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Tháng ${_pageStart.month}/${_pageStart.year}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: _pageStart.isAfter(_today) ? () => _changePage(-1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                onPressed: () => _changePage(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        Row(
          children: [
            const SizedBox(width: _timeWidth, child: Center(child: Text('Giờ', style: TextStyle(fontSize: 12)))),
            for (final date in days)
              Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: date == _today ? const Color(0xFFE8E6FF) : const Color(0xFFF2F3F8),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Column(
                    children: [
                      Text(
                        ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'][date.weekday - 1],
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      Text(_displayDate(date), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text(_error!, textAlign: TextAlign.center),
                TextButton(onPressed: _loadPage, child: const Text('Thử lại')),
              ],
            ),
          )
        else
          Stack(
            clipBehavior: Clip.none,
            children: [
              Column(
                children: [
                  for (int hour = _startHour; hour < _endHour; hour++)
                    SizedBox(
                      height: _rowHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned(
                            left: _timeWidth,
                            right: 0,
                            top: 0,
                            child: Container(height: 1, color: const Color(0xFFE6E8EE)),
                          ),
                          Positioned(
                            left: 0,
                            top: -7,
                            child: _timeLabel(hour),
                          ),
                          Positioned.fill(
                            child: Row(
                              children: [
                                const SizedBox(width: _timeWidth),
                                for (final day in days) _slotCell(day, hour),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(
                    height: 18,
                    child: Stack(
                      children: [
                        Positioned(left: 0, top: 0, child: _timeLabel(_endHour)),
                        Positioned(left: _timeWidth, right: 0, top: 7, child: Container(height: 1, color: const Color(0xFFE6E8EE))),
                      ],
                    ),
                  ),
                ],
              ),
              _currentTimeLine(),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selectedDate != null && _selectedTime != null;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: const Text('Đặt sân', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.fieldName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text('${_money(widget.price)}đ / giờ', style: const TextStyle(color: _blue, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: _buildCalendar(),
                ),
                const SizedBox(height: 8),
                const Text('Mỗi ô là một khung 1 giờ. Đường đỏ thể hiện thời gian hiện tại.',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -3))],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(hasSelection
                              ? '${_displayDate(_selectedDate!)} · ${_selectedTime!}–${_time(int.parse(_selectedTime!.substring(0, 2)) + 1)}'
                              : 'Chưa chọn khung giờ',
                              style: const TextStyle(fontSize: 13)),
                          const SizedBox(height: 4),
                          Text(hasSelection ? '1 khung giờ' : '0 khung giờ',
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Text('${_money(hasSelection ? widget.price : 0)}đ',
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: _blue)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _showRecurringInfo,
                          child: const Text('Đặt cố định'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: _blue),
                          onPressed: hasSelection && !_submitting ? _book : null,
                          child: Text(_submitting ? 'Đang đặt...' : 'Tiếp tục'),
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
    );
  }
}
