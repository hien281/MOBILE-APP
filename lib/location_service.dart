import 'dart:async';
import 'package:geolocator/geolocator.dart';

class LocationService {
  static Future<Position> getCurrentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('GPS dang tat. Hay bat Vi tri tren dien thoai.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw Exception('Ban chua cho phep Sporty truy cap vi tri.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Hay vao Cai dat > Ung dung > Sporty > Quyen > Vi tri de cho phep.');
    }

    Position? cached;
    try {
      cached = await Geolocator.getLastKnownPosition();
    } catch (_) {}

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 30),
        ),
      );
    } on TimeoutException {
      if (cached != null) return cached;
      throw Exception('Khong lay duoc GPS. Bat Vi tri chinh xac, Wi-Fi va thu o ngoai troi.');
    } catch (_) {
      if (cached != null) return cached;
      rethrow;
    }
  }
}
