import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'register.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const Color purple = Color.fromARGB(255, 53, 22, 127);
  static const Color background = Color(0xFFFFFEFC);

  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _remember = false;
  bool _hidePassword = true;
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _errorMessage(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return 'Email không hợp lệ.';
        case 'invalid-credential':
        case 'wrong-password':
        case 'user-not-found':
          return 'Email hoặc mật khẩu không chính xác.';
        case 'too-many-requests':
          return 'Bạn đã thử quá nhiều lần. Vui lòng thử lại sau.';
        case 'network-request-failed':
          return 'Không có kết nối mạng.';
        case 'operation-not-allowed':
          return 'Phương thức đăng nhập chưa được bật trong Firebase.';
        default:
          return error.message ?? 'Đăng nhập không thành công.';
      }
    }
    return 'Có lỗi xảy ra. Vui lòng thử lại.';
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate() || _loading) return;

    setState(() => _loading = true);

    try {
      if (kIsWeb) {
        await FirebaseAuth.instance.setPersistence(
          _remember ? Persistence.LOCAL : Persistence.SESSION,
        );
      }

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
    } catch (error) {
      _message(_errorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _socialLogin(AuthProvider provider) async {
    if (_loading) return;

    if (!kIsWeb) {
      _message('Đăng nhập Google/Facebook hiện chỉ hỗ trợ trên Web.');
      return;
    }

    setState(() => _loading = true);

    try {
      await FirebaseAuth.instance.setPersistence(
        _remember ? Persistence.LOCAL : Persistence.SESSION,
      );

      await FirebaseAuth.instance.signInWithPopup(provider);
    } on FirebaseAuthException catch (error) {
      if (error.code != 'popup-closed-by-user' &&
          error.code != 'cancelled-popup-request') {
        _message(_errorMessage(error));
      }
    } catch (error) {
      _message(_errorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final controller = TextEditingController(
      text: _email.text.trim(),
    );

    final email = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Quên mật khẩu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Nhập email để nhận liên kết đặt lại mật khẩu.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(
                dialogContext,
                controller.text.trim(),
              );
            },
            child: const Text('Gửi email'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (email == null || email.isEmpty) return;

    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
      _message('Email chưa đúng định dạng.');
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: email,
      );

      _message(
        'Nếu email có tài khoản, hãy kiểm tra hộp thư để đặt lại mật khẩu.',
      );
    } catch (error) {
      _message(_errorMessage(error));
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
        color: const Color.fromARGB(255, 55, 22, 127),
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
          color: Color.fromARGB(255, 55, 22, 127),
          width: 1.3,
        ),
      ),
      errorMaxLines: 2,
    );
  }

  Widget _socialButton(
    String label,
    Widget icon,
    VoidCallback onPressed,
  ) {
    return SizedBox(
      width: double.infinity,
      height: 43,
      child: OutlinedButton.icon(
        onPressed: _loading ? null : onPressed,
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
          // ẢNH NỀN BLEND VÀO MÀU TRẮNG
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SizedBox(
              height: height < 720 ? 255 : 305,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/images/login_bg.jpg',
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    errorBuilder: (_, __, ___) {
                      return const ColoredBox(
                        color: Color(0xFFD9D1F5),
                        child: Center(
                          child: Icon(
                            Icons.sports_tennis,
                            size: 95,
                            color: purple,
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
                          Color(0x30FFFEFC),
                          Color(0xCFFFFEFC),
                          background,
                        ],
                        stops: [0, 0.37, 0.74, 1],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // FORM ĐĂNG NHẬP - ĐÃ DỊCH XUỐNG
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
                        // Không còn nút quay lại.
                        SizedBox(
                          height: height < 720 ? 165 : 198,
                        ),

                        const Text(
                          'Chào mừng trở lại!',
                          style: TextStyle(
                            color: purple,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'Đăng nhập để tiếp tục đặt sân\n'
                          'và khám phá cộng đồng thể thao.',
                          style: TextStyle(
                            color: Color(0xFF6B687D),
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),

                        const SizedBox(height: 17),

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
                                : 'Vui lòng nhập email hợp lệ';
                          },
                        ),

                        const SizedBox(height: 11),

                        TextFormField(
                          controller: _password,
                          style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF29263B),
                        ),
                          obscureText: _hidePassword,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _login(),
                          decoration: _decoration(
                            'Nhập mật khẩu',
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
                            return (value?.isNotEmpty ?? false)
                                ? null
                                : 'Vui lòng nhập mật khẩu';
                          },
                        ),

                        const SizedBox(height: 3),

                        Row(
                          children: [
                            SizedBox(
                              width: 26,
                              height: 33,
                              child: Checkbox(
                                value: _remember,
                                activeColor: purple,
                                visualDensity: VisualDensity.compact,
                                onChanged: (value) {
                                  setState(() {
                                    _remember = value ?? false;
                                  });
                                },
                              ),
                            ),
                            const Text(
                              'Ghi nhớ đăng nhập',
                              style: TextStyle(fontSize: 11),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: _forgotPassword,
                              child: const Text(
                                'Quên mật khẩu?',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: purple,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 6),

                        SizedBox(
                          height: 46,
                          child: FilledButton(
                            onPressed: _loading ? null : _login,
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color.fromARGB(255, 50, 22, 127),
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
                                    'Đăng nhập',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 13),

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

                        const SizedBox(height: 12),

                        _socialButton(
                          'Đăng nhập với Google',
                          const Text(
                            'G',
                            style: TextStyle(
                              color: Color(0xFF4285F4),
                              fontWeight: FontWeight.w900,
                              fontSize: 19,
                            ),
                          ),
                          () => _socialLogin(GoogleAuthProvider()),
                        ),

                        const SizedBox(height: 9),

                        _socialButton(
                          'Đăng nhập với Facebook',
                          const Icon(
                            Icons.facebook,
                            color: Color(0xFF1877F2),
                            size: 22,
                          ),
                          () => _socialLogin(FacebookAuthProvider()),
                        ),

                        const SizedBox(height: 12),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Chưa có tài khoản?',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B687D),
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const RegisterScreen(),
                                  ),
                                );
                              },
                              child: const Text(
                                'Đăng ký ngay',
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
