// lib/api_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiService {
  // Load the API key from the .env file
  final String apiKey = dotenv.env['GRAPH_HOPPER_API_KEY'] ?? '';

  /// Fetches polyline route from GraphHopper
  Future<List<LatLng>> getRouteCoordinates(double startLat, double startLng, double endLat, double endLng, String mode) async {
    String url = 'https://graphhopper.com/api/1/route?'
        'point=$startLat,$startLng&'
        'point=$endLat,$endLng&'
        'profile=$mode&' // Use the selected mode
        'locale=en&'
        'points_encoded=false&'
        'key=$apiKey';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      List<LatLng> points = [];

      for (var point in data['paths'][0]['points']['coordinates']) {
        points.add(LatLng(point[1], point[0])); // Swap [lng, lat] to [lat, lng]
      }

      return points;
    } else {
      print('Error fetching route: ${response.statusCode}');
      throw Exception('Failed to load route');
    }
  }
}