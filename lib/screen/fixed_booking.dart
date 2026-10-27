import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'payment_screen.dart';

class FixedBookingScreen extends StatefulWidget {
  final String fieldId, fieldName, baseUrl;
  final int price;
  final DateTime initialDate;
  final List<Map<String, String>> initialSelections;
  const FixedBookingScreen({
    super.key,
    required this.fieldId,
    required this.fieldName,
    required this.price,
    required this.baseUrl,
    required this.initialDate,
    required this.initialSelections,
  });
  @override
  State<FixedBookingScreen> createState() => _FixedBookingScreenState();
}

class _FixedBookingScreenState extends State<FixedBookingScreen> {
  static const primary = Color(0xFF1E147B);
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  final Set<String> _dates = {};
  final Set<String> _courts = {};
  int _start = 18, _end = 20;

  int _openHour = 6;
  int _lastEndHour = 22;

  List<String> _availableCourts = [];
  bool _scheduleLoaded = false;
  bool _submitting = false, _checking = false;
  final Map<String, Set<String>> _busy = {};
  String? _checkError;
  int _checkId = 0;
  String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _time(int h) => '${h.toString().padLeft(2, '0')}:00';
  String _money(int v) => v.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  List<String> get _times => [for (int h = _start; h < _end; h++) _time(h)];
  int get _count => _dates.length * _courts.length * (_end - _start);
  bool get _hasConflict => _dates.any(
    (date) => _courts.any(
      (court) =>
          _times.any((time) => _busy[date]?.contains('$court|$time') ?? false),
    ),
  );
  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.initialDate.year, widget.initialDate.month);
    _dates.add(_key(widget.initialDate));
    final selections = widget.initialSelections;
    if (selections.isNotEmpty) {
      _courts.addAll(
        selections.map((s) => s['courtId'] ?? '').where((s) => s.isNotEmpty),
      );
      final hours =
          selections
              .map((s) => int.tryParse((s['startTime'] ?? '').split(':').first))
              .whereType<int>()
              .toList()
            ..sort();
      if (hours.isNotEmpty) {
        _start = hours.first;
        _end = hours.last + 1;
      }
    }
    if (_courts.isEmpty) _courts.add('court_1');
    _check();
  }

  @override
  void dispose() {
    _checkId++;
    super.dispose();
  }

  Future<void> _chooseTime() async {
    if (!_scheduleLoaded || _lastEndHour <= _openHour) {
      return;
    }

    int start = _start.clamp(_openHour, _lastEndHour - 1);
    int end = _end.clamp(_openHour + 1, _lastEndHour);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, update) => Padding(
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Chọn thời gian',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 155,
                  child: Row(
                    children: [
                      Expanded(
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(
                            initialItem: start - _openHour,
                          ),
                          itemExtent: 42,
                          onSelectedItemChanged: (i) {
                            update(() => start = _openHour + i);
                          },
                          children: [
                            for (int h = _openHour; h < _lastEndHour; h++)
                              Center(child: Text(h.toString().padLeft(2, '0'))),
                          ],
                        ),
                      ),
                      const Text(':00'),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14),
                        child: Text('Đến'),
                      ),
                      Expanded(
                        child: CupertinoPicker(
                          scrollController: FixedExtentScrollController(
                            initialItem: end - (_openHour + 1),
                          ),
                          itemExtent: 42,
                          onSelectedItemChanged: (i) {
                            update(() => end = _openHour + 1 + i);
                          },
                          children: [
                            for (int h = _openHour + 1; h <= _lastEndHour; h++)
                              Center(child: Text(h.toString().padLeft(2, '0'))),
                          ],
                        ),
                      ),
                      const Text(':00'),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child: const Text('Hủy'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: end <= start
                            ? null
                            : () {
                                setState(() {
                                  _start = start;
                                  _end = end;
                                });

                                Navigator.pop(sheetContext);
                                _check();
                              },
                        child: const Text('Xác nhận'),
                      ),
                    ),
                  ],
                ),
                if (end <= start)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      'Giờ kết thúc phải sau giờ bắt đầu.',
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _check() async {
    final id = ++_checkId;

    setState(() {
      _checking = true;
      _checkError = null;
      _busy.clear();
    });

    try {
      if (_dates.length > 60) {
        throw Exception('Vui lòng chọn tối đa 60 ngày.');
      }

      final datesToCheck = _dates.isEmpty
          ? [_key(widget.initialDate)]
          : (_dates.toList()..sort());

      final nextBusy = <String, Set<String>>{};
      List<String>? nextCourts;
      List<int>? nextHours;

      for (final date in datesToCheck) {
        final uri = Uri.parse(
          '${widget.baseUrl}/fields/${Uri.encodeComponent(widget.fieldId)}/availability',
        ).replace(queryParameters: {'date': date});

        final response = await http
            .get(uri)
            .timeout(const Duration(seconds: 15));

        final data = jsonDecode(utf8.decode(response.bodyBytes));

        if (response.statusCode != 200 ||
            data is! Map ||
            data['success'] != true ||
            data['courts'] is! List) {
          throw Exception(
            data is Map
                ? data['message']?.toString() ?? 'Lỗi tải lịch'
                : 'Lỗi tải lịch',
          );
        }

        if (!mounted || id != _checkId) return;

        final courtData = data['courts'] as List;
        final courtIds = <String>[];
        final availableHours = <int>[];
        final occupied = <String>{};

        for (final court in courtData) {
          if (court is! Map || court['slots'] is! List) {
            throw Exception('Dữ liệu sân không hợp lệ.');
          }

          final courtId = court['courtId'].toString();
          courtIds.add(courtId);

          for (final slot in court['slots'] as List) {
            final time = slot['startTime'].toString();

            if (slot['available'] != true) {
              occupied.add('$courtId|$time');
            }
          }
        }

        if (courtData.isNotEmpty) {
          final slots = (courtData.first as Map)['slots'] as List;

          for (final slot in slots) {
            final hour = int.tryParse(
              slot['startTime'].toString().split(':').first,
            );

            if (hour == null) {
              throw Exception('Khung giờ không hợp lệ.');
            }

            availableHours.add(hour);
          }
        }

        if (availableHours.isEmpty) {
          throw Exception('Cơ sở không có khung giờ đặt nguyên tiếng hợp lệ.');
        }

        nextCourts ??= courtIds;
        nextHours ??= availableHours;

        nextBusy[date] = occupied;
      }

      if (!mounted || id != _checkId) return;

      final courtIds = nextCourts!;
      final availableHours = nextHours!;

      final openHour = availableHours.first;
      final lastEndHour = availableHours.last + 1;

      setState(() {
        _availableCourts = courtIds;
        _openHour = openHour;
        _lastEndHour = lastEndHour;
        _scheduleLoaded = true;

        // Giữ lựa chọn ban đầu nếu còn hợp lệ.
        // Chỉ điều chỉnh khi giờ nằm ngoài lịch hoạt động.
        _start = _start.clamp(_openHour, _lastEndHour - 1);
        _end = _end.clamp(_start + 1, _lastEndHour);

        _courts.removeWhere((court) => !_availableCourts.contains(court));

        if (_courts.isEmpty && _availableCourts.isNotEmpty) {
          _courts.add(_availableCourts.first);
        }

        _busy
          ..clear()
          ..addAll(nextBusy);
      });
    } catch (e) {
      if (mounted && id == _checkId) {
        setState(() {
          _checkError = e.toString();
        });
      }
    } finally {
      if (mounted && id == _checkId) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_dates.isEmpty ||
        _courts.isEmpty ||
        _checking ||
        _checkError != null ||
        _hasConflict ||
        _submitting)
      return;
    if (_count > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tối đa 100 khung giờ trong một lần đặt.'),
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) throw Exception('Vui lòng đăng nhập lại.');
      final selections = [
        for (final date in _dates)
          for (final court in _courts)
            for (final time in _times)
              {'date': date, 'courtId': court, 'startTime': time},
      ];
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
          .timeout(const Duration(seconds: 40));
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (!mounted) return;
      if (response.statusCode == 201 &&
          data is Map &&
          data['success'] == true) {
        final bookingId = data['bookingId']?.toString();
        final booking = data['booking'];
        final expiresAt = DateTime.tryParse(
          (data['expiresAt'] ??
                  (booking is Map ? booking['expiresAt'] : null) ??
                  '')
              .toString(),
        );
        if (bookingId == null || bookingId.isEmpty || expiresAt == null)
          throw Exception('Backend chưa trả về bookingId hoặc expiresAt.');
        final totalPrice = booking is Map && booking['totalPrice'] is num
            ? (booking['totalPrice'] as num).toInt()
            : _count * widget.price;
        final details =
            selections.map((s) => Map<String, String>.from(s)).toList()
              ..sort((a, b) {
                final d = a['date']!.compareTo(b['date']!);
                if (d != 0) return d;
                final c = a['courtId']!.compareTo(b['courtId']!);
                return c != 0 ? c : a['startTime']!.compareTo(b['startTime']!);
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
              selections: details,
            ),
          ),
        );
        if (mounted) Navigator.pop(context, true);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            data is Map
                ? data['message']?.toString() ?? 'Đặt thất bại'
                : 'Đặt thất bại',
          ),
        ),
      );
      await _check();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _section(String title, Widget child) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final first = DateTime(_month.year, _month.month, 1);
    final offset = first.weekday % 7;
    final days = DateUtils.getDaysInMonth(_month.year, _month.month);
    final today = DateUtils.dateOnly(DateTime.now());
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Đặt cố định',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      backgroundColor: const Color(0xFFF7F8FC),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _section(
                  'Thiết lập lịch cố định',
                  const Text(
                    'Đã giữ khung giờ và sân bạn vừa chọn. Chọn thêm các ngày muốn lặp lại; chỉ đổi giờ nếu cần. Mỗi khung tính theo 1 giờ.',
                  ),
                ),
                _section(
                  '1. Chọn ngày chơi',
                  Column(
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => setState(
                              () => _month = DateTime(
                                _month.year,
                                _month.month - 1,
                              ),
                            ),
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Expanded(
                            child: Center(
                              child: Text(
                                'Tháng ${_month.month}/${_month.year}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(
                              () => _month = DateTime(
                                _month.year,
                                _month.month + 1,
                              ),
                            ),
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 7,
                              mainAxisSpacing: 3,
                              crossAxisSpacing: 3,
                            ),
                        itemCount: 7 + offset + days,
                        itemBuilder: (ctx, i) {
                          if (i < 7)
                            return Center(
                              child: Text(
                                ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'][i],
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          final day = i - 7 - offset + 1;
                          if (day < 1 || day > days)
                            return const SizedBox.shrink();
                          final d = DateTime(_month.year, _month.month, day);
                          final key = _key(d);
                          final selected = _dates.contains(key);
                          final past = d.isBefore(today);
                          final conflict =
                              selected &&
                              _courts.any(
                                (c) => _times.any(
                                  (t) => _busy[key]?.contains('$c|$t') ?? false,
                                ),
                              );
                          return InkWell(
                            onTap: past
                                ? null
                                : () {
                                    setState(() {
                                      if (selected) {
                                        _dates.remove(key);
                                      } else {
                                        _dates.add(key);
                                      }
                                    });
                                    _check();
                                  },
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: conflict
                                    ? Colors.red.shade100
                                    : selected
                                    ? const Color(0xFFE1DCFF)
                                    : null,
                                borderRadius: BorderRadius.circular(8),
                                border: selected
                                    ? Border.all(
                                        color: conflict ? Colors.red : primary,
                                      )
                                    : null,
                              ),
                              child: Text(
                                '$day',
                                style: TextStyle(
                                  color: past
                                      ? Colors.grey.shade400
                                      : conflict
                                      ? Colors.red
                                      : selected
                                      ? primary
                                      : Colors.black,
                                  fontWeight: selected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Đã chọn ${_dates.length} ngày. Chuyển tháng để chọn thêm.',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                _section(
                  '2. Chọn khung giờ',
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${_time(_start)} – ${_time(_end)}'),
                    subtitle: Text('${_end - _start} giờ / buổi'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _scheduleLoaded && !_checking && _checkError == null
                        ? _chooseTime
                        : null,
                  ),
                ),
                _section(
                  '3. Chọn sân',
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final court in _availableCourts)
                        FilterChip(
                          label: Text('Sân ${court.split('_').last}'),
                          selected: _courts.contains(court),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _courts.add(court);
                              } else {
                                _courts.remove(court);
                              }
                            });

                            _check();
                          },
                        ),
                    ],
                  ),
                ),
                if (_checking) const LinearProgressIndicator(),
                if (_checkError != null)
                  Text(
                    'Không kiểm tra được lịch: $_checkError',
                    style: const TextStyle(color: Colors.red),
                  ),
                if (_hasConflict)
                  const Text(
                    'Có ngày/giờ/sân bị trùng lịch (đánh dấu đỏ). Hãy bỏ ngày hoặc đổi giờ/sân.',
                    style: TextStyle(color: Colors.red),
                  ),
              ],
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '${_dates.length} ngày · ${_courts.length} sân · ${_end - _start} giờ/ngày',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Text(
                        '${_money(_count * widget.price)}đ',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: primary,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: primary),
                      onPressed:
                          _count > 0 &&
                              _count <= 100 &&
                              !_checking &&
                              _checkError == null &&
                              !_hasConflict &&
                              !_submitting
                          ? _submit
                          : null,
                      child: Text(_submitting ? 'Đang đặt...' : 'Tiếp tục'),
                    ),
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
