import 'package:flutter/material.dart';

class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  static const Color primary = Color(0xFF1E147B);
  static const Color background = Color(0xFFF6F7EB);

  @override
  Widget build(BuildContext context) {
    final faqs = [
      {
        'q': 'Làm sao để đặt sân thể thao?',
        'a': 'Bạn chỉ cần chọn sân yêu thích tại Trang chủ hoặc Bản đồ, chọn khung giờ còn trống và tiến hành thanh toán hoặc đặt lịch.'
      },
      {
        'q': 'Thẻ hội viên hoạt động như thế nào?',
        'a': 'Khi mua gói thẻ hội viên tại mục Khám phá, bạn sẽ được cấp trước số lượt đặt sân nhất định. Khi đặt sân, hệ thống sẽ trừ trực tiếp vào số lượt của thẻ thay vì trừ tiền.'
      },
      {
        'q': 'Chính sách hủy sân và hoàn tiền ra sao?',
        'a': 'Bạn có thể hủy lịch đặt trước ít nhất 24 giờ so với giờ bắt đầu để được hoàn tiền đầy đủ hoặc hoàn lại lượt đặt thẻ hội viên.'
      },
      {
        'q': 'Tôi muốn liên hệ hỗ trợ trực tiếp?',
        'a': 'Bạn có thể gọi hotline: 1900 6868 hoặc gửi email về support@sporty.vn (Hoạt động từ 8:00 - 22:00 hàng ngày).'
      },
    ];

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
          'Trung tâm trợ giúp',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primary),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFDFDCF9)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDFDCF9).withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.support_agent_rounded, color: primary, size: 28),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Chúng tôi luôn sẵn sàng hỗ trợ!', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: primary)),
                      SizedBox(height: 2),
                      Text('Hotline: 1900 6868 · support@sporty.vn', style: TextStyle(fontSize: 11.5, color: Color(0xFF77748E))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text('Câu hỏi thường gặp', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primary)),
          const SizedBox(height: 10),
          ...faqs.map((faq) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFDFDCF9)),
              ),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                shape: const Border(),
                collapsedShape: const Border(),
                title: Text(faq['q']!, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: primary)),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Text(faq['a']!, style: const TextStyle(fontSize: 12.5, color: Color(0xFF555555), height: 1.4)),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
