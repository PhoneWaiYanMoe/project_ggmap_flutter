import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GraphHopperService {
  final String apiKey = dotenv.env['GRAPH_HOPPER_API_KEY'] ?? '';

  Future<Map<String, dynamic>?> getLocationDetails(String place) async {
    final url = Uri.parse('https://graphhopper.com/api/1/geocode?q=$place&limit=5&key=$apiKey');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['hits'].isNotEmpty) {
        return {
          'coordinates': LatLng(
            data['hits'][0]['point']['lat'],
            data['hits'][0]['point']['lng'],
          ),
          'name': data['hits'][0]['name'],
          'country': data['hits'][0]['country'],
          'city': data['hits'][0]['city'],
          'state': data['hits'][0]['state'],
          'street': data['hits'][0]['street'],
          'housenumber': data['hits'][0]['housenumber'],
          'postcode': data['hits'][0]['postcode'],
        };
      }
    }
    return null;
  }

  Future<List<String>> getNavigationInstructions(
    LatLng start,
    LatLng end,
    String vehicleType,
  ) async {
    final url = Uri.parse(
      'https://graphhopper.com/api/1/route?'
      'point=${start.latitude},${start.longitude}&'
      'point=${end.latitude},${end.longitude}&'
      'vehicle=$vehicleType&'
      'points_encoded=false&'
      'instructions=true&'
      'locale=en&'
      'key=$apiKey'
    );

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final instructions = data['paths'][0]['instructions'] as List;
      return instructions.map((instruction) {
        String text = instruction['text'];
        double distance = instruction['distance'] / 1000;
        String distanceStr = distance > 0.1 ? ' (${distance.toStringAsFixed(1)} km)' : '';
        return '$text$distanceStr';
      }).toList();
    }
    return ['No instructions available'];
  }

  Future<LatLng?> getCoordinates(String place) async {
    final url = Uri.parse('https://graphhopper.com/api/1/geocode?q=$place&limit=1&key=$apiKey');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['hits'].isNotEmpty) {
        final location = data['hits'][0]['point'];
        return LatLng(location['lat'], location['lng']);
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> getRoute(
    LatLng start,
    LatLng end,
    String vehicleType,
  ) async {
    if (apiKey.isEmpty) {
      print('Error: GraphHopper API key is missing');
      return {'points': [], 'distance': 0.0, 'time': 0, 'instructions': []};
    }

    final url = Uri.parse(
      'https://graphhopper.com/api/1/route?'
      'point=${start.latitude},${start.longitude}&'
      'point=${end.latitude},${end.longitude}&'
      'vehicle=$vehicleType&'
      'points_encoded=false&'
      'instructions=true&'
      'key=$apiKey'
    );

    print('Request URL: $url');
    final response = await http.get(url);
    print('API Status Code: ${response.statusCode}');
    print('API Response: ${response.body}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final path = data['paths'][0];
      return {
        'points': (path['points']['coordinates'] as List)
            .map((point) => LatLng(point[1] as double, point[0] as double))
            .toList(),
        'distance': path['distance'] as double,
        'time': path['time'] as int,
        'instructions': _parseInstructions(path['instructions'] as List),
      };
    } else {
      print('API Error: Status ${response.statusCode}, Body: ${response.body}');
      return {'points': [], 'distance': 0.0, 'time': 0, 'instructions': []};
    }
  }

  List<Map<String, dynamic>> _parseInstructions(List<dynamic> instructions) {
    return instructions.map((instruction) {
      return {
        'text': instruction['text'],
        'distance': instruction['distance'],
        'time': instruction['time'],
        'sign': instruction['sign'],
        'street_name': instruction['street_name'],
      };
    }).toList();
  }
}