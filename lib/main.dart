
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'firebase_options.dart';
import 'screen/login.dart';
import 'screen/home.dart';
import 'screen/splash_screen.dart';
import 'screen/onboarding.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const SportsBookingApp());
}

class SportsBookingApp extends StatelessWidget {
  const SportsBookingApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xFF1E147B);
    const secondary = Color(0xFFC86FC9);
    const background = Color(0xFFF6F7EB);

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
        fontFamily: GoogleFonts.inter().fontFamily,
      ),

      // Mở Splash Screen trước tiên.
      home: const SplashScreen(
        nextScreen: StartupGate(),
      ),
    );
  }
}

// KIỂM TRA NGƯỜI DÙNG ĐÃ ĐĂNG NHẬP HAY CHƯA
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return const LoginScreen();
        }

        if (snapshot.data == null) {
          return const LoginScreen();
        }

        return const HomeScreen(
          accessToken: '',
        );
      },
    );
  }
}

// KIỂM TRA NGƯỜI DÙNG ĐÃ XEM ONBOARDING CHƯA
class StartupGate extends StatefulWidget {
  const StartupGate({super.key});

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  late final Future<bool> _onboardingCompleted;

  @override
  void initState() {
    super.initState();
    _onboardingCompleted = _checkOnboarding();
  }

  Future<bool> _checkOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      return prefs.getBool('sporty_onboarding_completed') ?? false;
    } catch (e) {
      debugPrint('Lỗi kiểm tra onboarding: $e');
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _onboardingCompleted,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // Đã xem Onboarding thì chuyển đến đăng nhập/trang chủ.
        if (snapshot.data == true) {
          return const AuthGate();
        }

        // Chưa xem Onboarding thì hiển thị 3 trang giới thiệu.
        return const OnboardingScreen(
          nextScreen: AuthGate(),
        );
      },
    );
  }
}
