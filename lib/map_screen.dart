import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'api_service.dart';

class MapScreen extends StatefulWidget {
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late GoogleMapController mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  LatLng _startLocation = LatLng(37.7749, -122.4194); // San Francisco
  LatLng _endLocation = LatLng(37.7849, -122.4094); // Another point

  String _selectedMode = "car"; // Default mode is car

  @override
  void initState() {
    super.initState();
    _addMarkers();
    _getPolyline(); // Fetch polyline for default mode
  }

  void _addMarkers() {
    _markers.add(Marker(
      markerId: MarkerId('start'),
      position: _startLocation,
      infoWindow: InfoWindow(title: 'Start Location'),
    ));
    _markers.add(Marker(
      markerId: MarkerId('end'),
      position: _endLocation,
      infoWindow: InfoWindow(title: 'End Location'),
    ));
  }

  Future<void> _getPolyline() async {
    ApiService apiService = ApiService();
    try {
      List<LatLng> points = await apiService.getRouteCoordinates(
        _startLocation.latitude,
        _startLocation.longitude,
        _endLocation.latitude,
        _endLocation.longitude,
        _selectedMode, // Pass selected mode (car, bike, foot)
      );

      setState(() {
        _polylines.clear();
        _polylines.add(Polyline(
          polylineId: PolylineId('route'),
          points: points,
          color: Colors.blue,
          width: 5,
        ));
      });
    } catch (e) {
      print('Error fetching polyline: $e');
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('GraphHopper Dynamic Routes')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text("Select Mode: "),
                DropdownButton<String>(
                  value: _selectedMode,
                  items: ["car", "bike", "foot"].map((mode) {
                    return DropdownMenuItem<String>(
                      value: mode,
                      child: Text(mode.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    setState(() {
                      _selectedMode = newValue!;
                      _getPolyline(); // Refresh route based on new mode
                    });
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: CameraPosition(target: _startLocation, zoom: 12),
              markers: _markers,
              polylines: _polylines,
            ),
          ),
        ],
      ),
    );
  }
}
