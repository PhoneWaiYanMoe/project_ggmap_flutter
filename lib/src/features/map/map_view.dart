import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'map_model.dart';
import 'map_controller.dart';
import '../../services/graphhopper_service.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import '../../widgets/compact_weather_icon.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/popular_places_widget.dart';
import '../../services/popular_places_service.dart';
import '../../services/hazard_service.dart';
import '../../services/language_service.dart';
import '../../widgets/language_selector.dart';

class MapView extends StatefulWidget {
  final MapModel model;
  final MapController controller;
  final LanguageService languageService;

  const MapView({
    super.key,
    required this.model,
    required this.controller,
    required this.languageService,
  });

  @override
  _MapViewState createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.languageService,
      builder: (context, _) {
        return AnimatedBuilder(
          animation: widget.model,
          builder: (context, _) => Scaffold(
            body: Stack(
              children: [
                GoogleMap(
                  onMapCreated: widget.controller.onMapCreated,
                  initialCameraPosition: CameraPosition(
                    target: LatLng(10.7769, 106.7009),
                    zoom: 12,
                  ),
                  markers: {
                    if (widget.model.fromLocation != null)
                      Marker(
                        markerId: MarkerId('fromLocation'),
                        position: widget.model.fromLocation!,
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                        infoWindow: InfoWindow(title: "${widget.languageService.translate('from')}: ${widget.model.fromPlaceName}"),
                      ),
                    if (widget.model.toLocation != null)
                      Marker(
                        markerId: MarkerId('toLocation'),
                        position: widget.model.toLocation!,
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                        infoWindow: InfoWindow(title: "${widget.languageService.translate('to')}: ${widget.model.toPlaceName}"),
                      ),
                    ...widget.model.cameraMarkers,
                    ...widget.model.hazardMarkers,
                  },
                  polylines: widget.model.polylines,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  compassEnabled: true,
                  onCameraMove: (_) {
                    if (widget.model.followUser && !widget.model.isNavigating) {
                      widget.controller.onFollowToggle();
                    }
                  },
                ),

                // Language Selector - Top Left
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 16,
                  child: LanguageSelector(
                    languageService: widget.languageService,
                    isCompact: true,
                  ),
                ),

                // Compact Weather Icon - Top Right
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  right: 16,
                  child: CompactWeatherIcon(
                    currentWeather: widget.model.currentWeather,
                    drivingConditions: widget.model.drivingConditions,
                    warnings: widget.model.weatherWarnings,
                    onTap: () => _showDetailedWeather(context),
                    onRefresh: () => widget.model.fetchWeatherData(),
                  ),
                ),

                SafeArea(
                  child: Column(
                    children: [
                      SizedBox(height: 8),
                      _buildSearchSection(context),
                      _buildDataSourceBanner(context),
                      if (widget.model.isNavigating) _buildNavigationHeader(context),
                      const Spacer(),
                      if (widget.model.toLocation != null) _buildDirectionSection(context),
                      if (widget.model.shortestPath.isNotEmpty) _buildShortestPathInfo(context),
                      if (widget.model.isNavigating) _buildTurnByTurnButton(context),
                    ],
                  ),
                ),
                _buildMapControls(context),
              ],
            ),
          ),
        );
      },
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
          if (!widget.model.showTwoSearchBars)
            _buildSingleSearchBar(context)
          else
            Column(
              children: [
                _buildSearchField(context, widget.languageService.translate('from'), widget.model.fromPlaceName, true),
                Divider(height: 1),
                _buildSearchField(context, widget.languageService.translate('to'), widget.model.toPlaceName, false),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildDataSourceBanner(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: widget.model.usingLiveData ? Colors.green.withOpacity(0.9) : Colors.red.withOpacity(0.9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              widget.model.usingLiveData
                  ? widget.languageService.translate('using_live_data')
                  : widget.languageService.translate('no_live_data'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleSearchBar(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => widget.controller.onToSelected(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.search, color: Colors.blue),
              const SizedBox(width: 16),
              Text(
                widget.languageService.translate('search_location'),
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
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
        onTap: () => isFrom ? widget.controller.onFromSelected(context) : widget.controller.onToSelected(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                isFrom ? Icons.my_location : Icons.location_on,
                color: isFrom ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      placeName,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.navigation, color: Theme.of(context).primaryColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${widget.languageService.translate('route_from')} ${widget.model.fromPlaceName}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (widget.model.estimatedArrival != null)
                  Text(
                    "${widget.languageService.translate('eta')}: ${widget.model.estimatedArrival!.hour}:${widget.model.estimatedArrival!.minute.toString().padLeft(2, '0')}",
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(widget.model.followUser ? Icons.gps_fixed : Icons.gps_not_fixed),
            onPressed: widget.controller.onFollowToggle,
            color: Theme.of(context).primaryColor,
          ),
        ],
      ),
    );
  }

  Widget _buildMapControls(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: widget.model.shortestPath.isNotEmpty || widget.model.isNavigating ? 290 : (widget.model.toLocation != null ? 240 : 56),
      child: Column(
        children: [
          FloatingActionButton(
            heroTag: "popularPlaces",
            mini: true,
            onPressed: () => _showPopularPlaces(context),
            backgroundColor: Colors.purple,
            tooltip: widget.languageService.translate('popular_places'),
            child: const Icon(Icons.explore, color: Colors.white),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "zoomIn",
            mini: true,
            onPressed: widget.controller.onZoomIn,
            child: const Icon(Icons.add),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "zoomOut",
            mini: true,
            onPressed: widget.controller.onZoomOut,
            child: const Icon(Icons.remove),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "location",
            mini: true,
            onPressed: widget.controller.onMyLocation,
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "startNav",
            mini: true,
            onPressed: () => widget.controller.onStartNavigation(),
            child: const Icon(Icons.play_arrow),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "regenPath",
            mini: true,
            onPressed: () async {
              await widget.model.regenerateShortestPath();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(widget.languageService.translate('path_recalculated'))),
              );
            },
            child: const Icon(Icons.refresh),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "viewNews",
            mini: true,
            onPressed: () => _showNewsModal(context),
            backgroundColor: Colors.deepOrange,
            child: const Icon(Icons.article, color: Colors.white),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "sharePath",
            mini: true,
            onPressed: () async {
              final filePath = await widget.model.getShortestPathFilePath();
              final file = File(filePath);
              if (await file.exists()) {
                await Share.shareXFiles(
                  [XFile(filePath)],
                  text: widget.languageService.translate('share_path_text'),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(widget.languageService.translate('path_file_not_found'))),
                );
              }
            },
            child: const Icon(Icons.route),
          ),
          const SizedBox(height: 8),
          FloatingActionButton(
            heroTag: "reportHazard",
            mini: true,
            onPressed: () => _showHazardReportDialog(context),
            backgroundColor: Colors.red.shade600,
            tooltip: widget.languageService.translate('report_hazard'),
            child: const Icon(Icons.warning, color: Colors.white),
          ),
        ],
      ),
    );
  }

  void _showPopularPlaces(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PopularPlacesWidget(
        currentLocation: widget.model.currentLocation,
        onPlaceSelected: (PopularPlace place) {
          widget.model.setToLocation(place.coordinates, place.name);
          if (widget.model.fromLocation != null) {
            widget.model.getRoute();
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.languageService.translate('selected_as_destination').replaceAll('{name}', place.name)),
              duration: const Duration(seconds: 2),
            ),
          );
        },
        languageService: widget.languageService,
      ),
    );
  }

  void _showHazardReportDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => HazardReportBottomSheet(
        currentLocation: widget.model.currentLocation,
        languageService: widget.languageService,
        onHazardReported: () async {
          await widget.model.loadHazards();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.languageService.translate('hazard_reported')),
              backgroundColor: Colors.green,
            ),
          );
        },
      ),
    );
  }

  Widget _buildDirectionSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
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
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.model.distance != null
                              ? "${widget.model.distance!.toStringAsFixed(2)} ${widget.languageService.translate('km')}"
                              : widget.languageService.translate('calculating'),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShortestPathInfo(BuildContext context) {
    final startCamera = widget.model.fromLocation != null ? widget.model.findNearestCamera(widget.model.fromLocation!) : widget.languageService.translate('unknown');
    final endCamera = widget.model.toLocation != null ? widget.model.findNearestCamera(widget.model.toLocation!) : widget.languageService.translate('unknown');
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "${widget.languageService.translate('shortest_path')} $startCamera ${widget.languageService.translate('to')} $endCamera",
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "${widget.languageService.translate('path')}: ${widget.model.shortestPath.join(" -> ")}",
            style: const TextStyle(fontSize: 16),
          ),
          Text(
            "${widget.languageService.translate('total_time')}: ${widget.model.totalTravelTime.toStringAsFixed(2)} ${widget.languageService.translate('minutes')}",
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildTurnByTurnButton(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ElevatedButton(
        onPressed: () => _showTurnByTurnNavigation(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: Theme.of(context).primaryColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(
          widget.languageService.translate('show_turn_by_turn'),
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Future<void> _showTurnByTurnNavigation(BuildContext context) async {
    if (widget.model.fromLocation == null || widget.model.toLocation == null) return;

    List<String> instructions = await GraphHopperService().getNavigationInstructions(
      widget.model.fromLocation!,
      widget.model.toLocation!,
      widget.model.selectedVehicle,
    );

    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.model.selectedVehicle == 'car'
                        ? Icons.directions_car
                        : widget.model.selectedVehicle == 'bike'
                        ? Icons.directions_bike
                        : Icons.directions_walk,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.languageService.translate('turn_by_turn_navigation'),
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            Container(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: instructions.asMap().entries.map((entry) {
                    int index = entry.key + 1;
                    String step = entry.value;
                    return Container(
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey[200]!, width: 1)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).primaryColor,
                          child: Text('$index', style: const TextStyle(color: Colors.white)),
                        ),
                        title: Text(step, style: const TextStyle(fontSize: 14)),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(foregroundColor: Theme.of(context).primaryColor),
                    child: Text(widget.languageService.translate('close')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDetailedWeather(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.languageService.translate('weather_details'),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () {
                      widget.model.fetchWeatherData();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (widget.model.currentWeather != null) ...[
                      _buildCurrentWeatherCard(),
                      const SizedBox(height: 16),
                      _buildAirQualityCard(),
                      const SizedBox(height: 16),
                      _buildDrivingConditionsCard(),
                    ] else
                      Center(
                        child: Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text(widget.languageService.translate('loading_weather')),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNewsModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.languageService.translate('local_news'),
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () async {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => const Center(
                          child: CircularProgressIndicator(),
                        ),
                      );
                      await widget.model.refreshNews();
                      Navigator.pop(context);
                      Navigator.pop(context);
                      _showNewsModal(context);
                    },
                  ),
                ],
              ),
            ),
            Expanded(child: _buildNewsContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildNewsContent() {
    if (widget.model.newsArticles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.article_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              widget.languageService.translate('no_news'),
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              widget.languageService.translate('try_refresh_news'),
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const Center(child: CircularProgressIndicator()),
                );
                await widget.model.refreshNews();
                Navigator.pop(context);
                Navigator.pop(context);
                _showNewsModal(context);
              },
              icon: const Icon(Icons.refresh),
              label: Text(widget.languageService.translate('refresh_news')),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: widget.model.newsArticles.length,
      itemBuilder: (context, index) {
        final article = widget.model.newsArticles[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          child: InkWell(
            onTap: () async {
              final url = article['url'] ?? '';
              if (url.isNotEmpty) {
                try {
                  await launchUrl(Uri.parse(url));
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(widget.languageService.translate('cannot_open_article').replaceAll('{error}', e.toString()))),
                  );
                }
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.article, color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          article['source'] ?? widget.languageService.translate('unknown_source'),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (article['publishedAt'] != null && article['publishedAt'].isNotEmpty)
                        Text(
                          _formatPublishDate(article['publishedAt']),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    article['title'] ?? widget.languageService.translate('no_title'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  if (article['description'] != null && article['description'].isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      article['description'],
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        height: 1.4,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        widget.languageService.translate('read_more'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_ios,
                        size: 12,
                        color: Theme.of(context).primaryColor,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatPublishDate(String publishedAt) {
    try {
      final date = DateTime.parse(publishedAt);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays > 0) {
        return '${difference.inDays} ${widget.languageService.translate('days_ago')}';
      } else if (difference.inHours > 0) {
        return '${difference.inHours} ${widget.languageService.translate('hours_ago')}';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes} ${widget.languageService.translate('minutes_ago')}';
      } else {
        return widget.languageService.translate('just_now');
      }
    } catch (e) {
      return '';
    }
  }

  Widget _buildCurrentWeatherCard() {
    final current = widget.model.currentWeather!['current'];
    final location = widget.model.currentWeather!['location'];

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (current['condition_icon'] != null)
                  CachedNetworkImage(
                    imageUrl: current['condition_icon'],
                    width: 64,
                    height: 64,
                    placeholder: (context, url) => const CircularProgressIndicator(),
                    errorWidget: (context, url, error) => const Icon(Icons.wb_sunny, size: 64),
                  ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${location['name']}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${current['condition']}',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                      Text(
                        '${current['temp_c']}°C',
                        style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildWeatherDetailItem(widget.languageService.translate('feels_like'), '${current['feelslike_c']}°C', Icons.thermostat),
                _buildWeatherDetailItem(widget.languageService.translate('humidity'), '${current['humidity']}%', Icons.water_drop),
                _buildWeatherDetailItem(widget.languageService.translate('wind'), '${current['wind_kph']} ${widget.languageService.translate('km_h')}', Icons.air),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildWeatherDetailItem(widget.languageService.translate('visibility'), '${current['vis_km']} ${widget.languageService.translate('km')}', Icons.visibility),
                _buildWeatherDetailItem(widget.languageService.translate('uv_index'), '${current['uv']}', Icons.wb_sunny),
                _buildWeatherDetailItem(widget.languageService.translate('pressure'), '${current['pressure_mb']} ${widget.languageService.translate('mb')}', Icons.speed),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeatherDetailItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.blue, size: 24),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildAirQualityCard() {
    final airQuality = widget.model.currentWeather!['air_quality'];
    if (airQuality == null) return const SizedBox.shrink();

    final usEpaIndex = airQuality['us_epa_index'] ?? 1;
    String aqiText = '';
    Color aqiColor = Colors.green;

    switch (usEpaIndex) {
      case 1:
        aqiText = widget.languageService.translate('aqi_good');
        aqiColor = Colors.green;
        break;
      case 2:
        aqiText = widget.languageService.translate('aqi_moderate');
        aqiColor = Colors.yellow;
        break;
      case 3:
        aqiText = widget.languageService.translate('aqi_unhealthy_sensitive');
        aqiColor = Colors.orange;
        break;
      case 4:
        aqiText = widget.languageService.translate('aqi_unhealthy');
        aqiColor = Colors.red;
        break;
      case 5:
        aqiText = widget.languageService.translate('aqi_very_unhealthy');
        aqiColor = Colors.purple;
        break;
      case 6:
        aqiText = widget.languageService.translate('aqi_hazardous');
        aqiColor = Colors.red.shade900;
        break;
    }

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.air, color: aqiColor),
                const SizedBox(width: 8),
                Text(
                  widget.languageService.translate('air_quality'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: aqiColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: aqiColor),
              ),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: aqiColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    aqiText,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: aqiColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildAQIItem('PM2.5', '${airQuality['pm2_5']}'),
                _buildAQIItem('PM10', '${airQuality['pm10']}'),
                _buildAQIItem('NO2', '${airQuality['no2']}'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAQIItem(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        Text(
          'μg/m³',
          style: TextStyle(fontSize: 10, color: Colors.grey[500]),
        ),
      ],
    );
  }

  Widget _buildDrivingConditionsCard() {
    if (widget.model.drivingConditions == null) return const SizedBox.shrink();

    final conditions = widget.model.drivingConditions!;
    final safe = conditions['safe'] ?? true;
    final warnings = List<String>.from(conditions['warnings'] ?? []);
    final recommendations = List<String>.from(conditions['recommendations'] ?? []);

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  safe ? Icons.check_circle : Icons.warning,
                  color: safe ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.languageService.translate('driving_conditions'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (safe ? Colors.green : Colors.red).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: safe ? Colors.green : Colors.red),
              ),
              child: Text(
                safe ? widget.languageService.translate('safe_to_drive') : widget.languageService.translate('drive_with_caution'),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: safe ? Colors.green : Colors.red,
                ),
              ),
            ),
            if (warnings.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(widget.languageService.translate('warnings'), style: TextStyle(fontWeight: FontWeight.bold)),
              ...warnings.map((warning) => Padding(
                padding: const EdgeInsets.only(left: 16, top: 4),
                child: Text('• $warning'),
              )),
            ],
            if (recommendations.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(widget.languageService.translate('recommendations'), style: TextStyle(fontWeight: FontWeight.bold)),
              ...recommendations.map((rec) => Padding(
                padding: const EdgeInsets.only(left: 16, top: 4),
                child: Text('• $rec'),
              )),
            ],
          ],
        ),
      ),
    );
  }
}

class HazardReportBottomSheet extends StatefulWidget {
  final LatLng? currentLocation;
  final VoidCallback onHazardReported;
  final LanguageService languageService;

  const HazardReportBottomSheet({
    super.key,
    required this.currentLocation,
    required this.onHazardReported,
    required this.languageService,
  });

  @override
  _HazardReportBottomSheetState createState() => _HazardReportBottomSheetState();
}

class _HazardReportBottomSheetState extends State<HazardReportBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();

  HazardType _selectedType = HazardType.accident;
  HazardDuration _selectedDuration = HazardDuration.oneHour;
  bool _isLoading = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitReport() async {
    if (!_formKey.currentState!.validate() || widget.currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.languageService.translate('fill_all_fields')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final hazardService = HazardService();
      await hazardService.reportHazard(
        type: _selectedType,
        description: _descriptionController.text.trim(),
        location: widget.currentLocation!,
        locationName: widget.languageService.translate('current_location'),
        duration: _selectedDuration,
      );

      if (mounted) {
        Navigator.pop(context);
        widget.onHazardReported();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.languageService.translate('error_reporting_hazard').replaceAll('{error}', e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.languageService.translate('report_hazard'),
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          widget.languageService.translate('at_current_location'),
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.languageService.translate('hazard_type'), style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...HazardType.values.map((type) => RadioListTile<HazardType>(
                      title: Text(HazardService.getHazardTypeLabel(type)),
                      value: type,
                      groupValue: _selectedType,
                      onChanged: (value) => setState(() => _selectedType = value!),
                    )),
                    const SizedBox(height: 16),
                    Text(widget.languageService.translate('detailed_description'), style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: _getDescriptionHint(),
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return widget.languageService.translate('enter_description');
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(widget.languageService.translate('duration'), style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<HazardDuration>(
                      value: _selectedDuration,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      items: HazardDuration.values.map((duration) {
                        return DropdownMenuItem(
                          value: duration,
                          child: Text(HazardService.getDurationLabel(duration)),
                        );
                      }).toList(),
                      onChanged: (value) => setState(() => _selectedDuration = value!),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submitReport,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade600,
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text(
                          widget.languageService.translate('report_hazard'),
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getDescriptionHint() {
    switch (_selectedType) {
      case HazardType.accident:
        return widget.languageService.translate('accident_hint');
      case HazardType.naturalHazard:
        return widget.languageService.translate('natural_hazard_hint');
      case HazardType.roadWork:
        return widget.languageService.translate('road_work_hint');
      case HazardType.other:
        return widget.languageService.translate('other_hazard_hint');
    }
  }
}