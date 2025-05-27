import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../services/graphhopper_service.dart';
import '../../services/overpass_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/scheduler.dart';
import '../../services/vietnam_weather_service.dart';

// Top-level functions for compute
double _haversineDistanceCoord(LatLng from, LatLng to) {
  const R = 6371;
  final lat1 = from.latitude * pi / 180;
  final lon1 = from.longitude * pi / 180;
  final lat2 = to.latitude * pi / 180;
  final lon2 = to.longitude * pi / 180;
  final dLat = lat2 - lat1;
  final dLon = lon2 - lon1;
  final a = pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLon / 2), 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  final distance = R * c;
  return distance < 0.01 ? 0.01 : distance;
}

double _haversineDistance(String from, String to, Map<String, LatLng> cameraCoords) {
  final distance = _haversineDistanceCoord(cameraCoords[from]!, cameraCoords[to]!);
  final finalDistance = distance < 0.01 ? 0.01 : distance;
  print('Haversine distance from $from to $to: $finalDistance km at ${DateTime.now()}');
  return finalDistance;
}

List<String> _aStar(String start, String goal, Map<String, Map<String, double>> travelTimes,
    Map<String, Map<String, double>> distances, Map<String, LatLng> cameraCoords) {
  final openSet = <String>{start};
  final cameFrom = <String, String>{};
  final gScore = <String, double>{start: 0};
  final fScore = <String, double>{start: _heuristic(start, goal, distances, cameraCoords)};

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
        fScore[neighbor] = gScore[neighbor]! + _heuristic(neighbor, goal, distances, cameraCoords);
        openSet.add(neighbor);
      }
    }
  }
  return [];
}

double _heuristic(String from, String to, Map<String, Map<String, double>> distances, Map<String, LatLng> cameraCoords) {
  final dist = distances[from]?.containsKey(to) == true ? distances[from]![to]! : _haversineDistance(from, to, cameraCoords);
  return (dist / 60) * 60;
}

List<String> _reconstructPath(Map<String, String> cameFrom, String current) {
  final path = [current];
  while (cameFrom.containsKey(current)) {
    current = cameFrom[current]!;
    path.insert(0, current);
  }
  return path;
}

Map<String, Map<String, double>> _calculateTravelTimes(
    Map<String, double> density,
    Map<String, Map<String, double>> distances,
    Map<String, double> maxSpeeds) {
  final travelTimes = <String, Map<String, double>>{};

  for (var from in distances.keys) {
    travelTimes[from] = {};
    for (var to in distances[from]!.keys) {
      if (from == to) continue;

      final distance = distances[from]![to]!;
      final speed = maxSpeeds[from] ?? 40.0;
      final cameraDensity = density[from] ?? 0.0;

      final speedFactor = (1 - (cameraDensity / 100.0)).clamp(0.1, 1.0);
      final effectiveSpeed = speed * speedFactor;

      final travelTime = (distance / effectiveSpeed) * 60;
      travelTimes[from]![to] = travelTime;
    }
  }

  return travelTimes;
}

class MapModel extends ChangeNotifier {
  LatLng? _currentLocation;
  LatLng? _fromLocation;
  LatLng? _toLocation;
  final Set<Polyline> _polylines = {};
  String _selectedVehicle = 'car';
  double? _distance;
  bool _showTwoSearchBars = false;
  String _fromPlaceName = "Your Location";
  String _toPlaceName = "Select Destination";
  DateTime? _estimatedArrival;
  bool _isNavigating = false;
  double _bearing = 0;
  bool _followUser = false;
  final Set<Marker> _cameraMarkers = {};
  List<String> _shortestPath = [];
  double _totalTravelTime = 0.0;
  Map<String, double> _lastDensities = {};
  String _currentCamera = 'A';
  bool _usingLiveData = false;

  // Weather fields
  Map<String, dynamic>? _currentWeather;
  Map<String, dynamic>? _weatherForecast;
  Map<String, dynamic>? _drivingConditions;
  List<String> _weatherWarnings = [];
  final VietnamWeatherService _weatherService = VietnamWeatherService();

  final Map<String, LatLng> _cameraCoords = {
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

  Map<String, Map<String, double>>? _cameraDistances;
  Map<String, double>? _maxSpeeds;
  Map<String, double>? _savedDensities;

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
  bool get usingLiveData => _usingLiveData;
  Map<String, dynamic>? get currentWeather => _currentWeather;
  Map<String, dynamic>? get weatherForecast => _weatherForecast;
  Map<String, dynamic>? get drivingConditions => _drivingConditions;
  List<String> get weatherWarnings => _weatherWarnings;

  MapModel() {
    _init();
  }

  Future<void> _init() async {
    print('Starting MapModel initialization at ${DateTime.now()}');
    await _requestLocationPermission();
    await getCurrentLocation(setAsFrom: true);
    _loadCameraMarkers();
    await _requestStoragePermission();
    await _fetchCurrentDensities();
    await fetchWeatherData();
    print('MapModel initialization completed at ${DateTime.now()}');
    notifyListeners();
  }

  Future<void> _requestStoragePermission() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
      if (!status.isGranted) {
        print('Storage permission denied at ${DateTime.now()}');
      }
    }
  }

  @override
  void dispose() {
    _stopDensityUpdates();
    super.dispose();
  }

  Future<void> _requestLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('Location permission denied at ${DateTime.now()}');
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      print('Location permission denied forever at ${DateTime.now()}');
      return;
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
        print('Set _fromLocation to current location: $_fromLocation at ${DateTime.now()}');
      }
      _bearing = position.heading;

      if (_isNavigating) {
        await _updateCurrentCamera();
      }

      if (_currentLocation != null) {
        await fetchWeatherData();
      }

      notifyListeners();
    } catch (e) {
      print("Error getting current location: $e at ${DateTime.now()}");
    }
  }

  Future<void> _updateCurrentCamera() async {
    if (_currentLocation == null) return;

    String closestCamera = _findNearestCamera(_currentLocation!);
    if (closestCamera != _currentCamera) {
      print('User moved to camera $closestCamera from $_currentCamera at ${DateTime.now()}');
      _currentCamera = closestCamera;
      await _calculateAndFindShortestPath();
      await _fetchCurrentDensities();
      await _updatePolylinesWithDensities();
    }
  }

  Future<void> _fetchPlaceName(LatLng location, bool isFrom) async {
    try {
      final locationDetails = await GraphHopperService().getLocationDetails(
        "${location.latitude},${location.longitude}",
      );
      if (locationDetails != null) {
        if (isFrom) {
          _fromPlaceName = locationDetails['name'] ?? 'Your Location';
        } else {
          _toPlaceName = locationDetails['name'] ?? 'Select Destination';
        }
        notifyListeners();
      }
    } catch (e) {
      print("Error fetching place name: $e at ${DateTime.now()}");
    }
  }

  Future<void> getRoute() async {
    if (_fromLocation == null || _toLocation == null) {
      print('Cannot calculate route: fromLocation or toLocation is null at ${DateTime.now()}');
      return;
    }

    await _calculateAndFindShortestPath();
    notifyListeners();
  }

  void setFromLocation(LatLng location, String name) {
    _fromLocation = location;
    _fromPlaceName = name;
    _showTwoSearchBars = _toLocation != null;
    _updateCameraMarkers();
    notifyListeners();
  }

  void setToLocation(LatLng location, String name) {
    _toLocation = location;
    _toPlaceName = name;
    _showTwoSearchBars = true;
    _updateCameraMarkers();
    notifyListeners();
  }

  void setVehicle(String vehicle) {
    _selectedVehicle = vehicle;
    notifyListeners();
  }

  Future<void> toggleNavigation() async {
    _isNavigating = !_isNavigating;
    _followUser = _isNavigating;
    print('Navigation ${_isNavigating ? 'started' : 'stopped'} from $_fromLocation to $_toLocation at ${DateTime.now()}');
    if (_isNavigating && _fromLocation != null && _toLocation != null) {
      await _calculateAndFindShortestPath();
      _startDensityUpdates();
    } else {
      _shortestPath = [];
      _totalTravelTime = 0.0;
      _polylines.clear();
      _updateCameraMarkers();
      _stopDensityUpdates();
    }
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

    _cameraMarkers.clear();
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
    print('Loaded ${cameraLocations.length} camera markers (all blue) at ${DateTime.now()}');
  }

  void _updateCameraMarkers() {
    _cameraMarkers.clear();
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

    String? fromCamera = _fromLocation != null ? _findNearestCamera(_fromLocation!) : null;
    String? toCamera = _toLocation != null ? _findNearestCamera(_toLocation!) : null;

    for (var camera in cameraLocations) {
      final cameraId = camera['id'] as String;
      double hue;

      if (cameraId == fromCamera && fromCamera != null) {
        hue = BitmapDescriptor.hueGreen;
      } else if (cameraId == toCamera && toCamera != null) {
        hue = BitmapDescriptor.hueRed;
      } else {
        hue = BitmapDescriptor.hueBlue;
      }

      _cameraMarkers.add(
        Marker(
          markerId: MarkerId(cameraId),
          position: LatLng(camera['lat'] as double, camera['lng'] as double),
          infoWindow: InfoWindow(title: camera['title'] as String),
          icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        ),
      );
    }

    print('Updated camera markers: fromCamera=$fromCamera (green), toCamera=$toCamera (red), others (blue) at ${DateTime.now()}');
    notifyListeners();
  }

  String findNearestCamera(LatLng location) {
    return _findNearestCamera(location);
  }

  String _findNearestCamera(LatLng location) {
    String closestCamera = _currentCamera;
    double minDistance = double.infinity;
    _cameraCoords.forEach((id, coord) {
      final distance = _haversineDistanceCoord(location, coord);
      if (distance < minDistance) {
        minDistance = distance;
        closestCamera = id;
      }
    });
    return closestCamera;
  }

  Future<void> _calculateAndSaveCameraSpeeds() async {
    print('Starting _calculateAndSaveCameraSpeeds at ${DateTime.now()}');
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
    if (await file.exists()) {
      print('Speeds file already exists, skipping calculation at ${DateTime.now()}');
      return;
    }

    final sink = file.openWrite();
    sink.write('Camera Free Flow Speeds (Generated on ${DateTime.now()})\n\n');

    final overpassService = OverpassService();
    for (var loc in cameraLocations) {
      final latLng = LatLng(loc['lat'] as double, loc['lng'] as double);
      try {
        final speed = await overpassService.getMaxSpeed(latLng).timeout(Duration(seconds: 5));
        sink.write('Camera ${loc['id']}: ${speed != null ? speed.toStringAsFixed(2) : "40.00"} km/h\n');
      } catch (e) {
        print('Error fetching speed for ${loc['id']}: $e at ${DateTime.now()}');
        sink.write('Camera ${loc['id']}: 40.00 km/h\n');
      }
    }

    await sink.close();
    print('Speeds saved to ${file.path} at ${DateTime.now()}');
  }

  Timer? _densityUpdateTimer;

  void _startDensityUpdates() {
    _stopDensityUpdates();
    _densityUpdateTimer = Timer.periodic(Duration(seconds: 30), (timer) async {
      if (!_isNavigating) {
        timer.cancel();
        return;
      }
      print('Periodic density update triggered at ${DateTime.now()}');
      await _fetchCurrentDensities();
      await _updatePolylinesWithDensities();
      final shouldRecalculate = _shortestPath.any((camera) {
        final oldDensity = _savedDensities?[camera] ?? 0.0;
        final newDensity = _lastDensities[camera] ?? 0.0;
        return (newDensity - oldDensity).abs() > 20.0;
      });
      if (shouldRecalculate) {
        print('Significant density change detected, recalculating shortest path at ${DateTime.now()}');
        await _calculateAndFindShortestPath();
      }
    });
  }

  void _stopDensityUpdates() {
    _densityUpdateTimer?.cancel();
    _densityUpdateTimer = null;
  }

  Future<void> fetchWeatherData() async {
    try {
      print('Fetching weather data at ${DateTime.now()}');

      final location = _currentLocation;

      _currentWeather = await _weatherService.getCurrentWeather(location: location);

      _weatherForecast = await _weatherService.getWeatherForecast(location: location);

      _drivingConditions = _weatherService.getDrivingConditions(_currentWeather);

      _weatherWarnings = List<String>.from(_drivingConditions?['warnings'] ?? []);

      print('Weather data updated successfully at ${DateTime.now()}');
      notifyListeners();
    } catch (e) {
      print('Error fetching weather data: $e');
    }
  }

  bool hasWeatherWarnings() {
    return _weatherWarnings.isNotEmpty || !(_drivingConditions?['safe'] ?? true);
  }

  String getWeatherAdvice() {
    if (!hasWeatherWarnings()) return 'Thời tiết tốt cho việc di chuyển';

    if (!(_drivingConditions?['safe'] ?? true)) {
      return 'Thời tiết nguy hiểm - Nên tránh lái xe';
    }

    return _weatherWarnings.isNotEmpty ? _weatherWarnings.first : 'Cẩn thận khi lái xe';
  }

  bool willItRainDuringTrip() {
    if (_weatherForecast == null || _estimatedArrival == null) return false;

    try {
      final forecastData = _weatherForecast!['forecast'];
      if (forecastData == null) return false;

      final forecastDays = forecastData['forecastday'] as List?;
      if (forecastDays == null || forecastDays.isEmpty) return false;

      final now = DateTime.now();
      final arrival = _estimatedArrival!;

      for (var day in forecastDays) {
        final dayDate = DateTime.parse(day['date']);
        if (dayDate.day == now.day || dayDate.day == arrival.day) {
          final hours = day['hour'] as List?;
          if (hours != null) {
            for (var hour in hours) {
              final hourTime = DateTime.parse(hour['time']);
              if (hourTime.isAfter(now) && hourTime.isBefore(arrival)) {
                if (hour['will_it_rain'] == 1) {
                  return true;
                }
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error checking rain during trip: $e');
    }

    return false;
  }

  String getAirQualityStatus() {
    if (_currentWeather == null || _currentWeather!['air_quality'] == null) {
      return 'Không có dữ liệu chất lượng không khí';
    }

    final airQuality = _currentWeather!['air_quality'];
    final usEpaIndex = airQuality['us_epa_index'];
    return _weatherService.getAirQualityDescription(usEpaIndex);
  }

  Future<void> _calculateAndFindShortestPath() async {
    if (_fromLocation == null || _toLocation == null) {
      print('Cannot calculate path: fromLocation or toLocation is null at ${DateTime.now()}');
      return;
    }

    print('Starting _calculateAndFindShortestPath from $_fromPlaceName to $_toPlaceName at ${DateTime.now()}');
    final startCamera = _findNearestCamera(_fromLocation!);
    final endCamera = _findNearestCamera(_toLocation!);
    print('Nearest cameras: Start=$startCamera, End=$endCamera at ${DateTime.now()}');

    final directory = await getApplicationDocumentsDirectory();
    final speedsFile = File('${directory.path}/camera_speeds.txt');

    if (!await speedsFile.exists()) {
      print('Warning: camera_speeds.txt not found, regenerating... at ${DateTime.now()}');
      await _calculateAndSaveCameraSpeeds();
    }

    _maxSpeeds = {};
    try {
      final speedLines = await speedsFile.readAsLines();
      for (var line in speedLines) {
        if (line.contains('Camera') && line.contains(': ')) {
          final parts = line.split(': ');
          if (parts.length < 2) continue;
          final idParts = parts[0].split(' ');
          if (idParts.length < 2) continue;
          final id = idParts[1];
          final speedStr = parts[1].split(' ')[0];
          _maxSpeeds![id] = double.tryParse(speedStr) ?? 40.0;
        }
      }
      print('Loaded max speeds: $_maxSpeeds at ${DateTime.now()}');
    } catch (e) {
      print('Error reading speeds file: $e at ${DateTime.now()}');
      _maxSpeeds = {
        'A': 40.0, 'B': 40.0, 'C': 40.0, 'D': 40.0, 'E': 40.0, 'F': 40.0,
        'G': 40.0, 'H': 40.0, 'I': 40.0, 'J': 40.0, 'K': 40.0, 'L': 40.0,
      };
    }

    _cameraDistances = {};
    try {
      final distancesString = await rootBundle.loadString('assets/camera_distances.json');
      final distancesJson = jsonDecode(distancesString) as Map<String, dynamic>;

      for (var from in distancesJson.keys) {
        _cameraDistances![from] = {};
        final toDistances = distancesJson[from] as Map<String, dynamic>;
        for (var to in toDistances.keys) {
          final dist = (toDistances[to] as num).toDouble();
          _cameraDistances![from]![to] = dist > 0 ? dist : _haversineDistance(from, to, _cameraCoords);
        }
      }

      final allCameras = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L'];
      for (var from in allCameras) {
        _cameraDistances![from] ??= {};
        for (var to in allCameras) {
          if (from != to && !_cameraDistances![from]!.containsKey(to)) {
            print('Warning: No distance from $from to $to in JSON, calculating Haversine distance at ${DateTime.now()}');
            final dist = _haversineDistance(from, to, _cameraCoords);
            _cameraDistances![from]![to] = dist;
          }
        }
      }

      print('Loaded distances from camera_distances.json: $_cameraDistances at ${DateTime.now()}');
    } catch (e) {
      print('Error loading camera_distances.json: $e at ${DateTime.now()}');
      _cameraDistances = {
        'A': {'B': 1.0, 'G': 1.5, 'K': 1.8},
        'B': {'A': 1.0, 'C': 1.0, 'J': 2.5},
        'C': {'B': 1.0, 'J': 2.0},
        'D': {'E': 0.5},
        'E': {'D': 0.5},
        'F': {},
        'G': {'A': 1.5, 'J': 2.0, 'K': 1.7},
        'H': {'I': 0.5, 'K': 1.2},
        'I': {'H': 0.5, 'J': 1.0, 'L': 0.3},
        'J': {'C': 2.0, 'G': 2.0, 'I': 1.0, 'K': 0.3},
        'K': {'A': 1.8, 'G': 1.7, 'H': 1.2, 'J': 0.3, 'L': 0.1},
        'L': {'I': 0.3, 'K': 0.1},
      };
      print('Using fallback distances: $_cameraDistances at ${DateTime.now()}');
    }

    if (_lastDensities.isEmpty) {
      print('Warning: No density data available from API. Using default density for path calculation at ${DateTime.now()}');
      _lastDensities = {
        'A': 10.0, 'B': 20.0, 'C': 30.0, 'D': 40.0, 'E': 50.0, 'F': 60.0,
        'G': 70.0, 'H': 80.0, 'I': 90.0, 'J': 25.0, 'K': 35.0, 'L': 45.0,
      };
      _usingLiveData = false;
    }

    _savedDensities = Map.from(_lastDensities);
    print('Using densities for path calculation: $_savedDensities at ${DateTime.now()}');

    print('Starting shortest path calculation from $startCamera to $endCamera at ${DateTime.now()}');
    _shortestPath = [];
    _totalTravelTime = 0.0;

    final result = await compute(_calculatePath, {
      'startCamera': startCamera,
      'endCamera': endCamera,
      'distances': _cameraDistances!,
      'maxSpeeds': _maxSpeeds!,
      'densities': _savedDensities!,
      'cameraCoords': _cameraCoords,
    });

    _shortestPath = result['shortestPath'];
    _totalTravelTime = result['totalTravelTime'];
    if (_shortestPath.isEmpty) {
      print('No path found from $startCamera to $endCamera at ${DateTime.now()}');
      _totalTravelTime = 0.0;
      return;
    }

    print('Shortest Path: $_shortestPath at ${DateTime.now()}');
    print('Total travel time: $_totalTravelTime minutes at ${DateTime.now()}');

    _estimatedArrival = DateTime.now().add(Duration(minutes: _totalTravelTime.toInt()));
    await _updatePolylinesWithDensities();
    _updateCameraMarkers();

    final resultFile = File('${directory.path}/shortest_path.txt');
    try {
      final sink = resultFile.openWrite();
      sink.write('Shortest Path from $startCamera to $endCamera (Generated on ${DateTime.now()})\n\n');
      sink.write('Path: ${_shortestPath.join(" -> ")}\n');
      sink.write('Total Travel Time: ${_totalTravelTime.toStringAsFixed(2)} minutes\n');
      await sink.close();
      print('Results saved to ${resultFile.path} at ${DateTime.now()}');
      if (await resultFile.exists()) {
        print('Confirmed: shortest_path.txt exists at ${resultFile.path} at ${DateTime.now()}');
      } else {
        print('Warning: shortest_path.txt was not created at ${DateTime.now()}');
      }
    } catch (e) {
      print('Error writing shortest_path.txt: $e at ${DateTime.now()}');
    }

    SchedulerBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  Future<void> _fetchCurrentDensities() async {
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 2);
    int attempt = 0;

    while (attempt < maxRetries) {
      try {
        final url = Uri.parse('https://traffic-xkny.onrender.com/live-densities');
        print('Attempting to fetch density from $url (Attempt ${attempt + 1}/$maxRetries) at ${DateTime.now()}');
        final response = await http.get(url).timeout(Duration(seconds: 10));
        print('HTTP Response Status: ${response.statusCode} at ${DateTime.now()}');
        print('HTTP Response Body: ${response.body} at ${DateTime.now()}');

        if (response.statusCode != 200) {
          print('Failed to fetch densities: Status ${response.statusCode}, Body: ${response.body} at ${DateTime.now()}');
          throw Exception('Non-200 status code: ${response.statusCode}');
        }

        final densityJson = jsonDecode(response.body);

        _debugDensityData(densityJson);

        if (densityJson is! Map || !densityJson.containsKey('cameras')) {
          print('Error: density data does not contain "cameras" key. Got: $densityJson at ${DateTime.now()}');
          throw Exception('Invalid density data format');
        }

        Map<String, double> newDensities = {};
        bool densitiesChanged = false; // ✅ Fixed variable name
        final cameras = densityJson['cameras'] as Map<String, dynamic>;

        for (var entry in cameras.entries) {
          if (entry.key is! String) {
            print('Error: Invalid key type in cameras: ${entry.key} (expected String) at ${DateTime.now()}');
            continue;
          }

          double? value;
          String? source;
          if (entry.value is Map) {
            final cameraData = entry.value as Map<String, dynamic>;
            if (cameraData.containsKey('density') && cameraData['density'] is num) {
              value = cameraData['density'].toDouble();
            } else if (cameraData.containsKey('density') && cameraData['density'] is String) {
              value = double.tryParse(cameraData['density']);
            }
            source = cameraData['source'] as String?;
          }

          if (value == 0.0 && source == "default") {
            print('Warning: Density for ${entry.key} is 0.0 with source "default", using previous value if available at ${DateTime.now()}');
            value = _lastDensities[entry.key] ?? 15.0;
          } else if (value == null || value < 0.0) {
            print('Error: Invalid density value for key ${entry.key}: ${entry.value}, using fallback at ${DateTime.now()}');
            value = _lastDensities[entry.key] ?? 15.0;
          } else if (value == 0.0) {
            print('Warning: Density for ${entry.key} is 0.0 from API, using minimum value at ${DateTime.now()}');
            value = 5.0;
          }

          newDensities[entry.key] = value;
          final oldDensity = _lastDensities[entry.key] ?? 0.0;
          if (oldDensity != value) {
            densitiesChanged = true; // ✅ Fixed variable name
            print('Density changed for camera ${entry.key}: $oldDensity -> $value (Source: ${source ?? "unknown"}) at ${DateTime.now()}');
          }
        }

        // ✅ Add missing camera fallback logic
        final allCameraIds = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L'];
        for (String cameraId in allCameraIds) {
          if (!newDensities.containsKey(cameraId)) {
            final fallbackDensity = _lastDensities[cameraId] ?? 25.0;
            newDensities[cameraId] = fallbackDensity;
            print('Warning: Camera $cameraId missing from API response, using fallback density: $fallbackDensity at ${DateTime.now()}');
          }
        }

        print('Final densities (with fallbacks): $newDensities at ${DateTime.now()}');
        print('Loaded new densities: $newDensities at ${DateTime.now()}');
        _lastDensities = newDensities;
        _usingLiveData = true;

        if (densitiesChanged && _isNavigating) { // ✅ Fixed variable name
          await _updatePolylinesWithDensities();
        }

        SchedulerBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });
        return;
      } catch (e, stackTrace) {
        attempt++;
        print('Error fetching density on attempt $attempt: $e at ${DateTime.now()}');
        print('Stack trace: $stackTrace at ${DateTime.now()}');
        if (attempt == maxRetries) {
          print('Max retries reached. Using previous densities if available at ${DateTime.now()}');
          _usingLiveData = false;
        } else {
          print('Retrying in ${retryDelay.inSeconds} seconds... at ${DateTime.now()}');
          await Future.delayed(retryDelay);
        }
      }
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }

  void _debugDensityData(Map<String, dynamic> densityJson) {
    print('=== DENSITY DEBUG START at ${DateTime.now()} ===');
    print('Raw API Response: ${jsonEncode(densityJson)}');

    if (densityJson.containsKey('cameras')) {
      final cameras = densityJson['cameras'] as Map<String, dynamic>;
      print('Number of cameras in response: ${cameras.length}');

      cameras.forEach((key, value) {
        print('Camera $key:');
        print('  Raw value: $value');
        print('  Value type: ${value.runtimeType}');

        if (value is Map) {
          final cameraData = value as Map<String, dynamic>;
          print('  Density: ${cameraData['density']} (${cameraData['density'].runtimeType})');
          print('  Source: ${cameraData['source']}');
          print('  All keys: ${cameraData.keys.toList()}');
        }
      });
    }
    print('=== DENSITY DEBUG END ===');
  }

  Future<void> _updatePolylinesWithDensities() async {
    if (_shortestPath.isEmpty || _lastDensities.isEmpty) return;

    _polylines.clear();
    for (int i = 0; i < _shortestPath.length - 1; i++) {
      final fromCamera = _shortestPath[i];
      final toCamera = _shortestPath[i + 1];
      final fromLocation = _cameraCoords[fromCamera];
      final toLocation = _cameraCoords[toCamera];

      final density = _lastDensities[fromCamera] ?? 0.0;

      Color color;
      if (density < 33.3) {
        color = Colors.green;
      } else if (density < 66.6) {
        color = Colors.yellow;
      } else {
        color = Colors.red;
      }

      if (fromLocation != null && toLocation != null) {
        try {
          final routeData = await GraphHopperService()
              .getRoute(fromLocation, toLocation, _selectedVehicle)
              .timeout(Duration(seconds: 10));
          _polylines.add(
            Polyline(
              polylineId: PolylineId('$fromCamera-$toCamera'),
              points: routeData['points'] as List<LatLng>,
              color: color,
              width: 7,
            ),
          );
          print('Updated polyline from $fromCamera to $toCamera with density $density (Color: ${color.toString()}) at ${DateTime.now()}');
        } catch (e) {
          print('Error fetching route from $fromCamera to $toCamera: $e at ${DateTime.now()}');
          _polylines.add(
            Polyline(
              polylineId: PolylineId('$fromCamera-$toCamera'),
              points: [fromLocation, toLocation],
              color: color,
              width: 7,
            ),
          );
          print('Added fallback polyline from $fromCamera to $toCamera with density $density (Color: ${color.toString()}) at ${DateTime.now()}');
        }
      }
    }

    SchedulerBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
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
    print('Shortest path file path requested: $path at ${DateTime.now()}');
    return path;
  }

  Future<void> regenerateShortestPath() async {
    print('Regenerating shortest path at ${DateTime.now()}');
    await _fetchCurrentDensities();
    _savedDensities = Map.from(_lastDensities);
    print('Saved densities for path calculation: $_savedDensities at ${DateTime.now()}');
    await _calculateAndFindShortestPath();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }
}

Map<String, dynamic> _calculatePath(Map<String, dynamic> args) {
  final startCamera = args['startCamera'] as String;
  final endCamera = args['endCamera'] as String;
  final distances = args['distances'] as Map<String, Map<String, double>>;
  final maxSpeeds = args['maxSpeeds'] as Map<String, double>;
  final densities = args['densities'] as Map<String, double>;
  final cameraCoords = args['cameraCoords'] as Map<String, LatLng>;

  final travelTimes = _calculateTravelTimes(densities, distances, maxSpeeds);
  final shortestPath = _aStar(startCamera, endCamera, travelTimes, distances, cameraCoords);
  double totalTravelTime = 0.0;

  for (int i = 0; i < shortestPath.length - 1; i++) {
    final fromCamera = shortestPath[i];
    final toCamera = shortestPath[i + 1];
    totalTravelTime += travelTimes[fromCamera]![toCamera]!;
  }

  return {'shortestPath': shortestPath, 'totalTravelTime': totalTravelTime};
}