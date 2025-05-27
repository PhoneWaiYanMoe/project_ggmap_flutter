// lib/src/services/vietnam_weather_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class VietnamWeatherService {
  static const String _apiKey = '7387dd4f2b21472fba193420251302';
  static const String _baseUrl = 'http://api.weatherapi.com/v1';

  // Ho Chi Minh City coordinates: 10.8231, 106.6297
  static const LatLng _hcmcLocation = LatLng(10.8231, 106.6297);

  Future<Map<String, dynamic>?> getCurrentWeather({LatLng? location}) async {
    try {
      final coords = location ?? _hcmcLocation;
      final url = '$_baseUrl/current.json?key=$_apiKey&q=${coords.latitude},${coords.longitude}&aqi=yes&lang=vi';

      print('Fetching weather from: $url');
      final response = await http.get(Uri.parse(url)).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'location': {
            'name': data['location']['name'],
            'region': data['location']['region'],
            'country': data['location']['country'],
            'local_time': data['location']['localtime'],
          },
          'current': {
            'temp_c': data['current']['temp_c'],
            'temp_f': data['current']['temp_f'],
            'condition': data['current']['condition']['text'], // In Vietnamese!
            'condition_icon': 'https:${data['current']['condition']['icon']}',
            'wind_kph': data['current']['wind_kph'],
            'wind_dir': data['current']['wind_dir'],
            'humidity': data['current']['humidity'],
            'cloud': data['current']['cloud'],
            'feelslike_c': data['current']['feelslike_c'],
            'vis_km': data['current']['vis_km'],
            'uv': data['current']['uv'],
            'pressure_mb': data['current']['pressure_mb'],
            'is_day': data['current']['is_day'],
          },
          'air_quality': data['current']['air_quality'] != null ? {
            'co': data['current']['air_quality']['co'],
            'no2': data['current']['air_quality']['no2'],
            'o3': data['current']['air_quality']['o3'],
            'so2': data['current']['air_quality']['so2'],
            'pm2_5': data['current']['air_quality']['pm2_5'],
            'pm10': data['current']['air_quality']['pm10'],
            'us_epa_index': data['current']['air_quality']['us-epa-index'],
            'gb_defra_index': data['current']['air_quality']['gb-defra-index'],
          } : null,
          'last_updated': data['current']['last_updated'],
        };
      }
    } catch (e) {
      print('Error fetching current weather: $e');
    }
    return null;
  }

  Future<Map<String, dynamic>?> getWeatherForecast({LatLng? location, int days = 7}) async {
    try {
      final coords = location ?? _hcmcLocation;
      final url = '$_baseUrl/forecast.json?key=$_apiKey&q=${coords.latitude},${coords.longitude}&days=$days&aqi=yes&alerts=yes&lang=vi';

      print('Fetching forecast from: $url');
      final response = await http.get(Uri.parse(url)).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      }
    } catch (e) {
      print('Error fetching weather forecast: $e');
    }
    return null;
  }

  // Get weather-based driving conditions
  Map<String, dynamic> getDrivingConditions(Map<String, dynamic>? weather) {
    if (weather == null) {
      return {
        'safe': true,
        'warnings': [],
        'recommendations': ['Kiểm tra thời tiết trước khi xuất phát'],
      };
    }

    List<String> warnings = [];
    List<String> recommendations = [];
    bool safe = true;

    final current = weather['current'];
    final visKm = current['vis_km'] ?? 10.0;
    final windKph = current['wind_kph'] ?? 0.0;
    final condition = current['condition']?.toString().toLowerCase() ?? '';

    // Visibility warnings
    if (visKm < 1.0) {
      safe = false;
      warnings.add('Tầm nhìn rất hạn chế (${visKm}km)');
      recommendations.add('Tránh lái xe nếu có thể');
    } else if (visKm < 5.0) {
      warnings.add('Tầm nhìn hạn chế (${visKm}km)');
      recommendations.add('Lái xe chậm và cẩn thận');
    }

    // Wind warnings
    if (windKph > 50.0) {
      warnings.add('Gió mạnh (${windKph}km/h)');
      recommendations.add('Cẩn thận khi điều khiển xe máy');
    }

    // Rain warnings
    if (condition.contains('rain') || condition.contains('mưa')) {
      warnings.add('Trời mưa - Đường có thể trơn trượt');
      recommendations.add('Giảm tốc độ và tăng khoảng cách an toàn');
    }

    // Fog warnings
    if (condition.contains('fog') || condition.contains('sương mù')) {
      warnings.add('Có sương mù');
      recommendations.add('Bật đèn và lái xe chậm');
    }

    // Storm warnings
    if (condition.contains('storm') || condition.contains('thunder') || condition.contains('bão')) {
      safe = false;
      warnings.add('Có bão/sấm sét');
      recommendations.add('Tránh lái xe cho đến khi thời tiết ổn định');
    }

    return {
      'safe': safe,
      'warnings': warnings,
      'recommendations': recommendations,
      'visibility_km': visKm,
      'wind_kph': windKph,
    };
  }

  // Get air quality description in Vietnamese
  String getAirQualityDescription(int? usEpaIndex) {
    if (usEpaIndex == null) return 'Không có dữ liệu';

    switch (usEpaIndex) {
      case 1:
        return 'Tốt - Chất lượng không khí tốt';
      case 2:
        return 'Trung bình - Chất lượng không khí ở mức chấp nhận được';
      case 3:
        return 'Không tốt cho nhóm nhạy cảm';
      case 4:
        return 'Không tốt cho sức khỏe';
      case 5:
        return 'Rất không tốt cho sức khỏe';
      case 6:
        return 'Nguy hiểm - Cảnh báo sức khỏe khẩn cấp';
      default:
        return 'Không xác định';
    }
  }
}