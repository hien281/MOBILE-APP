import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screen/login.dart';

void main() {
  runApp(const SportsBookingApp());
}

class SportsBookingApp extends StatelessWidget {
  const SportsBookingApp({super.key});

  @override
  Widget build(BuildContext context) {
    const Color primary = Color(0xFF1E147B);
    const Color secondary = Color(0xFFC86FC9);
    const Color background = Color(0xFFF6F7EB);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SPORTY',

      theme: ThemeData(
        useMaterial3: true,

        scaffoldBackgroundColor: background,

        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          primary: primary,
          secondary: secondary,
          surface: background,
        ),

        // Font mặc định cho toàn bộ ứng dụng: Inter
        fontFamily: GoogleFonts.inter().fontFamily,
      ),

      home: const LoginScreen(),
    );
  }
}