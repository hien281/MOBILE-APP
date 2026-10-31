import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  static const Color primary = Color(0xFF1E147B);
  static const Color background = Color(0xFFF6F7EB);

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _dobController;
  late final TextEditingController _emailController;

  bool _loading = false;
  bool _fetching = true;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _nameController = TextEditingController(text: user?.displayName ?? '');
    _emailController = TextEditingController(text: user?.email ?? '');
    _phoneController = TextEditingController();
    _dobController = TextEditingController();

    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists && mounted) {
          final data = doc.data();
          if (data != null) {
            if (_nameController.text.isEmpty && data['name'] != null) {
              _nameController.text = data['name'].toString();
            }
            if (data['phone'] != null) {
              _phoneController.text = data['phone'].toString();
            }
            if (data['dob'] != null) {
              _dobController.text = data['dob'].toString();
            }
          }
        }
      } catch (e) {
        debugPrint('Error loading user data: $e');
      }
    }
    if (mounted) setState(() => _fetching = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    DateTime initial = DateTime.now().subtract(const Duration(days: 365 * 20));
    try {
      final parts = _dobController.text.split('/');
      if (parts.length == 3) {
        initial = DateTime(int.parse(parts[2]), int.parse(parts[1]), int.parse(parts[0]));
      }
    } catch (_) {}

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1930),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: primary),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final day = picked.day.toString().padLeft(2, '0');
      final month = picked.month.toString().padLeft(2, '0');
      final year = picked.year.toString();
      setState(() {
        _dobController.text = '$day/$month/$year';
      });
    }
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _loading = true);

    try {
      final newName = _nameController.text.trim();
      final newPhone = _phoneController.text.trim();
      final newDob = _dobController.text.trim();
      final newEmail = _emailController.text.trim();

      // Cập nhật Firebase Auth
      if (newName != user.displayName) {
        await user.updateDisplayName(newName);
      }

      // Nếu đổi email thì gửi xác thực/cập nhật
      bool emailVerificationSent = false;
      if (newEmail.isNotEmpty && newEmail != user.email) {
        await user.verifyBeforeUpdateEmail(newEmail);
        emailVerificationSent = true;
      }

      // Cập nhật Firestore users collection
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': newName,
        'email': newEmail,
        'phone': newPhone,
        'dob': newDob,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(emailVerificationSent
              ? 'Đã lưu thông tin! Một email xác nhận đã được gửi đến $newEmail.'
              : 'Cập nhật thông tin thành công!'),
          backgroundColor: primary,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi: ${e.toString().replaceFirst("Exception: ", "")}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final initialLetter = (user?.displayName?.isNotEmpty == true
            ? user!.displayName![0]
            : (user?.email?.isNotEmpty == true ? user!.email![0] : 'U'))
        .toUpperCase();

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
          'Thông tin tài khoản',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primary),
        ),
        centerTitle: true,
      ),
      body: _fetching
          ? const Center(child: CircularProgressIndicator(color: primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Card Avatar
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFDFDCF9)),
                      ),
                      child: Row(
                        children: [
                          Stack(
                            children: [
                              CircleAvatar(
                                radius: 32,
                                backgroundColor: const Color(0xFFDFDCF9),
                                child: Text(
                                  initialLetter,
                                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: primary),
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.camera_alt_rounded, size: 12, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  user?.displayName?.isNotEmpty == true ? user!.displayName! : 'SPORTY User',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primary),
                                ),
                                const SizedBox(height: 3),
                                const Text(
                                  'Cập nhật thông tin để đặt sân nhanh hơn',
                                  style: TextStyle(fontSize: 11.5, color: Color(0xFF77748E)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Card Fields
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
                            'Thông tin cá nhân',
                            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: primary),
                          ),
                          const SizedBox(height: 14),

                          // Họ và tên
                          _buildLabel('Họ và tên *'),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _nameController,
                            decoration: _inputDeco('Nhập họ và tên'),
                            validator: (v) => v == null || v.trim().isEmpty ? 'Vui lòng nhập họ và tên' : null,
                          ),
                          const SizedBox(height: 14),

                          // Số điện thoại
                          _buildLabel('Số điện thoại *'),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: _inputDeco('Nhập số điện thoại liên hệ'),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Vui lòng nhập số điện thoại';
                              if (!RegExp(r'^[0-9]{9,11}$').hasMatch(v.trim())) return 'Số điện thoại không hợp lệ';
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),

                          // Ngày sinh
                          _buildLabel('Ngày sinh'),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _dobController,
                            readOnly: true,
                            onTap: _selectDate,
                            decoration: _inputDeco('dd/mm/yyyy').copyWith(
                              suffixIcon: const Icon(Icons.calendar_month_outlined, color: primary, size: 20),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Email
                          _buildLabel('Email *'),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: _inputDeco('Nhập địa chỉ email'),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Vui lòng nhập email';
                              if (!v.contains('@')) return 'Email không hợp lệ';
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Nút lưu
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _saveChanges,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: _loading
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                            : const Text('Lưu thay đổi', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
