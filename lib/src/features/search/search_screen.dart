// lib/src/features/search/search_screen.dart
// Replace your search_screen.dart with this FREE version using Nominatim

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/nominatim_geocoding_service.dart';
import 'dart:async';

class SearchLocation {
  final String placeId;
  final String name;
  final LatLng coordinates;
  final String? address;
  final String? description;
  final List<String> types;

  SearchLocation({
    required this.placeId,
    required this.name,
    required this.coordinates,
    this.address,
    this.description,
    this.types = const [],
  });
}

class SearchScreen extends StatefulWidget {
  final LatLng? currentLocation;

  const SearchScreen({super.key, required this.currentLocation});

  @override
  _SearchScreenState createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final NominatimGeocodingService _geocodingService = NominatimGeocodingService();

  List<SearchLocation> _searchHistory = [];
  List<NominatimPlace> _searchResults = [];
  bool _isSearching = false;
  bool _showResults = false;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadSearchHistory();
    _searchFocusNode.requestFocus();

    // Listen to text changes for live search with debouncing
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();

    // Cancel previous timer
    _debounceTimer?.cancel();

    if (query.isEmpty) {
      setState(() {
        _showResults = false;
        _searchResults.clear();
        _isSearching = false;
      });
      return;
    }

    if (query.length < 2) return; // Don't search for very short queries

    // Debounce the search to avoid too many API calls
    _debounceTimer = Timer(Duration(milliseconds: 800), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty || query.length < 2) return;

    setState(() {
      _isSearching = true;
      _showResults = true;
    });

    try {
      final results = await _geocodingService.searchPlaces(
        query: query,
        location: widget.currentLocation, // Bias results to current location
        limit: 15,
        countryCode: 'vn', // Focus on Vietnam
      );

      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      print('Error searching for places: $e');
      setState(() {
        _searchResults.clear();
        _isSearching = false;
      });
    }
  }

  Future<void> _selectPlace(NominatimPlace place) async {
    final location = SearchLocation(
      placeId: place.placeId,
      name: place.name,
      coordinates: place.coordinates,
      address: place.formattedAddress,
      description: place.shortAddress,
      types: place.placeTypes,
    );

    await _saveToSearchHistory(location);

    Navigator.pop(context, {
      'location': location.coordinates,
      'name': location.name,
      'address': location.address,
      'placeId': location.placeId,
    });
  }

  Future<void> _loadSearchHistory() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList('searchHistory') ?? [];
    setState(() {
      _searchHistory = history.map((item) {
        List<String> parts = item.split('|');
        if (parts.length >= 4) {
          return SearchLocation(
            placeId: parts.length > 4 ? parts[4] : '',
            name: parts[0],
            coordinates: LatLng(double.parse(parts[1]), double.parse(parts[2])),
            address: parts[3].isNotEmpty ? parts[3] : null,
            types: parts.length > 5 ? parts[5].split(',') : [],
          );
        }
        return null;
      }).where((item) => item != null).cast<SearchLocation>().toList();
    });
  }

  Future<void> _saveToSearchHistory(SearchLocation location) async {
    // Don't save if already exists
    if (_searchHistory.any((item) =>
    (item.placeId.isNotEmpty && item.placeId == location.placeId) ||
        (item.name == location.name && item.placeId.isEmpty && location.placeId.isEmpty))) {
      return;
    }

    // Remove similar entries
    _searchHistory.removeWhere((item) => item.name == location.name);

    // Add to beginning of list
    _searchHistory.insert(0, location);

    // Keep only last 15 searches
    if (_searchHistory.length > 15) {
      _searchHistory = _searchHistory.take(15).toList();
    }

    // Save to preferences
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> history = _searchHistory.map((loc) =>
    '${loc.name}|${loc.coordinates.latitude}|${loc.coordinates.longitude}|${loc.address ?? ""}|${loc.placeId}|${loc.types.join(",")}'
    ).toList();
    await prefs.setStringList('searchHistory', history);
  }

  void _selectHistoryLocation(SearchLocation location) {
    Navigator.pop(context, {
      'location': location.coordinates,
      'name': location.name,
      'address': location.address,
      'placeId': location.placeId,
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _showResults = false;
      _searchResults.clear();
      _isSearching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.primary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Tìm kiếm địa điểm',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Column(
        children: [
          // Search Input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    Icon(Icons.search, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        decoration: InputDecoration(
                          hintText: "Nhập tên đường, địa điểm, quận...",
                          border: InputBorder.none,
                          hintStyle: TextStyle(color: Colors.grey[400]),
                        ),
                        textInputAction: TextInputAction.search,
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: Icon(Icons.clear, color: Colors.grey[600]),
                        onPressed: _clearSearch,
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Search suggestions or powered by info
          if (_showResults)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.public, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    'Powered by OpenStreetMap',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                  Spacer(),
                  if (_searchResults.isNotEmpty)
                    Text(
                      '${_searchResults.length} kết quả',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // Content Area
          Expanded(
            child: _showResults ? _buildSearchResults() : _buildSearchHistory(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_isSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              'Đang tìm kiếm...',
              style: TextStyle(color: Colors.grey[600]),
            ),
            SizedBox(height: 8),
            Text(
              'Sử dụng dữ liệu OpenStreetMap miễn phí',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
            SizedBox(height: 16),
            Text(
              'Không tìm thấy kết quả',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            SizedBox(height: 8),
            Text(
              'Thử tìm kiếm với từ khóa khác',
              style: TextStyle(fontSize: 14, color: Colors.grey[500]),
            ),
            SizedBox(height: 4),
            Text(
              'VD: "Quận 1", "Bến Thành", "Nguyễn Huệ"',
              style: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final place = _searchResults[index];
        final placeIcon = _geocodingService.getPlaceIcon(place.placeTypes);
        final placeColor = _geocodingService.getPlaceColor(place.placeTypes);

        return Card(
          margin: EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: placeColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(placeIcon, color: placeColor, size: 20),
            ),
            title: Text(
              place.name,
              style: TextStyle(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (place.shortAddress.isNotEmpty)
                  Text(
                    place.shortAddress,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (place.type.isNotEmpty)
                  Text(
                    place.type.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      color: placeColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.north_west, color: Colors.grey[400], size: 16),
                if (place.importance > 0)
                  Container(
                    margin: EdgeInsets.only(top: 2),
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: place.importance > 0.5 ? Colors.green : Colors.orange,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            onTap: () => _selectPlace(place),
          ),
        );
      },
    );
  }

  Widget _buildSearchHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_searchHistory.isNotEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.history, color: Colors.grey[600], size: 20),
                SizedBox(width: 8),
                Text(
                  'Tìm kiếm gần đây',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                Spacer(),
                TextButton(
                  onPressed: () async {
                    setState(() {
                      _searchHistory.clear();
                    });
                    SharedPreferences prefs = await SharedPreferences.getInstance();
                    await prefs.remove('searchHistory');
                  },
                  child: Text(
                    'Xóa tất cả',
                    style: TextStyle(fontSize: 12, color: Colors.red),
                  ),
                ),
              ],
            ),
          ),

        if (_searchHistory.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.map_outlined, size: 64, color: Colors.grey[400]),
                  SizedBox(height: 16),
                  Text(
                    'Tìm kiếm địa điểm',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600], fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 12),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Nhập tên đường, địa điểm, quận huyện để tìm kiếm',
                      style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  SizedBox(height: 16),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.eco, size: 16, color: Colors.green),
                        SizedBox(width: 4),
                        Text(
                          'Miễn phí • Không cần API key',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: 16),
              itemCount: _searchHistory.length,
              itemBuilder: (context, index) {
                final location = _searchHistory[index];
                final placeIcon = _geocodingService.getPlaceIcon(location.types);
                final placeColor = _geocodingService.getPlaceColor(location.types);

                return Card(
                  margin: EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: placeColor.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(placeIcon, color: placeColor, size: 20),
                    ),
                    title: Text(
                      location.name,
                      style: TextStyle(fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: location.address != null && location.address!.isNotEmpty
                        ? Text(
                      location.address!,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                        : Text(
                      '${location.coordinates.latitude.toStringAsFixed(4)}, ${location.coordinates.longitude.toStringAsFixed(4)}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    ),
                    trailing: Icon(Icons.north_west, color: Colors.grey[400], size: 16),
                    onTap: () => _selectHistoryLocation(location),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}