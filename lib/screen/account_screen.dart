import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api_client.dart';
import 'change_password_screen.dart';
import 'edit_profile_screen.dart';
import 'favorite_fields_screen.dart';
import 'help_center_screen.dart';
import 'login.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, this.isActive = true});
  final bool isActive;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  static const Color primary = Color(0xFF1E147B);
  static const Color background = Color(0xFFF6F7EB);
  static const Color lavender = Color(0xFFDFDCF9);

  Timer? _poller;
  bool _refreshing = false;
  bool loading = true;
  String? error;
  List<dynamic> cards = [];
  Map<String, dynamic>? userProfile;

  @override
  void initState() {
    super.initState();
    refresh();
    _loadUserProfile();
    _startPolling();
  }

  void _startPolling() {
    _poller?.cancel();
    if (widget.isActive) {
      _poller = Timer.periodic(const Duration(seconds: 8), (_) => refresh(silent: true));
    }
  }

  @override
  void didUpdateWidget(covariant AccountScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _startPolling();
      if (widget.isActive) {
        refresh(silent: true);
        _loadUserProfile();
      }
    }
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _loadUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists && mounted) {
          setState(() => userProfile = doc.data());
        }
      } catch (_) {}
    }
  }

  Future<void> refresh({bool silent = false}) async {
    if (_refreshing || !mounted) return;
    _refreshing = true;
    if (!silent) setState(() { loading = true; error = null; });
    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) throw Exception('Vui lòng đăng nhập.');
      final response = await http.get(
        Uri.parse('${ApiClient.baseUrl}/my-memberships').replace(
          queryParameters: {'_fresh': DateTime.now().millisecondsSinceEpoch.toString()},
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Cache-Control': 'no-cache',
        },
      ).timeout(const Duration(seconds: 20));

      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200 || data is! Map || data['success'] != true) {
        throw Exception(data is Map ? (data['message'] ?? 'Không tải được thẻ hội viên.') : 'Không tải được thẻ hội viên.');
      }
      if (mounted) setState(() => cards = data['memberships'] as List? ?? []);
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      _refreshing = false;
      if (mounted && !silent) setState(() => loading = false);
    }
  }

  Future<void> _cancelMembership(Map raw) async {
    final cardId = raw['id']?.toString() ?? '';
    final name = cardName(raw);
    final remaining = raw['remainingSlots'] ?? 0;
    final total = raw['totalSlots'] ?? 0;
    final refundPct = total > 0 ? ((remaining / total) * 100).round() : 0;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Huỷ thẻ hội viên?', style: TextStyle(fontWeight: FontWeight.bold, color: primary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bạn có chắc chắn muốn huỷ gói "$name"?', style: const TextStyle(fontSize: 13.5)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: lavender.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '• Số lượt còn lại: $remaining / $total lượt\n• Tỷ lệ hoàn tiền ước tính: $refundPct%\n• Số tiền hoàn sẽ được xử lý tự động theo chính sách.',
                style: const TextStyle(fontSize: 12, height: 1.4, color: primary),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Giữ lại', style: TextStyle(color: Color(0xFF77748E))),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Xác nhận huỷ'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) throw Exception('Vui lòng đăng nhập lại.');

      final res = await http.post(
        Uri.parse('${ApiClient.baseUrl}/my-memberships/$cardId/cancel'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (res.statusCode == 200 && data['success'] == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã huỷ gói thẻ thành công! Hoàn $refundPct% số tiền còn lại.'),
            backgroundColor: primary,
          ),
        );
        refresh();
      } else {
        throw Exception(data['message'] ?? 'Không thể huỷ gói thẻ.');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: ${e.toString().replaceFirst("Exception: ", "")}'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Xoá tài khoản?', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
        content: const Text(
          'Hành động này sẽ xoá vĩnh viễn tài khoản và toàn bộ lịch sử đặt sân của bạn. Bạn không thể hoàn tác.',
          style: TextStyle(fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xoá vĩnh viễn'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
        await user.delete();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thể xoá tài khoản: $e'), backgroundColor: Colors.red),
      );
    }
  }

  String cardName(Map card) {
    for (final key in ['membershipName', 'cardName', 'name']) {
      final value = card[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && value != 'cardName') return value;
    }
    return 'Thẻ hội viên';
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = userProfile?['name'] ?? (user?.displayName?.isNotEmpty == true ? user!.displayName! : 'Tài khoản SPORTY');
    final email = userProfile?['email'] ?? (user?.email ?? 'Chưa có email');
    final initialLetter = (displayName.isNotEmpty ? displayName[0] : 'S').toUpperCase();

    // Phân loại thẻ: Đang hoạt động vs Đã huỷ / Hết hạn
    final activeCards = cards.where((c) => c is Map && c['status'] == 'active').toList();
    final inactiveCards = cards.where((c) => c is Map && c['status'] != 'active').toList();

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: RefreshIndicator(
          color: primary,
          onRefresh: () async {
            await refresh();
            await _loadUserProfile();
          },
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // Tiêu đề
              const Text(
                'Cá nhân',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: primary),
              ),
              const SizedBox(height: 12),

              // Card Banner Profile
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E147B), Color(0xFF3524B5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: primary.withValues(alpha: 0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.white,
                      child: Text(
                        initialLetter,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: primary),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TÀI KHOẢN CỦA BẠN',
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFFDFDCF9), letterSpacing: 0.8),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, color: Color(0xFFDFDCF9)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.edit_outlined, color: Colors.white, size: 16),
                      ),
                      onPressed: () async {
                        final updated = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                        );
                        if (updated == true) _loadUserProfile();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Section Thẻ hội viên của tôi
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Thẻ hội viên của tôi',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: primary),
                  ),
                  if (activeCards.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: lavender.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${activeCards.length} thẻ đang dùng',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primary),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              if (loading) const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(color: primary, strokeWidth: 2))),
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),

              if (!loading && cards.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: lavender),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.card_membership_outlined, color: Color(0xFF77748E), size: 22),
                      SizedBox(width: 10),
                      Text('Bạn chưa đăng ký thẻ hội viên nào.', style: TextStyle(fontSize: 12.5, color: Color(0xFF77748E))),
                    ],
                  ),
                ),

              // Danh sách thẻ đang hoạt động
              for (final raw in activeCards)
                if (raw is Map) _buildMembershipCard(raw, isActive: true),

              // Danh sách thẻ đã huỷ / hết hạn (thu gọn)
              if (inactiveCards.isNotEmpty) ...[
                const SizedBox(height: 6),
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      'Thẻ đã huỷ / hết hạn (${inactiveCards.length})',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF77748E)),
                    ),
                    children: [
                      for (final raw in inactiveCards)
                        if (raw is Map) _buildMembershipCard(raw, isActive: false),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 18),

              // Section Tài khoản & Hỗ trợ
              const Text(
                'Tài khoản & Tiện ích',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: primary),
              ),
              const SizedBox(height: 8),

              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: lavender),
                ),
                child: Column(
                  children: [
                    // Sân yêu thích / đã lưu
                    _buildMenuTile(
                      icon: Icons.favorite_border_rounded,
                      title: 'Sân yêu thích đã lưu',
                      subtitle: 'Xem lại các sân thể thao bạn đã thích',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const FavoriteFieldsScreen(accessToken: ''),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1, indent: 54, color: Color(0xFFF0F1F8)),

                    // Thông tin cơ bản
                    _buildMenuTile(
                      icon: Icons.person_outline_rounded,
                      title: 'Thông tin tài khoản',
                      subtitle: 'Họ tên, ngày sinh, số điện thoại & email',
                      onTap: () async {
                        final updated = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                        );
                        if (updated == true) _loadUserProfile();
                      },
                    ),
                    const Divider(height: 1, indent: 54, color: Color(0xFFF0F1F8)),

                    // Đổi mật khẩu
                    _buildMenuTile(
                      icon: Icons.lock_outline_rounded,
                      title: 'Đổi mật khẩu',
                      subtitle: 'Bảo mật tài khoản của bạn',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
                        );
                      },
                    ),
                    const Divider(height: 1, indent: 54, color: Color(0xFFF0F1F8)),

                    // Trung tâm trợ giúp
                    _buildMenuTile(
                      icon: Icons.help_outline_rounded,
                      title: 'Trung tâm trợ giúp',
                      subtitle: 'Câu hỏi thường gặp và liên hệ hỗ trợ',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const HelpCenterScreen()),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Section Hành động nguy hiểm: Xoá tài khoản & Đăng xuất
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: lavender),
                ),
                child: Column(
                  children: [
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.logout_rounded, color: primary, size: 20),
                      title: const Text('Đăng xuất', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: primary)),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Color(0xFFA09EB0)),
                      onTap: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            title: const Text('Đăng xuất?', style: TextStyle(fontWeight: FontWeight.bold, color: primary)),
                            content: const Text('Bạn có chắc chắn muốn đăng xuất khỏi tài khoản này?'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: FilledButton.styleFrom(backgroundColor: primary),
                                child: const Text('Đăng xuất'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await FirebaseAuth.instance.signOut();
                        }
                      },
                    ),
                    const Divider(height: 1, indent: 54, color: Color(0xFFF0F1F8)),
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                      title: const Text('Xoá tài khoản', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Color(0xFFA09EB0)),
                      onTap: _deleteAccount,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMembershipCard(Map raw, {required bool isActive}) {
    final name = cardName(raw);
    final remaining = raw['remainingSlots'] ?? 0;
    final total = raw['totalSlots'] ?? 0;
    final expires = raw['expiresAt']?.toString().split('T').first ?? '-';
    final progress = total > 0 ? (remaining / total).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isActive ? lavender : const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: isActive ? primary.withValues(alpha: 0.08) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.card_membership_rounded,
                    size: 18,
                    color: isActive ? primary : Colors.grey,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isActive ? primary : Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Hạn sử dụng: $expires',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF77748E)),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isActive ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isActive ? 'Đang hoạt động' : 'Đã huỷ',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: isActive ? const Color(0xFF2E7D32) : const Color(0xFFC62828),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Thanh tiến trình số lượt
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Số lượt còn lại: $remaining / $total',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: primary),
                ),
                Text(
                  '${(progress * 100).toInt()}%',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF77748E)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: lavender.withValues(alpha: 0.4),
                valueColor: AlwaysStoppedAnimation<Color>(isActive ? primary : Colors.grey),
                minHeight: 6,
              ),
            ),

            if (isActive) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _cancelMembership(raw),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.cancel_outlined, size: 14, color: Colors.redAccent),
                  label: const Text(
                    'Huỷ đăng ký thẻ',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.redAccent),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(7),
        decoration: BoxDecoration(
          color: lavender.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: primary, size: 18),
      ),
      title: Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: primary)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF77748E))),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Color(0xFFA09EB0)),
    );
  }
}
