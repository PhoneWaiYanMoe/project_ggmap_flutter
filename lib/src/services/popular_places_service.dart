// lib/src/services/popular_places_service.dart
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class PopularPlace {
  final String name;
  final String category;
  final LatLng coordinates;
  final String address;
  final String? description;
  final double? rating;
  final String? openingHours;

  PopularPlace({
    required this.name,
    required this.category,
    required this.coordinates,
    required this.address,
    this.description,
    this.rating,
    this.openingHours,
  });

  factory PopularPlace.fromNominatim(Map<String, dynamic> json) {
    return PopularPlace(
      name: json['display_name']?.toString().split(',').first ?? 'Unknown Place',
      category: _getCategoryFromType(json['type']?.toString() ?? ''),
      coordinates: LatLng(
        double.parse(json['lat']?.toString() ?? '0'),
        double.parse(json['lon']?.toString() ?? '0'),
      ),
      address: json['display_name']?.toString() ?? '',
      description: json['type']?.toString(),
    );
  }

  static String _getCategoryFromType(String type) {
    switch (type.toLowerCase()) {
      case 'restaurant':
      case 'cafe':
      case 'fast_food':
        return 'Ăn uống';
      case 'hospital':
      case 'clinic':
      case 'pharmacy':
        return 'Y tế';
      case 'school':
      case 'university':
      case 'college':
        return 'Giáo dục';
      case 'bank':
      case 'atm':
        return 'Ngân hàng';
      case 'fuel':
      case 'gas_station':
        return 'Xăng dầu';
      case 'shopping_mall':
      case 'supermarket':
      case 'shop':
        return 'Mua sắm';
      case 'hotel':
      case 'motel':
        return 'Khách sạn';
      case 'tourist_attraction':
      case 'museum':
      case 'monument':
        return 'Du lịch';
      case 'park':
      case 'garden':
        return 'Công viên';
      case 'bus_station':
      case 'subway_station':
        return 'Giao thông';
      default:
        return 'Khác';
    }
  }
}

class PopularPlacesService {
  static const String _nominatimUrl = 'https://nominatim.openstreetmap.org/search';
  static const Duration _requestDelay = Duration(seconds: 1); // Nominatim rate limit
  static DateTime _lastRequestTime = DateTime.now().subtract(Duration(minutes: 1));

  // Ho Chi Minh City bounds
  static const double _hcmcNorth = 11.2;
  static const double _hcmcSouth = 10.3;
  static const double _hcmcEast = 107.0;
  static const double _hcmcWest = 106.3;

  Future<void> _enforceRateLimit() async {
    final now = DateTime.now();
    final timeSinceLastRequest = now.difference(_lastRequestTime);

    if (timeSinceLastRequest < _requestDelay) {
      final waitTime = _requestDelay - timeSinceLastRequest;
      await Future.delayed(waitTime);
    }

    _lastRequestTime = DateTime.now();
  }

  Future<List<PopularPlace>> getPopularPlaces({
    LatLng? center,
    double radiusKm = 5.0,
    String category = 'all',
    int limit = 20,
  }) async {
    // Default to Ho Chi Minh City center if no location provided
    final searchCenter = center ?? LatLng(10.7769, 106.7009);

    // Calculate bounding box
    final latOffset = radiusKm / 111.32; // Rough conversion: 1 degree lat ≈ 111.32 km
    final lonOffset = radiusKm / (111.32 * cos(searchCenter.latitude * pi / 180));

    final bbox = {
      'south': (searchCenter.latitude - latOffset).clamp(_hcmcSouth, _hcmcNorth),
      'north': (searchCenter.latitude + latOffset).clamp(_hcmcSouth, _hcmcNorth),
      'west': (searchCenter.longitude - lonOffset).clamp(_hcmcWest, _hcmcEast),
      'east': (searchCenter.longitude + lonOffset).clamp(_hcmcWest, _hcmcEast),
    };

    List<PopularPlace> allPlaces = [];

    // Define search queries based on category
    List<String> queries = _getQueriesForCategory(category);

    for (String query in queries) {
      try {
        await _enforceRateLimit();

        final places = await _searchPlaces(
          query: query,
          bbox: bbox,
          limit: limit ~/ queries.length + 5, // Get more per query to compensate for filtering
        );

        allPlaces.addAll(places);

        // Break early if we have enough places
        if (allPlaces.length >= limit * 2) break;

      } catch (e) {
        print('Error searching for $query: $e');
        continue;
      }
    }

    // Remove duplicates based on name and coordinates proximity
    final uniquePlaces = _removeDuplicates(allPlaces);

    // Sort by distance from center
    uniquePlaces.sort((a, b) {
      final distanceA = _calculateDistance(searchCenter, a.coordinates);
      final distanceB = _calculateDistance(searchCenter, b.coordinates);
      return distanceA.compareTo(distanceB);
    });

    return uniquePlaces.take(limit).toList();
  }

  List<String> _getQueriesForCategory(String category) {
    switch (category.toLowerCase()) {
      case 'food':
        return [
          'restaurant in Ho Chi Minh City',
          'cafe in Ho Chi Minh City',
          'pho in Ho Chi Minh City',
          'food court in Ho Chi Minh City',
        ];
      case 'shopping':
        return [
          'shopping mall in Ho Chi Minh City',
          'market in Ho Chi Minh City',
          'supermarket in Ho Chi Minh City',
          'department store in Ho Chi Minh City',
        ];
      case 'healthcare':
        return [
          'hospital in Ho Chi Minh City',
          'clinic in Ho Chi Minh City',
          'pharmacy in Ho Chi Minh City',
        ];
      case 'education':
        return [
          'university in Ho Chi Minh City',
          'school in Ho Chi Minh City',
          'college in Ho Chi Minh City',
        ];
      case 'tourism':
        return [
          'tourist attraction in Ho Chi Minh City',
          'museum in Ho Chi Minh City',
          'temple in Ho Chi Minh City',
          'park in Ho Chi Minh City',
          'landmark in Ho Chi Minh City',
        ];
      case 'transport':
        return [
          'bus station in Ho Chi Minh City',
          'airport in Ho Chi Minh City',
          'train station in Ho Chi Minh City',
        ];
      case 'banking':
        return [
          'bank in Ho Chi Minh City',
          'ATM in Ho Chi Minh City',
        ];
      case 'fuel':
        return [
          'gas station in Ho Chi Minh City',
          'petrol station in Ho Chi Minh City',
        ];
      default: // 'all'
        return [
          'popular places in Ho Chi Minh City',
          'tourist attraction in Ho Chi Minh City',
          'restaurant in Ho Chi Minh City',
          'shopping mall in Ho Chi Minh City',
          'hospital in Ho Chi Minh City',
          'university in Ho Chi Minh City',
          'bank in Ho Chi Minh City',
          'park in Ho Chi Minh City',
        ];
    }
  }

  Future<List<PopularPlace>> _searchPlaces({
    required String query,
    required Map<String, double> bbox,
    required int limit,
  }) async {
    final url = Uri.parse(_nominatimUrl).replace(queryParameters: {
      'q': query,
      'format': 'json',
      'limit': limit.toString(),
      'bounded': '1',
      'viewbox': '${bbox['west']},${bbox['north']},${bbox['east']},${bbox['south']}',
      'addressdetails': '1',
      'extratags': '1',
      'namedetails': '1',
    });

    print('Searching Nominatim: $url');

    try {
      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'VietnamNavigationApp/1.0 (contact@example.com)', // Required by Nominatim
        },
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);

        return data
            .where((item) => item['lat'] != null && item['lon'] != null)
            .map((item) => PopularPlace.fromNominatim(item))
            .where((place) => _isValidPlace(place))
            .toList();
      } else {
        print('Nominatim error: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      print('Error fetching from Nominatim: $e');
      return [];
    }
  }

  bool _isValidPlace(PopularPlace place) {
    // Filter out places that are too generic or not useful
    final name = place.name.toLowerCase();

    // Skip if name is just a number or too short
    if (name.length < 3 || RegExp(r'^\d+$').hasMatch(name)) {
      return false;
    }

    // Skip generic addresses
    if (name.contains('unnamed') ||
        name.contains('no name') ||
        name.startsWith('đường') ||
        name.startsWith('street')) {
      return false;
    }

    return true;
  }

  List<PopularPlace> _removeDuplicates(List<PopularPlace> places) {
    final uniquePlaces = <PopularPlace>[];

    for (final place in places) {
      bool isDuplicate = false;

      for (final existing in uniquePlaces) {
        // Check if names are very similar
        if (_areSimilarNames(place.name, existing.name)) {
          isDuplicate = true;
          break;
        }

        // Check if coordinates are very close (within 100 meters)
        if (_calculateDistance(place.coordinates, existing.coordinates) < 0.1) {
          isDuplicate = true;
          break;
        }
      }

      if (!isDuplicate) {
        uniquePlaces.add(place);
      }
    }

    return uniquePlaces;
  }

  bool _areSimilarNames(String name1, String name2) {
    final clean1 = name1.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
    final clean2 = name2.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');

    // Check if one name contains the other
    return clean1.contains(clean2) || clean2.contains(clean1);
  }

  double _calculateDistance(LatLng point1, LatLng point2) {
    const double radiusEarth = 6371; // Earth's radius in kilometers

    final lat1Rad = point1.latitude * pi / 180;
    final lon1Rad = point1.longitude * pi / 180;
    final lat2Rad = point2.latitude * pi / 180;
    final lon2Rad = point2.longitude * pi / 180;

    final dLat = lat2Rad - lat1Rad;
    final dLon = lon2Rad - lon1Rad;

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1Rad) * cos(lat2Rad) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return radiusEarth * c;
  }

  // Get pre-defined famous places in Ho Chi Minh City
  List<PopularPlace> getFamousPlaces() {
    return [
      PopularPlace(
        name: 'Chợ Bến Thành',
        category: 'Du lịch',
        coordinates: LatLng(10.7720, 106.6983),
        address: 'Lê Lợi, Phường Bến Thành, Quận 1, TP.HCM',
        description: 'Chợ truyền thống nổi tiếng của Sài Gòn',
      ),
      PopularPlace(
        name: 'Nhà Thờ Đức Bà',
        category: 'Du lịch',
        coordinates: LatLng(10.7797, 106.6990),
        address: '01 Công xã Paris, Bến Nghé, Quận 1, TP.HCM',
        description: 'Kiến trúc Pháp cổ điển nổi tiếng',
      ),
      PopularPlace(
        name: 'Bưu Điện Trung Tâm',
        category: 'Du lịch',
        coordinates: LatLng(10.7799, 106.6991),
        address: '2 Công xã Paris, Bến Nghé, Quận 1, TP.HCM',
        description: 'Bưu điện lịch sử của Sài Gòn',
      ),
      PopularPlace(
        name: 'Dinh Độc Lập',
        category: 'Du lịch',
        coordinates: LatLng(10.7769, 106.6955),
        address: '135 Nam Kỳ Khởi Nghĩa, Phường Bến Thành, Quận 1, TP.HCM',
        description: 'Dinh thự lịch sử quan trọng',
      ),
      PopularPlace(
        name: 'Phố Đi Bộ Nguyễn Huệ',
        category: 'Du lịch',
        coordinates: LatLng(10.7748, 106.7017),
        address: 'Nguyễn Huệ, Bến Nghé, Quận 1, TP.HCM',
        description: 'Phố đi bộ sầm uất nhất Sài Gòn',
      ),
      PopularPlace(
        name: 'Landmark 81',
        category: 'Mua sắm',
        coordinates: LatLng(10.7943, 106.7212),
        address: '720A Điện Biên Phủ, Bình Thạnh, TP.HCM',
        description: 'Tòa nhà cao nhất Việt Nam',
      ),
      PopularPlace(
        name: 'Saigon Centre',
        category: 'Mua sắm',
        coordinates: LatLng(10.7782, 106.7017),
        address: '65 Lê Lợi, Bến Nghé, Quận 1, TP.HCM',
        description: 'Trung tâm thương mại cao cấp',
      ),
      PopularPlace(
        name: 'Vincom Center',
        category: 'Mua sắm',
        coordinates: LatLng(10.7763, 106.7006),
        address: '70-72 Lê Thánh Tôn, Bến Nghé, Quận 1, TP.HCM',
        description: 'Trung tâm mua sắm nổi tiếng',
      ),
    ];
  }
}