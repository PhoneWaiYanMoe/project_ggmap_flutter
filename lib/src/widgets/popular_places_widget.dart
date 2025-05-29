// lib/src/widgets/popular_places_widget.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/popular_places_service.dart';

class PopularPlacesWidget extends StatefulWidget {
  final LatLng? currentLocation;
  final Function(PopularPlace) onPlaceSelected;

  const PopularPlacesWidget({
    Key? key,
    required this.currentLocation,
    required this.onPlaceSelected,
  }) : super(key: key);

  @override
  _PopularPlacesWidgetState createState() => _PopularPlacesWidgetState();
}

class _PopularPlacesWidgetState extends State<PopularPlacesWidget> {
  final PopularPlacesService _placesService = PopularPlacesService();
  List<PopularPlace> _places = [];
  bool _isLoading = false;
  String _selectedCategory = 'all';
  bool _showFamousPlaces = true;

  final List<Map<String, dynamic>> _categories = [
    {'key': 'all', 'name': 'Tất cả', 'icon': Icons.explore},
    {'key': 'food', 'name': 'Ăn uống', 'icon': Icons.restaurant},
    {'key': 'shopping', 'name': 'Mua sắm', 'icon': Icons.shopping_bag},
    {'key': 'tourism', 'name': 'Du lịch', 'icon': Icons.camera_alt},
    {'key': 'healthcare', 'name': 'Y tế', 'icon': Icons.local_hospital},
    {'key': 'education', 'name': 'Giáo dục', 'icon': Icons.school},
    {'key': 'transport', 'name': 'Giao thông', 'icon': Icons.directions_bus},
    {'key': 'banking', 'name': 'Ngân hàng', 'icon': Icons.account_balance},
    {'key': 'fuel', 'name': 'Xăng dầu', 'icon': Icons.local_gas_station},
  ];

  @override
  void initState() {
    super.initState();
    _loadFamousPlaces();
  }

  void _loadFamousPlaces() {
    setState(() {
      _places = _placesService.getFamousPlaces();
      _showFamousPlaces = true;
    });
  }

  Future<void> _searchPlaces(String category) async {
    setState(() {
      _isLoading = true;
      _selectedCategory = category;
      _showFamousPlaces = false;
    });

    try {
      final places = await _placesService.getPopularPlaces(
        center: widget.currentLocation,
        category: category,
        radiusKm: 10.0,
        limit: 30,
      );

      setState(() {
        _places = places;
      });
    } catch (e) {
      print('Error loading places: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi khi tải địa điểm: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            margin: EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Địa điểm nổi tiếng',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(Icons.star,
                          color: _showFamousPlaces ? Colors.orange : Colors.grey),
                      onPressed: _loadFamousPlaces,
                      tooltip: 'Địa điểm nổi tiếng',
                    ),
                    IconButton(
                      icon: Icon(Icons.refresh),
                      onPressed: () => _searchPlaces(_selectedCategory),
                      tooltip: 'Làm mới',
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Category tabs
          Container(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: 16),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = _selectedCategory == category['key'] && !_showFamousPlaces;

                return Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: FilterChip(
                    selected: isSelected,
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          category['icon'],
                          size: 16,
                          color: isSelected ? Colors.white : Colors.grey[600],
                        ),
                        SizedBox(width: 4),
                        Text(
                          category['name'],
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        _searchPlaces(category['key']);
                      }
                    },
                    selectedColor: Theme.of(context).primaryColor,
                    backgroundColor: Colors.grey[100],
                  ),
                );
              },
            ),
          ),

          // Loading indicator
          if (_isLoading)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Đang tải địa điểm...'),
                  ],
                ),
              ),
            )

          // Places list
          else
            Expanded(
              child: _places.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.location_off, size: 64, color: Colors.grey[400]),
                    SizedBox(height: 16),
                    Text(
                      'Không tìm thấy địa điểm nào',
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Thử chọn danh mục khác hoặc làm mới',
                      style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                padding: EdgeInsets.all(16),
                itemCount: _places.length,
                itemBuilder: (context, index) {
                  final place = _places[index];
                  return _buildPlaceCard(place);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaceCard(PopularPlace place) {
    final distance = widget.currentLocation != null
        ? _calculateDistance(widget.currentLocation!, place.coordinates)
        : null;

    return Card(
      margin: EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          widget.onPlaceSelected(place);
          Navigator.pop(context);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _getCategoryColor(place.category).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getCategoryIcon(place.category),
                      color: _getCategoryColor(place.category),
                      size: 20,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          place.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getCategoryColor(place.category),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                place.category,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (distance != null) ...[
                              SizedBox(width: 8),
                              Icon(Icons.location_on, size: 14, color: Colors.grey[500]),
                              SizedBox(width: 2),
                              Text(
                                '${distance.toStringAsFixed(1)} km',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey[400],
                  ),
                ],
              ),
              if (place.description != null) ...[
                SizedBox(height: 12),
                Text(
                  place.description!,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              SizedBox(height: 12),
              Text(
                place.address,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Ăn uống':
        return Colors.orange;
      case 'Mua sắm':
        return Colors.purple;
      case 'Du lịch':
        return Colors.blue;
      case 'Y tế':
        return Colors.red;
      case 'Giáo dục':
        return Colors.green;
      case 'Giao thông':
        return Colors.indigo;
      case 'Ngân hàng':
        return Colors.teal;
      case 'Xăng dầu':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'Ăn uống':
        return Icons.restaurant;
      case 'Mua sắm':
        return Icons.shopping_bag;
      case 'Du lịch':
        return Icons.camera_alt;
      case 'Y tế':
        return Icons.local_hospital;
      case 'Giáo dục':
        return Icons.school;
      case 'Giao thông':
        return Icons.directions_bus;
      case 'Ngân hàng':
        return Icons.account_balance;
      case 'Xăng dầu':
        return Icons.local_gas_station;
      default:
        return Icons.place;
    }
  }

  double _calculateDistance(LatLng point1, LatLng point2) {
    const double radiusEarth = 6371; // Earth's radius in kilometers

    final lat1Rad = point1.latitude * pi / 180;
    final lon1Rad = point1.longitude * pi / 180;
    final lat2Rad = point2.latitude * pi / 180;
    final lon2Rad = point2.longitude * pi / 180;

    final dLat = lat2Rad - lat1Rad;
    final dLon = lon2Rad - lon1Rad;

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1Rad) * cos(lat2Rad) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return radiusEarth * c;
  }
}