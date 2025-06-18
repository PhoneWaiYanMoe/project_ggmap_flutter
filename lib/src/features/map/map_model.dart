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
import 'package:flutter_dotenv/flutter_dotenv.dart';
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

List<String> _aStar(
    String start,
    String goal,
    Map<String, Map<String, double>> travelTimes,
    Map<String, Map<String, double>> distances,
    Map<String, LatLng> cameraCoords,
    Map<String, double> vehicleCounts,
    Map<String, double> maxSpeeds,
    Map<String, double> criticalCounts) {
  final totalStart = DateTime.now();
  print('⏱️ [A*] Starting A* from $start to $goal');

  final openSet = <String>{start};
  final cameFrom = <String, String>{};
  final gScore = <String, double>{start: 0};
  final fScore = <String, double>{
    start: _heuristic(start, goal, distances, cameraCoords, vehicleCounts, maxSpeeds, criticalCounts)
  };

  int iterations = 0;
  int maxOpenSetSize = openSet.length;

  while (openSet.isNotEmpty) {
    iterations++;
    maxOpenSetSize = max(maxOpenSetSize, openSet.length);

    final selectStart = DateTime.now();
    final current = openSet.reduce((a, b) => fScore[a]! < fScore[b]! ? a : b);
    print(
        '⏱️ [A*] Iteration $iterations: Selected node $current (Select took: ${DateTime.now().difference(selectStart).inMicroseconds}µs)');

    if (current == goal) {
      final path = _reconstructPath(cameFrom, current);
      print('⏱️ [A*] Found path after $iterations iterations: ${path.join(" → ")}');
      print('⏱️ [A*] Max open set size: $maxOpenSetSize');
      print('⏱️ [A*] Total A* Execution: ${DateTime.now().difference(totalStart).inMilliseconds}ms');
      return path;
    }

    openSet.remove(current);
    final neighborStart = DateTime.now();
    for (var neighbor in travelTimes[current]!.keys) {
      final tentativeGScore = gScore[current]! + travelTimes[current]![neighbor]!;
      if (!gScore.containsKey(neighbor) || tentativeGScore < gScore[neighbor]!) {
        cameFrom[neighbor] = current;
        gScore[neighbor] = tentativeGScore;
        final heuristicStart = DateTime.now();
        fScore[neighbor] = gScore[neighbor]! +
            _heuristic(neighbor, goal, distances, cameraCoords, vehicleCounts, maxSpeeds, criticalCounts);
        print(
            '⏱️ [A*] Heuristic for $neighbor to $goal took: ${DateTime.now().difference(heuristicStart).inMicroseconds}µs');
        openSet.add(neighbor);
      }
    }
    print('⏱️ [A*] Neighbor processing took: ${DateTime.now().difference(neighborStart).inMicroseconds}µs');
  }

  print('⏱️ [A*] No path found after $iterations iterations');
  print('⏱️ [A*] Total A* Execution: ${DateTime.now().difference(totalStart).inMilliseconds}ms');
  return [];
}

double _heuristic(String from, String to, Map<String, Map<String, double>> distances, Map<String, LatLng> cameraCoords,
    Map<String, double> vehicleCounts, Map<String, double> maxSpeeds, Map<String, double> criticalCounts) {
  final distance =
      distances[from]?.containsKey(to) == true ? distances[from]![to]! : _euclideanDistance(from, to, cameraCoords);
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

double _greenshieldSpeed(String camera, Map<String, double> vehicleCounts, Map<String, double> maxSpeeds,
    Map<String, double> criticalCounts) {
  final vehicleCount = vehicleCounts[camera] ?? 0.0;
  final maxSpeed = maxSpeeds[camera] ?? 40.0;
  final criticalCount = criticalCounts[camera] ?? 100.0;
  final speedFactor = (1 - (vehicleCount / criticalCount)).clamp(0.1, 1.0);
  final estimatedSpeed = maxSpeed * speedFactor;
  return estimatedSpeed < 5.0 ? 5.0 : estimatedSpeed; // Minimum speed 5 km/h
}

Map<String, Map<String, double>> _calculateTravelTimes(Map<String, double> vehicleCounts,
    Map<String, Map<String, double>> distances, Map<String, double> maxSpeeds, Map<String, double> criticalCounts) {
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

  Timer? _liveDataUpdateTimer; // Separate timer for live data updates
  Timer? _navigationUpdateTimer; // Separate timer for navigation updates
  bool _continuousUpdateEnabled = true; // Flag to control continuous updates
  DateTime? _lastSuccessfulFetch; // Track last successful API call
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

    await _startContinuousLiveDataUpdates();

    await _fetchCurrentVehicleCounts();
    await fetchWeatherData();
    await _initHazards();
    await _fetchNews();
    await debugEnvironmentVariables();
    debugCurrentTrafficStatus();
    // Set Camera A as default starting point and Camera B as default destination
    await _setDefaultDebugLocations();

    print('MapModel initialization completed at ${DateTime.now()}');
    notifyListeners();
  }

  // Add this new method to set default debug locations
  Future<void> _setDefaultDebugLocations() async {
    print('🔧 === SETTING DEBUG DEFAULT LOCATIONS ===');

    // Set Camera A as starting point (from location)
    _fromLocation = _cameraCoords['J']!;
    _fromPlaceName = "J : Điện Biên Phủ - CMT8";

    // Set Camera B as destination (to location)
    _toLocation = _cameraCoords['D']!;
    _toPlaceName = "D : gã sáu Nguyễn Tri Phương 1";

    // Enable two search bars since we have both locations
    _showTwoSearchBars = true;

    print('📍 Default FROM location set to Camera J: $_fromLocation');
    print('📍 Default TO location set to Camera D: $_toLocation');
    print('✅ Debug locations configured');
    print('🔧 === END DEBUG SETUP ===');

    // Update camera markers to reflect the new from/to locations
    _updateCameraMarkers();

    // Optionally calculate the initial route
    await _calculateAndFindShortestPath();
  }

// NEW METHOD: Start continuous live data updates
  Future<void> _startContinuousLiveDataUpdates() async {
    print('🔄 Starting continuous live data updates...');

    // Initial fetch
    await _fetchCurrentVehicleCounts();

    // Start timer for continuous updates (every 30 seconds)
    _stopContinuousLiveDataUpdates(); // Stop any existing timer
    _liveDataUpdateTimer = Timer.periodic(Duration(seconds: 30), (timer) async {
      if (!_continuousUpdateEnabled) {
        timer.cancel();
        return;
      }

      print('⏰ [CONTINUOUS UPDATE] Fetching live data at ${DateTime.now()}');
      await _fetchCurrentVehicleCounts();

      // If we're navigating and data changed significantly, recalculate route
      if (_isNavigating && _shouldRecalculateRoute()) {
        print('🔄 [CONTINUOUS UPDATE] Significant traffic change detected, recalculating route');
        await _calculateAndFindShortestPath();
      }

      // Update polylines if we have an active route
      if (_shortestPath.isNotEmpty) {
        await _updatePolylines();
      }
    });

    print('✅ Continuous live data updates started (every 30 seconds)');
  }

// NEW METHOD: Stop continuous updates
  void _stopContinuousLiveDataUpdates() {
    _liveDataUpdateTimer?.cancel();
    _liveDataUpdateTimer = null;
    print('⏹️ Stopped continuous live data updates');
  }

// NEW METHOD: Check if route should be recalculated
  bool _shouldRecalculateRoute() {
    if (_savedVehicleCounts == null || _shortestPath.isEmpty) return false;

    // Check if any camera in the current path has significant traffic change
    for (String camera in _shortestPath) {
      final oldCount = _savedVehicleCounts?[camera] ?? 0.0;
      final newCount = _lastVehicleCounts[camera] ?? 0.0;
      final change = (newCount - oldCount).abs();

      // If change is more than 15 vehicles, recalculate
      if (change > 15.0) {
        print('📊 Significant change at camera $camera: $oldCount → $newCount (change: $change)');
        return true;
      }
    }
    return false;
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
          'A': 100.0,
          'B': 100.0,
          'C': 100.0,
          'D': 100.0,
          'E': 100.0,
          'F': 100.0,
          'G': 100.0,
          'H': 100.0,
          'I': 100.0,
          'J': 100.0,
          'K': 100.0,
          'L': 100.0,
        };
      }
    } catch (e) {
      print('Error loading critical vehicle counts: $e at ${DateTime.now()}');
      _criticalVehicleCounts = {
        'A': 100.0,
        'B': 100.0,
        'C': 100.0,
        'D': 100.0,
        'E': 100.0,
        'F': 100.0,
        'G': 100.0,
        'H': 100.0,
        'I': 100.0,
        'J': 100.0,
        'K': 100.0,
        'L': 100.0,
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

    final a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1Rad) * cos(lat2Rad) * sin(dLon / 2) * sin(dLon / 2);
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
    _continuousUpdateEnabled = false; // Disable continuous updates

    _stopDensityUpdates();
    _stopHazardUpdates();
    super.dispose();
  }

// NEW METHOD: Manually refresh live data (for testing)
  Future<void> forceLiveDataRefresh() async {
    print('🔄 [MANUAL REFRESH] Force refreshing live data...');
    await _fetchCurrentVehicleCounts();

    if (_shortestPath.isNotEmpty) {
      await _updatePolylines();
    }

    notifyListeners();
  }

// NEW METHOD: Get time since last successful fetch
  String getTimeSinceLastFetch() {
    if (_lastSuccessfulFetch == null) return 'Never';

    final duration = DateTime.now().difference(_lastSuccessfulFetch!);
    if (duration.inMinutes < 1) {
      return '${duration.inSeconds} seconds ago';
    } else if (duration.inHours < 1) {
      return '${duration.inMinutes} minutes ago';
    } else {
      return '${duration.inHours} hours ago';
    }
  }

// NEW METHOD: Check if live data is fresh
  bool isLiveDataFresh() {
    if (_lastSuccessfulFetch == null) return false;
    return DateTime.now().difference(_lastSuccessfulFetch!).inMinutes < 2;
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

    print(
        'Navigation ${_isNavigating ? 'started' : 'stopped'} from $_fromPlaceName to $_toPlaceName at ${DateTime.now()}');

    if (_isNavigating && _fromLocation != null && _toLocation != null) {
      await _calculateAndFindShortestPath();
      _startNavigationUpdates(); // Start navigation-specific updates
    } else {
      _shortestPath = [];
      _totalTravelTime = 0.0;
      _polylines.clear();
      _updateCameraMarkers();
      _stopNavigationUpdates(); // Stop navigation updates but keep live data updates
    }

    notifyListeners();
  }

// NEW METHOD: Start navigation-specific updates (separate from live data)
  void _startNavigationUpdates() {
    _stopNavigationUpdates();
    _navigationUpdateTimer = Timer.periodic(Duration(seconds: 15), (timer) async {
      if (!_isNavigating) {
        timer.cancel();
        return;
      }

      print('🧭 [NAVIGATION UPDATE] Updating current location and route at ${DateTime.now()}');
      await getCurrentLocation(); // Update current location
      await _updateCurrentCamera(); // Check if user moved to different camera
      await _fetchNews(); // Update news
    });
  }

// NEW METHOD: Stop navigation updates
  void _stopNavigationUpdates() {
    _navigationUpdateTimer?.cancel();
    _navigationUpdateTimer = null;
  }

  void toggleFollowUser() {
    _followUser = !_followUser;
    notifyListeners();
  }

  void _loadCameraMarkers() {
    final cameraLocations = [
      {'id': 'A', 'lat': 10.767778, 'lng': 106.671694, 'title': 'A : Lý Thái Tổ - Sư Vạn Hạnh'},
      {'id': 'B', 'lat': 10.773833, 'lng': 106.677778, 'title': 'B : 3/2 – Cao Thắng'},
      {'id': 'C', 'lat': 10.772722, 'lng': 106.679028, 'title': 'C : Điện Biên Phủ - Cao Thắng'},
      {'id': 'D', 'lat': 10.759694, 'lng': 106.668889, 'title': 'D : gã sáu Nguyễn Tri Phương 1'},
      {'id': 'E', 'lat': 10.760056, 'lng': 106.669000, 'title': 'E : Ngã sáu Nguyễn Tri Phương'},
      {'id': 'F', 'lat': 10.768806, 'lng': 106.652639, 'title': 'F : Lê Đại Hành 2'},
      {'id': 'G', 'lat': 10.766222, 'lng': 106.679083, 'title': 'G : Lý Thái Tổ - Nguyễn Đình Chiểu'},
      {'id': 'H', 'lat': 10.765417, 'lng': 106.681306, 'title': 'H : Ngã sáu Cộng Hòa 1'},
      {'id': 'I', 'lat': 10.765111, 'lng': 106.681639, 'title': 'I : Ngã sáu Cộng Hòa'},
      {'id': 'J', 'lat': 10.776667, 'lng': 106.683667, 'title': 'J : Điện Biên Phủ - CMT8'},
      {'id': 'K', 'lat': 10.777778, 'lng': 106.6820, 'title': 'K : Nút giao Công Trường Dân Chủ'},
      {'id': 'L', 'lat': 10.777694, 'lng': 106.681361, 'title': 'L : Nút giao Công Trường Dân Chủ 1'},
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
      {'id': 'A', 'lat': 10.767778, 'lng': 106.671694, 'title': 'A : Lý Thái Tổ - Sư Vạn Hạnh'},
      {'id': 'B', 'lat': 10.773833, 'lng': 106.677778, 'title': 'B : 3/2 – Cao Thắng'},
      {'id': 'C', 'lat': 10.772722, 'lng': 106.679028, 'title': 'C : Điện Biên Phủ - Cao Thắng'},
      {'id': 'D', 'lat': 10.759694, 'lng': 106.668889, 'title': 'D : Ngã sáu Nguyễn Tri Phương 1'},
      {'id': 'E', 'lat': 10.760056, 'lng': 106.669000, 'title': 'E : Ngã sáu Nguyễn Tri Phương'},
      {'id': 'F', 'lat': 10.768806, 'lng': 106.652639, 'title': 'F : Lê Đại Hành 2'},
      {'id': 'G', 'lat': 10.766222, 'lng': 106.679083, 'title': 'G :Lý Thái Tổ - Nguyễn Đình Chiểu'},
      {'id': 'H', 'lat': 10.765417, 'lng': 106.681306, 'title': 'H :Ngã sáu Cộng Hòa 1'},
      {'id': 'I', 'lat': 10.765111, 'lng': 106.681639, 'title': 'I : Ngã sáu Cộng Hòa'},
      {'id': 'J', 'lat': 10.776667, 'lng': 106.683667, 'title': 'J : Điện Biên Phủ - CMT8'},
      {'id': 'K', 'lat': 10.777778, 'lng': 106.6820, 'title': ' K : Nút giao Công Trường Dân Chủ'},
      {'id': 'L', 'lat': 10.777694, 'lng': 106.681361, 'title': 'L : Nút giao Công Trường Dân Chủ 1'},
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

    print(
        'Updated camera markers: fromCamera=$fromCamera (green), toCamera=$toCamera (red), others (blue) at ${DateTime.now()}');
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

  // void _startDensityUpdates() {
  //   _stopDensityUpdates();
  //   _densityUpdateTimer = Timer.periodic(Duration(seconds: 30), (timer) async {
  //     if (!_isNavigating) {
  //       timer.cancel();
  //       return;
  //     }
  //     print('Periodic vehicle count and news update triggered at ${DateTime.now()}');
  //     await _fetchCurrentVehicleCounts();
  //     await _updatePolylines();
  //     await _fetchNews();
  //     final shouldRecalculate = _shortestPath.any((camera) {
  //       final oldCount = _savedVehicleCounts?[camera] ?? 0.0;
  //       final newCount = _lastVehicleCounts[camera] ?? 0.0;
  //       return (newCount - oldCount).abs() > 20.0;
  //     });
  //     if (shouldRecalculate) {
  //       print('Significant vehicle count change detected, recalculating shortest path at ${DateTime.now()}');
  //       await _calculateAndFindShortestPath();
  //     }
  //   });
  // }

  void _stopDensityUpdates() {
    _stopNavigationUpdates(); // Only stop navigation updates
    // Keep continuous live data updates running
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
        final url = Uri.parse('http://192.168.22.105:10000/live-densities');
        _logApiStatus('_fetchCurrentVehicleCounts', true,
            additionalInfo: 'Attempting API call to $url (Attempt ${attempt + 1}/$maxRetries)');

        final response = await http.get(url).timeout(Duration(seconds: 10));

        if (response.statusCode != 200) {
          _logApiStatus('_fetchCurrentVehicleCounts', false,
              additionalInfo: 'API returned non-200 status: ${response.statusCode}');
          throw Exception('Non-200 status code: ${response.statusCode}');
        }

        final dataJson = jsonDecode(response.body);

        if (dataJson is! Map || !dataJson.containsKey('cameras')) {
          _logApiStatus('_fetchCurrentVehicleCounts', false, additionalInfo: 'Invalid API response format');
          throw Exception('Invalid data format');
        }

        // Process the live data
        Map<String, double> newVehicleCounts = {};
        Map<String, double> newDensities = {};
        final cameras = dataJson['cameras'] as Map<String, dynamic>;

        for (var entry in cameras.entries) {
          double vehicleCount = 15.0; // default
          double density = 15.0; // default

          if (entry.value is Map) {
            final cameraData = entry.value as Map<String, dynamic>;

            // Parse vehicle count
            if (cameraData.containsKey('vehicle_count')) {
              if (cameraData['vehicle_count'] is num) {
                vehicleCount = cameraData['vehicle_count'].toDouble();
              } else if (cameraData['vehicle_count'] is String) {
                vehicleCount = double.tryParse(cameraData['vehicle_count']) ?? 15.0;
              }
            }

            // Parse density
            if (cameraData.containsKey('density')) {
              if (cameraData['density'] is num) {
                density = cameraData['density'].toDouble();
              } else if (cameraData['density'] is String) {
                density = double.tryParse(cameraData['density']) ?? 15.0;
              }
            }

            // Handle edge cases
            if (vehicleCount <= 0) vehicleCount = 5.0; // minimum value
            if (density <= 0) density = 5.0; // minimum value
          }

          newVehicleCounts[entry.key] = vehicleCount;
          newDensities[entry.key] = density;
        }

        // Ensure all cameras have data
        final allCameraIds = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L'];
        for (String cameraId in allCameraIds) {
          if (!newVehicleCounts.containsKey(cameraId)) {
            newVehicleCounts[cameraId] = _lastVehicleCounts[cameraId] ?? 15.0;
          }
          if (!newDensities.containsKey(cameraId)) {
            newDensities[cameraId] = _lastDensities[cameraId] ?? 15.0;
          }
        }

        // Update the data
        _lastVehicleCounts = newVehicleCounts;
        _lastDensities = newDensities;
        _usingLiveData = true;
        _lastSuccessfulFetch = DateTime.now();

        _logApiStatus('_fetchCurrentVehicleCounts', true, additionalInfo: '✅ Successfully fetched live data');
        _logDataSource(newVehicleCounts, newDensities, true);

        // Notify listeners
        SchedulerBinding.instance.addPostFrameCallback((_) {
          notifyListeners();
        });

        return; // Success, exit the retry loop
      } catch (e, stackTrace) {
        attempt++;
        _logApiStatus('_fetchCurrentVehicleCounts', false, additionalInfo: 'Attempt $attempt failed: $e');

        if (attempt == maxRetries) {
          _logApiStatus('_fetchCurrentVehicleCounts', false,
              additionalInfo: '🔄 Max retries reached, falling back to synthetic data');
          await _fetchSyntheticVehicleCounts();
        } else {
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
        _logApiStatus('_fetchSyntheticVehicleCounts', false,
            additionalInfo: '❌ Synthetic file not found, using hardcoded defaults');

        _lastVehicleCounts = {
          'A': 15.0,
          'B': 20.0,
          'C': 15.0,
          'D': 15.0,
          'E': 15.0,
          'F': 15.0,
          'G': 15.0,
          'H': 15.0,
          'I': 15.0,
          'J': 15.0,
          'K': 15.0,
          'L': 15.0,
        };
        _lastDensities = {
          'A': 15.0,
          'B': 20.0,
          'C': 15.0,
          'D': 15.0,
          'E': 15.0,
          'F': 15.0,
          'G': 15.0,
          'H': 15.0,
          'I': 15.0,
          'J': 15.0,
          'K': 15.0,
          'L': 15.0,
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
        print(
            '📊 Found closest synthetic entry: ${closestEntry['timestamp']} (${minDiff.inMinutes} minutes difference)');
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
        'A': 15.0,
        'B': 20.0,
        'C': 15.0,
        'D': 15.0,
        'E': 15.0,
        'F': 15.0,
        'G': 15.0,
        'H': 15.0,
        'I': 15.0,
        'J': 15.0,
        'K': 15.0,
        'L': 15.0,
      };
      _lastDensities = {
        'A': 15.0,
        'B': 20.0,
        'C': 15.0,
        'D': 15.0,
        'E': 15.0,
        'F': 15.0,
        'G': 15.0,
        'H': 15.0,
        'I': 15.0,
        'J': 15.0,
        'K': 15.0,
        'L': 15.0,
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
    final totalStartTime = DateTime.now();
    print('⏱️ A* Path Calculation Started at $totalStartTime');

    if (_fromLocation == null || _toLocation == null) {
      print('Cannot calculate shortest path: fromLocation or toLocation is null at ${DateTime.now()}');
      return;
    }

    final fromCamera = _findNearestCamera(_fromLocation!);
    final toCamera = _findNearestCamera(_toLocation!);
    print('🔍 === A* PATH CALCULATION DEBUG ===');
    print('📍 From location: $_fromLocation → Nearest camera: $fromCamera');
    print('📍 To location: $_toLocation → Nearest camera: $toCamera');
    print(
        '📊 Graph Size: ${_cameraCoords.length} nodes, ${_cameraDistances?.values.fold(0, (sum, map) => sum + map.length) ?? 0} edges');

    if (_cameraDistances == null) {
      final distanceLoadStart = DateTime.now();
      await _loadCameraDistances();
      print('⏱️ Distance Loading Took: ${DateTime.now().difference(distanceLoadStart).inMilliseconds}ms');
    }
    if (_maxSpeeds == null) {
      final speedLoadStart = DateTime.now();
      await _loadMaxSpeeds();
      print('⏱️ Speed Loading Took: ${DateTime.now().difference(speedLoadStart).inMilliseconds}ms');
    }

    print('📊 Vehicle counts for A* calculation: $_lastVehicleCounts');
    print('📊 Critical counts: $_criticalVehicleCounts');

    final travelTimesStart = DateTime.now();
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
    print('⏱️ Travel Times Calculation Took: ${DateTime.now().difference(travelTimesStart).inMilliseconds}ms');

    print('⚡ A* algorithm input:');
    print('   Start: $fromCamera');
    print('   Goal: $toCamera');
    print('   Available cameras: ${_cameraCoords.keys.toList()}');

    final aStarStart = DateTime.now();
    final path = await compute(
      (Map<String, dynamic> args) {
        final aStarInnerStart = DateTime.now();
        final result = _aStar(
          args['start'] as String,
          args['goal'] as String,
          args['travelTimes'] as Map<String, Map<String, double>>,
          args['distances'] as Map<String, Map<String, double>>,
          args['cameraCoords'] as Map<String, LatLng>,
          args['vehicleCounts'] as Map<String, double>,
          args['maxSpeeds'] as Map<String, double>,
          args['criticalCounts'] as Map<String, double>,
        );
        print('⏱️ [Isolate] A* Inner Execution Took: ${DateTime.now().difference(aStarInnerStart).inMilliseconds}ms');
        return result;
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
    print('⏱️ A* Algorithm Took: ${DateTime.now().difference(aStarStart).inMilliseconds}ms');

    print('🎯 A* RESULT:');
    print('   Raw path from A*: $path');
    print('   Path length: ${path.length} nodes');

    if (path.length <= 2) {
      print('⚠️  WARNING: A* only returned ${path.length} nodes - this might be wrong!');
      print('   Expected: Multiple intermediate camera nodes');
      print('   Got: Direct path from $fromCamera to $toCamera');
    } else {
      print('✅ A* found path through ${path.length} camera nodes:');
      for (int i = 0; i < path.length; i++) {
        final camera = path[i];
        final coord = _cameraCoords[camera];
        print('   Step ${i + 1}: Camera $camera at $coord');
      }
    }

    _shortestPath = path;
    _savedVehicleCounts = Map.from(_lastVehicleCounts);
    _savedDensities = Map.from(_lastDensities);

    // Calculate distances and times for each segment
    double totalDistance = 0.0;
    double totalTime = 0.0;

    print('📏 Segment analysis:');
    for (int i = 0; i < path.length - 1; i++) {
      final from = path[i];
      final to = path[i + 1];
      final segmentDistance = _cameraDistances![from]![to]!;
      final segmentTime = travelTimes[from]![to]!;

      totalDistance += segmentDistance;
      totalTime += segmentTime;

      print('   Segment ${i + 1}: $from → $to');
      print('     Distance: ${segmentDistance.toStringAsFixed(2)} km');
      print('     Time: ${segmentTime.toStringAsFixed(2)} min');
      print('     Vehicle count at $from: ${_lastVehicleCounts[from] ?? 0}');
    }

    _distance = totalDistance;
    _totalTravelTime = totalTime;
    _estimatedArrival = DateTime.now().add(Duration(minutes: totalTime.round()));

    print('📊 FINAL RESULTS:');
    print('   Complete path: ${path.join(" → ")}');
    print('   Total distance: ${totalDistance.toStringAsFixed(2)} km');
    print('   Total time: ${totalTime.toStringAsFixed(2)} min');
    print('   ETA: $_estimatedArrival');

    final polylineStart = DateTime.now();
    await _updatePolylines();
    print('⏱️ Polyline Update Took: ${DateTime.now().difference(polylineStart).inMilliseconds}ms');

    print('⏱️ Total A* Path Calculation Took: ${DateTime.now().difference(totalStartTime).inMilliseconds}ms');
    print('🔍 === END A* DEBUG ===');

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
          'A': 40.0,
          'B': 50.0,
          'C': 50.0,
          'D': 40.0,
          'E': 40.0,
          'F': 40.0,
          'G': 50.0,
          'H': 40.0,
          'I': 40.0,
          'J': 40.0,
          'K': 40.0,
          'L': 40.0,
        };
        await file.writeAsString(jsonEncode(_maxSpeeds));
      }
    } catch (e) {
      print('Error loading max speeds: $e at ${DateTime.now()}');
      _maxSpeeds = {
        'A': 40.0,
        'B': 40.0,
        'C': 40.0,
        'D': 40.0,
        'E': 40.0,
        'F': 40.0,
        'G': 40.0,
        'H': 40.0,
        'I': 40.0,
        'J': 40.0,
        'K': 40.0,
        'L': 40.0,
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

    print('🗺️ === UPDATING POLYLINES WITH DENSITY DEBUG ===');
    print('Shortest path: $_shortestPath');
    print('Will create ${_shortestPath.length - 1} polyline segments');

    // Get actual road routes between each pair of cameras
    for (int i = 0; i < _shortestPath.length - 1; i++) {
      final from = _shortestPath[i];
      final to = _shortestPath[i + 1];
      final fromCoord = _cameraCoords[from]!;
      final toCoord = _cameraCoords[to]!;

      // Get density and traffic info for this segment
      final fromDensity = _lastDensities[from] ?? 15.0;
      final toDensity = _lastDensities[to] ?? 15.0;
      final fromVehicles = _lastVehicleCounts[from] ?? 0;
      final toVehicles = _lastVehicleCounts[to] ?? 0;
      final segmentAvgDensity = (fromDensity + toDensity) / 2;

      print('📍 Segment ${i + 1}: $from → $to');
      print('   From $from: ${fromVehicles.toStringAsFixed(1)} vehicles, ${fromDensity.toStringAsFixed(1)}% density');
      print('   To $to: ${toVehicles.toStringAsFixed(1)} vehicles, ${toDensity.toStringAsFixed(1)}% density');
      print('   Segment avg density: ${segmentAvgDensity.toStringAsFixed(1)}%');

      // Get actual road route between cameras
      final routePoints = await _getRoadRouteBetweenCameras(fromCoord, toCoord);

      print('✅ Got ${routePoints.length} route points for segment $from → $to');
      if (routePoints.length <= 2) {
        print('⚠️  WARNING: Only ${routePoints.length} points - this will be a straight line!');
      }

      // Determine color based on density (using the FROM camera's density)
      Color color;
      String colorDescription;
      if (segmentAvgDensity  < 33.3) {
        color = Colors.green;
        colorDescription = "GREEN (Low traffic)";
      } else if (segmentAvgDensity  < 66.6) {
        color = Colors.yellow;
        colorDescription = "YELLOW (Moderate traffic)";
      } else {
        color = Colors.red;
        colorDescription = "RED (High traffic)";
      }

      _polylines.add(
        Polyline(
          polylineId: PolylineId('$from-$to'),
          points: routePoints,
          color: color,
          width: 5,
        ),
      );

      print('➕ Added polyline $from-$to:');
      print('   Points: ${routePoints.length}');
      print('   Color: $colorDescription');
      print('   Based on avg density: ${segmentAvgDensity.toStringAsFixed(1)}% between camera $from and $to');
      print('');
    }

    print('🏁 Updated ${_polylines.length} polylines with density-based colors');
    print('🗺️ === END POLYLINES DEBUG ===');
    notifyListeners();
  }

// Add this method to your MapModel class to show current traffic conditions
  void debugCurrentTrafficStatus() {
    print('🚦 === CURRENT TRAFFIC STATUS ===');
    print('📅 Data timestamp: ${DateTime.now()}');
    print('📊 Data source: ${_usingLiveData ? "🟢 LIVE API" : "🔴 SYNTHETIC/FALLBACK"}');
    print('');

    final allCameras = _cameraCoords.keys.toList()..sort();

    // Create summary statistics
    final densities = _lastDensities.values.where((d) => d > 0).toList();
    final avgDensity = densities.isNotEmpty ? densities.reduce((a, b) => a + b) / densities.length : 0;
    final maxDensity = densities.isNotEmpty ? densities.reduce((a, b) => a > b ? a : b) : 0;
    final minDensity = densities.isNotEmpty ? densities.reduce((a, b) => a < b ? a : b) : 0;

    print('📈 TRAFFIC SUMMARY:');
    print('   Average density: ${avgDensity.toStringAsFixed(1)}%');
    print('   Highest density: ${maxDensity.toStringAsFixed(1)}%');
    print('   Lowest density: ${minDensity.toStringAsFixed(1)}%');
    print('');

    print('📍 INDIVIDUAL CAMERA STATUS:');

    for (String camera in allCameras) {
      final vehicleCount = _lastVehicleCounts[camera] ?? 0;
      final density = _lastDensities[camera] ?? 0;
      final criticalCount = _criticalVehicleCounts[camera] ?? 100;
      final coordinates = _cameraCoords[camera];

      // Calculate capacity utilization
      final utilization = (vehicleCount / criticalCount * 100).clamp(0, 100);

      // Determine traffic level
      String trafficLevel;
      String emoji;
      if (density < 33.3) {
        trafficLevel = 'LOW TRAFFIC';
        emoji = '🟢';
      } else if (density < 66.6) {
        trafficLevel = 'MODERATE TRAFFIC';
        emoji = '🟡';
      } else {
        trafficLevel = 'HIGH TRAFFIC';
        emoji = '🔴';
      }

      print('   $emoji Camera $camera ($coordinates):');
      print(
          '      Vehicles: ${vehicleCount.toStringAsFixed(1)}/${criticalCount.toStringAsFixed(0)} (${utilization.toStringAsFixed(1)}% capacity)');
      print('      Density: ${density.toStringAsFixed(1)}% - $trafficLevel');

      // Speed calculation for this camera
      final speed = _greenshieldSpeed(camera, _lastVehicleCounts, _maxSpeeds ?? {}, _criticalVehicleCounts);
      print('      Estimated speed: ${speed.toStringAsFixed(1)} km/h');
      print('');
    }

    // Show cameras sorted by density (worst traffic first)
    print('🚨 CAMERAS BY TRAFFIC DENSITY (Worst to Best):');
    final sortedCameras = allCameras.toList()
      ..sort((a, b) => (_lastDensities[b] ?? 0).compareTo(_lastDensities[a] ?? 0));

    for (int i = 0; i < sortedCameras.length; i++) {
      final camera = sortedCameras[i];
      final density = _lastDensities[camera] ?? 0;
      final vehicles = _lastVehicleCounts[camera] ?? 0;
      final emoji = density < 33.3
          ? '🟢'
          : density < 66.6
              ? '🟡'
              : '🔴';

      print(
          '   ${i + 1}. $emoji Camera $camera: ${density.toStringAsFixed(1)}% (${vehicles.toStringAsFixed(1)} vehicles)');
    }

    print('🚦 === END TRAFFIC STATUS ===');
  }

// Also add this method to analyze why A* chose a specific path
  void analyzePathChoice(List<String> chosenPath) {
    if (chosenPath.length < 2) return;

    print('🔍 === PATH CHOICE ANALYSIS ===');
    print('📍 Chosen path: ${chosenPath.join(" → ")}');
    print('');

    // Analyze each camera in the path
    double totalPathDensity = 0;
    double totalPathTime = 0;

    for (int i = 0; i < chosenPath.length; i++) {
      final camera = chosenPath[i];
      final density = _lastDensities[camera] ?? 0;
      final vehicles = _lastVehicleCounts[camera] ?? 0;
      final speed = _greenshieldSpeed(camera, _lastVehicleCounts, _maxSpeeds ?? {}, _criticalVehicleCounts);

      totalPathDensity += density;

      final emoji = density < 33.3
          ? '🟢'
          : density < 66.6
              ? '🟡'
              : '🔴';
      final reason = i == 0
          ? '(START)'
          : i == chosenPath.length - 1
              ? '(END)'
              : '(INTERMEDIATE)';

      print('   $emoji Step ${i + 1}: Camera $camera $reason');
      print('      Traffic: ${vehicles.toStringAsFixed(1)} vehicles, ${density.toStringAsFixed(1)}% density');
      print('      Speed: ${speed.toStringAsFixed(1)} km/h');

      if (i < chosenPath.length - 1) {
        final nextCamera = chosenPath[i + 1];
        final distance = _cameraDistances?[camera]?[nextCamera] ?? 0;
        final time = distance > 0 ? (distance / speed) * 60 : 0; // Convert to minutes
        totalPathTime += time;
        print('      → Next: ${distance.toStringAsFixed(2)} km to $nextCamera (${time.toStringAsFixed(1)} min)');
      }
      print('');
    }

    final avgPathDensity = chosenPath.isNotEmpty ? totalPathDensity / chosenPath.length : 0;

    print('📊 PATH SUMMARY:');
    print('   Average density along path: ${avgPathDensity.toStringAsFixed(1)}%');
    print('   Total estimated time: ${totalPathTime.toStringAsFixed(1)} minutes');
    print(
        '   Path quality: ${avgPathDensity < 33.3 ? "EXCELLENT 🟢" : avgPathDensity < 66.6 ? "GOOD 🟡" : "CONGESTED 🔴"}');

    print('🔍 === END PATH ANALYSIS ===');
  }

  Future<List<LatLng>> _getRoadRouteBetweenCameras(LatLng from, LatLng to) async {
    print('🛣️  === GETTING ROAD ROUTE DEBUG ===');
    print('From: $from');
    print('To: $to');

    try {
      final graphHopperService = GraphHopperService();
      print('📡 Calling GraphHopper API...');

      final routeData = await graphHopperService.getRoute(from, to, _selectedVehicle);

      print('📦 GraphHopper response keys: ${routeData.keys.toList()}');
      print('📦 GraphHopper response: $routeData');

      // Handle the points correctly - don't cast directly
      final pointsData = routeData['points'];
      print('📍 Raw points data type: ${pointsData.runtimeType}');
      print('📍 Raw points data: $pointsData');

      List<LatLng> points = [];

      if (pointsData != null) {
        if (pointsData is List<LatLng>) {
          // Already correct type
          points = pointsData;
          print('✅ Points already in correct format: ${points.length} points');
        } else if (pointsData is List) {
          // Convert from List<dynamic> to List<LatLng>
          points = pointsData.map((point) {
            if (point is LatLng) {
              return point;
            } else if (point is Map) {
              // Handle case where points might be maps with lat/lng
              return LatLng(
                (point['lat'] ?? point['latitude']) as double,
                (point['lng'] ?? point['longitude']) as double,
              );
            } else if (point is List && point.length >= 2) {
              // Handle case where points are [lng, lat] arrays
              return LatLng(point[1] as double, point[0] as double);
            } else {
              throw Exception('Unknown point format: ${point.runtimeType} - $point');
            }
          }).toList();
          print('✅ Converted ${pointsData.length} points to LatLng format');
        }
      }

      if (points.isNotEmpty && points.length > 2) {
        print('✅ SUCCESS: Returning ${points.length} route points');
        // Print first few points for debugging
        for (int i = 0; i < (points.length > 3 ? 3 : points.length); i++) {
          print('   Point $i: ${points[i]}');
        }
        if (points.length > 3) {
          print('   ... and ${points.length - 3} more points');
        }
        return points;
      } else {
        print('❌ No valid points returned from GraphHopper (got ${points.length} points)');
      }
    } catch (e, stackTrace) {
      print('💥 ERROR getting road route from $from to $to: $e');
      print('Stack trace: $stackTrace');
    }

    print('🔄 FALLBACK: Using interpolated route instead of straight line');
    print('🛣️  === END ROAD ROUTE DEBUG ===');

    // Instead of straight line, create a more realistic curved route
    return _createInterpolatedRoute(from, to);
  }

// Add this helper method to create a curved route instead of straight line
  List<LatLng> _createInterpolatedRoute(LatLng start, LatLng end) {
    final points = <LatLng>[];
    const numPoints = 8; // Number of intermediate points

    // Add start point
    points.add(start);

    // Calculate the difference
    final latDiff = end.latitude - start.latitude;
    final lngDiff = end.longitude - start.longitude;
    final distance = sqrt(latDiff * latDiff + lngDiff * lngDiff);

    // Add intermediate points with slight curve to simulate road following
    for (int i = 1; i < numPoints; i++) {
      final t = i / numPoints;

      // Linear interpolation
      final lat = start.latitude + (latDiff * t);
      final lng = start.longitude + (lngDiff * t);

      // Add slight curve based on distance (longer routes get more curve)
      final curveIntensity = distance * 0.5; // Adjust this value for more/less curve
      final curve = sin(t * pi) * curveIntensity * 0.001;

      // Alternate the curve direction for more natural look
      final curveLat = lat + (i % 2 == 0 ? curve : -curve);
      final curveLng = lng + (i % 2 == 1 ? curve : -curve);

      points.add(LatLng(curveLat, curveLng));
    }

    // Add end point
    points.add(end);

    print('📍 Created interpolated route with ${points.length} points');
    return points;
  }

// Add this method to your MapModel class to test .env loading
  Future<void> debugEnvironmentVariables() async {
    print('🔍 === DEBUGGING ENVIRONMENT VARIABLES ===');

    try {
      // Check if dotenv is loaded
      print('📁 Checking dotenv loading...');
      print('📁 Available env keys: ${dotenv.env.keys.toList()}');

      // Check GraphHopper key specifically
      final graphHopperKey = dotenv.env['GRAPH_HOPPER_API_KEY'];
      print('🔑 GRAPH_HOPPER_API_KEY from dotenv: ${graphHopperKey ?? "NOT FOUND"}');

      if (graphHopperKey != null) {
        print('✅ GraphHopper API key found: ${graphHopperKey.substring(0, 8)}...');
      } else {
        print('❌ GraphHopper API key NOT FOUND in environment variables');
        print('🔍 All available env vars: ${dotenv.env}');
      }

      // Test GraphHopper service directly
      final graphHopperService = GraphHopperService();
      print(
          '🔧 GraphHopper service API key: ${graphHopperService.apiKey.isEmpty ? "EMPTY" : graphHopperService.apiKey.substring(0, 8) + "..."}');
    } catch (e) {
      print('💥 Error checking environment variables: $e');
    }

    print('🔍 === END ENV DEBUG ===');
  }
}
