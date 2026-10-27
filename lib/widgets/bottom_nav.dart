import 'package:flutter/material.dart';

class SportyBottomNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onTap;

  const SportyBottomNav({super.key, required this.selectedIndex, required this.onTap});

  static const _purple = Color.fromARGB(255, 52, 23, 125);
  static const _inactive = Color(0xFF85839A);

  @override
  Widget build(BuildContext context) {
    const items = [
      (icon: Icons.home_outlined, active: Icons.home_rounded, label: 'Trang chủ'),
      (icon: Icons.map_outlined, active: Icons.map_rounded, label: 'Bản đồ'),
      (icon: Icons.explore_outlined, active: Icons.explore_rounded, label: 'Khám phá'),
      (icon: Icons.calendar_month_outlined, active: Icons.calendar_month_rounded, label: 'Lịch của tôi'),
      (icon: Icons.person_outline_rounded, active: Icons.person_rounded, label: 'Tài khoản'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEAE7F1))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 9, 4, 8),
          child: Row(
            children: List.generate(items.length, (index) {
              final item = items[index];
              final active = selectedIndex == index;
              return Expanded(
                child: InkWell(
                  onTap: () => onTap(index),
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(active ? item.active : item.icon,
                          size: 23, color: active ? _purple : _inactive),
                      const SizedBox(height: 5),
                      Text(item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                            color: active ? _purple : _inactive,
                          )),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
