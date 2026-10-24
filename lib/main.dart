import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'screen/login.dart';
import 'screen/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
          seedColor: primary, primary: primary,
          secondary: secondary, surface: background,
        ),
        fontFamily: GoogleFonts.inter().fontFamily,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return snapshot.data == null
              ? const LoginScreen()
              : const HomeScreen(accessToken: '');
        },
      ),
    );
  }
}
