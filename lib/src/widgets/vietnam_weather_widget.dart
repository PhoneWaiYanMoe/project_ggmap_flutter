// lib/src/widgets/vietnam_weather_widget.dart
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class VietnamWeatherWidget extends StatelessWidget {
  final Map<String, dynamic>? currentWeather;
  final Map<String, dynamic>? forecast;
  final Map<String, dynamic>? drivingConditions;
  final List<String> warnings;
  final VoidCallback onRefresh;
  final VoidCallback onExpand;

  const VietnamWeatherWidget({
    Key? key,
    required this.currentWeather,
    required this.forecast,
    required this.drivingConditions,
    required this.warnings,
    required this.onRefresh,
    required this.onExpand,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (currentWeather == null) {
      return _buildLoadingCard(context);
    }

    return Card(
      margin: EdgeInsets.all(12),
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onExpand,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: _getWeatherGradient(),
          ),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildMainWeatherInfo(context),
                if (warnings.isNotEmpty) ...[
                  SizedBox(height: 12),
                  _buildWarningsSection(context),
                ],
                SizedBox(height: 12),
                _buildAirQualitySection(context),
                SizedBox(height: 8),
                _buildActionButtons(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingCard(BuildContext context) {
    return Card(
      margin: EdgeInsets.all(12),
      elevation: 4,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            CircularProgressIndicator(strokeWidth: 2),
            SizedBox(width: 16),
            Text('Đang tải thông tin thời tiết...'),
            Spacer(),
            IconButton(
              icon: Icon(Icons.refresh),
              onPressed: onRefresh,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainWeatherInfo(BuildContext context) {
    final current = currentWeather!['current'];
    final location = currentWeather!['location'];

    return Row(
      children: [
        // Weather icon and temperature
        Column(
          children: [
            if (current['condition_icon'] != null)
              CachedNetworkImage(
                imageUrl: current['condition_icon'],
                width: 64,
                height: 64,
                placeholder: (context, url) => CircularProgressIndicator(),
                errorWidget: (context, url, error) => Icon(Icons.wb_sunny, size: 64),
              )
            else
              Icon(Icons.wb_sunny, size: 64, color: Colors.white),
            Text(
              '${current['temp_c']}°C',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
        SizedBox(width: 16),

        // Weather details
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                location['name'] ?? 'Ho Chi Minh City',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                current['condition'] ?? 'Không rõ',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.9),
                ),
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.water_drop, size: 16, color: Colors.white70),
                  SizedBox(width: 4),
                  Text(
                    '${current['humidity']}%',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  SizedBox(width: 16),
                  Icon(Icons.air, size: 16, color: Colors.white70),
                  SizedBox(width: 4),
                  Text(
                    '${current['wind_kph']} km/h',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
              Text(
                'Cảm giác như ${current['feelslike_c']}°C',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),

        // Driving safety indicator
        _buildDrivingSafetyIndicator(),
      ],
    );
  }

  Widget _buildDrivingSafetyIndicator() {
    if (drivingConditions == null) return SizedBox.shrink();

    final safe = drivingConditions!['safe'] ?? true;
    final hasWarnings = warnings.isNotEmpty;

    Color indicatorColor;
    IconData indicatorIcon;
    String indicatorText;

    if (!safe) {
      indicatorColor = Colors.red;
      indicatorIcon = Icons.warning;
      indicatorText = 'Nguy hiểm';
    } else if (hasWarnings) {
      indicatorColor = Colors.orange;
      indicatorIcon = Icons.info;
      indicatorText = 'Cẩn thận';
    } else {
      indicatorColor = Colors.green;
      indicatorIcon = Icons.check_circle;
      indicatorText = 'An toàn';
    }

    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: indicatorColor.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            indicatorIcon,
            color: indicatorColor,
            size: 24,
          ),
        ),
        SizedBox(height: 4),
        Text(
          indicatorText,
          style: TextStyle(
            fontSize: 10,
            color: indicatorColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildWarningsSection(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning, color: Colors.red, size: 16),
              SizedBox(width: 8),
              Text(
                'Cảnh báo lái xe',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          ...warnings.take(2).map((warning) => Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              '• $warning',
              style: TextStyle(
                color: Colors.red.shade700,
                fontSize: 12,
              ),
            ),
          )),
          if (warnings.length > 2)
            Text(
              '+ ${warnings.length - 2} cảnh báo khác...',
              style: TextStyle(
                color: Colors.red.shade600,
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAirQualitySection(BuildContext context) {
    final airQuality = currentWeather!['air_quality'];
    if (airQuality == null) return SizedBox.shrink();

    final usEpaIndex = airQuality['us_epa_index'] ?? 1;
    final pm25 = airQuality['pm2_5'] ?? 0.0;

    Color aqiColor;
    String aqiText;

    switch (usEpaIndex) {
      case 1:
        aqiColor = Colors.green;
        aqiText = 'Tốt';
        break;
      case 2:
        aqiColor = Colors.yellow;
        aqiText = 'Trung bình';
        break;
      case 3:
        aqiColor = Colors.orange;
        aqiText = 'Không tốt cho nhóm nhạy cảm';
        break;
      case 4:
        aqiColor = Colors.red;
        aqiText = 'Không tốt';
        break;
      case 5:
        aqiColor = Colors.purple;
        aqiText = 'Rất không tốt';
        break;
      case 6:
        aqiColor = Colors.red.shade900;
        aqiText = 'Nguy hiểm';
        break;
      default:
        aqiColor = Colors.grey;
        aqiText = 'Không rõ';
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: aqiColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.air_outlined, color: aqiColor, size: 16),
          SizedBox(width: 8),
          Text(
            'Chất lượng không khí: $aqiText',
            style: TextStyle(
              color: aqiColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          Spacer(),
          Text(
            'PM2.5: ${pm25.toStringAsFixed(1)}',
            style: TextStyle(
              color: aqiColor,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton.icon(
          onPressed: onRefresh,
          icon: Icon(Icons.refresh, color: Colors.white70, size: 16),
          label: Text(
            'Cập nhật',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        TextButton.icon(
          onPressed: onExpand,
          icon: Icon(Icons.expand_more, color: Colors.white70, size: 16),
          label: Text(
            'Chi tiết',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ],
    );
  }

  LinearGradient _getWeatherGradient() {
    if (currentWeather == null) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.blue.shade400, Colors.blue.shade600],
      );
    }

    final condition = currentWeather!['current']['condition']?.toString().toLowerCase() ?? '';
    final isDay = currentWeather!['current']['is_day'] == 1;

    if (condition.contains('rain') || condition.contains('mưa')) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.blueGrey.shade400, Colors.blueGrey.shade700],
      );
    } else if (condition.contains('cloud') || condition.contains('mây')) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.grey.shade400, Colors.grey.shade600],
      );
    } else if (condition.contains('storm') || condition.contains('thunder') || condition.contains('bão')) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade700],
      );
    } else if (isDay) {
      // Sunny day
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.orange.shade400, Colors.deepOrange.shade600],
      );
    } else {
      // Clear night
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.indigo.shade400, Colors.indigo.shade700],
      );
    }
  }
}