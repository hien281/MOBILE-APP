import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const Color purple = Color.fromARGB(255, 55, 22, 127);
  static const Color background = Color(0xFFFFFEFC);

  final _formKey = GlobalKey<FormState>();
  final _lastName = TextEditingController();
  final _firstName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _loading = false;
  bool _hidePassword = true;
  bool _hideConfirm = true;

  @override
  void dispose() {
    _lastName.dispose();
    _firstName.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _message(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate() || _loading) return;

    setState(() => _loading = true);

    try {
      if (kIsWeb) {
        await FirebaseAuth.instance.setPersistence(
          Persistence.LOCAL,
        );
      }

      final result =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );

      final fullName =
          '${_lastName.text.trim()} ${_firstName.text.trim()}';

      await result.user!.updateDisplayName(fullName);
      await result.user!.sendEmailVerification();
      await result.user!.reload();

      _message(
        'Đã tạo tài khoản! Hãy kiểm tra email để xác minh tài khoản.',
      );

      if (!mounted) return;

      Navigator.of(context).pop();
    } on FirebaseAuthException catch (error) {
      final message = switch (error.code) {
        'email-already-in-use' => 'Email này đã được đăng ký.',
        'weak-password' => 'Mật khẩu chưa đủ mạnh.',
        'invalid-email' => 'Email không hợp lệ.',
        'network-request-failed' => 'Không có kết nối mạng.',
        _ => error.message ?? 'Không thể tạo tài khoản.',
      };

      _message(message);
    } catch (_) {
      _message(
        'Có lỗi khi hoàn tất đăng ký. Hãy thử lại.',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _socialRegister(AuthProvider provider) async {
    if (_loading) return;

    if (!kIsWeb) {
      _message(
        'Đăng ký Google/Facebook hiện chỉ hỗ trợ trên Web.',
      );
      return;
    }

    setState(() => _loading = true);

    try {
      await FirebaseAuth.instance.setPersistence(
        Persistence.LOCAL,
      );

      await FirebaseAuth.instance.signInWithPopup(provider);

      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (error) {
      if (error.code != 'popup-closed-by-user' &&
          error.code != 'cancelled-popup-request') {
        _message(
          error.message ?? 'Không thể đăng ký bằng tài khoản này.',
        );
      }
    } catch (_) {
      _message('Không thể đăng ký. Vui lòng thử lại.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _decoration(
    String hint,
    IconData icon, {
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        fontSize: 12,
        color: Color(0xFF9A9AA8),
      ),
      prefixIcon: Icon(
        icon,
        size: 18,
        color: const Color.fromARGB(255, 53, 22, 127),
      ),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF5F5F8),
      contentPadding: const EdgeInsets.symmetric(
        vertical: 13,
        horizontal: 12,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(
          color: Color.fromARGB(255, 52, 22, 127),
          width: 1.3,
        ),
      ),
      errorMaxLines: 2,
    );
  }

  Widget _socialButton(
    String label,
    Widget icon,
    AuthProvider provider,
  ) {
    return SizedBox(
      width: double.infinity,
      height: 42,
      child: OutlinedButton.icon(
        onPressed: _loading
            ? null
            : () => _socialRegister(provider),
        icon: icon,
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF29263B),
          backgroundColor: Colors.white,
          side: const BorderSide(
            color: Color(0xFFE5E4EB),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;

    return Scaffold(
      backgroundColor: background,
      body: Stack(
        children: [
          // ẢNH NỀN BLEND
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SizedBox(
              height: height < 720 ? 210 : 250,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/images/register_bg.jpg',
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    errorBuilder: (_, __, ___) {
                      return const ColoredBox(
                        color: Color(0xFFE0D5F7),
                        child: Center(
                          child: Icon(
                            Icons.sports_basketball,
                            size: 85,
                            color: Color.fromARGB(255, 53, 22, 127),
                          ),
                        ),
                      );
                    },
                  ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x00FFFEFC),
                          Color(0x44FFFEFC),
                          Color(0xD9FFFEFC),
                          background,
                        ],
                        stops: [0, 0.36, 0.74, 1],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // FORM ĐĂNG KÝ
          SafeArea(
            child: SingleChildScrollView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.symmetric(
                horizontal: 23,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 410,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // NÚT QUAY LẠI TRONG HÌNH TRÒN
                        const SizedBox(height: 18),

                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(
                                alpha: 0.85,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: 0.06,
                                  ),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              icon: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                size: 18,
                                color: Color.fromARGB(255, 53, 22, 127),
                              ),
                            ),
                          ),
                        ),

                        // ĐẨY NỘI DUNG XUỐNG
                        SizedBox(
                          height: height < 720 ? 56 : 86,
                        ),

                        const Text(
                          'Tạo tài khoản',
                          style: TextStyle(
                            color: Color.fromARGB(255, 55, 22, 127),
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),

                        const SizedBox(height: 5),

                        const Text(
                          'Tham gia SPORTY để đặt sân dễ dàng\n'
                          'và kết nối với những người cùng đam mê.',
                          style: TextStyle(
                            color: Color(0xFF6B687D),
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),

                        const SizedBox(height: 15),

                        // HỌ VÀ TÊN
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _lastName,
                                style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF29263B),
                              ),
                                textCapitalization:
                                    TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                decoration: _decoration(
                                  'Họ',
                                  Icons.person_outline_rounded,
                                ),
                                validator: (value) {
                                  return (value?.trim().isNotEmpty ??
                                          false)
                                      ? null
                                      : 'Nhập họ';
                                },
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: TextFormField(
                                controller: _firstName,
                                style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF29263B),
                              ),
                                textCapitalization:
                                    TextCapitalization.words,
                                textInputAction: TextInputAction.next,
                                decoration: _decoration(
                                  'Tên',
                                  Icons.person_outline_rounded,
                                ),
                                validator: (value) {
                                  return (value?.trim().isNotEmpty ??
                                          false)
                                      ? null
                                      : 'Nhập tên';
                                },
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        TextFormField(
                          controller: _email,
                          style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF29263B),
                        ),
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: _decoration(
                            'Nhập email của bạn',
                            Icons.mail_outline_rounded,
                          ),
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            return RegExp(
                              r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                            ).hasMatch(email)
                                ? null
                                : 'Email không hợp lệ';
                          },
                        ),

                        const SizedBox(height: 10),

                        TextFormField(
                          controller: _password,
                          style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF29263B),
                        ),
                          obscureText: _hidePassword,
                          textInputAction: TextInputAction.next,
                          decoration: _decoration(
                            'Mật khẩu (ít nhất 8 ký tự)',
                            Icons.lock_outline_rounded,
                            suffix: IconButton(
                              onPressed: () {
                                setState(() {
                                  _hidePassword = !_hidePassword;
                                });
                              },
                              icon: Icon(
                                _hidePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 19,
                              ),
                            ),
                          ),
                          validator: (value) {
                            return (value?.length ?? 0) >= 8
                                ? null
                                : 'Mật khẩu cần ít nhất 8 ký tự';
                          },
                        ),

                        const SizedBox(height: 10),

                        TextFormField(
                          controller: _confirm,
                          style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF29263B),
                        ),
                          obscureText: _hideConfirm,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _register(),
                          decoration: _decoration(
                            'Xác nhận mật khẩu',
                            Icons.verified_user_outlined,
                            suffix: IconButton(
                              onPressed: () {
                                setState(() {
                                  _hideConfirm = !_hideConfirm;
                                });
                              },
                              icon: Icon(
                                _hideConfirm
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 19,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Vui lòng xác nhận mật khẩu';
                            }

                            if (value != _password.text) {
                              return 'Mật khẩu không khớp';
                            }

                            return null;
                          },
                        ),

                        const SizedBox(height: 15),

                        SizedBox(
                          height: 46,
                          child: FilledButton(
                            onPressed: _loading ? null : _register,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color.fromARGB(255, 52, 22, 127),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(25),
                              ),
                            ),
                            child: _loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Đăng ký',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        const Row(
                          children: [
                            Expanded(
                              child: Divider(
                                color: Color(0xFFE5E4EB),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'Hoặc',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF77758A),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Divider(
                                color: Color(0xFFE5E4EB),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        _socialButton(
                          'Đăng ký với Google',
                          const Text(
                            'G',
                            style: TextStyle(
                              color: Color(0xFF4285F4),
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          GoogleAuthProvider(),
                        ),

                        const SizedBox(height: 8),

                        _socialButton(
                          'Đăng ký với Facebook',
                          const Icon(
                            Icons.facebook,
                            color: Color(0xFF1877F2),
                            size: 22,
                          ),
                          FacebookAuthProvider(),
                        ),

                        const SizedBox(height: 7),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Đã có tài khoản?',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B687D),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              child: const Text(
                                'Đăng nhập',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: purple,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
