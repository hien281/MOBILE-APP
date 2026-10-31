import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  static const Color primary = Color(0xFF1E147B);
  static const Color background = Color(0xFFF6F7EB);

  final _formKey = GlobalKey<FormState>();
  final _oldPassController = TextEditingController();
  final _newPassController = TextEditingController();
  final _confirmPassController = TextEditingController();

  bool _obscureOld = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _loading = false;

  @override
  void dispose() {
    _oldPassController.dispose();
    _newPassController.dispose();
    _confirmPassController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;

    setState(() => _loading = true);

    try {
      // Re-authenticate
      final cred = EmailAuthProvider.credential(
        email: user.email!,
        password: _oldPassController.text.trim(),
      );
      await user.reauthenticateWithCredential(cred);

      // Update password
      await user.updatePassword(_newPassController.text.trim());

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đổi mật khẩu thành công!'),
          backgroundColor: primary,
        ),
      );
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      String msg = 'Không thể đổi mật khẩu.';
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        msg = 'Mật khẩu hiện tại không chính xác.';
      } else if (e.code == 'weak-password') {
        msg = 'Mật khẩu mới quá yếu (ít nhất 6 ký tự).';
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: primary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Đổi mật khẩu',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primary),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFDFDCF9)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bảo mật tài khoản',
                      style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: primary),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tạo mật khẩu an toàn có ít nhất 6 ký tự để bảo vệ tài khoản của bạn',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF77748E)),
                    ),
                    const SizedBox(height: 16),

                    // Mật khẩu hiện tại
                    _buildLabel('Mật khẩu hiện tại *'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _oldPassController,
                      obscureText: _obscureOld,
                      decoration: _inputDeco('Nhập mật khẩu hiện tại').copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(_obscureOld ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: Colors.grey),
                          onPressed: () => setState(() => _obscureOld = !_obscureOld),
                        ),
                      ),
                      validator: (v) => v == null || v.isEmpty ? 'Vui lòng nhập mật khẩu hiện tại' : null,
                    ),
                    const SizedBox(height: 14),

                    // Mật khẩu mới
                    _buildLabel('Mật khẩu mới *'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _newPassController,
                      obscureText: _obscureNew,
                      decoration: _inputDeco('Nhập mật khẩu mới').copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(_obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: Colors.grey),
                          onPressed: () => setState(() => _obscureNew = !_obscureNew),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Vui lòng nhập mật khẩu mới';
                        if (v.length < 6) return 'Mật khẩu phải có ít nhất 6 ký tự';
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),

                    // Nhập lại mật khẩu mới
                    _buildLabel('Nhập lại mật khẩu mới *'),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _confirmPassController,
                      obscureText: _obscureConfirm,
                      decoration: _inputDeco('Xác nhận lại mật khẩu mới').copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: Colors.grey),
                          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Vui lòng xác nhận mật khẩu mới';
                        if (v != _newPassController.text) return 'Mật khẩu xác nhận không khớp';
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _loading ? null : _changePassword,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _loading
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Cập nhật mật khẩu', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF333333)),
    );
  }

  InputDecoration _inputDeco(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFA09EB0)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      filled: true,
      fillColor: const Color(0xFFF9FAFD),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E4F0))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE2E4F0))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: primary, width: 1.5)),
    );
  }
}
