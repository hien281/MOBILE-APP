import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/main.dart';

void main() {
  testWidgets('SportsBookingApp displays login screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SportsBookingApp());

    expect(find.text('Sporty'), findsOneWidget);
    expect(find.text('Welcome Back!'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Log In'), findsOneWidget);
  });

  testWidgets('Login form validates empty fields', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));

    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
    });

    await tester.pumpWidget(const SportsBookingApp());

    await tester.ensureVisible(find.text('Log In'));
    await tester.tap(find.text('Log In'));
    await tester.pumpAndSettle();

    expect(find.text('Vui lòng nhập email'), findsOneWidget);
    expect(find.text('Vui lòng nhập mật khẩu'), findsOneWidget);
  });
}