import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _key = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  bool _hidePassword = true;
  bool _hideConfirm = true;
  @override
  void dispose() {
    _name.dispose(); _email.dispose(); _password.dispose(); _confirm.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final result = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _email.text.trim(), password: _password.text,
      );
      await result.user!.updateDisplayName(_name.text.trim());
      await result.user!.sendEmailVerification();
      await result.user!.reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Đã tạo tài khoản! Kiểm tra email để xác minh tài khoản.'),
      ));
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final message = switch (e.code) {
        'email-already-in-use' => 'Email này đã được đăng ký.',
        'weak-password' => 'Mật khẩu chưa đủ mạnh.',
        'invalid-email' => 'Email không hợp lệ.',
        _ => e.message ?? 'Không thể đăng ký.',
      };
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Có lỗi khi tạo tài khoản. Vui lòng thử lại.'),
      ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F7EB),
    appBar: AppBar(title: const Text('Tạo tài khoản SPORTY')),
    body: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420),
        child: Form(key: _key, child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.sports_tennis, color: Color(0xFF1E147B), size: 56),
            const SizedBox(height: 20),
            TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Tên tài khoản', hintText: 'Ví dụ: hien281', border: OutlineInputBorder()),
              validator: (v) {
                final name = v?.trim() ?? '';
                if (name.isEmpty) return 'Vui lòng nhập tên tài khoản';
                if (!RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(name)) {
                  return 'Dùng 3–20 ký tự: chữ, số hoặc dấu _';
                }
                return null;
              }),
            const SizedBox(height: 14),
            TextFormField(controller: _email, keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
              validator: (v) => (v?.contains('@') ?? false) && (v?.contains('.') ?? false) ? null : 'Email không hợp lệ'),
            const SizedBox(height: 14),
            TextFormField(
              controller: _password, obscureText: _hidePassword,
              onChanged: (_) => _key.currentState?.validate(),
              decoration: InputDecoration(
                labelText: 'Mật khẩu', border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _hidePassword ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                  onPressed: () => setState(() => _hidePassword = !_hidePassword),
                  icon: Icon(_hidePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                ),
              ),
              validator: (v) => (v?.length ?? 0) < 8 ? 'Dùng ít nhất 8 ký tự' : null),
            const SizedBox(height: 14),
            TextFormField(
              controller: _confirm, obscureText: _hideConfirm,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              decoration: InputDecoration(
                labelText: 'Nhập lại mật khẩu', border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _hideConfirm ? 'Hiện mật khẩu' : 'Ẩn mật khẩu',
                  onPressed: () => setState(() => _hideConfirm = !_hideConfirm),
                  icon: Icon(_hideConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                ),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Vui lòng nhập lại mật khẩu';
                if (v != _password.text) return 'Mật khẩu không khớp';
                return null;
              }),
            const SizedBox(height: 24),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E147B), padding: const EdgeInsets.all(16)),
              onPressed: _loading ? null : _register,
              child: Text(_loading ? 'Đang tạo tài khoản...' : 'Đăng ký'),
            ),
          ],
        )),
      ),
    )),
  );
}
