// lib/src/features/map/map_model.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import '../../services/graphhopper_service.dart';

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

  // Getters
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

  MapModel() {
    _init();
  }

  Future<void> _init() async {
    await getCurrentLocation(setAsFrom: true);
    await _requestLocationPermission();
    _loadCameraMarkers();
    await _calculateAndSaveCameraDistances();
    notifyListeners();
  }
Future<String> getCameraDistancesFilePath() async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/camera_distances.txt';
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
      {'id': 'cam1', 'lat': 10.767778, 'lng': 106.671694, 'title': 'Lý Thái Tổ - Sư Vạn Hạnh'},
      {'id': 'cam2', 'lat': 10.773833, 'lng': 106.677778, 'title': '3/2 – Cao Thắng'},
      {'id': 'cam3', 'lat': 10.772722, 'lng': 106.679028, 'title': 'Điện Biên Phủ - Cao Thắng'},
      {'id': 'cam4', 'lat': 10.759694, 'lng': 106.668889, 'title': 'Ngã sáu Nguyễn Tri Phương 1'},
      {'id': 'cam5', 'lat': 10.760056, 'lng': 106.669000, 'title': 'Ngã sáu Nguyễn Tri Phương 2'},
      {'id': 'cam6', 'lat': 10.768806, 'lng': 106.652639, 'title': 'Lê Đại Hành 2'},
      {'id': 'cam7', 'lat': 10.766222, 'lng': 106.679083, 'title': 'Lý Thái Tổ - Nguyễn Đình Chiểu'},
      {'id': 'cam8', 'lat': 10.765417, 'lng': 106.681306, 'title': 'Ngã sáu Cộng Hòa 1'},
      {'id': 'cam9', 'lat': 10.765111, 'lng': 106.681639, 'title': 'Ngã sáu Cộng Hòa 2'},
      {'id': 'cam10', 'lat': 10.776667, 'lng': 106.683667, 'title': 'Điện Biên Phủ - CMT8'},
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
  }

  Future<void> _calculateAndSaveCameraDistances() async {
    final cameraLocations = [
      {'id': 'A', 'lat': 10.767778, 'lng': 106.671694, 'title': 'Lý Thái Tổ - Sư Vạn Hạnh'},
      {'id': 'B', 'lat': 10.773833, 'lng': 106.677778, 'title': '3/2 – Cao Thắng'},
      {'id': 'C', 'lat': 10.772722, 'lng': 106.679028, 'title': 'Điện Biên Phủ - Cao Thắng'},
      {'id': 'D', 'lat': 10.759694, 'lng': 106.668889, 'title': 'Ngã sáu Nguyễn Tri Phương 1'},
      {'id': 'E', 'lat': 10.760056, 'lng': 106.669000, 'title': 'Ngã sáu Nguyễn Tri Phương 2'},
      {'id': 'F', 'lat': 10.768806, 'lng': 106.652639, 'title': 'Lê Đại Hành 2'},
      {'id': 'G', 'lat': 10.766222, 'lng': 106.679083, 'title': 'Lý Thái Tổ - Nguyễn Đình Chiểu'},
      {'id': 'H', 'lat': 10.765417, 'lng': 106.681306, 'title': 'Ngã sáu Cộng Hòa 1'},
      {'id': 'I', 'lat': 10.765111, 'lng': 106.681639, 'title': 'Ngã sáu Cộng Hòa 2'},
      {'id': 'J', 'lat': 10.776667, 'lng': 106.683667, 'title': 'Điện Biên Phủ - CMT8'},
    ];

    // Get the documents directory
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/camera_distances.txt');
    
    // Create or overwrite the file
    final sink = file.openWrite();
    sink.write('Camera Distances (Generated on ${DateTime.now()})\n\n');

    for (int i = 0; i < cameraLocations.length - 1; i++) {
      for (int j = i + 1; j < cameraLocations.length; j++) {
        final start = LatLng(cameraLocations[i]['lat'] as double, cameraLocations[i]['lng'] as double);
        final end = LatLng(cameraLocations[j]['lat'] as double, cameraLocations[j]['lng'] as double);
        final startId = cameraLocations[i]['id'] as String;
        final endId = cameraLocations[j]['id'] as String;
        final startTitle = cameraLocations[i]['title'] as String;
        final endTitle = cameraLocations[j]['title'] as String;

        try {
          final routeData = await GraphHopperService().getRoute(start, end, 'car');
          final distanceKm = (routeData['distance'] as double) / 1000;
          sink.write('From $startId ($startTitle) to $endId ($endTitle): ${distanceKm.toStringAsFixed(2)} km\n');
        } catch (e) {
          sink.write('From $startId ($startTitle) to $endId ($endTitle): Error - $e\n');
        }
      }
    }

    await sink.close();
    print('Distances saved to ${file.path}');
  }
}