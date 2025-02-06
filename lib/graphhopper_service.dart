import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GraphHopperService {
  final String apiKey = dotenv.env['GRAPH_HOPPER_API_KEY'] ?? '';

  /// Convert place name to coordinates (Geocoding)
  Future<LatLng?> getCoordinates(String place) async {
    final url = Uri.parse('https://graphhopper.com/api/1/geocode?q=$place&limit=1&key=$apiKey');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['hits'].isNotEmpty) {
        return LatLng(data['hits'][0]['point']['lat'], data['hits'][0]['point']['lng']);
      }
    }
    return null;
  }

  /// Get the best route using GraphHopper
  Future<List<LatLng>> getRoute(LatLng start, LatLng end, String vehicleType) async {
    final url = Uri.parse(
        'https://graphhopper.com/api/1/route?'
        'point=${start.latitude},${start.longitude}&'
        'point=${end.latitude},${end.longitude}&'
        'vehicle=$vehicleType&'
        'points_encoded=false&'
        'key=$apiKey');

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return (data['paths'][0]['points']['coordinates'] as List)
          .map((point) => LatLng(point[1], point[0]))
          .toList();
    }
    return [];
  }

  /// Matrix API: Get distances between multiple locations
  Future<List<List<double>>> getDistanceMatrix(List<LatLng> locations, String vehicleType) async {
    final points = locations.map((loc) => "point=${loc.latitude},${loc.longitude}").join('&');
    final url = Uri.parse(
        'https://graphhopper.com/api/1/matrix?$points&vehicle=$vehicleType&out_array=distances&out_array=times&key=$apiKey');

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return List<List<double>>.from(data['distances']);
    }
    return [];
  }

  /// Isochrone API: Get reachable areas within a time limit
  Future<List<LatLng>> getReachableArea(LatLng location, int timeLimit, String vehicleType) async {
    final url = Uri.parse(
        'https://graphhopper.com/api/1/isochrone?point=${location.latitude},${location.longitude}&'
        'time_limit=$timeLimit&vehicle=$vehicleType&key=$apiKey');

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return (data['polygons'][0]['geometry']['coordinates'][0] as List)
          .map((point) => LatLng(point[1], point[0]))
          .toList();
    }
    return [];
  }

  /// Turn-by-turn navigation instructions
  Future<List<String>> getNavigationInstructions(LatLng start, LatLng end, String vehicleType) async {
    final url = Uri.parse(
        'https://graphhopper.com/api/1/route?'
        'point=${start.latitude},${start.longitude}&'
        'point=${end.latitude},${end.longitude}&'
        'vehicle=$vehicleType&'
        'instructions=true&'
        'key=$apiKey');

    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return (data['paths'][0]['instructions'] as List)
          .map((step) => "${step['text']} (${step['distance']}m)")
          .toList();
    }
    return [];
  }
}
