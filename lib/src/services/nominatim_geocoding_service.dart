// lib/src/services/nominatim_geocoding_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter/material.dart';

class NominatimPlace {
  final String placeId;
  final String displayName;
  final String name;
  final String type;
  final LatLng coordinates;
  final String? houseNumber;
  final String? road;
  final String? suburb;
  final String? city;
  final String? state;
  final String? country;
  final String? postcode;
  final double importance;

  NominatimPlace({
    required this.placeId,
    required this.displayName,
    required this.name,
    required this.type,
    required this.coordinates,
    this.houseNumber,
    this.road,
    this.suburb,
    this.city,
    this.state,
    this.country,
    this.postcode,
    required this.importance,
  });

  factory NominatimPlace.fromJson(Map<String, dynamic> json) {
    final address = json['address'] ?? {};

    // Extract name from display_name or use the first part
    String name = json['name'] ?? '';
    if (name.isEmpty) {
      final displayParts = json['display_name']?.toString().split(',') ?? [];
      name = displayParts.isNotEmpty ? displayParts.first.trim() : 'Unknown Place';
    }

    return NominatimPlace(
      placeId: json['place_id']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? '',
      name: name,
      type: json['type']?.toString() ?? '',
      coordinates: LatLng(
        double.tryParse(json['lat']?.toString() ?? '0') ?? 0.0,
        double.tryParse(json['lon']?.toString() ?? '0') ?? 0.0,
      ),
      houseNumber: address['house_number']?.toString(),
      road: address['road']?.toString(),
      suburb: address['suburb']?.toString() ?? address['neighbourhood']?.toString(),
      city: address['city']?.toString() ?? address['town']?.toString() ?? address['village']?.toString(),
      state: address['state']?.toString(),
      country: address['country']?.toString(),
      postcode: address['postcode']?.toString(),
      importance: double.tryParse(json['importance']?.toString() ?? '0') ?? 0.0,
    );
  }

  String get formattedAddress {
    final parts = <String>[];

    if (houseNumber != null && road != null) {
      parts.add('$houseNumber $road');
    } else if (road != null) {
      parts.add(road!);
    }

    if (suburb != null) parts.add(suburb!);
    if (city != null) parts.add(city!);
    if (state != null) parts.add(state!);
    if (country != null) parts.add(country!);

    return parts.join(', ');
  }

  String get shortAddress {
    final parts = <String>[];

    if (road != null) parts.add(road!);
    if (city != null) parts.add(city!);

    return parts.join(', ');
  }

  List<String> get placeTypes {
    // Convert Nominatim types to our standardized types
    switch (type.toLowerCase()) {
      case 'restaurant':
      case 'fast_food':
      case 'cafe':
        return ['restaurant', 'food'];
      case 'fuel':
      case 'gas_station':
        return ['gas_station'];
      case 'hospital':
      case 'clinic':
        return ['hospital', 'health'];
      case 'school':
      case 'university':
      case 'college':
        return ['school', 'education'];
      case 'bank':
      case 'atm':
        return ['bank', 'finance'];
      case 'shop':
      case 'supermarket':
      case 'shopping_mall':
        return ['shopping', 'store'];
      case 'tourism':
      case 'attraction':
      case 'museum':
        return ['tourist_attraction'];
      case 'place_of_worship':
      case 'church':
      case 'temple':
        return ['place_of_worship'];
      case 'park':
      case 'garden':
        return ['park'];
      case 'bus_station':
      case 'railway_station':
        return ['transit_station'];
      case 'hotel':
      case 'motel':
        return ['lodging'];
      default:
        if (road != null) return ['street'];
        if (city != null) return ['locality'];
        return ['place'];
    }
  }
}

class NominatimGeocodingService {
  static const String _baseUrl = 'https://nominatim.openstreetmap.org';
  static const Duration _requestDelay = Duration(milliseconds: 1100); // Respect rate limit (1 req/sec)
  static DateTime _lastRequestTime = DateTime.now().subtract(Duration(minutes: 1));

  Future<void> _enforceRateLimit() async {
    final now = DateTime.now();
    final timeSinceLastRequest = now.difference(_lastRequestTime);

    if (timeSinceLastRequest < _requestDelay) {
      final waitTime = _requestDelay - timeSinceLastRequest;
      await Future.delayed(waitTime);
    }

    _lastRequestTime = DateTime.now();
  }

  Future<List<NominatimPlace>> searchPlaces({
    required String query,
    LatLng? location,
    int limit = 10,
    String? countryCode = 'vn', // Default to Vietnam
  }) async {
    if (query.trim().isEmpty) return [];

    await _enforceRateLimit();

    try {
      final queryParams = {
        'q': query.trim(),
        'format': 'jsonv2',
        'addressdetails': '1',
        'limit': limit.toString(),
        'dedupe': '1', // Remove duplicates
        'namedetails': '1',
        'extratags': '1',
      };

      // Add country restriction if specified
      if (countryCode != null) {
        queryParams['countrycodes'] = countryCode;
      }

      // Add location bias if provided
      if (location != null) {
        // Create viewbox around the location (roughly 50km radius)
        final lat = location.latitude;
        final lng = location.longitude;
        final offset = 0.45; // Roughly 50km in degrees

        queryParams['viewbox'] = '${lng - offset},${lat + offset},${lng + offset},${lat - offset}';
        queryParams['bounded'] = '1';
      }

      final uri = Uri.parse('$_baseUrl/search').replace(queryParameters: queryParams);

      print('Nominatim search: $uri');

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'VietnamTrafficApp/1.0 (contact@example.com)', // Required by Nominatim
        },
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);

        final places = data
            .map((item) => NominatimPlace.fromJson(item))
            .where((place) => _isValidPlace(place))
            .toList();

        // Sort by importance (Nominatim's relevance score)
        places.sort((a, b) => b.importance.compareTo(a.importance));

        return places;
      } else {
        print('Nominatim error: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      print('Error searching places: $e');
      return [];
    }
  }

  bool _isValidPlace(NominatimPlace place) {
    // Filter out very generic or invalid results
    if (place.name.length < 2) return false;
    if (place.coordinates.latitude == 0 && place.coordinates.longitude == 0) return false;

    // Filter out some unwanted types
    final lowercaseName = place.name.toLowerCase();
    if (lowercaseName.contains('unnamed') ||
        lowercaseName.contains('unknown') ||
        lowercaseName.startsWith('way ') ||
        lowercaseName.startsWith('node ')) {
      return false;
    }

    return true;
  }

  Future<NominatimPlace?> reverseGeocode(LatLng location) async {
    await _enforceRateLimit();

    try {
      final queryParams = {
        'lat': location.latitude.toString(),
        'lon': location.longitude.toString(),
        'format': 'jsonv2',
        'addressdetails': '1',
        'namedetails': '1',
        'zoom': '18', // High detail level
      };

      final uri = Uri.parse('$_baseUrl/reverse').replace(queryParameters: queryParams);

      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'VietnamTrafficApp/1.0 (contact@example.com)',
        },
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return NominatimPlace.fromJson(data);
      } else {
        print('Nominatim reverse geocode error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error in reverse geocoding: $e');
      return null;
    }
  }

  // Get place icon based on type
  IconData getPlaceIcon(List<String> types) {
    if (types.contains('restaurant') || types.contains('food')) return Icons.restaurant;
    if (types.contains('gas_station')) return Icons.local_gas_station;
    if (types.contains('hospital') || types.contains('health')) return Icons.local_hospital;
    if (types.contains('school') || types.contains('education')) return Icons.school;
    if (types.contains('bank') || types.contains('finance')) return Icons.account_balance;
    if (types.contains('shopping') || types.contains('store')) return Icons.shopping_cart;
    if (types.contains('tourist_attraction')) return Icons.attractions;
    if (types.contains('place_of_worship')) return Icons.place;
    if (types.contains('park')) return Icons.park;
    if (types.contains('transit_station')) return Icons.train;
    if (types.contains('lodging')) return Icons.hotel;
    if (types.contains('street')) return Icons.route;
    if (types.contains('locality')) return Icons.location_city;
    return Icons.location_on;
  }

  // Get place color based on type
  Color getPlaceColor(List<String> types) {
    if (types.contains('restaurant') || types.contains('food')) return Colors.orange;
    if (types.contains('gas_station')) return Colors.blue;
    if (types.contains('hospital') || types.contains('health')) return Colors.red;
    if (types.contains('school') || types.contains('education')) return Colors.green;
    if (types.contains('bank') || types.contains('finance')) return Colors.indigo;
    if (types.contains('shopping') || types.contains('store')) return Colors.purple;
    if (types.contains('tourist_attraction')) return Colors.brown;
    if (types.contains('place_of_worship')) return Colors.deepPurple;
    if (types.contains('park')) return Colors.lightGreen;
    if (types.contains('transit_station')) return Colors.teal;
    if (types.contains('lodging')) return Colors.pink;
    if (types.contains('street')) return Colors.grey[700]!;
    if (types.contains('locality')) return Colors.blueGrey;
    return Colors.blue;
  }
}