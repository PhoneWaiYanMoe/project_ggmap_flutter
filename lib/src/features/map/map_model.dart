// lib/src/features/map/map_model.dart
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
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

  MapModel() {
    _init();
  }

  Future<void> _init() async {
    await getCurrentLocation(setAsFrom: true); // Changed to public method
    await _requestLocationPermission();
    notifyListeners();
  }

  Future<void> _requestLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
  }

  Future<void> getCurrentLocation({bool setAsFrom = false}) async { // Made public
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
// lib/src/features/map/map_model.dart (snippet)
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
}