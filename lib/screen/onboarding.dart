import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  final Widget nextScreen;

  const OnboardingScreen({
    super.key,
    required this.nextScreen,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const Color purple = Color.fromARGB(255, 53, 22, 127);
  static const Color lavender = Color.fromARGB(255, 230, 222, 255);
  static const Color background = Color.fromARGB(255, 250, 249, 242);

  final PageController _controller = PageController();

  int _currentPage = 0;
  bool _finishing = false;

  final List<_OnboardingData> _pages = const [
    _OnboardingData(
      label: 'KHÁM PHÁ SÂN THỂ THAO',
      title: 'Tìm sân yêu thích,\nthật dễ dàng',
      description:
          'Khám phá các sân thể thao gần bạn, xem thông tin và lựa chọn địa điểm phù hợp chỉ trong vài chạm.',
      image: 'assets/images/onboarding_1.jpg',
    ),
    _OnboardingData(
      label: 'ĐẶT SÂN NHANH CHÓNG',
      title: 'Chọn giờ chơi,\nđặt sân tức thì',
      description:
          'Xem lịch trống, chọn ngày và khung giờ phù hợp. Mọi thao tác đặt sân đều đơn giản và tiện lợi.',
      image: 'assets/images/onboarding_2.jpg',
    ),
    _OnboardingData(
      label: 'SẴN SÀNG RA SÂN',
      title: 'Sẵn sàng cho\nmọi cuộc chơi',
      description:
          'Chủ động lên lịch, rủ bạn bè và tận hưởng những trận đấu đáng nhớ cùng SPORTY.',
      image: 'assets/images/onboarding_3.jpg',
    ),
  ];

  Future<void> _finish() async {
    if (_finishing) return;

    setState(() {
      _finishing = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setBool(
        'sporty_onboarding_completed',
        true,
      );
    } catch (e) {
      debugPrint('Không thể lưu trạng thái onboarding: $e');
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => widget.nextScreen,
      ),
    );
  }

  void _next() {
    if (_currentPage == _pages.length - 1) {
      _finish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isSmall = size.height < 700;

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 12),

              // HEADER: LOGO TÍM + CHỮ SPORTY
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/images/sporty_logo_purple.png',
                        width: 34,
                        height: 34,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(
                            Icons.sports_basketball_outlined,
                            color: purple,
                            size: 34,
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'sporty',
                        style: TextStyle(
                          color: purple,
                          fontSize: 27,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1.3,
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: _finishing ? null : _finish,
                    child: const Text(
                      'Bỏ qua',
                      style: TextStyle(
                        color: Color(0xFF77748A),
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),

              // NỘI DUNG 3 TRANG ONBOARDING
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (index) {
                    setState(() {
                      _currentPage = index;
                    });
                  },
                  itemBuilder: (context, index) {
                    final page = _pages[index];

                    return Column(
                      children: [
                        const Spacer(),

                        // ẢNH MINH HỌA
                        ClipRRect(
                          borderRadius: BorderRadius.circular(34),
                          child: SizedBox(
                            width: double.infinity,
                            height: isSmall
                                ? size.height * 0.33
                                : size.height * 0.39,
                            child: Image.asset(
                              page.image,
                              fit: BoxFit.cover,
                              errorBuilder: (
                                context,
                                error,
                                stackTrace,
                              ) {
                                return Container(
                                  color: lavender,
                                  child: const Center(
                                    child: Icon(
                                      Icons.image_not_supported_outlined,
                                      color: purple,
                                      size: 50,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),

                        const Spacer(),

                        // NHÃN GIỚI THIỆU
                        Text(
                          page.label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF8E73CA),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),

                        const SizedBox(height: 12),

                        // TIÊU ĐỀ
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: purple,
                            fontSize: isSmall ? 27 : 31,
                            height: 1.18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                          ),
                        ),

                        const SizedBox(height: 14),

                        // MÔ TẢ
                        Text(
                          page.description,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF777587),
                            fontSize: 14,
                            height: 1.55,
                          ),
                        ),

                        const Spacer(),
                      ],
                    );
                  },
                ),
              ),

              // DẤU CHẤM CHUYỂN TRANG
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _pages.length,
                  (index) {
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _currentPage == index ? 27 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _currentPage == index
                            ? purple
                            : lavender,
                        borderRadius: BorderRadius.circular(20),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 24),

              // NÚT TIẾP TỤC / BẮT ĐẦU
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _finishing ? null : _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: purple,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: _finishing
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _currentPage == 2
                                  ? 'Bắt đầu ngay'
                                  : 'Tiếp tục',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 20,
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// MODEL LƯU THÔNG TIN TỪNG TRANG
class _OnboardingData {
  final String label;
  final String title;
  final String description;
  final String image;

  const _OnboardingData({
    required this.label,
    required this.title,
    required this.description,
    required this.image,
  });
}
