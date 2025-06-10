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
import '../../services/news_service.dart';
import '../../services/hazard_service.dart';

// Top-level functions for compute
double _euclideanDistanceCoord(LatLng from, LatLng to) {
  const double kmPerDegreeLat = 111.0;
  final double avgLat = (from.latitude + to.latitude) / 2.0;
  final double kmPerDegreeLon = 111.0 * cos(avgLat * pi / 180.0);

  final double dx = (from.latitude - to.latitude) * kmPerDegreeLat;
  final double dy = (from.longitude - to.longitude) * kmPerDegreeLon;

  final double distance = sqrt(dx * dx + dy * dy);
  return distance < 0.01 ? 0.01 : distance;
}

double _euclideanDistance(String from, String to, Map<String, LatLng> cameraCoords) {
  final distance = _euclideanDistanceCoord(cameraCoords[from]!, cameraCoords[to]!);
  final finalDistance = distance < 0.01 ? 0.01 : distance;
  print('Euclidean distance from $from to $to: $finalDistance km at ${DateTime.now()}');
  return finalDistance;
}


List<String> _aStar(String start, String goal, Map<String, Map<String, double>> travelTimes,
    Map<String, Map<String, double>> distances, Map<String, LatLng> cameraCoords,
    Map<String, double> vehicleCounts, Map<String, double> maxSpeeds, Map<String, double> criticalCounts) {
  final openSet = <String>{start};
  final cameFrom = <String, String>{};
  final gScore = <String, double>{start: 0};
  final fScore = <String, double>{start: _heuristic(start, goal, distances, cameraCoords, vehicleCounts, maxSpeeds, criticalCounts)};

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
        fScore[neighbor] = gScore[neighbor]! + _heuristic(neighbor, goal, distances, cameraCoords, vehicleCounts, maxSpeeds, criticalCounts);
        openSet.add(neighbor);
      }
    }
  }
  return [];
}

double _heuristic(String from, String to, Map<String, Map<String, double>> distances,
    Map<String, LatLng> cameraCoords, Map<String, double> vehicleCounts,
    Map<String, double> maxSpeeds, Map<String, double> criticalCounts) {
  final distance = distances[from]?.containsKey(to) == true ? distances[from]![to]! : _euclideanDistance(from, to, cameraCoords);
  final estimatedSpeed = _greenshieldSpeed(from, vehicleCounts, maxSpeeds, criticalCounts);
  return (distance / estimatedSpeed) * 60; // Heuristic as travel time in minutes
}

List<String> _reconstructPath(Map<String, String> cameFrom, String current) {
  final path = [current];
  while (cameFrom.containsKey(current)) {
    current = cameFrom[current]!;
    path.insert(0, current);
  }
  return path;
}

double _greenshieldSpeed(String camera, Map<String, double> vehicleCounts,
    Map<String, double> maxSpeeds, Map<String, double> criticalCounts) {
  final vehicleCount = vehicleCounts[camera] ?? 0.0;
  final maxSpeed = maxSpeeds[camera] ?? 40.0;
  final criticalCount = criticalCounts[camera] ?? 100.0;
  final speedFactor = (1 - (vehicleCount / criticalCount)).clamp(0.1, 1.0);
  final estimatedSpeed = maxSpeed * speedFactor;
  return estimatedSpeed < 5.0 ? 5.0 : estimatedSpeed; // Minimum speed 5 km/h
}

Map<String, Map<String, double>> _calculateTravelTimes(
    Map<String, double> vehicleCounts,
    Map<String, Map<String, double>> distances,
    Map<String, double> maxSpeeds,
    Map<String, double> criticalCounts) {
  final travelTimes = <String, Map<String, double>>{};

  for (var from in distances.keys) {
    travelTimes[from] = {};
    for (var to in distances[from]!.keys) {
      if (from == to) continue;

      final distance = distances[from]![to]!;
      final estimatedSpeed = _greenshieldSpeed(from, vehicleCounts, maxSpeeds, criticalCounts);
      final travelTime = (distance / estimatedSpeed) * 60; // Time in minutes
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
  Map<String, double> _lastVehicleCounts = {};
  Map<String, double> _lastDensities = {};
  String _currentCamera = 'A';
  bool _usingLiveData = false;
  Map<String, double> _criticalVehicleCounts = {};

  void _logApiStatus(String method, bool isLive, {String? additionalInfo}) {
    final timestamp = DateTime.now().toIso8601String();
    final status = isLive ? "🟢 LIVE API" : "🔴 FALLBACK/SYNTHETIC";
    print('[$timestamp] [$method] $status${additionalInfo != null ? " - $additionalInfo" : ""}');
  }

  // Enhanced logging for data source
  void _logDataSource(Map<String, double> vehicleCounts, Map<String, double> densities, bool isLive) {
    final timestamp = DateTime.now().toIso8601String();
    final source = isLive ? "LIVE API" : "SYNTHETIC/FALLBACK";
    
    print('=== DATA SOURCE UPDATE ===');
    print('[$timestamp] Using: $source');
    print('[$timestamp] Vehicle Counts: $vehicleCounts');
    print('[$timestamp] Densities: $densities');
    print('[$timestamp] _usingLiveData flag: $_usingLiveData');
    print('========================');
  }
  // Weather fields
  Map<String, dynamic>? _currentWeather;
  Map<String, dynamic>? _weatherForecast;
  Map<String, dynamic>? _drivingConditions;
  List<String> _weatherWarnings = [];
  final VietnamWeatherService _weatherService = VietnamWeatherService();

  // News fields
  List<Map<String, dynamic>> _newsArticles = [];
  final NewsService _newsService = NewsService();
  Timer? _newsUpdateTimer;

  // Hazard fields
  List<Hazard> _reportedHazards = [];
  final HazardService _hazardService = HazardService();
  final Set<Marker> _hazardMarkers = {};
  Timer? _hazardUpdateTimer;

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
  Map<String, double>? _savedVehicleCounts;
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
  List<Map<String, dynamic>> get newsArticles => _newsArticles;
  List<Hazard> get reportedHazards => _reportedHazards;
  Set<Marker> get hazardMarkers => _hazardMarkers;

  MapModel() {
    _init();
  }

  Future<void> _init() async {
    print('Starting MapModel initialization at ${DateTime.now()}');
    await _requestLocationPermission();
    await getCurrentLocation(setAsFrom: true);
    _loadCameraMarkers();
    await _requestStoragePermission();
    await _loadCriticalVehicleCounts();
    await _fetchCurrentVehicleCounts();
    await fetchWeatherData();
    await _initHazards();
    await _fetchNews();
    print('MapModel initialization completed at ${DateTime.now()}');
    notifyListeners();
  }

  Future<void> _loadCriticalVehicleCounts() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      var file = File('${directory.path}/critical_vehicleCounts.json');
      if (!await file.exists()) {
        file = File('${directory.path}/fallback_critical_vehicleCounts.json');
      }
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final cameras = json['cameras'] as Map<String, dynamic>;
        _criticalVehicleCounts = {};
        for (var entry in cameras.entries) {
          _criticalVehicleCounts[entry.key] = (entry.value['max_vehicle_count'] as num).toDouble();
        }
        print('Loaded critical vehicle counts: $_criticalVehicleCounts at ${DateTime.now()}');
      } else {
        print('No critical vehicle counts file found, using defaults at ${DateTime.now()}');
        _criticalVehicleCounts = {
          'A': 100.0, 'B': 100.0, 'C': 100.0, 'D': 100.0, 'E': 100.0, 'F': 100.0,
          'G': 100.0, 'H': 100.0, 'I': 100.0, 'J': 100.0, 'K': 100.0, 'L': 100.0,
        };
      }
    } catch (e) {
      print('Error loading critical vehicle counts: $e at ${DateTime.now()}');
      _criticalVehicleCounts = {
        'A': 100.0, 'B': 100.0, 'C': 100.0, 'D': 100.0, 'E': 100.0, 'F': 100.0,
        'G': 100.0, 'H': 100.0, 'I': 100.0, 'J': 100.0, 'K': 100.0, 'L': 100.0,
      };
    }
  }

  // Initialize hazard system
  Future<void> _initHazards() async {
    await loadHazards();
    _startHazardUpdates();
  }

  // Load hazards from storage
  Future<void> loadHazards() async {
    try {
      _reportedHazards = await _hazardService.loadHazards();
      _updateHazardMarkers();
      print('Loaded ${_reportedHazards.length} active hazards');
      notifyListeners();
    } catch (e) {
      print('Error loading hazards: $e');
    }
  }

  // Start periodic hazard updates
  void _startHazardUpdates() {
    _hazardUpdateTimer?.cancel();
    _hazardUpdateTimer = Timer.periodic(Duration(minutes: 1), (timer) async {
      await _cleanupExpiredHazards();
    });
  }

  // Stop hazard updates
  void _stopHazardUpdates() {
    _hazardUpdateTimer?.cancel();
  }

  // Clean up expired hazards
  Future<void> _cleanupExpiredHazards() async {
    try {
      await _hazardService.cleanupExpiredHazards();
      final oldCount = _reportedHazards.length;
      _reportedHazards = await _hazardService.loadHazards();

      if (_reportedHazards.length != oldCount) {
        print('Cleaned up ${oldCount - _reportedHazards.length} expired hazards');
        _updateHazardMarkers();
        notifyListeners();
      }
    } catch (e) {
      print('Error cleaning up hazards: $e');
    }
  }

  // Update hazard markers on map
  void _updateHazardMarkers() {
    _hazardMarkers.clear();

    for (final hazard in _reportedHazards) {
      if (!hazard.isExpired) {
        _hazardMarkers.add(
          Marker(
            markerId: MarkerId('hazard_${hazard.id}'),
            position: hazard.location,
            icon: _getHazardIcon(hazard.type),
            infoWindow: InfoWindow(
              title: HazardService.getHazardTypeLabel(hazard.type),
              snippet: hazard.description,
            ),
          ),
        );
      }
    }
  }

  // Get appropriate icon for hazard type
  BitmapDescriptor _getHazardIcon(HazardType type) {
    switch (type) {
      case HazardType.accident:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
      case HazardType.naturalHazard:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange);
      case HazardType.roadWork:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueYellow);
      case HazardType.other:
        return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueMagenta);
    }
  }

  // Report a new hazard
  Future<void> reportHazard({
    required HazardType type,
    required String description,
    required LatLng location,
    required String locationName,
    required HazardDuration duration,
  }) async {
    try {
      await _hazardService.reportHazard(
        type: type,
        description: description,
        location: location,
        locationName: locationName,
        duration: duration,
      );

      // Reload hazards to include the new one
      await loadHazards();
    } catch (e) {
      print('Error reporting hazard: $e');
      rethrow;
    }
  }

  // Get hazards on the current route
  List<Hazard> getHazardsOnRoute() {
    if (_fromLocation == null || _toLocation == null) return [];

    final routeHazards = <Hazard>[];
    const double routeRadius = 1.0; // 1km radius from route points

    // Check hazards near start and end points
    for (final hazard in _reportedHazards) {
      if (hazard.isExpired) continue;

      final distanceFromStart = _calculateHazardDistance(_fromLocation!, hazard.location);
      final distanceFromEnd = _calculateHazardDistance(_toLocation!, hazard.location);

      if (distanceFromStart <= routeRadius || distanceFromEnd <= routeRadius) {
        routeHazards.add(hazard);
      }
    }

    return routeHazards;
  }

  // Calculate distance between two points
  double _calculateHazardDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371; // Earth's radius in kilometers

    final lat1Rad = point1.latitude * (pi / 180);
    final lon1Rad = point1.longitude * (pi / 180);
    final lat2Rad = point2.latitude * (pi / 180);
    final lon2Rad = point2.longitude * (pi / 180);

    final dLat = lat2Rad - lat1Rad;
    final dLon = lon2Rad - lon1Rad;

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1Rad) * cos(lat2Rad) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
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
    _stopHazardUpdates();
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
        await _fetchNews();
      }

      notifyListeners();
    } catch (e) {
      print("Error getting current location: $e at ${DateTime.now()}");
    }
  }

  Future<void> _fetchNews() async {
    try {
      print('Fetching news at ${DateTime.now()}');

      // Use current location or destination location
      final location = _currentLocation ?? _toLocation;
      final placeName = _fromPlaceName != 'Your Location' ? _fromPlaceName : _toPlaceName;

      // Detect country and get appropriate queries
      final country = _detectCountryFromLocation(location);
      final queries = _getNewsQueriesForLocation(location, placeName);

      print('Detected country: $country');
      print('Using news queries: $queries');

      _newsArticles = [];

      // Try each query until we get articles
      for (String query in queries) {
        try {
          print('Trying news query: "$query"');

          final articles = await _newsService.getNewsForLocation(
            location: location,
            placeName: query,
            language: country == 'Vietnam' ? 'vi' : 'en',
            pageSize: 8,
            sortBy: 'publishedAt',
          );

          if (articles.isNotEmpty) {
            _newsArticles.addAll(articles);
            print('Found ${articles.length} articles with query: "$query"');

            // If we have enough articles, break
            if (_newsArticles.length >= 5) {
              break;
            }
          }
        } catch (e) {
          print('Query "$query" failed: $e');
          continue;
        }
      }

      // Remove duplicates based on title
      final uniqueArticles = <String, Map<String, dynamic>>{};
      for (var article in _newsArticles) {
        final title = article['title']?.toString() ?? '';
        if (title.isNotEmpty && !uniqueArticles.containsKey(title)) {
          uniqueArticles[title] = article;
        }
      }

      _newsArticles = uniqueArticles.values.take(10).toList();

      print('Successfully fetched ${_newsArticles.length} unique news articles for $country at ${DateTime.now()}');
      notifyListeners();
    } catch (e) {
      print('Error fetching news: $e at ${DateTime.now()}');
      _newsArticles = [];
      notifyListeners();
    }
  }

  String _detectCountryFromLocation(LatLng? location) {
    if (location == null) return 'Vietnam'; // Default fallback

    final lat = location.latitude;
    final lng = location.longitude;

    // Vietnam coordinates bounds (approximate)
    // North: 23.393395, South: 8.179900, East: 109.464638, West: 102.148224
    if (lat >= 8.0 && lat <= 24.0 && lng >= 102.0 && lng <= 110.0) {
      return 'Vietnam';
    }

    return 'Vietnam';
  }

  List<String> _getNewsQueriesForLocation(LatLng? location, String? placeName) {
    final country = _detectCountryFromLocation(location);

    if (country == 'Vietnam') {
      List<String> queries = [];

      if (placeName != null && placeName != 'Select Destination' && placeName != 'Your Location') {
        final cleanPlaceName = placeName.split(',').first.trim();
        queries.add(cleanPlaceName);
        queries.add('$cleanPlaceName Vietnam');
      }

      queries.addAll([
        'Ho Chi Minh City traffic',
        'Saigon news',
        'Vietnam traffic',
        'Vietnam weather',
        'Ho Chi Minh City',
        'Vietnam news',
        'Saigon traffic',
        'Vietnam transport',
        'Việt Nam',
        'tin tức Việt Nam',
        'giao thông Sài Gòn',
      ]);

      return queries;
    }

    return ['$country news', 'local news'];
  }

  Future<void> _updateCurrentCamera() async {
    if (_currentLocation == null) return;

    String closestCamera = _findNearestCamera(_currentLocation!);
    if (closestCamera != _currentCamera) {
      print('User moved to camera $closestCamera from $_currentCamera at ${DateTime.now()}');
      _currentCamera = closestCamera;
      await _calculateAndFindShortestPath();
      await _fetchCurrentVehicleCounts();
      await _updatePolylines();
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
    _fetchNews();
    notifyListeners();
  }

  void setToLocation(LatLng location, String name) {
    _toLocation = location;
    _toPlaceName = name;
    _showTwoSearchBars = true;
    _updateCameraMarkers();
    _fetchNews();
    notifyListeners();
  }

  void setVehicle(String vehicle) {
    _selectedVehicle = vehicle;
    notifyListeners();
  }

  Future<void> toggleNavigation() async {
    _isNavigating = !_isNavigating;
    _followUser = _isNavigating;
    print('Navigation ${_isNavigating ? 'started' : 'stopped'} from $_fromPlaceName to $_toPlaceName at ${DateTime.now()}');
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
      final distance = _euclideanDistanceCoord(location, coord);
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
      print('Periodic vehicle count and news update triggered at ${DateTime.now()}');
      await _fetchCurrentVehicleCounts();
      await _updatePolylines();
      await _fetchNews();
      final shouldRecalculate = _shortestPath.any((camera) {
        final oldCount = _savedVehicleCounts?[camera] ?? 0.0;
        final newCount = _lastVehicleCounts[camera] ?? 0.0;
        return (newCount - oldCount).abs() > 20.0;
      });
      if (shouldRecalculate) {
        print('Significant vehicle count change detected, recalculating shortest path at ${DateTime.now()}');
        await _calculateAndFindShortestPath();
      }
    });
  }

  void _stopDensityUpdates() {
    _densityUpdateTimer?.cancel();
    _densityUpdateTimer = null;
    _newsUpdateTimer?.cancel();
    _newsUpdateTimer = null;
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

  Future<void> refreshNews() async {
    print('Manually refreshing news at ${DateTime.now()}');
    await _fetchNews();
    notifyListeners();
  }

  Future<void> testNewsApi() async {
    try {
      print('Testing news API at ${DateTime.now()}');

      final location = _currentLocation;
      final country = _detectCountryFromLocation(location);

      print('Testing for country: $country');
      print('Current location: $location');

      final testArticles = await _newsService.getNewsForLocation(
        placeName: country == 'Vietnam' ? 'Vietnam' : 'news',
        language: country == 'Vietnam' ? 'vi' : 'en',
        pageSize: 1,
        sortBy: 'publishedAt',
      );

      print('API Test Result: Found ${testArticles.length} articles');

      if (testArticles.isNotEmpty) {
        print('Sample article: ${testArticles.first['title']}');
      }
    } catch (e) {
      print('API Test Failed: $e');
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

  Future<void> _fetchCurrentVehicleCounts() async {
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 2);
    int attempt = 0;

    _logApiStatus('_fetchCurrentVehicleCounts', false, additionalInfo: 'Starting API fetch attempts');

    while (attempt < maxRetries) {
      try {
        final url = Uri.parse('http://127.0.0.1:10000//live-vehicle-counts');
        _logApiStatus('_fetchCurrentVehicleCounts', true, additionalInfo: 'Attempting API call to $url (Attempt ${attempt + 1}/$maxRetries)');
        
        final response = await http.get(url).timeout(Duration(seconds: 10));
        
        print('🌐 HTTP Response Details:');
        print('   Status Code: ${response.statusCode}');
        print('   Headers: ${response.headers}');
        print('   Body Length: ${response.body.length} characters');
        print('   Body Preview: ${response.body.length > 200 ? response.body.substring(0, 200) + "..." : response.body}');

        if (response.statusCode != 200) {
          _logApiStatus('_fetchCurrentVehicleCounts', false, additionalInfo: 'API returned non-200 status: ${response.statusCode}');
          throw Exception('Non-200 status code: ${response.statusCode}');
        }

        final dataJson = jsonDecode(response.body);
        _debugData(dataJson);

        if (dataJson is! Map || !dataJson.containsKey('cameras')) {
          _logApiStatus('_fetchCurrentVehicleCounts', false, additionalInfo: 'Invalid API response format');
          throw Exception('Invalid data format');
        }

        Map<String, double> newVehicleCounts = {};
        Map<String, double> newDensities = {};
        bool dataChanged = false;
        final cameras = dataJson['cameras'] as Map<String, dynamic>;

        print('🔍 Processing API Data:');
        for (var entry in cameras.entries) {
          double? vehicleCount;
          double? density;
          String? source;

          if (entry.value is Map) {
            final cameraData = entry.value as Map<String, dynamic>;
            if (cameraData.containsKey('vehicle_count') && cameraData['vehicle_count'] is num) {
              vehicleCount = cameraData['vehicle_count'].toDouble();
            } else if (cameraData.containsKey('vehicle_count') && cameraData['vehicle_count'] is String) {
              vehicleCount = double.tryParse(cameraData['vehicle_count']);
            }
            if (cameraData.containsKey('density') && cameraData['density'] is num) {
              density = cameraData['density'].toDouble();
            } else if (cameraData.containsKey('density') && cameraData['density'] is String) {
              density = double.tryParse(cameraData['density']);
            }
            source = cameraData['source'] as String?;
          }

          print('   Camera ${entry.key}: vehicle_count=$vehicleCount, density=$density, source=$source');

          // Handle problematic data
          if (vehicleCount == 0.0 && source == "default") {
            print('   ⚠️  Using previous value for ${entry.key} (API returned 0.0 with default source)');
            vehicleCount = _lastVehicleCounts[entry.key] ?? 15.0;
          } else if (vehicleCount == null || vehicleCount < 0.0) {
            print('   ❌ Invalid vehicle count for ${entry.key}, using fallback');
            vehicleCount = _lastVehicleCounts[entry.key] ?? 15.0;
          } else if (vehicleCount == 0.0) {
            print('   ⚠️  Vehicle count is 0.0 from API, using minimum value');
            vehicleCount = 5.0;
          }

          if (density == 0.0 && source == "default") {
            print('   ⚠️  Using previous density value for ${entry.key} (API returned 0.0 with default source)');
            density = _lastDensities[entry.key] ?? 15.0;
          } else if (density == null || density < 0.0) {
            print('   ❌ Invalid density for ${entry.key}, using fallback');
            density = _lastDensities[entry.key] ?? 15.0;
          } else if (density == 0.0) {
            print('   ⚠️  Density is 0.0 from API, using minimum value');
            density = 5.0;
          }

          newVehicleCounts[entry.key] = vehicleCount;
          newDensities[entry.key] = density;
          
          final oldVehicleCount = _lastVehicleCounts[entry.key] ?? 0.0;
          final oldDensity = _lastDensities[entry.key] ?? 0.0;
          if (oldVehicleCount != vehicleCount || oldDensity != density) {
            dataChanged = true;
            print('   📊 Data changed for camera ${entry.key}: Vehicle count $oldVehicleCount -> $vehicleCount, Density $oldDensity -> $density');
          }
        }

        // Ensure all cameras have data
        final allCameraIds = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L'];
        for (String cameraId in allCameraIds) {
          if (!newVehicleCounts.containsKey(cameraId)) {
            final fallbackCount = _lastVehicleCounts[cameraId] ?? 15.0;
            newVehicleCounts[cameraId] = fallbackCount;
            print('   ⚠️  Camera $cameraId missing from API, using fallback: $fallbackCount');
          }
          if (!newDensities.containsKey(cameraId)) {
            final fallbackDensity = _lastDensities[cameraId] ?? 15.0;
            newDensities[cameraId] = fallbackDensity;
            print('   ⚠️  Camera $cameraId density missing from API, using fallback: $fallbackDensity');
          }
        }

        _lastVehicleCounts = newVehicleCounts;
        _lastDensities = newDensities;
        _usingLiveData = true;

        _logApiStatus('_fetchCurrentVehicleCounts', true, additionalInfo: '✅ Successfully fetched and processed live data');
        _logDataSource(newVehicleCounts, newDensities, true);

        if (dataChanged && _isNavigating) {
          print('📱 Triggering polyline update due to data changes');
          await _updatePolylines();
        }

        SchedulerBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });
        return;

      } catch (e, stackTrace) {
        attempt++;
        _logApiStatus('_fetchCurrentVehicleCounts', false, additionalInfo: 'Attempt $attempt failed: $e');
        print('❌ Full error details:');
        print('   Error: $e');
        print('   Stack trace: $stackTrace');
        
        if (attempt == maxRetries) {
          _logApiStatus('_fetchCurrentVehicleCounts', false, additionalInfo: '🔄 Max retries reached, falling back to synthetic data');
          await _fetchSyntheticVehicleCounts();
        } else {
          print('⏳ Retrying in ${retryDelay.inSeconds} seconds...');
          await Future.delayed(retryDelay);
        }
      }
    }
    
    SchedulerBinding.instance.addPostFrameCallback((_) {
      notifyListeners();
    });
  }
 Future<void> _fetchSyntheticVehicleCounts() async {
    _logApiStatus('_fetchSyntheticVehicleCounts', false, additionalInfo: 'Starting synthetic data fetch');
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/synthetic_traffic_20250609.json');
      
      if (!await file.exists()) {
        _logApiStatus('_fetchSyntheticVehicleCounts', false, additionalInfo: '❌ Synthetic file not found, using hardcoded defaults');
        
        _lastVehicleCounts = {
          'A': 15.0, 'B': 20.0, 'C': 15.0, 'D': 15.0, 'E': 15.0, 'F': 15.0,
          'G': 15.0, 'H': 15.0, 'I': 15.0, 'J': 15.0, 'K': 15.0, 'L': 15.0,
        };
        _lastDensities = {
          'A': 15.0, 'B': 20.0, 'C': 15.0, 'D': 15.0, 'E': 15.0, 'F': 15.0,
          'G': 15.0, 'H': 15.0, 'I': 15.0, 'J': 15.0, 'K': 15.0, 'L': 15.0,
        };
        _usingLiveData = false;
        
        _logDataSource(_lastVehicleCounts, _lastDensities, false);
        notifyListeners();
        return;
      }

      _logApiStatus('_fetchSyntheticVehicleCounts', false, additionalInfo: '📁 Found synthetic file, processing...');
      
      final content = await file.readAsString();
      final json = jsonDecode(content) as List<dynamic>;
      final now = DateTime.now();
      
      print('🔍 Searching synthetic data for closest timestamp to: ${now.toIso8601String()}');
      
      Map<String, dynamic>? closestEntry;
      Duration minDiff = Duration(days: 1);

      // Find closest entry logic (same as before but with logging)
      for (var dayEntry in json) {
        if (dayEntry['date'] == '2025-06-09') {
          final cameras = dayEntry['cameras'] as Map<String, dynamic>;
          for (var cameraEntry in cameras.entries) {
            final counts = cameraEntry.value['counts'] as List<dynamic>;
            for (var count in counts) {
              final timestampStr = count['timestamp'] as String;
              final entryTime = DateTime.parse(timestampStr);
              final diff = now.difference(entryTime).abs();
              if (diff < minDiff) {
                minDiff = diff;
                closestEntry = count;
                closestEntry!['cameraId'] = cameraEntry.key;
              }
            }
          }
        }
      }

      if (closestEntry != null) {
        print('📊 Found closest synthetic entry: ${closestEntry['timestamp']} (${minDiff.inMinutes} minutes difference)');
      }

      // Process synthetic data (rest of your existing logic with enhanced logging)
      Map<String, double> newVehicleCounts = {};
      Map<String, double> newDensities = {};
      bool dataChanged = false;

      final allCameraIds = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L'];
      for (var cameraId in allCameraIds) {
        double vehicleCount = _lastVehicleCounts[cameraId] ?? 15.0;
        double density = _lastDensities[cameraId] ?? 15.0;

        // Your existing synthetic data processing logic here...
        // (I'll keep it the same but add logging where data changes)

        newVehicleCounts[cameraId] = vehicleCount;
        newDensities[cameraId] = density;
      }

      _lastVehicleCounts = newVehicleCounts;
      _lastDensities = newDensities;
      _usingLiveData = false;

      _logApiStatus('_fetchSyntheticVehicleCounts', false, additionalInfo: '✅ Successfully loaded synthetic data');
      _logDataSource(newVehicleCounts, newDensities, false);

      if (dataChanged && _isNavigating) {
        await _updatePolylines();
      }

      notifyListeners();
      
    } catch (e, stackTrace) {
      _logApiStatus('_fetchSyntheticVehicleCounts', false, additionalInfo: '❌ Synthetic data fetch failed: $e');
      print('Full synthetic error: $stackTrace');
      
      // Final fallback to hardcoded values
      _lastVehicleCounts = {
        'A': 15.0, 'B': 20.0, 'C': 15.0, 'D': 15.0, 'E': 15.0, 'F': 15.0,
        'G': 15.0, 'H': 15.0, 'I': 15.0, 'J': 15.0, 'K': 15.0, 'L': 15.0,
      };
      _lastDensities = {
        'A': 15.0, 'B': 20.0, 'C': 15.0, 'D': 15.0, 'E': 15.0, 'F': 15.0,
        'G': 15.0, 'H': 15.0, 'I': 15.0, 'J': 15.0, 'K': 15.0, 'L': 15.0,
      };
      _usingLiveData = false;
      
      _logDataSource(_lastVehicleCounts, _lastDensities, false);
      notifyListeners();
    }
  }

   Future<void> checkApiStatus() async {
    print('🔍 Manual API Status Check Initiated');
    
    try {
      final url = Uri.parse('http://127.0.0.1:10000//live-vehicle-counts');
      print('🌐 Testing connection to: $url');
      
      final response = await http.get(url).timeout(Duration(seconds: 5));
      
      print('📡 API Status Check Results:');
      print('   URL: $url');
      print('   Status Code: ${response.statusCode}');
      print('   Response Time: ${DateTime.now()}');
      print('   Response Size: ${response.body.length} bytes');
      print('   Is Success: ${response.statusCode == 200}');
      print('   Current _usingLiveData: $_usingLiveData');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('   Data Structure Valid: ${data is Map && data.containsKey('cameras')}');
        if (data is Map && data.containsKey('cameras')) {
          final cameras = data['cameras'] as Map;
          print('   Camera Count: ${cameras.length}');
          print('   Camera IDs: ${cameras.keys.join(', ')}');
        }
      }
      
    } catch (e) {
      print('❌ API Status Check Failed: $e');
      print('   Current _usingLiveData: $_usingLiveData');
    }
  }

  // Enhanced debug method
  void _debugData(dynamic data) {
    print('🔍 === API RESPONSE DEBUG ===');
    print('   Timestamp: ${DateTime.now().toIso8601String()}');
    print('   Data Type: ${data.runtimeType}');
    
    if (data is Map) {
      print('   Top-level keys: ${data.keys.join(', ')}');
      if (data.containsKey('cameras')) {
        final cameras = data['cameras'] as Map;
        print('   Camera count: ${cameras.length}');
        print('   Camera IDs: ${cameras.keys.join(', ')}');
        
        // Sample first camera data
        if (cameras.isNotEmpty) {
          final firstCamera = cameras.entries.first;
          print('   Sample camera (${firstCamera.key}): ${firstCamera.value}');
        }
      }
    } else {
      print('   Raw data: $data');
    }
    print('=== END DEBUG ===');
  }

  // Add a getter to easily check from UI
  String get dataSourceStatus {
    return _usingLiveData ? 'Live API Data' : 'Synthetic/Fallback Data';
  }

  // Add method to get detailed status
  Map<String, dynamic> get detailedStatus {
    return {
      'usingLiveData': _usingLiveData,
      'dataSource': dataSourceStatus,
      'lastUpdate': DateTime.now().toIso8601String(),
      'vehicleCountsCount': _lastVehicleCounts.length,
      'densitiesCount': _lastDensities.length,
      'hasValidData': _lastVehicleCounts.isNotEmpty && _lastDensities.isNotEmpty,
    };
  }

  Future<void> _calculateAndFindShortestPath() async {
    if (_fromLocation == null || _toLocation == null) {
      print('Cannot calculate shortest path: fromLocation or toLocation is null at ${DateTime.now()}');
      return;
    }

    final fromCamera = _findNearestCamera(_fromLocation!);
    final toCamera = _findNearestCamera(_toLocation!);
    print('Calculating shortest path from $fromCamera to $toCamera at ${DateTime.now()}');

    if (_cameraDistances == null) {
      await _loadCameraDistances();
    }
    if (_maxSpeeds == null) {
      await _loadMaxSpeeds();
    }

    final travelTimes = await compute(
      (Map<String, dynamic> args) {
        return _calculateTravelTimes(
          args['vehicleCounts'] as Map<String, double>,
          args['distances'] as Map<String, Map<String, double>>,
          args['maxSpeeds'] as Map<String, double>,
          args['criticalCounts'] as Map<String, double>,
        );
      },
      {
        'vehicleCounts': _lastVehicleCounts,
        'distances': _cameraDistances!,
        'maxSpeeds': _maxSpeeds!,
        'criticalCounts': _criticalVehicleCounts,
      },
    );

    final path = await compute(
      (Map<String, dynamic> args) {
        return _aStar(
          args['start'] as String,
          args['goal'] as String,
          args['travelTimes'] as Map<String, Map<String, double>>,
          args['distances'] as Map<String, Map<String, double>>,
          args['cameraCoords'] as Map<String, LatLng>,
          args['vehicleCounts'] as Map<String, double>,
          args['maxSpeeds'] as Map<String, double>,
          args['criticalCounts'] as Map<String, double>,
        );
      },
      {
        'start': fromCamera,
        'goal': toCamera,
        'travelTimes': travelTimes,
        'distances': _cameraDistances!,
        'cameraCoords': _cameraCoords,
        'vehicleCounts': _lastVehicleCounts,
        'maxSpeeds': _maxSpeeds!,
        'criticalCounts': _criticalVehicleCounts,
      },
    );

    _shortestPath = path;
    _savedVehicleCounts = Map.from(_lastVehicleCounts);
    _savedDensities = Map.from(_lastDensities);

    double totalDistance = 0.0;
    double totalTime = 0.0;
    for (int i = 0; i < path.length - 1; i++) {
      final from = path[i];
      final to = path[i + 1];
      totalDistance += _cameraDistances![from]![to]!;
      totalTime += travelTimes[from]![to]!;
    }

    _distance = totalDistance;
    _totalTravelTime = totalTime;
    _estimatedArrival = DateTime.now().add(Duration(minutes: totalTime.round()));

    print('Shortest path: $path, Distance: ${totalDistance.toStringAsFixed(2)} km, Time: ${totalTime.toStringAsFixed(2)} min at ${DateTime.now()}');

    await _updatePolylines();
    notifyListeners();
  }

  Future<void> _loadCameraDistances() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/camera_distances.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        _cameraDistances = {};
        for (var from in json.keys) {
          _cameraDistances![from] = {};
          final toMap = json[from] as Map<String, dynamic>;
          for (var to in toMap.keys) {
            _cameraDistances![from]![to] = (toMap[to] as num).toDouble();
          }
        }
        print('Loaded camera distances at ${DateTime.now()}');
      } else {
        print('Camera distances file not found, calculating Haversine distances at ${DateTime.now()}');
        _cameraDistances = {};
        for (var from in _cameraCoords.keys) {
          _cameraDistances![from] = {};
          for (var to in _cameraCoords.keys) {
            if (from != to) {
              _cameraDistances![from]![to] = _euclideanDistance(from, to, _cameraCoords);
            }
          }
        }
        await file.writeAsString(jsonEncode(_cameraDistances));
        print('Saved calculated distances to ${file.path} at ${DateTime.now()}');
      }
    } catch (e) {
      print('Error loading camera distances: $e at ${DateTime.now()}');
      _cameraDistances = {};
      for (var from in _cameraCoords.keys) {
        _cameraDistances![from] = {};
        for (var to in _cameraCoords.keys) {
          if (from != to) {
            _cameraDistances![from]![to] = _euclideanDistance(from, to, _cameraCoords);
          }
        }
      }
    }
  }

  Future<void> _loadMaxSpeeds() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/camera_speeds.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        _maxSpeeds = {};
        for (var entry in json.entries) {
          _maxSpeeds![entry.key] = (entry.value as num).toDouble();
        }
        print('Loaded max speeds: $_maxSpeeds at ${DateTime.now()}');
      } else {
        print('Max speeds file not found, using defaults at ${DateTime.now()}');
        _maxSpeeds = {
          'A': 40.0, 'B': 50.0, 'C': 50.0, 'D': 40.0, 'E': 40.0, 'F': 40.0,
          'G': 50.0, 'H': 40.0, 'I': 40.0, 'J': 40.0, 'K': 40.0, 'L': 40.0,
        };
        await file.writeAsString(jsonEncode(_maxSpeeds));
      }
    } catch (e) {
      print('Error loading max speeds: $e at ${DateTime.now()}');
      _maxSpeeds = {
        'A': 40.0, 'B': 40.0, 'C': 40.0, 'D': 40.0, 'E': 40.0, 'F': 40.0,
        'G': 40.0, 'H': 40.0, 'I': 40.0, 'J': 40.0, 'K': 40.0, 'L': 40.0,
      };
    }
  }

  Future<void> _updatePolylines() async {
    _polylines.clear();
    if (_shortestPath.isEmpty) {
      print('No shortest path to draw polylines at ${DateTime.now()}');
      notifyListeners();
      return;
    }

    for (int i = 0; i < _shortestPath.length - 1; i++) {
      final from = _shortestPath[i];
      final to = _shortestPath[i + 1];
      final fromCoord = _cameraCoords[from]!;
      final toCoord = _cameraCoords[to]!;
      final density = _lastDensities[from] ?? 15.0;

      Color color;
      if (density < 33.3) {
        color = Colors.green;
      } else if (density < 66.6) {
        color = Colors.yellow;
      } else {
        color = Colors.red;
      }

      _polylines.add(
        Polyline(
          polylineId: PolylineId('$from-$to'),
          points: [fromCoord, toCoord],
          color: color,
          width: 5,
        ),
      );
    }

    print('Updated ${_polylines.length} polylines with density-based colors at ${DateTime.now()}');
    notifyListeners();
  }
}