import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// A social provider's picture is preferred; email/password users use initials.
class SportyProfileAvatar extends StatelessWidget {
  const SportyProfileAvatar({
    super.key,
    required this.user,
    required this.displayName,
    required this.radius,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final User? user;
  final String displayName;
  final double radius;
  final Color backgroundColor;
  final Color foregroundColor;

  String? get _socialPhoto {
    final providers = user?.providerData ?? const <UserInfo>[];
    for (final providerId in ['facebook.com', 'google.com']) {
      for (final provider in providers) {
        if (provider.providerId != providerId) continue;
        final url = provider.photoURL?.trim() ?? '';
        if (url.startsWith('https://')) return url;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final name = displayName.trim();
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : 'S';
    final fallback = Center(child: Text(
      initial,
      style: TextStyle(fontWeight: FontWeight.w700, fontSize: radius * .8, color: foregroundColor),
    ));
    final url = _socialPhoto;
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: ClipOval(
        child: SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: url == null
              ? fallback
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => fallback,
                ),
        ),
      ),
    );
  }
}
