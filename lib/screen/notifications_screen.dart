import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api_client.dart';
import '../notification_badge_service.dart';
import 'my_schedule.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const Color purple = Color(0xFF1E147B);
  static const Color lavender = Color(0xFFDFDCF9);
  static const Color background = Color(0xFFF6F7EB);
  static const Color secondary = Color(0xFF77748E);
  static const Color danger = Color(0xFFD94248);

  List<Map<String, dynamic>> items = [];
  bool loading = true;
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<String> _jwt() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null || token.isEmpty) {
      throw Exception('Vui lòng đăng nhập lại.');
    }
    return token;
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
  }) async {
    final token = await _jwt();
    final url = Uri.parse('${ApiClient.baseUrl}$path');
    final headers = {
      'Authorization': 'Bearer $token',
      'Cache-Control': 'no-cache',
    };
    late final http.Response response;
    if (method == 'DELETE') {
      response = await http.delete(url, headers: headers)
          .timeout(const Duration(seconds: 25));
    } else if (method == 'POST') {
      response = await http.post(url, headers: headers)
          .timeout(const Duration(seconds: 15));
    } else {
      response = await http.get(url, headers: headers)
          .timeout(const Duration(seconds: 15));
    }

    Map<String, dynamic>? result;
    try {
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is Map) result = Map<String, dynamic>.from(json);
    } catch (_) {}
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        result?['success'] != true) {
      throw Exception(result?['message']?.toString() ??
          'Không xử lý được yêu cầu. Vui lòng thử lại.');
    }
    return result!;
  }

  void _syncBadge() {
    SportyNotificationBadge.instance.unread.value =
        items.where((item) => item['read'] != true).length;
  }

  void _toast(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? danger : purple,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
  }

  Future<void> load() async {
    if (!mounted || busy) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await _request('/notifications');
      if (data['notifications'] is! List) {
        throw Exception('Dữ liệu thông báo không hợp lệ.');
      }
      if (!mounted) return;
      setState(() {
        items = (data['notifications'] as List)
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      });
      _syncBadge();
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<bool> _confirmDelete({bool all = false}) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
            actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            title: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    color: danger,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    all ? 'Xóa tất cả thông báo?' : 'Xóa thông báo này?',
                    style: const TextStyle(
                      color: purple,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            content: Text(
              all
                  ? 'Toàn bộ thông báo trong hộp thư sẽ bị xóa. Hành động này không thể hoàn tác.'
                  : 'Thông báo sẽ bị xóa khỏi danh sách. Hành động này không thể hoàn tác.',
              style: const TextStyle(
                color: secondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                style: TextButton.styleFrom(
                  foregroundColor: purple,
                  backgroundColor: lavender,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 17, vertical: 11,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                child: const Text(
                  'Giữ lại',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: danger,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 11,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                child: Text(
                  all ? 'Xóa tất cả' : 'Xóa',
                  style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteOne(Map<String, dynamic> item) async {
    if (busy) return;
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty || !await _confirmDelete()) return;
    if (!mounted) return;
    setState(() => busy = true);
    try {
      await _request(
        '/notifications/${Uri.encodeComponent(id)}',
        method: 'DELETE',
      );
      if (!mounted) return;
      setState(() => items.removeWhere((n) => n['id']?.toString() == id));
      _syncBadge();
      _toast('Đã xóa thông báo.');
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _deleteAll() async {
    if (busy || items.isEmpty || !await _confirmDelete(all: true)) return;
    if (!mounted) return;
    setState(() => busy = true);
    try {
      await _request('/notifications', method: 'DELETE');
      if (!mounted) return;
      setState(() => items.clear());
      _syncBadge();
      _toast('Đã xóa tất cả thông báo.');
    } catch (e) {
      // The server may have partially removed a large inbox: reload truth.
      _toast(e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (mounted && items.isNotEmpty) await load();
  }

  Future<void> _markRead(Map<String, dynamic> item) async {
    if (item['read'] == true || busy) return;
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) return;
    try {
      await _request(
        '/notifications/${Uri.encodeComponent(id)}/read',
        method: 'POST',
      );
      if (!mounted) return;
      setState(() => item['read'] = true);
      _syncBadge();
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), isError: true);
    }
  }

  Future<void> _readAll() async {
    if (busy || loading) return;
    setState(() => busy = true);
    try {
      await _request('/notifications/read-all', method: 'POST');
      if (!mounted) return;
      setState(() {
        for (final item in items) {
          item['read'] = true;
        }
      });
      _syncBadge();
      _toast('Đã đánh dấu tất cả là đã đọc.');
    } catch (e) {
      _toast(e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String _dateLabel(dynamic raw) {
    final date = DateTime.tryParse(raw?.toString() ?? '')?.toLocal();
    if (date == null) return '';
    final d = '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
    return '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')} · $d';
  }

  Future<void> _openNotification(Map<String, dynamic> item) async {
    if (busy) return;
    await _markRead(item);
    if (!mounted) return;
    final bookingId = item['bookingId']?.toString();
    if (bookingId == null || bookingId.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MyScheduleScreen(
          initialBookingId: bookingId,
          initialDate: item['date']?.toString(),
          initialCourtId: item['courtId']?.toString(),
        ),
      ),
    );
  }

  Widget _toolbar() {
    final unread = items.where((item) => item['read'] != true).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                unread > 0 ? '$unread thông báo chưa đọc' : 'Tất cả đã đọc',
                style: const TextStyle(color: secondary, fontSize: 12),
              ),
              const Spacer(),
              if (busy)
                const SizedBox(
                  width: 17, height: 17,
                  child: CircularProgressIndicator(
                    strokeWidth: 2, color: purple,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: unread == 0 || busy ? null : _readAll,
                icon: const Icon(Icons.done_all_rounded, size: 17),
                label: const Text('Đánh dấu đã đọc'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: purple,
                  side: const BorderSide(color: lavender),
                  backgroundColor: Colors.white,
                  textStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : _deleteAll,
                icon: const Icon(Icons.delete_sweep_outlined, size: 17),
                label: const Text('Xóa tất cả'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: danger,
                  side: const BorderSide(color: Color(0xFFF0C9CB)),
                  backgroundColor: const Color(0xFFFFF7F7),
                  textStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _notificationCard(Map<String, dynamic> item) {
    final read = item['read'] == true;
    return Container(
      decoration: BoxDecoration(
        color: read ? Colors.white : const Color(0xFFF3EEFF),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: read ? const Color(0xFFE7E2F0) : const Color(0xFFD3C5F4),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(17),
        child: InkWell(
          onTap: busy ? null : () => _openNotification(item),
          borderRadius: BorderRadius.circular(17),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(13, 14, 8, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5DCFF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.event_available_rounded,
                    color: purple,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item['title']?.toString() ?? 'SPORTY',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: purple,
                                fontWeight: read
                                    ? FontWeight.w600
                                    : FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (!read)
                            const Padding(
                              padding: EdgeInsets.only(left: 5),
                              child: CircleAvatar(
                                radius: 4, backgroundColor: purple,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item['body']?.toString() ?? '',
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: Color(0xFF303044),
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        _dateLabel(item['createdAt']),
                        style: const TextStyle(
                          fontSize: 10, color: Color(0xFF858097),
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  enabled: !busy,
                  tooltip: 'Tùy chọn thông báo',
                  color: Colors.white,
                  surfaceTintColor: Colors.transparent,
                  elevation: 5,
                  position: PopupMenuPosition.under,
                  icon: const Icon(
                    Icons.more_vert_rounded,
                    size: 20,
                    color: secondary,
                  ),
                  onSelected: (value) {
                    if (value == 'delete') _deleteOne(item);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.delete_outline_rounded,
                            color: danger,
                            size: 19,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Xóa thông báo',
                            style: TextStyle(
                              color: danger,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        centerTitle: true,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
            color: purple,
          ),
        ),
        title: const Text(
          'Thông báo',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: purple,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: load,
        color: purple,
        child: Column(
          children: [
            if (!loading && error == null && items.isNotEmpty) _toolbar(),
            Expanded(
              child: loading
                  ? const Center(
                      child: CircularProgressIndicator(color: purple),
                    )
                  : error != null
                      ? ListView(
                          children: [
                            const SizedBox(height: 110),
                            const Icon(
                              Icons.wifi_off_rounded,
                              size: 44,
                              color: Color(0xFFAAA3C4),
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ),
                            Center(
                              child: TextButton(
                                onPressed: load,
                                child: const Text('Thử lại'),
                              ),
                            ),
                          ],
                        )
                      : items.isEmpty
                          ? ListView(
                              children: const [
                                SizedBox(height: 110),
                                Icon(
                                  Icons.notifications_off_outlined,
                                  size: 58,
                                  color: Color(0xFFB5A9DE),
                                ),
                                SizedBox(height: 16),
                                Center(
                                  child: Text(
                                    'Chưa có thông báo',
                                    style: TextStyle(
                                      color: purple,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                SizedBox(height: 8),
                                Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 36,
                                    ),
                                    child: Text(
                                      'Thông báo mới về lịch đặt sân sẽ xuất hiện tại đây.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: secondary,
                                        fontSize: 12,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(
                                16, 8, 16, 24,
                              ),
                              itemCount: items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, index) =>
                                  _notificationCard(items[index]),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
