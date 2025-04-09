// lib/src/services/overpass_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class OverpassService {
  Future<double?> getMaxSpeed(LatLng location) async {
    // Query OSM for ways within 50 meters of the location with maxspeed tag
    final query = '''
      [out:json];
      way(around:50,${location.latitude},${location.longitude})["highway"]["maxspeed"];
      out body;
    ''';
    final url = Uri.parse('https://overpass-api.de/api/interpreter');
    final response = await http.post(url, body: query);

    print('Overpass Request for $location: $query');
    print('Overpass Status Code: ${response.statusCode}');
    print('Overpass Response: ${response.body}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final elements = data['elements'] as List;
      if (elements.isNotEmpty) {
        final maxspeed = elements.first['tags']['maxspeed'] as String;
        // Parse maxspeed (e.g., "50" or "50 km/h")
        final speed = double.tryParse(maxspeed.replaceAll(RegExp(r'[^0-9.]'), ''));
        print('Maxspeed found: $speed km/h');
        return speed;
      } else {
        print('No maxspeed tag found near $location');
        return null;
      }
    } else {
      print('Overpass Error: ${response.statusCode}, ${response.body}');
      return null;
    }
  }
}