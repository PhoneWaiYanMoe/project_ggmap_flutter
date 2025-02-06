import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:geolocator/geolocator.dart';
import 'graphhopper_service.dart';

class MapScreen extends StatefulWidget {
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late GoogleMapController _mapController;
  final TextEditingController _fromController = TextEditingController();
  final TextEditingController _toController = TextEditingController();
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  final Set<Polygon> _polygons = {};
  String _selectedVehicle = 'car';
  int _selectedTime = 15;

  LatLng? _startLocation;
  LatLng? _endLocation;
  Position? _currentPosition;

  final List<String> vehicleTypes = ['car', 'bike', 'foot'];
  final List<int> timeOptions = [5, 10, 15, 20, 30];

  @override
  void initState() {
    super.initState();
    _requestLocationPermission();
  }

  // Request location permission
  Future<void> _requestLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.deniedForever) {
        return;
      }
    }
    _getCurrentLocation();
  }

  // Get current location
  Future<void> _getCurrentLocation() async {
    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    setState(() {
      _currentPosition = position;
      _startLocation = LatLng(position.latitude, position.longitude);
      _markers.add(Marker(
        markerId: MarkerId('currentLocation'),
        position: _startLocation!,
        infoWindow: InfoWindow(title: "Your Location"),
      ));
      _mapController.animateCamera(
        CameraUpdate.newLatLngZoom(_startLocation!, 14),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("GraphHopper Route Finder")),
      body: Column(
        children: [
          _buildSearchSection(),
          Expanded(child: _buildGoogleMap()),
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildSearchSection() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          _buildTextField(_fromController, "From...", true),
          SizedBox(height: 8),
          _buildTextField(_toController, "To...", false),
          SizedBox(height: 8),
          _buildVehicleDropdown(),
          SizedBox(height: 8),
          _buildIsochroneControls(),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, bool isStart) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hint,
        suffixIcon: IconButton(
          icon: Icon(Icons.search),
          onPressed: () => _searchLocation(controller.text, isStart),
        ),
      ),
    );
  }

  Widget _buildVehicleDropdown() {
    return DropdownButton<String>(
      value: _selectedVehicle,
      onChanged: (value) {
        setState(() => _selectedVehicle = value!);
      },
      items: vehicleTypes.map((type) {
        return DropdownMenuItem(value: type, child: Text(type.toUpperCase()));
      }).toList(),
    );
  }

  Widget _buildIsochroneControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        DropdownButton<int>(
          value: _selectedTime,
          onChanged: (value) {
            setState(() => _selectedTime = value!);
          },
          items: timeOptions.map((time) {
            return DropdownMenuItem(value: time, child: Text("$time min"));
          }).toList(),
        ),
        ElevatedButton(
          onPressed: _fetchIsochrone,
          child: Text("Find Reachable Area"),
        ),
      ],
    );
  }

  Widget _buildGoogleMap() {
    return GoogleMap(
      onMapCreated: (controller) => _mapController = controller,
      initialCameraPosition: CameraPosition(
        target: LatLng(10.7769, 106.7009),
        zoom: 12,
      ),
      markers: _markers,
      polylines: _polylines,
      polygons: _polygons,
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ElevatedButton(
          onPressed: _fetchRoute,
          child: Text("Find Route"),
        ),
        ElevatedButton(
          onPressed: _showTurnByTurnNavigation,
          child: Text("Turn-by-Turn"),
        ),
      ],
    );
  }

  Future<void> _searchLocation(String query, bool isStart) async {
    if (query.isEmpty) return;

    LatLng? location = await GraphHopperService().getCoordinates(query);

    if (location != null) {
      setState(() {
        if (isStart) {
          _startLocation = location;
          _markers.add(Marker(markerId: MarkerId('start'), position: location));
        } else {
          _endLocation = location;
          _markers.add(Marker(markerId: MarkerId('end'), position: location));
        }
        _mapController.animateCamera(CameraUpdate.newLatLngZoom(location, 14));
      });
    }
  }

  Future<void> _fetchRoute() async {
    if (_startLocation == null || _endLocation == null) return;

    List<LatLng> route = await GraphHopperService().getRoute(
      _startLocation!,
      _endLocation!,
      _selectedVehicle,
    );

    setState(() {
      _polylines.clear();
      _polylines.add(Polyline(
        polylineId: PolylineId('route'),
        points: route,
        color: Colors.blue,
        width: 5,
      ));
    });
  }

  Future<void> _fetchIsochrone() async {
    if (_startLocation == null) return;

    List<LatLng> area = await GraphHopperService().getReachableArea(
      _startLocation!,
      _selectedTime,
      _selectedVehicle,
    );

    setState(() {
      _polygons.clear();
      _polygons.add(Polygon(
        polygonId: PolygonId('isochrone'),
        points: area,
        strokeColor: Colors.red,
        strokeWidth: 2,
        fillColor: Colors.red.withOpacity(0.3),
      ));
    });
  }

  Future<void> _showTurnByTurnNavigation() async {
    if (_startLocation == null || _endLocation == null) return;

    List<String> instructions = await GraphHopperService().getNavigationInstructions(
      _startLocation!,
      _endLocation!,
      _selectedVehicle,
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Turn-by-Turn Navigation"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: instructions.map((step) => Text(step)).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text("Close"),
          ),
        ],
      ),
    );
  }
}