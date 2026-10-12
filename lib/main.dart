import 'package:flutter/material.dart';
import 'screen/login.dart';

void main() {
  runApp(const SportsBookingApp());
}

class SportsBookingApp extends StatelessWidget {
  const SportsBookingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Sports Booking',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF668D13),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}