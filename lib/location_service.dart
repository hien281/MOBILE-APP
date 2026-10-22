import 'package:geolocator/geolocator.dart';

class LocationService {
  static Future<Position> getCurrentLocation() async {
    // Kiểm tra thiết bị đã bật dịch vụ vị trí chưa
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw Exception(
        'Dịch vụ vị trí đang tắt. Vui lòng bật GPS hoặc vị trí.',
      );
    }

    // Kiểm tra quyền truy cập vị trí
    LocationPermission permission = await Geolocator.checkPermission();

    // Nếu chưa cấp quyền thì yêu cầu người dùng cấp quyền
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();

      if (permission == LocationPermission.denied) {
        throw Exception('Bạn chưa cấp quyền truy cập vị trí.');
      }
    }

    // Nếu người dùng từ chối vĩnh viễn
    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Quyền vị trí đã bị từ chối vĩnh viễn. '
        'Vui lòng cấp quyền trong phần cài đặt.',
      );
    }

    // Lấy tọa độ hiện tại
    final Position position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );

    return position;
  }
}