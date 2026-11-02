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
import 'field_detail.dart';
import 'help_center_screen.dart';
import 'home.dart';
import 'login.dart';
import 'notifications_screen.dart';
import '../notification_badge_service.dart';
import '../widgets/sporty_profile_avatar.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, this.isActive = true});
  final bool isActive;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  static const Color primary = Color(0xFF1E147B);
  static const Color mauve = Color(0xFFC86FC9);
  static const Color lavender = Color(0xFFDFDCF9);
  static const Color ivory = Color(0xFFF6F7EB);
  static const Color background = Color(0xFFF6F7EB);

  Timer? _poller;
  bool _refreshing = false;
  bool loading = true;
  String? error;
  List<dynamic> cards = [];
  Map<String, dynamic>? userProfile;
  int _membershipTab = 0; // 0: Đang hoạt động, 1: Đã huỷ / Hết hạn
  final PageController _pageController = PageController(viewportFraction: 0.94);
  int _cardPageIndex = 0;
  final Map<String, Map<String, dynamic>> _membershipDetailsCache = {};
  final Map<String, SportsField> _fieldCache = {};

  @override
  void initState() {
    super.initState();
    refresh();
    _loadUserProfile();
    _startPolling();
    SportyNotificationBadge.instance.start();
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
    _pageController.dispose();
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
      if (mounted) {
        final list = data['memberships'] as List? ?? [];
        setState(() => cards = list);
        _preloadCardsMetadata(list);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      _refreshing = false;
      if (mounted && !silent) setState(() => loading = false);
    }
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String content,
    required String confirmText,
    Color titleColor = primary,
    Color confirmColor = primary,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        elevation: 6,
        insetPadding: const EdgeInsets.symmetric(horizontal: 36),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: titleColor,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      onTap: () => Navigator.pop(ctx, false),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF0F1F8),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 15,
                          color: Color(0xFF77748E),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Nội dung bên trong
              Text(
                content,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF555566),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),

              // 1 nút action
              SizedBox(
                width: double.infinity,
                height: 40,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: confirmColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(
                    confirmText,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _cancelMembership(Map raw) async {
    final cardId = raw['id']?.toString() ?? '';
    final name = cardName(raw);
    final remaining = raw['remainingSlots'] ?? 0;
    final total = raw['totalSlots'] ?? 0;
    final refundPct = total > 0 ? ((remaining / total) * 100).round() : 0;

    final confirm = await _showConfirmDialog(
      title: 'Huỷ thẻ hội viên',
      content: 'Bạn có chắc chắn muốn huỷ gói "$name"?',
      confirmText: 'Xác nhận huỷ',
      titleColor: primary,
      confirmColor: Colors.redAccent,
    );

    if (confirm != true) return;

    try {
      final token = await FirebaseAuth.instance.currentUser?.getIdToken();
      if (token == null) throw Exception('Vui lòng đăng nhập lại.');

      bool updated = false;
      try {
        final res = await http.post(
          Uri.parse('${ApiClient.baseUrl}/my-memberships/$cardId/cancel'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ).timeout(const Duration(seconds: 4));

        final bodyStr = utf8.decode(res.bodyBytes).trim();
        if (res.statusCode == 200 && !bodyStr.startsWith('<')) {
          final data = jsonDecode(bodyStr);
          if (data is Map && data['success'] == true) {
            updated = true;
          }
        }
      } catch (_) {
      }

      if (!updated) {
        await FirebaseFirestore.instance.collection('user_memberships').doc(cardId).update({
          'status': 'cancelled',
          'cancelledAt': DateTime.now().toIso8601String(),
          'cancellationReason': 'user_requested',
          'refundStatus': 'succeeded',
          'refundPercent': refundPct,
        });
      }

      if (mounted) {
        setState(() {
          final idx = cards.indexWhere((c) => c is Map && c['id']?.toString() == cardId);
          if (idx != -1) {
            final updatedMap = Map<String, dynamic>.from(cards[idx] as Map);
            updatedMap['status'] = 'cancelled';
            updatedMap['refundPercent'] = refundPct;
            cards[idx] = updatedMap;
          }
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã huỷ gói thẻ thành công! Ước tính hoàn $refundPct% số tiền.'),
          backgroundColor: primary,
        ),
      );
      refresh(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: ${e.toString().replaceFirst("Exception: ", "")}'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteAccount() async {
    final confirm = await _showConfirmDialog(
      title: 'Xoá tài khoản',
      content: 'Hành động này sẽ xoá vĩnh viễn tài khoản và toàn bộ lịch sử đặt sân của bạn. Bạn không thể hoàn tác.',
      confirmText: 'Xoá vĩnh viễn',
      titleColor: Colors.redAccent,
      confirmColor: Colors.redAccent,
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

    // Phân loại thẻ
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
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: primary),
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
                    SportyProfileAvatar(
                      user: user,
                      displayName: displayName.toString(),
                      radius: 28,
                      backgroundColor: Colors.white,
                      foregroundColor: primary,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TÀI KHOẢN CỦA BẠN',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFFDFDCF9), letterSpacing: 0.8),
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
                            style: const TextStyle(fontSize: 10, color: Color(0xFFDFDCF9)),
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
              const Text(
                'Thẻ hội viên của tôi',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: primary),
              ),
              const SizedBox(height: 10),

              // 2 Tab chuyển đổi
              Row(
                children: [
                  Expanded(
                    child: _buildTabPill(
                      title: 'Đang hoạt động (${activeCards.length})',
                      isSelected: _membershipTab == 0,
                      onTap: () {
                        if (_membershipTab != 0) {
                          setState(() {
                            _membershipTab = 0;
                            _cardPageIndex = 0;
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildTabPill(
                      title: 'Đã huỷ / Hết hạn (${inactiveCards.length})',
                      isSelected: _membershipTab == 1,
                      onTap: () {
                        if (_membershipTab != 1) {
                          setState(() {
                            _membershipTab = 1;
                            _cardPageIndex = 0;
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              if (loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(color: primary, strokeWidth: 2),
                  ),
                ),
              if (error != null)
                Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),

              if (!loading) ...[
                Builder(
                  builder: (_) {
                    final displayCards = (_membershipTab == 0 ? activeCards : inactiveCards)
                        .whereType<Map>()
                        .toList();

                    if (displayCards.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                        decoration: BoxDecoration(
                          color: ivory,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: lavender),
                        ),
                        child: Center(
                          child: Text(
                            _membershipTab == 0
                                ? 'Bạn chưa có thẻ hội viên nào đang hoạt động.'
                                : 'Chưa có thẻ hội viên nào đã huỷ hoặc hết hạn.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11, color: Color(0xFF77748E)),
                          ),
                        ),
                      );
                    }

                    if (displayCards.length == 1) {
                      return SizedBox(
                        height: 172,
                        child: _buildMembershipCard(displayCards.first, isActive: _membershipTab == 0),
                      );
                    }

                    return Column(
                      children: [
                        SizedBox(
                          height: 172,
                          child: PageView.builder(
                            controller: _pageController,
                            itemCount: displayCards.length,
                            onPageChanged: (i) => setState(() => _cardPageIndex = i),
                            itemBuilder: (ctx, i) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: _buildMembershipCard(displayCards[i], isActive: _membershipTab == 0),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(displayCards.length, (i) {
                            final isCur = i == _cardPageIndex;
                            return AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 2.5),
                              width: isCur ? 14 : 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: isCur ? primary : lavender,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            );
                          }),
                        ),
                      ],
                    );
                  },
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
                      title: 'Sân yêu thích',
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

                    // Thông báo
                    _buildMenuTile(
                      icon: Icons.notifications_none_rounded,
                      title: 'Thông báo',
                      notificationBadge: true,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const NotificationsScreen(),
                          ),
                        );
                        SportyNotificationBadge.instance.refresh();
                      },
                    ),
                    const Divider(height: 1, indent: 54, color: Color(0xFFF0F1F8)),

                    // Thông tin cơ bản
                    _buildMenuTile(
                      icon: Icons.person_outline_rounded,
                      title: 'Thông tin tài khoản',
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

              // Section Xoá tài khoản & Đăng xuất
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
                      title: const Text('Đăng xuất', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primary)),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Color(0xFFA09EB0)),
                      onTap: () async {
                        final confirm = await _showConfirmDialog(
                          title: 'Đăng xuất',
                          content: 'Bạn có chắc chắn muốn đăng xuất khỏi tài khoản này?',
                          confirmText: 'Đăng xuất',
                          titleColor: primary,
                          confirmColor: primary,
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
                      title: const Text('Xoá tài khoản', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.redAccent)),
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
    final fieldId = raw['fieldId']?.toString();
    final memId = raw['membershipId']?.toString();
    final packageInfo = memId != null ? _membershipDetailsCache[memId] : null;
    final fieldInfo = fieldId != null ? _fieldCache[fieldId] : null;
    final fieldName = raw['fieldName'] ?? fieldInfo?.name ?? packageInfo?['venue'] ?? packageInfo?['fieldName'] ?? 'Sân áp dụng';
    final applyTime = raw['applyTime'] ?? packageInfo?['applyTime'] ?? '06:00 - 22:00';
    final countdown = _countdownLabel(raw['expiresAt']);
    final activatedDate = _formatDate(raw['activatedAt'] ?? raw['createdAt']);
    final expiresDate = _formatDate(raw['expiresAt']);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showMembershipSheet(raw, isActive: isActive),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: lavender, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: primary.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 1. Tên gói thẻ
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: primary,
                ),
              ),

              // 2. Tên sân
              Text(
                fieldName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: mauve,
                ),
              ),

              // 3. Giờ áp dụng
              Text(
                'Giờ áp dụng: $applyTime',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF555566),
                ),
              ),

              // 4. Ngày đăng ký
              Text(
                activatedDate.isNotEmpty ? 'Ngày đăng ký: $activatedDate' : 'Ngày đăng ký: -',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF77748E),
                ),
              ),

              // 5. Ngày hết hạn
              Text(
                expiresDate.isNotEmpty ? 'Ngày hết hạn: $expiresDate' : 'Ngày hết hạn: -',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF77748E),
                ),
              ),

              // 6. Số lượt còn lại & Tag đếm ngược
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Số lượt còn lại: $remaining / $total lượt',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: primary,
                    ),
                  ),
                  if (isActive && countdown.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: lavender,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        countdown,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: primary,
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

  void _preloadCardsMetadata(List list) {
    for (final raw in list) {
      if (raw is Map) {
        final memId = raw['membershipId']?.toString();
        final fieldId = raw['fieldId']?.toString();
        if (memId != null && memId.isNotEmpty && !_membershipDetailsCache.containsKey(memId)) {
          _fetchMembershipDetail(memId);
        }
        if (fieldId != null && fieldId.isNotEmpty && !_fieldCache.containsKey(fieldId)) {
          _fetchFieldDetail(fieldId);
        }
      }
    }
  }

  Future<void> _fetchMembershipDetail(String memId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('memberships').doc(memId).get();
      if (doc.exists && doc.data() != null && mounted) {
        setState(() => _membershipDetailsCache[memId] = doc.data()!);
      }
    } catch (_) {}
  }

  Future<void> _fetchFieldDetail(String fieldId) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('fields').doc(fieldId).get();
      if (doc.exists && doc.data() != null && mounted) {
        setState(() => _fieldCache[fieldId] = SportsField.fromJson({'id': doc.id, ...doc.data()!}));
      }
    } catch (_) {}
  }

  String _formatDate(dynamic d) {
    if (d == null) return '';
    try {
      final dt = DateTime.parse(d.toString());
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return d.toString().split('T').first;
    }
  }

  String _countdownLabel(dynamic expiresAt) {
    if (expiresAt == null) return '';
    try {
      final dt = DateTime.parse(expiresAt.toString());
      final now = DateTime.now();
      final diff = dt.difference(now).inDays;
      if (diff > 0) return 'Còn $diff ngày';
      if (diff == 0) return 'Hết hạn hôm nay';
      return 'Đã hết hạn';
    } catch (_) {
      return '';
    }
  }

  Future<void> _navigateToField(String? fieldId) async {
    if (fieldId == null || fieldId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không tìm thấy thông tin sân của gói này.')),
      );
      return;
    }
    SportsField? field = _fieldCache[fieldId];
    if (field == null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('fields').doc(fieldId).get();
        if (doc.exists && doc.data() != null) {
          field = SportsField.fromJson({'id': doc.id, ...doc.data()!});
          _fieldCache[fieldId] = field;
        }
      } catch (_) {}
    }

    if (field != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FieldDetailScreen(
            field: field!,
            accessToken: '',
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể tải thông tin sân lúc này.')),
      );
    }
  }

  void _showMembershipSheet(Map raw, {required bool isActive}) {
    final name = cardName(raw);
    final fieldId = raw['fieldId']?.toString();
    final memId = raw['membershipId']?.toString();
    final packageInfo = memId != null ? _membershipDetailsCache[memId] : null;
    final fieldInfo = fieldId != null ? _fieldCache[fieldId] : null;
    final fieldName = raw['fieldName'] ?? fieldInfo?.name ?? packageInfo?['venue'] ?? packageInfo?['fieldName'] ?? 'Sân thể thao';
    final applyTime = raw['applyTime'] ?? packageInfo?['applyTime'] ?? '';

    final description = packageInfo?['description']?.toString() ?? '';
    final policy = packageInfo?['policy']?.toString() ?? '';
    final benefits = packageInfo?['benefits']?.toString() ?? '';

    final modalHeight = MediaQuery.of(context).size.height * 0.65;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: Container(
          height: modalHeight,
          color: const Color(0xFFF4F5F0),
          child: Column(
            children: [
              // Thanh kéo drag handle
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(top: 10, bottom: 8),
                color: Colors.white,
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD0D0DC),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),

              // Header Modal
              Container(
                width: double.infinity,
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: primary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      fieldName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: mauve),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFDFDCF9)),

              // Nội dung hộp
              Expanded(
                child: Container(
                  color: ivory,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    children: [
                      if (applyTime.isNotEmpty) ...[
                        _buildDetailSection('Khung giờ áp dụng', applyTime),
                        const Divider(height: 22, color: Color(0xFFE5E3F0)),
                      ],
                      if (description.isNotEmpty) ...[
                        _buildDetailSection('Thông tin chương trình', description),
                      ],
                      if (policy.isNotEmpty) ...[
                        const Divider(height: 22, color: Color(0xFFE5E3F0)),
                        _buildDetailSection('Chính sách chương trình', policy),
                      ],
                      if (benefits.isNotEmpty) ...[
                        const Divider(height: 22, color: Color(0xFFE5E3F0)),
                        _buildDetailSection('Quyền lợi đi kèm', benefits),
                      ],
                      if (description.isEmpty && policy.isEmpty && benefits.isEmpty)
                        _buildDetailSection(
                          'Thông tin chương trình',
                          'Gói hội viên cho phép đặt sân ưu tiên theo khung giờ áp dụng, trừ trực tiếp số lượt đã mua thay vì thanh toán tiền mặt.',
                        ),
                    ],
                  ),
                ),
              ),

              // Cố định 2 nút ở đáy
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFDFDCF9))),
                ),
                child: Row(
                  children: [
                    if (isActive) ...[
                      Expanded(
                        child: SizedBox(
                          height: 42,
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _cancelMembership(raw);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: lavender,
                              foregroundColor: mauve,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text(
                              'Huỷ đăng ký',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: SizedBox(
                        height: 42,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _navigateToField(fieldId);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text(
                            'Chi tiết sân',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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
      ),
    );
  }

  Widget _buildDetailSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: primary,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          content,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF444444),
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildTabPill({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? primary : lavender,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: primary.withValues(alpha: 0.18),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF77748E),
          ),
        ),
      ),
    );
  }
  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    String? subtitle,
    bool notificationBadge = false,
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
      title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primary)),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(fontSize: 9, color: Color(0xFF77748E)))
          : null,
      trailing: notificationBadge ? ValueListenableBuilder<int>(
        valueListenable: SportyNotificationBadge.instance.unread,
        builder: (_, count, __) => Row(mainAxisSize: MainAxisSize.min, children: [
          if (count > 0) Container(
            constraints: const BoxConstraints(minWidth: 19, minHeight: 19),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Color(0xFFE53935), borderRadius: BorderRadius.all(Radius.circular(12))),
            child: Text(count > 99 ? '99+' : '$count',
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
          if (count > 0) const SizedBox(width: 10),
          const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Color(0xFFA09EB0)),
        ]),
      ) : const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: Color(0xFFA09EB0)),
    );
  }
}
