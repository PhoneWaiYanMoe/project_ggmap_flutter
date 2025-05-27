import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GraphHopperService {
  final String apiKey = dotenv.env['GRAPH_HOPPER_API_KEY'] ?? '';
  static const int _requestsPerMinute = 20; // Free tier limit (adjust based on your plan)
  static const Duration _delayBetweenRequests = Duration(milliseconds: (60 * 1000) ~/ _requestsPerMinute); // 3000ms delay
  static DateTime _lastRequestTime = DateTime.now().subtract(Duration(minutes: 1));
  static int _requestCount = 0;

  // Helper method to enforce rate limiting
  Future<void> _enforceRateLimit() async {
    final now = DateTime.now();
    if (now.difference(_lastRequestTime).inMinutes < 1) {
      _requestCount++;
      if (_requestCount >= _requestsPerMinute) {
        final waitTime = _lastRequestTime.add(Duration(minutes: 1)).difference(now);
        print('Rate limit reached, waiting for ${waitTime.inMilliseconds}ms');
        await Future.delayed(waitTime);
        _lastRequestTime = DateTime.now();
        _requestCount = 0;
      } else {
        final elapsedSinceLast = now.difference(_lastRequestTime).inMilliseconds;
        if (elapsedSinceLast < _delayBetweenRequests.inMilliseconds) {
          final waitTime = _delayBetweenRequests.inMilliseconds - elapsedSinceLast;
          print('Throttling request, waiting for ${waitTime}ms');
          await Future.delayed(Duration(milliseconds: waitTime));
        }
      }
    } else {
      _lastRequestTime = now;
      _requestCount = 0;
    }
    _lastRequestTime = DateTime.now();
  }

  Future<Map<String, dynamic>?> getLocationDetails(String place) async {
    if (apiKey.isEmpty) {
      print('Error: GraphHopper API key is missing');
      return null;
    }

    await _enforceRateLimit();

    final url = Uri.parse('https://graphhopper.com/api/1/geocode?q=$place&limit=5&key=$apiKey');
    print('Request URL: $url');
    final response = await http.get(url);
    print('API Status Code: ${response.statusCode}');
    print('API Response: ${response.body}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['hits'].isNotEmpty) {
        return {
          'coordinates': LatLng(
            data['hits'][0]['point']['lat'],
            data['hits'][0]['point']['lng'],
          ),
          'name': data['hits'][0]['name'] ?? '',
          'country': data['hits'][0]['country'] ?? '',
          'city': data['hits'][0]['city'] ?? '',
          'state': data['hits'][0]['state'] ?? '',
          'street': data['hits'][0]['street'] ?? '',
          'housenumber': data['hits'][0]['housenumber'] ?? '',
          'postcode': data['hits'][0]['postcode'] ?? '',
        };
      }
    } else {
      print('API Error: Status ${response.statusCode}, Body: ${response.body}');
    }
    return null;
  }

  Future<List<String>> getNavigationInstructions(
    LatLng start,
    LatLng end,
    String vehicleType,
  ) async {
    if (apiKey.isEmpty) {
      print('Error: GraphHopper API key is missing');
      return ['Error: API key missing'];
    }

    await _enforceRateLimit();

    final url = Uri.parse(
      'https://graphhopper.com/api/1/route?'
      'point=${start.latitude},${start.longitude}&'
      'point=${end.latitude},${end.longitude}&'
      'vehicle=$vehicleType&'
      'points_encoded=false&'
      'instructions=true&'
      'locale=en&'
      'key=$apiKey',
    );

    print('Request URL: $url');
    final response = await http.get(url);
    print('API Status Code: ${response.statusCode}');
    print('API Response: ${response.body}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final instructions = data['paths'][0]['instructions'] as List;
      return instructions.map((instruction) {
        String text = instruction['text'];
        double distance = instruction['distance'] / 1000;
        String distanceStr = distance > 0.1 ? ' (${distance.toStringAsFixed(1)} km)' : '';
        return '$text$distanceStr';
      }).toList();
    } else {
      print('API Error: Status ${response.statusCode}, Body: ${response.body}');
      return ['No instructions available'];
    }
  }

  Future<LatLng?> getCoordinates(String place) async {
    if (apiKey.isEmpty) {
      print('Error: GraphHopper API key is missing');
      return null;
    }

    await _enforceRateLimit();

    final url = Uri.parse('https://graphhopper.com/api/1/geocode?q=$place&limit=1&key=$apiKey');
    print('Request URL: $url');
    final response = await http.get(url);
    print('API Status Code: ${response.statusCode}');
    print('API Response: ${response.body}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['hits'].isNotEmpty) {
        final location = data['hits'][0]['point'];
        return LatLng(location['lat'], location['lng']);
      }
    } else {
      print('API Error: Status ${response.statusCode}, Body: ${response.body}');
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

    await _enforceRateLimit();

    final url = Uri.parse(
      'https://graphhopper.com/api/1/route?'
      'point=${start.latitude},${start.longitude}&'
      'point=${end.latitude},${end.longitude}&'
      'vehicle=$vehicleType&'
      'points_encoded=false&'
      'instructions=true&'
      'key=$apiKey',
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

  // Method to get route with multiple waypoints
  Future<Map<String, dynamic>> getRouteWithWaypoints(
    List<LatLng> points,
    String vehicleType,
  ) async {
    if (apiKey.isEmpty) {
      print('Error: GraphHopper API key is missing');
      return {'points': [], 'distance': 0.0, 'time': 0, 'instructions': []};
    }

    await _enforceRateLimit();

    final url = StringBuffer('https://graphhopper.com/api/1/route?');
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      url.write('point=${point.latitude},${point.longitude}');
      if (i < points.length - 1) url.write('&');
    }
    url.write('&vehicle=$vehicleType&points_encoded=false&instructions=true&key=$apiKey');

    print('Request URL: $url');
    final response = await http.get(Uri.parse(url.toString()));
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
        'text': instruction['text'] ?? '',
        'distance': instruction['distance'] ?? 0.0,
        'time': instruction['time'] ?? 0,
        'sign': instruction['sign'] ?? 0,
        'street_name': instruction['street_name'] ?? '',
      };
    }).toList();
  }
}