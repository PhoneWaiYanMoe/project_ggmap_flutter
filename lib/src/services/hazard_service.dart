// lib/src/services/hazard_service.dart
import 'dart:convert';
import 'dart:math'; // Added this import for sin, cos, sqrt, and asin
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum HazardType {
  accident,
  naturalHazard,
  roadWork,
  other,
}

enum HazardDuration {
  fifteenMinutes,
  thirtyMinutes,
  oneHour,
  threeHours,
  sixHours,
  twelveHours,
  twentyFourHours,
}

class Hazard {
  final String id;
  final HazardType type;
  final String description;
  final LatLng location;
  final String locationName;
  final DateTime reportedAt;
  final DateTime expiresAt;
  final String reportedBy;

  Hazard({
    required this.id,
    required this.type,
    required this.description,
    required this.location,
    required this.locationName,
    required this.reportedAt,
    required this.expiresAt,
    required this.reportedBy,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.index,
      'description': description,
      'latitude': location.latitude,
      'longitude': location.longitude,
      'locationName': locationName,
      'reportedAt': reportedAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'reportedBy': reportedBy,
    };
  }

  factory Hazard.fromJson(Map<String, dynamic> json) {
    return Hazard(
      id: json['id'],
      type: HazardType.values[json['type']],
      description: json['description'],
      location: LatLng(json['latitude'], json['longitude']),
      locationName: json['locationName'],
      reportedAt: DateTime.parse(json['reportedAt']),
      expiresAt: DateTime.parse(json['expiresAt']),
      reportedBy: json['reportedBy'],
    );
  }
}

class HazardService {
  static const String _storageKey = 'reported_hazards';

  // Get Vietnamese labels for hazard types
  static String getHazardTypeLabel(HazardType type) {
    switch (type) {
      case HazardType.accident:
        return 'Tai nạn';
      case HazardType.naturalHazard:
        return 'Thiên tai';
      case HazardType.roadWork:
        return 'Sửa chữa đường';
      case HazardType.other:
        return 'Khác';
    }
  }

  // Get Vietnamese labels for duration
  static String getDurationLabel(HazardDuration duration) {
    switch (duration) {
      case HazardDuration.fifteenMinutes:
        return '15 phút';
      case HazardDuration.thirtyMinutes:
        return '30 phút';
      case HazardDuration.oneHour:
        return '1 giờ';
      case HazardDuration.threeHours:
        return '3 giờ';
      case HazardDuration.sixHours:
        return '6 giờ';
      case HazardDuration.twelveHours:
        return '12 giờ';
      case HazardDuration.twentyFourHours:
        return '24 giờ';
    }
  }

  // Get duration in minutes
  static int getDurationMinutes(HazardDuration duration) {
    switch (duration) {
      case HazardDuration.fifteenMinutes:
        return 15;
      case HazardDuration.thirtyMinutes:
        return 30;
      case HazardDuration.oneHour:
        return 60;
      case HazardDuration.threeHours:
        return 180;
      case HazardDuration.sixHours:
        return 360;
      case HazardDuration.twelveHours:
        return 720;
      case HazardDuration.twentyFourHours:
        return 1440;
    }
  }

  // Save hazards to local storage
  Future<void> _saveHazards(List<Hazard> hazards) async {
    final prefs = await SharedPreferences.getInstance();
    final hazardJsonList = hazards.map((h) => h.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(hazardJsonList));
  }

  // Load hazards from local storage
  Future<List<Hazard>> loadHazards() async {
    final prefs = await SharedPreferences.getInstance();
    final hazardJsonString = prefs.getString(_storageKey);

    if (hazardJsonString == null) return [];

    try {
      final hazardJsonList = jsonDecode(hazardJsonString) as List;
      final hazards = hazardJsonList
          .map((json) => Hazard.fromJson(json))
          .where((hazard) => !hazard.isExpired) // Filter out expired hazards
          .toList();

      // Save back the filtered list (removes expired hazards)
      await _saveHazards(hazards);
      return hazards;
    } catch (e) {
      print('Error loading hazards: $e');
      return [];
    }
  }

  // Report a new hazard
  Future<void> reportHazard({
    required HazardType type,
    required String description,
    required LatLng location,
    required String locationName,
    required HazardDuration duration,
    String reportedBy = 'Anonymous',
  }) async {
    final hazards = await loadHazards();

    final newHazard = Hazard(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      description: description,
      location: location,
      locationName: locationName,
      reportedAt: DateTime.now(),
      expiresAt: DateTime.now().add(
        Duration(minutes: getDurationMinutes(duration)),
      ),
      reportedBy: reportedBy,
    );

    hazards.add(newHazard);
    await _saveHazards(hazards);
  }

  // Remove a hazard
  Future<void> removeHazard(String hazardId) async {
    final hazards = await loadHazards();
    hazards.removeWhere((h) => h.id == hazardId);
    await _saveHazards(hazards);
  }

  // Clean up expired hazards
  Future<void> cleanupExpiredHazards() async {
    final hazards = await loadHazards();
    final activeHazards = hazards.where((h) => !h.isExpired).toList();
    await _saveHazards(activeHazards);
  }

  // Get hazards near a location (within specified radius in km)
  Future<List<Hazard>> getHazardsNearLocation(LatLng location, double radiusKm) async {
    final allHazards = await loadHazards();

    return allHazards.where((hazard) {
      final distance = _calculateDistance(location, hazard.location);
      return distance <= radiusKm;
    }).toList();
  }

  // Calculate distance between two points in kilometers
  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371; // Earth's radius in kilometers

    final lat1Rad = point1.latitude * (pi / 180);
    final lon1Rad = point1.longitude * (pi / 180);
    final lat2Rad = point2.latitude * (pi / 180);
    final lon2Rad = point2.longitude * (pi / 180);

    final dLat = lat2Rad - lat1Rad;
    final dLon = lon2Rad - lon1Rad;

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1Rad) * cos(lat2Rad) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * asin(sqrt(a));

    return earthRadius * c;
  }
}