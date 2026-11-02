import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';

/// One avatar rule for Home, Account and Edit Profile.
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

  static final Map<String, Future<String?>> _facebookPictures = {};

  Future<String?> _facebookPicture(String uid) =>
      _facebookPictures.putIfAbsent(uid, () async {
        try {
          final accessToken = await FacebookAuth.instance.accessToken;
          if (accessToken == null) return null;
          final data = await FacebookAuth.instance.getUserData(
            fields: 'id,picture.width(240).height(240)',
          );
          final picture = data['picture'];
          if (picture is! Map) return null;
          final detail = picture['data'];
          if (detail is! Map || detail['is_silhouette'] == true) return null;
          final url = detail['url']?.toString().trim() ?? '';
          return url.startsWith('https://') ? url : null;
        } catch (_) {
          return null;
        }
      });

  String? get _googlePhoto {
    for (final provider in user?.providerData ?? const <UserInfo>[]) {
      if (provider.providerId != 'google.com') continue;
      final url = provider.photoURL?.trim() ?? '';
      if (url.startsWith('https://')) return url;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final name = displayName.trim();
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : 'S';
    final fallback = Center(
      child: Text(initial, style: TextStyle(
        fontSize: radius * .8,
        fontWeight: FontWeight.w700,
        color: foregroundColor,
      )),
    );
    final facebook = user?.providerData.any((p) => p.providerId == 'facebook.com') ?? false;

    Widget imageOrInitial(String? url) => url == null
        ? fallback
        : Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => fallback,
          );

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: ClipOval(
        child: SizedBox(
          width: radius * 2,
          height: radius * 2,
          child: facebook && user != null
              ? FutureBuilder<String?>(
                  future: _facebookPicture(user!.uid),
                  builder: (_, snapshot) => imageOrInitial(snapshot.data),
                )
              : imageOrInitial(_googlePhoto),
        ),
      ),
    );
  }
}
