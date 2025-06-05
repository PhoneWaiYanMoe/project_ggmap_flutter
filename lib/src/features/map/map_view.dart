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

class _MapViewState extends State<MapView> with TickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeInOut,
    );
    _slideController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    final safeAreaTop = MediaQuery.of(context).padding.top;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        return ListenableBuilder(
          listenable: widget.languageService,
          builder: (context, _) {
            return AnimatedBuilder(
              animation: widget.model,
              builder: (context, _) => Scaffold(
                body: Stack(
                  children: [
                    // Google Map - Full screen
                    GoogleMap(
                      onMapCreated: widget.controller.onMapCreated,
                      initialCameraPosition: const CameraPosition(
                        target: LatLng(10.7769, 106.7009),
                        zoom: 12,
                      ),
                      markers: {
                        if (widget.model.fromLocation != null)
                          Marker(
                            markerId: const MarkerId('fromLocation'),
                            position: widget.model.fromLocation!,
                            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                            infoWindow: InfoWindow(
                              title: "${widget.languageService.translate('from')}: ${widget.model.fromPlaceName}",
                            ),
                          ),
                        if (widget.model.toLocation != null)
                          Marker(
                            markerId: const MarkerId('toLocation'),
                            position: widget.model.toLocation!,
                            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                            infoWindow: InfoWindow(
                              title: "${widget.languageService.translate('to')}: ${widget.model.toPlaceName}",
                            ),
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

                    // Top Header with Language and Settings
                    Positioned(
                      top: safeAreaTop + 8,
                      left: 16,
                      right: 16,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, -1),
                          end: Offset.zero,
                        ).animate(_slideAnimation),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildLanguageButton(),
                            _buildSettingsButton(context),
                          ],
                        ),
                      ),
                    ),

                    // Search Container
                    Positioned(
                      top: safeAreaTop + 70,
                      left: 16,
                      right: 16,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, -1),
                          end: Offset.zero,
                        ).animate(_slideAnimation),
                        child: _buildSearchContainer(context),
                      ),
                    ),

                    // Data Source Banner
                    Positioned(
                      top: safeAreaTop + (widget.model.showTwoSearchBars ? 190 : 140),
                      left: 16,
                      right: 16,
                      child: _buildDataSourceBanner(context),
                    ),

                    // Navigation Header (when navigating)
                    if (widget.model.isNavigating)
                      Positioned(
                        top: safeAreaTop + (widget.model.showTwoSearchBars ? 240 : 190),
                        left: 16,
                        right: 16,
                        child: _buildNavigationHeader(context),
                      ),

                    // Map Controls (Zoom + My Location)
                    Positioned(
                      right: 16,
                      top: screenHeight * 0.4,
                      child: _buildMapControls(context),
                    ),

                    // Bottom Action Container (Start Navigation)
                    if (widget.model.toLocation != null && !widget.model.isNavigating)
                      Positioned(
                        bottom: safeAreaBottom + 16,
                        left: 16,
                        right: 16,
                        child: _buildBottomActionContainer(context),
                      ),

                    // Route Info Container (when route exists)
                    if (widget.model.shortestPath.isNotEmpty)
                      Positioned(
                        bottom: safeAreaBottom + (widget.model.toLocation != null && !widget.model.isNavigating ? 90 : 16),
                        left: 16,
                        right: 16,
                        child: _buildRouteInfoContainer(context),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLanguageButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: LanguageSelector(
        languageService: widget.languageService,
        isCompact: true,
      ),
    );
  }

  Widget _buildSettingsButton(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: _buildSettingsDropdown(context),
    );
  }

  Widget _buildSearchContainer(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
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
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  color: Colors.grey.shade200,
                ),
                _buildSearchField(context, widget.languageService.translate('to'), widget.model.toPlaceName, false),
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
        onTap: () => widget.controller.onToSelected(context),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.search, color: Colors.blue, size: 20),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  widget.languageService.translate('search_location'),
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
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
        borderRadius: isFrom 
          ? const BorderRadius.vertical(top: Radius.circular(16))
          : const BorderRadius.vertical(bottom: Radius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isFrom ? Colors.green : Colors.red).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isFrom ? Icons.my_location : Icons.location_on,
                  color: isFrom ? Colors.green : Colors.red,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      placeName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
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

  Widget _buildDataSourceBanner(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: widget.model.usingLiveData 
            ? Colors.green.withOpacity(0.9) 
            : Colors.orange.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.model.usingLiveData ? Icons.wifi : Icons.wifi_off,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              widget.model.usingLiveData
                  ? widget.languageService.translate('using_live_data')
                  : widget.languageService.translate('no_live_data'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade600, Colors.blue.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.navigation, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${widget.languageService.translate('route_from')} ${widget.model.fromPlaceName}",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
                if (widget.model.estimatedArrival != null)
                  Text(
                    "${widget.languageService.translate('eta')}: ${widget.model.estimatedArrival!.hour}:${widget.model.estimatedArrival!.minute.toString().padLeft(2, '0')}",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: IconButton(
              icon: Icon(
                widget.model.followUser ? Icons.gps_fixed : Icons.gps_not_fixed,
                color: Colors.white,
              ),
              onPressed: widget.controller.onFollowToggle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapControls(BuildContext context) {
    return Column(
      children: [
        // Zoom Controls
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildZoomButton(Icons.add, widget.controller.onZoomIn, true),
              Container(
                width: 48,
                height: 1,
                color: Colors.grey.shade200,
              ),
              _buildZoomButton(Icons.remove, widget.controller.onZoomOut, false),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // My Location Button
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => _handleLocationTap(context),
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.my_location,
                  color: Colors.blue,
                  size: 24,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildZoomButton(IconData icon, VoidCallback onPressed, bool isTop) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.vertical(
        top: isTop ? const Radius.circular(12) : Radius.zero,
        bottom: !isTop ? const Radius.circular(12) : Radius.zero,
      ),
      child: InkWell(
        borderRadius: BorderRadius.vertical(
          top: isTop ? const Radius.circular(12) : Radius.zero,
          bottom: !isTop ? const Radius.circular(12) : Radius.zero,
        ),
        onTap: onPressed,
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(icon, color: Colors.grey[700], size: 24),
        ),
      ),
    );
  }

  Widget _buildBottomActionContainer(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: widget.controller.onStartNavigation,
              icon: const Icon(Icons.play_arrow, size: 24),
              label: Text(
                widget.languageService.translate('start_nav'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _buildActionButton(
            Icons.refresh,
            () => _handleRefreshRoute(context),
            Colors.grey.shade100,
            Colors.grey.shade700,
          ),
          const SizedBox(width: 8),
          _buildActionButton(
            Icons.share,
            () => _handleShareRoute(context),
            Colors.grey.shade100,
            Colors.grey.shade700,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, VoidCallback onPressed, Color backgroundColor, Color iconColor) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onPressed,
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            child: Icon(icon, color: iconColor, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildRouteInfoContainer(BuildContext context) {
    final startCamera = widget.model.fromLocation != null 
      ? widget.model.findNearestCamera(widget.model.fromLocation!) 
      : widget.languageService.translate('unknown');
    final endCamera = widget.model.toLocation != null 
      ? widget.model.findNearestCamera(widget.model.toLocation!) 
      : widget.languageService.translate('unknown');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.route, color: Colors.green, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "${widget.languageService.translate('shortest_path')} $startCamera ${widget.languageService.translate('to')} $endCamera",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${widget.languageService.translate('path')}: ${widget.model.shortestPath.join(" → ")}",
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.schedule, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      "${widget.languageService.translate('total_time')}: ${widget.model.totalTravelTime.toStringAsFixed(1)} ${widget.languageService.translate('minutes')}",
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Event Handlers
  void _handleLocationTap(BuildContext context) async {
    try {
      _showSnackBar(
        context,
        widget.languageService.translate('getting_location'),
        icon: const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
        backgroundColor: Colors.blue,
      );
      
      // Uncomment when onMyLocation is implemented
      // await widget.controller.onMyLocation();
      
      _showSnackBar(
        context,
        widget.languageService.translate('location_updated'),
        backgroundColor: Colors.green,
      );
    } catch (e) {
      _showSnackBar(
        context,
        widget.languageService.translate('location_error'),
        backgroundColor: Colors.red,
      );
    }
  }

  void _handleRefreshRoute(BuildContext context) async {
    await widget.model.regenerateShortestPath();
    _showSnackBar(
      context,
      widget.languageService.translate('path_recalculated'),
      backgroundColor: Colors.green,
    );
  }

  void _handleShareRoute(BuildContext context) async {
    try {
      final filePath = await widget.model.getShortestPathFilePath();
      final file = File(filePath);
      if (await file.exists()) {
        await Share.shareXFiles(
          [XFile(filePath)],
          text: widget.languageService.translate('share_path_text'),
        );
      } else {
        _showSnackBar(
          context,
          widget.languageService.translate('path_file_not_found'),
          backgroundColor: Colors.orange,
        );
      }
    } catch (e) {
      _showSnackBar(
        context,
        'Error sharing route',
        backgroundColor: Colors.red,
      );
    }
  }

  void _showSnackBar(BuildContext context, String message, {Widget? icon, Color? backgroundColor}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (icon != null) ...[
              icon,
              const SizedBox(width: 12),
            ],
            Text(message),
          ],
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Settings Dropdown
  Widget _buildSettingsDropdown(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Container(
        padding: const EdgeInsets.all(8),
        child: const Icon(Icons.settings, color: Colors.grey, size: 24),
      ),
      color: Colors.white,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      offset: const Offset(0, 50),
      itemBuilder: (BuildContext context) => [
        _buildPopupMenuItem('weather', Icons.wb_sunny, Colors.blue,
          widget.languageService.translate('weather'),
          widget.languageService.translate('view_weather_details')),
        _buildPopupMenuItem('popular_places', Icons.explore, Colors.purple,
          widget.languageService.translate('popular_places'),
          widget.languageService.translate('discover_attractions')),
        _buildPopupMenuItem('news', Icons.article, Colors.deepOrange,
          widget.languageService.translate('local_news'),
          widget.languageService.translate('latest_updates')),
        _buildPopupMenuItem('report_hazard', Icons.warning, Colors.red,
          widget.languageService.translate('report_hazard'),
          widget.languageService.translate('report_road_issues')),
      ],
      onSelected: (String value) {
        switch (value) {
          case 'weather':
            _showDetailedWeather(context);
            break;
          case 'popular_places':
            _showPopularPlaces(context);
            break;
          case 'news':
            _showNewsModal(context);
            break;
          case 'report_hazard':
            _showHazardReportDialog(context);
            break;
        }
      },
    );
  }

  PopupMenuItem<String> _buildPopupMenuItem(String value, IconData icon, Color color, String title, String subtitle) {
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Modal Methods
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
          _showSnackBar(
            context,
            widget.languageService.translate('selected_as_destination').replaceAll('{name}', place.name),
            backgroundColor: Colors.green,
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
          _showSnackBar(
            context,
            widget.languageService.translate('hazard_reported'),
            backgroundColor: Colors.green,
          );
        },
      ),
    );
  }

  void _showDetailedWeather(BuildContext context) {
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
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.languageService.translate('weather_details'),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    if (widget.model.currentWeather != null) ...[
                      _buildCurrentWeatherCard(),
                      const SizedBox(height: 20),
                      _buildAirQualityCard(),
                      const SizedBox(height: 20),
                      _buildDrivingConditionsCard(),
                    ] else
                      const Center(
                        child: Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Loading weather data...'),
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
    // Debug: Check if news is loading and trigger fetch if needed
   

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.languageService.translate('local_news'),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () async {
                      print('📰 Manual refresh triggered');
                      print('🔍 Using location: ${widget.model.currentLocation}');
                      print('🔍 From place: ${widget.model.fromPlaceName}');
                      print('🔍 To place: ${widget.model.toPlaceName}');
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => const Center(child: CircularProgressIndicator()),
                      );
                      try {
                        // Try both method names in case one doesn't exist
                        await widget.model.refreshNews();
                        print('✅ News refresh completed: ${widget.model.newsArticles.length} articles');
                        if (widget.model.newsArticles.isNotEmpty) {
                          print('📰 First article: ${widget.model.newsArticles[0]['title']}');
                        } else {
                          print('⚠️ No articles returned after refresh');
                        }
                      } catch (e) {
                        print('❌ News refresh failed: $e');
                        // Try alternative method if refreshNews() doesn't exist
                        try {
                          // If your model has _fetchNews() as private method, you might need to call it differently
                          print('🔄 Trying alternative news fetch method...');
                          // You might need to expose _fetchNews() as a public method
                        } catch (e2) {
                          print('❌ Alternative news fetch also failed: $e2');
                        }
                        // Show error to user
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to load news: $e'),
                              backgroundColor: Colors.red,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      }
                      if (context.mounted) {
                        Navigator.pop(context); // Close loading dialog
                        Navigator.pop(context); // Close news modal
                        _showNewsModal(context); // Reopen with new data
                      }
                    },
                  ),
                ],
              ),
            ),
            // Debug info with more details
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: widget.model.newsArticles.isEmpty 
                    ? Colors.orange.withOpacity(0.1)
                    : Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: widget.model.newsArticles.isEmpty 
                      ? Colors.orange.withOpacity(0.3)
                      : Colors.green.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.model.newsArticles.isEmpty ? '🔍 Debug Info:' : '✅ News Status:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold, 
                        color: widget.model.newsArticles.isEmpty 
                          ? Colors.orange[800] 
                          : Colors.green[800],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Articles count: ${widget.model.newsArticles.length}',
                      style: TextStyle(
                        fontSize: 12, 
                        color: widget.model.newsArticles.isEmpty 
                          ? Colors.orange[700] 
                          : Colors.green[700],
                      ),
                    ),
                 
                    Text(
                      'Location: ${widget.model.currentLocation?.latitude.toStringAsFixed(4) ?? 'null'}, ${widget.model.currentLocation?.longitude.toStringAsFixed(4) ?? 'null'}',
                      style: TextStyle(
                        fontSize: 12, 
                        color: widget.model.newsArticles.isEmpty 
                          ? Colors.orange[700] 
                          : Colors.green[700],
                      ),
                    ),
                    Text(
                      'From: ${widget.model.fromPlaceName ?? 'null'}',
                      style: TextStyle(
                        fontSize: 12, 
                        color: widget.model.newsArticles.isEmpty 
                          ? Colors.orange[700] 
                          : Colors.green[700],
                      ),
                    ),
                    Text(
                      'To: ${widget.model.toPlaceName ?? 'null'}',
                      style: TextStyle(
                        fontSize: 12, 
                        color: widget.model.newsArticles.isEmpty 
                          ? Colors.orange[700] 
                          : Colors.green[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Content
            Expanded(child: _buildNewsContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildNewsContent() {
    // Debug logging

    print('📰 Displaying ${widget.model.newsArticles.length} news articles');
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: widget.model.newsArticles.length,
      itemBuilder: (context, index) {
        final article = widget.model.newsArticles[index];
        print('📰 Article $index: ${article['title'] ?? 'No title'}');
        
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                final url = article['url'] ?? '';
                print('📰 Attempting to open article: $url');
                if (url.isNotEmpty) {
                  try {
                    await launchUrl(Uri.parse(url));
                  } catch (e) {
                    print('❌ Failed to open article: $e');
                    _showSnackBar(
                      context,
                      widget.languageService.translate('cannot_open_article').replaceAll('{error}', e.toString()),
                      backgroundColor: Colors.red,
                    );
                  }
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Source and date
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.article, color: Colors.blue, size: 16),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            article['source'] ?? widget.languageService.translate('unknown_source'),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w600,
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
                    const SizedBox(height: 12),
                    // Title
                    Text(
                      article['title'] ?? widget.languageService.translate('no_title'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                        height: 1.3,
                      ),
                    ),
                    // Description
                    if (article['description'] != null && article['description'].isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        article['description'],
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[700],
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 12),
                    // Read more
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          widget.languageService.translate('read_more'),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[600],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 12,
                          color: Colors.blue[600],
                        ),
                      ],
                    ),
                  ],
                ),
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

  // Weather Cards
  Widget _buildCurrentWeatherCard() {
    final current = widget.model.currentWeather!['current'];
    final location = widget.model.currentWeather!['location'];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade400, Colors.blue.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (current['condition_icon'] != null)
                CachedNetworkImage(
                  imageUrl: current['condition_icon'],
                  width: 80,
                  height: 80,
                  placeholder: (context, url) => const CircularProgressIndicator(color: Colors.white),
                  errorWidget: (context, url, error) => const Icon(Icons.wb_sunny, size: 80, color: Colors.white),
                ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${location['name']}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '${current['condition']}',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withOpacity(0.9),
                      ),
                    ),
                    Text(
                      '${current['temp_c']}°C',
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            height: 1,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildWeatherDetailItem(
                widget.languageService.translate('feels_like'),
                '${current['feelslike_c']}°C',
                Icons.thermostat,
              ),
              _buildWeatherDetailItem(
                widget.languageService.translate('humidity'),
                '${current['humidity']}%',
                Icons.water_drop,
              ),
              _buildWeatherDetailItem(
                widget.languageService.translate('wind'),
                '${current['wind_kph']} ${widget.languageService.translate('km_h')}',
                Icons.air,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildWeatherDetailItem(
                widget.languageService.translate('visibility'),
                '${current['vis_km']} ${widget.languageService.translate('km')}',
                Icons.visibility,
              ),
              _buildWeatherDetailItem(
                widget.languageService.translate('uv_index'),
                '${current['uv']}',
                Icons.wb_sunny,
              ),
              _buildWeatherDetailItem(
                widget.languageService.translate('pressure'),
                '${current['pressure_mb']} ${widget.languageService.translate('mb')}',
                Icons.speed,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherDetailItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withOpacity(0.8),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
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

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: aqiColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.air, color: aqiColor, size: 24),
              ),
              const SizedBox(width: 12),
              Text(
                widget.languageService.translate('air_quality'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: aqiColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: aqiColor.withOpacity(0.3)),
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
                    fontSize: 16,
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
    );
  }

  Widget _buildAQIItem(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (safe ? Colors.green : Colors.red).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  safe ? Icons.check_circle : Icons.warning,
                  color: safe ? Colors.green : Colors.red,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                widget.languageService.translate('driving_conditions'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: (safe ? Colors.green : Colors.red).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: (safe ? Colors.green : Colors.red).withOpacity(0.3)),
            ),
            child: Text(
              safe 
                ? widget.languageService.translate('safe_to_drive') 
                : widget.languageService.translate('drive_with_caution'),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: safe ? Colors.green : Colors.red,
                fontSize: 16,
              ),
            ),
          ),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              widget.languageService.translate('warnings'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ...warnings.map((warning) => Padding(
              padding: const EdgeInsets.only(left: 16, top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(color: Colors.red[600], fontWeight: FontWeight.bold)),
                  Expanded(child: Text(warning, style: const TextStyle(height: 1.4))),
                ],
              ),
            )),
          ],
          if (recommendations.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              widget.languageService.translate('recommendations'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ...recommendations.map((rec) => Padding(
              padding: const EdgeInsets.only(left: 16, top: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(color: Colors.blue[600], fontWeight: FontWeight.bold)),
                  Expanded(child: Text(rec, style: const TextStyle(height: 1.4))),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }
}

// Hazard Report Bottom Sheet
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
          behavior: SnackBarBehavior.floating,
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
            content: Text(
              widget.languageService.translate('error_reporting_hazard').replaceAll('{error}', e.toString()),
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
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
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.languageService.translate('report_hazard'),
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          widget.languageService.translate('at_current_location'),
                          style: TextStyle(color: Colors.grey[600], fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Hazard Type Section
                    Text(
                      widget.languageService.translate('hazard_type'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: HazardType.values.map((type) {
                          final isLast = type == HazardType.values.last;
                          return Column(
                            children: [
                              RadioListTile<HazardType>(
                                title: Text(
                                  HazardService.getHazardTypeLabel(type),
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                                value: type,
                                groupValue: _selectedType,
                                onChanged: (value) => setState(() => _selectedType = value!),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                              ),
                              if (!isLast)
                                Divider(height: 1, color: Colors.grey.shade200),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 20),
                    
                    // Description Section
                    Text(
                      widget.languageService.translate('detailed_description'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _descriptionController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: _getDescriptionHint(),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.blue),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return widget.languageService.translate('enter_description');
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),
                    
                    // Duration Section
                    Text(
                      widget.languageService.translate('duration'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<HazardDuration>(
                      value: _selectedDuration,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Colors.blue),
                        ),
                      ),
                      items: HazardDuration.values.map((duration) {
                        return DropdownMenuItem(
                          value: duration,
                          child: Text(HazardService.getDurationLabel(duration)),
                        );
                      }).toList(),
                      onChanged: (value) => setState(() => _selectedDuration = value!),
                    ),
                    const SizedBox(height: 32),
                    
                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submitReport,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.send, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    widget.languageService.translate('report_hazard'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),
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