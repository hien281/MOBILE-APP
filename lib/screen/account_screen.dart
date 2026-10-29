import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../api_client.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool loading = true;
  String? error;
  List<dynamic> cards = [];

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() { loading = true; error = null; });
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
      if (mounted) setState(() => loading = false);
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
    return Scaffold(
      backgroundColor: const Color(0xFFFEFFF7),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              const Text('Tài khoản', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF35167F))),
              const SizedBox(height: 14),
              Card(child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(user?.displayName?.isNotEmpty == true ? user!.displayName! : 'Tài khoản SPORTY'),
                subtitle: Text(user?.email ?? 'Chưa có email'),
              )),
              const SizedBox(height: 18),
              const Text('Thẻ hội viên của tôi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (loading) const LinearProgressIndicator(),
              if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
              if (!loading && cards.isEmpty) const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Bạn chưa có thẻ hội viên.'),
              ),
              for (final raw in cards)
                if (raw is Map)
                  Card(child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(cardName(raw), style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('Còn ${raw['remainingSlots'] ?? 0} / ${raw['totalSlots'] ?? 0} lượt'),
                      Text('Hạn sử dụng: ${raw['expiresAt']?.toString().split('T').first ?? '-'}'),
                      Text('Trạng thái: ${raw['status'] ?? '-'}'),
                    ]),
                  )),
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: () async => FirebaseAuth.instance.signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Đăng xuất'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
