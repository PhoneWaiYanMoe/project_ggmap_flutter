import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'map_model.dart';
import '../../features/search/search_screen.dart';
import '../../services/language_service.dart';

class MapController {
  final MapModel model;
  final LanguageService languageService;
  late GoogleMapController _mapController;

  MapController(this.model, this.languageService);

  void onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _setMapStyle();
    _fitCameraMarkers();
  }

  Future<void> onFromSelected(BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SearchScreen(
          currentLocation: model.currentLocation,
          languageService: languageService,
        ),
      ),
    );
    if (result != null && result is Map) {
      LatLng selectedLocation = result['location'] as LatLng;
      String searchedName = result['name'] as String;
      model.setFromLocation(selectedLocation, searchedName);
      if (model.toLocation != null) {
        await model.getRoute();
        _updateMapCamera();
      }
    }
  }

  Future<void> onToSelected(BuildContext context) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SearchScreen(
          currentLocation: model.currentLocation,
          languageService: languageService,
        ),
      ),
    );
    if (result != null && result is Map) {
      LatLng selectedLocation = result['location'] as LatLng;
      String searchedName = result['name'] as String;
      model.setToLocation(selectedLocation, searchedName);
      if (model.fromLocation != null) {
        await model.getRoute();
        _updateMapCamera();
      }
    }
  }

  void onVehicleSelected(String vehicle) {
    model.setVehicle(vehicle);
    if (model.fromLocation != null && model.toLocation != null) {
      model.getRoute();
      _updateMapCamera();
    }
  }

  Future<void> onStartNavigation() async {
    await model.toggleNavigation();
    if (model.isNavigating && model.polylines.isNotEmpty) {
      _updateMapCamera();
    }
  }

  void onFollowToggle() {
    model.toggleFollowUser();
    if (model.followUser && model.currentLocation != null) {
      _mapController.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: model.currentLocation!,
            zoom: 17,
            bearing: model.bearing,
            tilt: 50,
          ),
        ),
      );
    }
  }

  void onZoomIn() {
    _mapController.animateCamera(CameraUpdate.zoomIn());
  }

  void onZoomOut() {
    _mapController.animateCamera(CameraUpdate.zoomOut());
  }

  void onMyLocation() {
    model.getCurrentLocation(setAsFrom: true);
    model.toggleFollowUser();
    if (model.toLocation != null) {
      model.getRoute();
      _updateMapCamera();
    }
  }

  void _updateMapCamera() {
    if (model.polylines.isNotEmpty) {
      final bounds = _computeBounds(model.polylines.first.points);
      _mapController.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
    } else if (model.fromLocation != null && model.toLocation != null) {
      final bounds = _computeBounds([model.fromLocation!, model.toLocation!]);
      _mapController.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
    }
  }

  void _fitCameraMarkers() {
    if (model.cameraMarkers.isNotEmpty) {
      final lats = model.cameraMarkers.map((m) => m.position.latitude).toList();
      final lngs = model.cameraMarkers.map((m) => m.position.longitude).toList();
      final bounds = LatLngBounds(
        southwest: LatLng(lats.reduce((a, b) => a < b ? a : b), lngs.reduce((a, b) => a < b ? a : b)),
        northeast: LatLng(lats.reduce((a, b) => a > b ? a : b), lngs.reduce((a, b) => a > b ? a : b)),
      );
      _mapController.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
    }
  }

  LatLngBounds _computeBounds(List<LatLng> points) {
    double minLat = points[0].latitude;
    double maxLat = points[0].latitude;
    double minLng = points[0].longitude;
    double maxLng = points[0].longitude;

    for (LatLng point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }
    return LatLngBounds(southwest: LatLng(minLat, minLng), northeast: LatLng(maxLat, maxLng));
  }

  void _setMapStyle() async {
    String style = '''
      [
        {
          "featureType": "poi",
          "elementType": "labels",
          "stylers": [
            {
              "visibility": "off"
            }
          ]
        }
      ]
    ''';
    _mapController.setMapStyle(style);
  }
}