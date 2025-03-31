// lib/src/features/search/search_screen.dart
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/graphhopper_service.dart';

class SearchLocation {
  final String name;
  final LatLng coordinates;

  SearchLocation(this.name, this.coordinates);
}

class SearchScreen extends StatefulWidget {
  final LatLng? currentLocation;

  SearchScreen({required this.currentLocation});

  @override
  _SearchScreenState createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<SearchLocation> _searchHistory = [];
  LatLng? _selectedLocation;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadSearchHistory();
  }

  Future<void> _loadSearchHistory() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> history = prefs.getStringList('searchHistory') ?? [];
    setState(() {
      _searchHistory = history.map((item) {
        List<String> parts = item.split('|');
        return SearchLocation(parts[0], LatLng(double.parse(parts[1]), double.parse(parts[2])));
      }).toList();
    });
  }

  Future<void> _saveSearchHistory() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> history = _searchHistory.map((loc) => '${loc.name}|${loc.coordinates.latitude}|${loc.coordinates.longitude}').toList();
    await prefs.setStringList('searchHistory', history);
  }

  void _searchLocation() async {
    setState(() => _isSearching = true);
    String query = _searchController.text;

    if (query.isEmpty) {
      setState(() => _isSearching = false);
      return;
    }

    try {
      LatLng? location = await GraphHopperService().getCoordinates(query);
      if (location != null) {
        setState(() {
          _selectedLocation = location;
          if (!_searchHistory.any((loc) => loc.name == query)) {
            _searchHistory.insert(0, SearchLocation(query, location)); // Add to start of list
            _saveSearchHistory();
          }
        });
      }
    } finally {
      setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Theme.of(context).colorScheme.primary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
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
                        decoration: InputDecoration(
                          hintText: "Search for a location...",
                          border: InputBorder.none,
                          hintStyle: TextStyle(color: Colors.grey[400]),
                        ),
                        onSubmitted: (_) => _searchLocation(),
                      ),
                    ),
                    if (_searchController.text.isNotEmpty)
                      IconButton(
                        icon: Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {});
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (_isSearching)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          Expanded(
            child: _searchHistory.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No search history',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _searchHistory.length,
                    itemBuilder: (context, index) {
                      final location = _searchHistory[index];
                      return ListTile(
                        leading: Icon(Icons.history),
                        title: Text(location.name),
                        subtitle: Text(
                          '${location.coordinates.latitude.toStringAsFixed(4)}, ${location.coordinates.longitude.toStringAsFixed(4)}',
                          style: TextStyle(fontSize: 12),
                        ),
                        trailing: Icon(Icons.chevron_right),
                        onTap: () {
                          setState(() => _selectedLocation = location.coordinates);
                          Navigator.pop(context, {
                            'location': location.coordinates,
                            'name': location.name, // Return the searched name
                          });
                        },
                      );
                    },
                  ),
          ),
          if (_selectedLocation != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, {
                  'location': _selectedLocation,
                  'name': _searchController.text.isNotEmpty ? _searchController.text : 'Unknown', // Use the typed query
                }),
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  "Select Location",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }
}