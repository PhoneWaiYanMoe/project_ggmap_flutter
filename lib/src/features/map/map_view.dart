// lib/src/features/map/map_view.dart
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'map_model.dart';
import 'map_controller.dart';
import '../../features/auth/login_screen.dart';
import '../../features/search/search_screen.dart';
import '../../services/graphhopper_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

class MapView extends StatelessWidget {
  final MapModel model;
  final MapController controller;

  const MapView({required this.model, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: model,
      builder: (context, _) => Scaffold(
        body: Stack(
          children: [
            GoogleMap(
              onMapCreated: controller.onMapCreated,
              initialCameraPosition: CameraPosition(
                target: LatLng(10.7769, 106.7009), // Ho Chi Minh City center
                zoom: 12,
              ),
              markers: {
                if (model.fromLocation != null)
                  Marker(
                    markerId: MarkerId('fromLocation'),
                    position: model.fromLocation!,
                    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                    infoWindow: InfoWindow(title: "From: ${model.fromPlaceName}"),
                  ),
                if (model.toLocation != null)
                  Marker(
                    markerId: MarkerId('toLocation'),
                    position: model.toLocation!,
                    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                    infoWindow: InfoWindow(title: "To: ${model.toPlaceName}"),
                  ),
                ...model.cameraMarkers,
              },
              polylines: model.polylines,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              compassEnabled: true,
              onCameraMove: (_) {
                if (model.followUser && !model.isNavigating) {
                  controller.onFollowToggle();
                }
              },
            ),
            SafeArea(
              child: Column(
                children: [
                  _buildSearchSection(context),
                  if (model.isNavigating) _buildNavigationHeader(context),
                  const Spacer(),
                  if (model.toLocation != null) _buildDirectionSection(context),
                  if (model.shortestPath.isNotEmpty) _buildShortestPathInfo(context),
                ],
              ),
            ),
            _buildMapControls(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchSection(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!model.showTwoSearchBars)
            _buildSingleSearchBar(context)
          else
            Column(
              children: [
                _buildSearchField(context, "From", model.fromPlaceName, true),
                Divider(height: 1),
                _buildSearchField(context, "To", model.toPlaceName, false),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSingleSearchBar(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => controller.onToSelected(context),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.search, color: Theme.of(context).primaryColor),
              SizedBox(width: 16),
              Text(
                "Search for a location...",
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField(BuildContext context, String label, String placeName, bool isFrom) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => isFrom ? controller.onFromSelected(context) : controller.onToSelected(context),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                isFrom ? Icons.my_location : Icons.location_on,
                color: isFrom ? Colors.green : Colors.red,
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    SizedBox(height: 4),
                    Text(
                      placeName,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationHeader(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.navigation, color: Theme.of(context).primaryColor),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Route from ${model.fromPlaceName}",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                if (model.estimatedArrival != null)
                  Text(
                    "ETA: ${model.estimatedArrival!.hour}:${model.estimatedArrival!.minute.toString().padLeft(2, '0')}",
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(model.followUser ? Icons.gps_fixed : Icons.gps_not_fixed),
            onPressed: controller.onFollowToggle,
            color: Theme.of(context).primaryColor,
          ),
        ],
      ),
    );
  }

  Widget _buildMapControls(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: model.shortestPath.isNotEmpty ? 200 : (model.toLocation != null ? 200 : 16),
      child: Column(
        children: [
          FloatingActionButton(
            heroTag: "zoomIn",
            mini: true,
            onPressed: controller.onZoomIn,
            child: Icon(Icons.add),
          ),
          SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "zoomOut",
            mini: true,
            onPressed: controller.onZoomOut,
            child: Icon(Icons.remove),
          ),
          SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "location",
            mini: true,
            onPressed: controller.onMyLocation,
            child: Icon(Icons.my_location),
          ),
          SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "shareDistances",
            mini: true,
            onPressed: () async {
              final filePath = await model.getCameraDistancesFilePath();
              final file = File(filePath);
              if (await file.exists()) {
                await Share.shareXFiles(
                  [XFile(filePath)],
                  text: 'Here are the camera distances',
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Distances file not found!')),
                );
              }
            },
            child: Icon(Icons.share),
          ),
          SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "shareSpeeds",
            mini: true,
            onPressed: () async {
              final filePath = await model.getCameraSpeedsFilePath();
              final file = File(filePath);
              if (await file.exists()) {
                await Share.shareXFiles(
                  [XFile(filePath)],
                  text: 'Here are the camera speeds',
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Speeds file not found!')),
                );
              }
            },
            child: Icon(Icons.speed),
          ),
          SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "sharePath",
            mini: true,
            onPressed: () async {
              final filePath = await model.getShortestPathFilePath();
              final file = File(filePath);
              if (await file.exists()) {
                await Share.shareXFiles(
                  [XFile(filePath)],
                  text: 'Here is the shortest path',
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Shortest path file not found!')),
                );
              }
            },
            child: Icon(Icons.route),
          ),
          SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "logout",
            mini: true,
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('token');
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => LoginScreen()),
              );
            },
            child: Icon(Icons.logout),
          ),
          // In _buildMapControls, add this before the "sharePath" button:
FloatingActionButton(
  heroTag: "regenPath",
  mini: true,
  onPressed: () async {
    await model.regenerateShortestPath();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Shortest path recalculated')),
    );
  },
  child: Icon(Icons.refresh),
),
SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildDirectionSection(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      model.selectedVehicle == 'car'
                          ? Icons.directions_car
                          : model.selectedVehicle == 'bike'
                              ? Icons.directions_bike
                              : Icons.directions_walk,
                      color: Theme.of(context).primaryColor,
                      size: 28,
                    ),
                    SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          model.distance != null
                              ? "${model.distance!.toStringAsFixed(2)} km"
                              : "Calculating...",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        if (model.estimatedArrival != null)
                          Text(
                            "ETA: ${model.estimatedArrival!.hour}:${model.estimatedArrival!.minute.toString().padLeft(2, '0')}",
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    _buildVehicleButton(context, 'car', Icons.directions_car),
                    _buildVehicleButton(context, 'bike', Icons.directions_bike),
                    _buildVehicleButton(context, 'foot', Icons.directions_walk),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: controller.onStartNavigation,
                  icon: Icon(Icons.directions),
                  label: Text(model.isNavigating ? "Stop Navigation" : "Start Navigation"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8),
              IconButton(
                onPressed: () => _showTurnByTurnNavigation(context),
                icon: Icon(Icons.list),
                tooltip: "Turn-by-Turn",
                style: IconButton.styleFrom(
                  backgroundColor: Colors.grey[200],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShortestPathInfo(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Shortest Path by Time",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text(
            "Path: ${model.shortestPath.join(" -> ")}",
            style: TextStyle(fontSize: 16),
          ),
          Text(
            "Total Time: ${model.totalTravelTime.toStringAsFixed(2)} minutes",
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleButton(BuildContext context, String vehicle, IconData icon) {
    bool isSelected = model.selectedVehicle == vehicle;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => controller.onVehicleSelected(vehicle),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Theme.of(context).primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: isSelected ? Colors.white : Colors.grey[600],
            size: 24,
          ),
        ),
      ),
    );
  }

  Future<void> _showTurnByTurnNavigation(BuildContext context) async {
    if (model.fromLocation == null || model.toLocation == null) return;

    List<String> instructions = await GraphHopperService().getNavigationInstructions(
      model.fromLocation!,
      model.toLocation!,
      model.selectedVehicle,
    );

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(
                    model.selectedVehicle == 'car'
                        ? Icons.directions_car
                        : model.selectedVehicle == 'bike'
                            ? Icons.directions_bike
                            : Icons.directions_walk,
                    color: Colors.white,
                  ),
                  SizedBox(width: 12),
                  Text(
                    "Turn-by-Turn Navigation",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: instructions.asMap().entries.map((entry) {
                    int index = entry.key + 1;
                    String step = entry.value;
                    return Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[200]!, width: 1),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).primaryColor,
                          child: Text('$index', style: TextStyle(color: Colors.white)),
                        ),
                        title: Text(step, style: TextStyle(fontSize: 14)),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text("Close"),
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).primaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}