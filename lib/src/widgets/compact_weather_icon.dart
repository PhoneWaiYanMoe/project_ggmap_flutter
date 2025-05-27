// lib/src/widgets/compact_weather_icon.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CompactWeatherIcon extends StatelessWidget {
  final Map<String, dynamic>? currentWeather;
  final Map<String, dynamic>? drivingConditions;
  final List<String> warnings;
  final VoidCallback onTap;
  final VoidCallback onRefresh;

  const CompactWeatherIcon({
    Key? key,
    required this.currentWeather,
    required this.drivingConditions,
    required this.warnings,
    required this.onTap,
    required this.onRefresh,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (currentWeather == null) {
      return _buildLoadingIcon();
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Weather icon and temperature
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildWeatherIcon(),
                SizedBox(width: 6),
                Text(
                  '${currentWeather!['current']['temp_c']}°',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),

            // Warning indicator (if any)
            if (_hasWarnings())
              Container(
                margin: EdgeInsets.only(top: 4),
                child: Icon(
                  Icons.warning,
                  color: _getWarningColor(),
                  size: 12,
                ),
              ),

            // Air quality dot
            Container(
              margin: EdgeInsets.only(top: 2),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _getAirQualityColor(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingIcon() {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }

  Widget _buildWeatherIcon() {
    final iconUrl = currentWeather!['current']['condition_icon'];

    if (iconUrl != null) {
      return CachedNetworkImage(
        imageUrl: iconUrl,
        width: 32,
        height: 32,
        placeholder: (context, url) => Icon(Icons.wb_sunny, size: 32),
        errorWidget: (context, url, error) => Icon(Icons.wb_sunny, size: 32),
      );
    }

    // Fallback icon based on condition
    return Icon(
      _getWeatherIconFallback(),
      size: 32,
      color: Colors.orange,
    );
  }

  IconData _getWeatherIconFallback() {
    final condition = currentWeather!['current']['condition']?.toString().toLowerCase() ?? '';
    final isDay = currentWeather!['current']['is_day'] == 1;

    if (condition.contains('rain') || condition.contains('mưa')) {
      return Icons.grain;
    } else if (condition.contains('cloud') || condition.contains('mây')) {
      return Icons.cloud;
    } else if (condition.contains('storm') || condition.contains('thunder') || condition.contains('bão')) {
      return Icons.thunderstorm;
    } else if (condition.contains('fog') || condition.contains('sương mù')) {
      return Icons.foggy;
    } else if (isDay) {
      return Icons.wb_sunny;
    } else {
      return Icons.nightlight_round;
    }
  }

  bool _hasWarnings() {
    return warnings.isNotEmpty || !(drivingConditions?['safe'] ?? true);
  }

  Color _getWarningColor() {
    if (!(drivingConditions?['safe'] ?? true)) {
      return Colors.red;
    } else if (warnings.isNotEmpty) {
      return Colors.orange;
    }
    return Colors.green;
  }

  Color _getAirQualityColor() {
    final airQuality = currentWeather!['air_quality'];
    if (airQuality == null) return Colors.grey;

    final usEpaIndex = airQuality['us_epa_index'] ?? 1;

    switch (usEpaIndex) {
      case 1:
        return Colors.green;
      case 2:
        return Colors.yellow;
      case 3:
        return Colors.orange;
      case 4:
        return Colors.red;
      case 5:
        return Colors.purple;
      case 6:
        return Colors.red.shade900;
      default:
        return Colors.grey;
    }
  }
}