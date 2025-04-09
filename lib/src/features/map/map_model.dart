import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../services/graphhopper_service.dart';
import '../../services/overpass_service.dart';

class MapModel extends ChangeNotifier {
  LatLng? _currentLocation;
  LatLng? _fromLocation;
  LatLng? _toLocation;
  Set<Polyline> _polylines = {};
  String _selectedVehicle = 'car';
  double? _distance;
  bool _showTwoSearchBars = false;
  String _fromPlaceName = "Your Location";
  String _toPlaceName = "Select Destination";
  DateTime? _estimatedArrival;
  bool _isNavigating = false;
  double _bearing = 0;
  bool _followUser = false;
  Set<Marker> _cameraMarkers = {};
  List<String> _shortestPath = [];
  double _totalTravelTime = 0.0;

  LatLng? get currentLocation => _currentLocation;
  LatLng? get fromLocation => _fromLocation;
  LatLng? get toLocation => _toLocation;
  Set<Polyline> get polylines => _polylines;
  String get selectedVehicle => _selectedVehicle;
  double? get distance => _distance;
  bool get showTwoSearchBars => _showTwoSearchBars;
  String get fromPlaceName => _fromPlaceName;
  String get toPlaceName => _toPlaceName;
  DateTime? get estimatedArrival => _estimatedArrival;
  bool get isNavigating => _isNavigating;
  double get bearing => _bearing;
  bool get followUser => _followUser;
  Set<Marker> get cameraMarkers => _cameraMarkers;
  List<String> get shortestPath => _shortestPath;
  double get totalTravelTime => _totalTravelTime;

  MapModel() {
    _init();
  }

  Future<void> _init() async {
    print('Starting MapModel initialization');
    await getCurrentLocation(setAsFrom: true);
    await _requestLocationPermission();
    _loadCameraMarkers();
    await _calculateAndSaveCameraSpeeds();
    await _calculateAndSaveCameraDistances();
    await _calculateAndFindShortestPath();
    print('MapModel initialization completed');
    notifyListeners();
  }

  Future<void> _requestLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
  }

  Future<void> getCurrentLocation({bool setAsFrom = false}) async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _currentLocation = LatLng(position.latitude, position.longitude);
      if (setAsFrom) {
        _fromLocation = _currentLocation;
        await _fetchPlaceName(_currentLocation!, true);
        print('Set _fromLocation to current location: $_fromLocation');
      }
      _bearing = position.heading;
      notifyListeners();
    } catch (e) {
      print("Error getting current location: $e");
    }
  }

  Future<void> _fetchPlaceName(LatLng location, bool isFrom) async {
    try {
      final locationDetails = await GraphHopperService().getLocationDetails(
        "${location.latitude},${location.longitude}",
      );
      if (locationDetails != null) {
        if (isFrom) {
          _fromPlaceName = locationDetails['name'];
        } else {
          _toPlaceName = locationDetails['name'];
        }
        notifyListeners();
      }
    } catch (e) {
      print("Error fetching place name: $e");
    }
  }

  Future<void> getRoute() async {
    if (_fromLocation == null || _toLocation == null) return;

    print('Calculating route from $_fromLocation to $_toLocation');
    try {
      final routeData = await GraphHopperService().getRoute(
        _fromLocation!,
        _toLocation!,
        _selectedVehicle,
      );
      _polylines.clear();
      _polylines.add(
        Polyline(
          polylineId: PolylineId('route'),
          points: routeData['points'],
          color: Colors.blue,
          width: 5,
        ),
      );
      _distance = routeData['distance'] / 1000;
      _estimatedArrival = DateTime.now().add(Duration(milliseconds: routeData['time'] as int));
      notifyListeners();
    } catch (e) {
      print('Route error: $e');
    }
  }

  void setFromLocation(LatLng location, String name) {
    _fromLocation = location;
    _fromPlaceName = name;
    notifyListeners();
  }

  void setToLocation(LatLng location, String name) {
    _toLocation = location;
    _toPlaceName = name;
    _showTwoSearchBars = true;
    notifyListeners();
  }

  void setVehicle(String vehicle) {
    _selectedVehicle = vehicle;
    notifyListeners();
  }

  void toggleNavigation() {
    _isNavigating = !_isNavigating;
    _followUser = _isNavigating;
    print('Navigation ${_isNavigating ? 'started' : 'stopped'} from $_fromLocation to $_toLocation');
    notifyListeners();
  }

  void toggleFollowUser() {
    _followUser = !_followUser;
    notifyListeners();
  }

  void _loadCameraMarkers() {
    final cameraLocations = [
      {'id': 'A', 'lat': 10.767778, 'lng': 106.671694, 'title': 'Lý Thái Tổ - Sư Vạn Hạnh'},
      {'id': 'B', 'lat': 10.773833, 'lng': 106.677778, 'title': '3/2 – Cao Thắng'},
      {'id': 'C', 'lat': 10.772722, 'lng': 106.679028, 'title': 'Điện Biên Phủ - Cao Thắng'},
      {'id': 'D', 'lat': 10.759694, 'lng': 106.668889, 'title': 'Ngã sáu Nguyễn Tri Phương 1'},
      {'id': 'E', 'lat': 10.760056, 'lng': 106.669000, 'title': 'Ngã sáu Nguyễn Tri Phương'},
      {'id': 'F', 'lat': 10.768806, 'lng': 106.652639, 'title': 'Lê Đại Hành 2'},
      {'id': 'G', 'lat': 10.766222, 'lng': 106.679083, 'title': 'Lý Thái Tổ - Nguyễn Đình Chiểu'},
      {'id': 'H', 'lat': 10.765417, 'lng': 106.681306, 'title': 'Ngã sáu Cộng Hòa 1'},
      {'id': 'I', 'lat': 10.765111, 'lng': 106.681639, 'title': 'Ngã sáu Cộng Hòa'},
      {'id': 'J', 'lat': 10.776667, 'lng': 106.683667, 'title': 'Điện Biên Phủ - CMT8'},
      {'id': 'K', 'lat': 10.777778, 'lng': 106.6820, 'title': 'Nút giao Công Trường Dân Chủ'},
      {'id': 'L', 'lat': 10.777694, 'lng': 106.681361, 'title': 'Nút giao Công Trường Dân Chủ 1'},
    ];

    for (var camera in cameraLocations) {
      _cameraMarkers.add(
        Marker(
          markerId: MarkerId(camera['id'] as String),
          position: LatLng(camera['lat'] as double, camera['lng'] as double),
          infoWindow: InfoWindow(title: camera['title'] as String),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    }
    print('Loaded ${cameraLocations.length} camera markers');
  }

  Future<void> _calculateAndSaveCameraSpeeds() async {
    print('Starting _calculateAndSaveCameraSpeeds');
    final cameraLocations = [
      {'id': 'A', 'lat': 10.767778, 'lng': 106.671694},
      {'id': 'B', 'lat': 10.773833, 'lng': 106.677778},
      {'id': 'C', 'lat': 10.772722, 'lng': 106.679028},
      {'id': 'D', 'lat': 10.759694, 'lng': 106.668889},
      {'id': 'E', 'lat': 10.760056, 'lng': 106.669000},
      {'id': 'F', 'lat': 10.768806, 'lng': 106.652639},
      {'id': 'G', 'lat': 10.766222, 'lng': 106.679083},
      {'id': 'H', 'lat': 10.765417, 'lng': 106.681306},
      {'id': 'I', 'lat': 10.765111, 'lng': 106.681639},
      {'id': 'J', 'lat': 10.776667, 'lng': 106.683667},
      {'id': 'K', 'lat': 10.777778, 'lng': 106.6820},
      {'id': 'L', 'lat': 10.777694, 'lng': 106.681361},
    ];

    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/camera_speeds.txt');
    final sink = file.openWrite();
    sink.write('Camera Free Flow Speeds (Generated on ${DateTime.now()})\n\n');

    final overpassService = OverpassService();
    for (var loc in cameraLocations) {
      final latLng = LatLng(loc['lat'] as double, loc['lng'] as double);
      try {
        final speed = await overpassService.getMaxSpeed(latLng).timeout(Duration(seconds: 5));
        sink.write('Camera ${loc['id']}: ${speed != null ? speed.toStringAsFixed(2) : "40.00"} km/h\n');
      } catch (e) {
        print('Error fetching speed for ${loc['id']}: $e');
        sink.write('Camera ${loc['id']}: 40.00 km/h\n');
      }
    }

    await sink.close();
    print('Speeds saved to ${file.path}');
  }

  Future<void> _calculateAndSaveCameraDistances() async {
    print('Starting _calculateAndSaveCameraDistances');
    final cameraCoords = {
      'A': LatLng(10.767778, 106.671694),
      'B': LatLng(10.773833, 106.677778),
      'C': LatLng(10.772722, 106.679028),
      'D': LatLng(10.759694, 106.668889),
      'E': LatLng(10.760056, 106.669000),
      'F': LatLng(10.768806, 106.652639),
      'G': LatLng(10.766222, 106.679083),
      'H': LatLng(10.765417, 106.681306),
      'I': LatLng(10.765111, 106.681639),
      'J': LatLng(10.776667, 106.683667),
      'K': LatLng(10.777778, 106.6820),
      'L': LatLng(10.777694, 106.681361),
    };
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/camera_distances.txt');
    final sink = file.openWrite();
    sink.write('Camera Distances (Generated on ${DateTime.now()})\n\n');
    final service = GraphHopperService();
    for (var from in cameraCoords.keys) {
      for (var to in cameraCoords.keys) {
        if (from != to) {
          try {
            final routeData = await service.getRoute(cameraCoords[from]!, cameraCoords[to]!, 'car').timeout(Duration(seconds: 10));
            final distance = routeData['distance'] / 1000;
            sink.write('Distance from $from to $to: ${distance.toStringAsFixed(2)} km\n');
          } catch (e) {
            print('Error calculating distance from $from to $to: $e');
            sink.write('Distance from $from to $to: 1.00 km\n');
          }
        }
      }
    }
    await sink.close();
    print('Distances saved to ${file.path}');
  }

  Future<void> _calculateAndFindShortestPath() async {
    print('Starting _calculateAndFindShortestPath');
    final directory = await getApplicationDocumentsDirectory();
    final speedsFile = File('${directory.path}/camera_speeds.txt');
    final distancesFile = File('${directory.path}/camera_distances.txt');
    final densitiesFile = File('${directory.path}/densities.json');

    // Ensure prerequisite files exist
    if (!await speedsFile.exists()) {
      print('Warning: camera_speeds.txt not found, regenerating...');
      await _calculateAndSaveCameraSpeeds();
    }
    if (!await distancesFile.exists()) {
      print('Warning: camera_distances.txt not found, regenerating...');
      await _calculateAndSaveCameraDistances();
    }

    // Read speeds
    Map<String, double> maxSpeeds = {};
    try {
      final speedLines = await speedsFile.readAsLines();
      for (var line in speedLines) {
        if (line.contains('Camera')) {
          final parts = line.split(': ');
          final id = parts[0].split(' ')[1];
          final speedStr = parts[1].split(' ')[0];
          maxSpeeds[id] = double.tryParse(speedStr) ?? 40.0;
        }
      }
      print('Loaded max speeds: $maxSpeeds');
    } catch (e) {
      print('Error reading speeds file: $e');
      maxSpeeds = { 'A': 40.0, 'B': 40.0, 'C': 40.0, 'D': 40.0, 'E': 40.0, 'F': 40.0, 'G': 40.0, 'H': 40.0, 'I': 40.0, 'J': 40.0, 'K': 40.0, 'L': 40.0 };
    }

    // Read distances
    Map<String, Map<String, double>> distances = {};
    try {
      final distanceLines = await distancesFile.readAsLines();
      for (var line in distanceLines) {
        if (line.contains('Distance from')) {
          final parts = line.split(' ');
          final from = parts[2];
          final to = parts[4];
          final distStr = parts[6];
          distances[from] ??= {};
          distances[from]![to] = double.parse(distStr);
        }
      }
      print('Loaded distances: $distances');
    } catch (e) {
      print('Error reading distances file: $e');
      distances = {
        'A': {'B': 1.0, 'G': 1.5, 'K': 1.8}, 'B': {'A': 1.0, 'C': 1.0, 'J': 2.5},
        'C': {'B': 1.0, 'J': 2.0}, 'D': {'E': 0.5}, 'E': {'D': 0.5},
        'F': {}, 'G': {'A': 1.5, 'J': 2.0, 'K': 1.7}, 'H': {'I': 0.5, 'K': 1.2},
        'I': {'H': 0.5, 'J': 1.0, 'L': 0.3}, 'J': {'C': 2.0, 'G': 2.0, 'I': 1.0, 'K': 0.3},
        'K': {'A': 1.8, 'G': 1.7, 'H': 1.2, 'J': 0.3, 'L': 0.1}, 'L': {'I': 0.3, 'K': 0.1},
      };
    }

    // Read densities from JSON
    Map<String, double> densities = {};
    try {
      // If densities.json is in assets, copy to documents directory first
      final densitiesString = await rootBundle.loadString('assets/densities.json');
      final jsonFile = File('${directory.path}/densities.json');
      await jsonFile.writeAsString(densitiesString);
      final densitiesJson = jsonDecode(await jsonFile.readAsString());
      densities = densitiesJson.map((key, value) => MapEntry(key, value.toDouble()));
      print('Loaded densities: $densities');
    } catch (e) {
      print('Error reading densities file: $e');
      densities = {
        'A': 15.0, 'B': 45.0, 'C': 25.0, 'D': 40.0, 'E': 35.0, 'F': 30.0,
        'G': 10.0, 'H': 50.0, 'I': 55.0, 'J': 60.0, 'K': 50.0, 'L': 55.0,
      };
    }

    // Calculate travel times using Greenshield
    Map<String, Map<String, double>> travelTimes = {};
    const double kc = 100.0; // Jam density
    for (var from in distances.keys) {
      travelTimes[from] = {};
      for (var to in distances[from]!.keys) {
        final vf = maxSpeeds[from]!;
        final k = (densities[from]! + densities[to]!) / 2; // Average density
        final v = vf * (1 - k / kc);
        final distance = distances[from]![to]!;
        final time = (distance / v) * 60;
        travelTimes[from]![to] = time > 0 ? time : double.infinity;
      }
    }
    print('Calculated travel times: $travelTimes');   

    // Run A* from A to L
    _shortestPath = aStar('A', 'L', travelTimes, distances);
    print('Shortest Path from A to L: $_shortestPath');

    // Calculate total travel time
    _totalTravelTime = 0.0;
    for (int i = 0; i < _shortestPath.length - 1; i++) {
      final from = _shortestPath[i];
      final to = _shortestPath[i + 1];
      _totalTravelTime += travelTimes[from]![to]!;
    }
    print('Total travel time: $_totalTravelTime minutes');

    // Fetch GraphHopper route
    await _fetchShortestPathRoute(travelTimes);

    // Save results
    final resultFile = File('${directory.path}/shortest_path.txt');
    try {
      final sink = resultFile.openWrite();
      sink.write('Shortest Path from A to L (Generated on ${DateTime.now()})\n\n');
      sink.write('Path: ${_shortestPath.join(" -> ")}\n');
      sink.write('Total Travel Time: ${_totalTravelTime.toStringAsFixed(2)} minutes\n');
      sink.write('Travel Times:\n');
      travelTimes.forEach((from, toMap) {
        toMap.forEach((to, time) {
          sink.write('From $from to $to: ${time.toStringAsFixed(2)} minutes\n');
        });
      });
      await sink.close();
      print('Results saved to ${resultFile.path}');
      if (await resultFile.exists()) {
        print('Confirmed: shortest_path.txt exists at ${resultFile.path}');
      } else {
        print('Warning: shortest_path.txt was not created');
      }
    } catch (e) {
      print('Error writing shortest_path.txt: $e');
    }
  }

  Future<void> _fetchShortestPathRoute(Map<String, Map<String, double>> travelTimes) async {
    print('Starting _fetchShortestPathRoute');
    if (_shortestPath.isEmpty) {
      print('No shortest path to fetch route for');
      return;
    }

    final cameraCoords = {
      'A': LatLng(10.767778, 106.671694),
      'B': LatLng(10.773833, 106.677778),
      'C': LatLng(10.772722, 106.679028),
      'D': LatLng(10.759694, 106.668889),
      'E': LatLng(10.760056, 106.669000),
      'F': LatLng(10.768806, 106.652639),
      'G': LatLng(10.766222, 106.679083),
      'H': LatLng(10.765417, 106.681306),
      'I': LatLng(10.765111, 106.681639),
      'J': LatLng(10.776667, 106.683667),
      'K': LatLng(10.777778, 106.6820),
      'L': LatLng(10.777694, 106.681361),
    };

    _polylines.clear();
    for (int i = 0; i < _shortestPath.length - 1; i++) {
      final from = _shortestPath[i];
      final to = _shortestPath[i + 1];
      final start = cameraCoords[from]!;
      final end = cameraCoords[to]!;
      try {
        final routeData = await GraphHopperService().getRoute(start, end, _selectedVehicle).timeout(Duration(seconds: 10));
        _polylines.add(
          Polyline(
            polylineId: PolylineId('shortest_$from$to'),
            points: routeData['points'],
            color: Colors.green,
            width: 5,
          ),
        );
        print('Added polyline from $from to $to');
      } catch (e) {
        print('Error fetching route from $from to $to: $e');
      }
    }
    print('Finished _fetchShortestPathRoute');
    notifyListeners();
  }

  List<String> aStar(String start, String goal, Map<String, Map<String, double>> travelTimes,
      Map<String, Map<String, double>> distances) {
    final openSet = <String>{start};
    final cameFrom = <String, String>{};
    final gScore = <String, double>{start: 0};
    final fScore = <String, double>{start: _heuristic(start, goal, distances)};

    while (openSet.isNotEmpty) {
      final current = openSet.reduce((a, b) => fScore[a]! < fScore[b]! ? a : b);
      if (current == goal) {
        return _reconstructPath(cameFrom, current);
      }
      openSet.remove(current);
      for (var neighbor in travelTimes[current]!.keys) {
        final tentativeGScore = gScore[current]! + travelTimes[current]![neighbor]!;
        if (!gScore.containsKey(neighbor) || tentativeGScore < gScore[neighbor]!) {
          cameFrom[neighbor] = current;
          gScore[neighbor] = tentativeGScore;
          fScore[neighbor] = gScore[neighbor]! + _heuristic(neighbor, goal, distances);
          openSet.add(neighbor);
        }
      }
    }
    return [];
  }

  double _heuristic(String from, String to, Map<String, Map<String, double>> distances) {
    final dist = distances[from]![to] ?? _haversineDistance(from, to);
    return (dist / 60) * 60; // Minutes assuming 60 km/h max
  }

  double _haversineDistance(String from, String to) {
    final coords = {
      'A': LatLng(10.767778, 106.671694),
      'B': LatLng(10.773833, 106.677778),
      'C': LatLng(10.772722, 106.679028),
      'D': LatLng(10.759694, 106.668889),
      'E': LatLng(10.760056, 106.669000),
      'F': LatLng(10.768806, 106.652639),
      'G': LatLng(10.766222, 106.679083),
      'H': LatLng(10.765417, 106.681306),
      'I': LatLng(10.765111, 106.681639),
      'J': LatLng(10.776667, 106.683667),
      'K': LatLng(10.777778, 106.6820),
      'L': LatLng(10.777694, 106.681361),
    };
    const R = 6371; // Earth radius in km
    final lat1 = coords[from]!.latitude * pi / 180;
    final lon1 = coords[from]!.longitude * pi / 180;
    final lat2 = coords[to]!.latitude * pi / 180;
    final lon2 = coords[to]!.longitude * pi / 180;
    final dLat = lat2 - lat1;
    final dLon = lon2 - lon1;
    final a = pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLon / 2), 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  List<String> _reconstructPath(Map<String, String> cameFrom, String current) {
    final path = [current];
    while (cameFrom.containsKey(current)) {
      current = cameFrom[current]!;
      path.insert(0, current);
    }
    return path;
  }

  Future<String> getCameraDistancesFilePath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/camera_distances.txt';
  }

  Future<String> getCameraSpeedsFilePath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/camera_speeds.txt';
  }

  Future<String> getShortestPathFilePath() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = '${directory.path}/shortest_path.txt';
    print('Shortest path file path requested: $path');
    return path;
  }

  Future<void> regenerateShortestPath() async {
    print('Regenerating shortest path');
    await _calculateAndFindShortestPath();
    notifyListeners();
  }
}