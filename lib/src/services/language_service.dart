import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLanguage {
  vietnamese('vi', 'Tiếng Việt', '🇻🇳'),
  english('en', 'English', '🇬🇧');

  final String code;
  final String name;
  final String flag;

  const AppLanguage(this.code, this.name, this.flag);
}

class LanguageService extends ChangeNotifier {
  static const String _languageKey = 'app_language';
  AppLanguage _currentLanguage = AppLanguage.vietnamese;

  AppLanguage get currentLanguage => _currentLanguage;
  String get languageCode => _currentLanguage.code;

  LanguageService() {
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final languageCode = prefs.getString(_languageKey) ?? 'vi';

    _currentLanguage = AppLanguage.values.firstWhere(
          (lang) => lang.code == languageCode,
      orElse: () => AppLanguage.vietnamese,
    );
    notifyListeners();
  }

  Future<void> setLanguage(AppLanguage language) async {
    if (_currentLanguage == language) return;

    _currentLanguage = language;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, language.code);
    notifyListeners();
  }

  // Translation method
  String translate(String key) {
    return _translations[languageCode]?[key] ?? key;
  }

  // Get all translations for current language
  Map<String, String> get translations => _translations[languageCode] ?? {};
}

// Translation strings
final Map<String, Map<String, String>> _translations = {
  'vi': {
    // Navigation & Map
    'search_location': 'Tìm kiếm địa điểm...',
    'from': 'Từ',
    'to': 'Đến',
    'your_location': 'Vị trí của bạn',
    'select_destination': 'Chọn điểm đến',
    'calculating': 'Đang tính...',
    'km': 'km',
    'minutes': 'phút',
    'hours': 'giờ',
    'eta': 'Dự kiến đến',
    'shortest_path': 'Đường đi ngắn nhất',
    'total_time': 'Tổng thời gian',
    'show_turn_by_turn': 'Hiển thị chỉ đường',
    'turn_by_turn_navigation': 'Chỉ đường từng bước',
    'close': 'Đóng',
    'refresh': 'Làm mới',
    'details': 'Chi tiết',
    'update': 'Cập nhật',

    // Data status
    'using_live_data': 'Đang dùng dữ liệu trực tiếp',
    'no_live_data': 'Không có dữ liệu trực tiếp (API không khả dụng)',

    // Weather
    'weather_details': 'Chi tiết thời tiết',
    'current_weather': 'Thời tiết hiện tại',
    'feels_like': 'Cảm giác như',
    'humidity': 'Độ ẩm',
    'wind': 'Gió',
    'visibility': 'Tầm nhìn',
    'uv_index': 'Chỉ số UV',
    'pressure': 'Áp suất',
    'air_quality': 'Chất lượng không khí',
    'good': 'Tốt',
    'moderate': 'Trung bình',
    'unhealthy_sensitive': 'Không tốt cho nhóm nhạy cảm',
    'unhealthy': 'Không tốt',
    'very_unhealthy': 'Rất không tốt',
    'hazardous': 'Nguy hiểm',
    'unknown': 'Không rõ',
    'no_air_quality_data': 'Không có dữ liệu chất lượng không khí',

    // Driving conditions
    'driving_conditions': 'Điều kiện lái xe',
    'safe_to_drive': 'An toàn để lái xe',
    'be_careful': 'Cẩn thận khi lái xe',
    'dangerous_weather': 'Thời tiết nguy hiểm - Nên tránh lái xe',
    'weather_good_for_driving': 'Thời tiết tốt cho việc di chuyển',
    'warnings': 'Cảnh báo',
    'recommendations': 'Khuyến nghị',

    // News
    'local_news': 'Tin tức địa phương',
    'no_news': 'Không có tin tức nào hiện tại',
    'try_refresh': 'Hãy thử làm mới để tải tin tức mới',
    'refresh_news': 'Làm mới tin tức',
    'unknown_source': 'Không rõ nguồn',
    'no_title': 'Không có tiêu đề',
    'no_description': 'Không có mô tả',
    'tap_to_read_more': 'Nhấn để đọc thêm',
    'error_opening_article': 'Không thể mở bài báo',

    // Popular places
    'popular_places': 'Địa điểm nổi tiếng',
    'famous_places': 'Địa điểm nổi tiếng',
    'all': 'Tất cả',
    'food': 'Ăn uống',
    'shopping': 'Mua sắm',
    'tourism': 'Du lịch',
    'healthcare': 'Y tế',
    'education': 'Giáo dục',
    'transport': 'Giao thông',
    'banking': 'Ngân hàng',
    'fuel': 'Xăng dầu',
    'loading_places': 'Đang tải địa điểm...',
    'no_places_found': 'Không tìm thấy địa điểm nào',
    'try_another_category': 'Thử chọn danh mục khác hoặc làm mới',
    'selected_as_destination': 'Đã chọn "{name}" làm điểm đến',

    // Search
    'search_places': 'Tìm kiếm địa điểm',
    'enter_street_place': 'Nhập tên đường, địa điểm, quận...',
    'recent_searches': 'Tìm kiếm gần đây',
    'clear_all': 'Xóa tất cả',
    'searching': 'Đang tìm kiếm...',
    'no_results': 'Không tìm thấy kết quả',
    'try_different_keywords': 'Thử tìm kiếm với từ khóa khác',
    'example_searches': 'VD: "Quận 1", "Bến Thành", "Nguyễn Huệ"',
    'free_no_api_key': 'Miễn phí • Không cần API key',
    'results': 'kết quả',

    // Hazards
    'report_hazard': 'Báo cáo sự cố',
    'at_current_location': 'Tại vị trí hiện tại của bạn',
    'hazard_type': 'Loại sự cố',
    'accident': 'Tai nạn',
    'natural_hazard': 'Thiên tai',
    'road_work': 'Sửa chữa đường',
    'other': 'Khác',
    'detailed_description': 'Mô tả chi tiết',
    'please_enter_description': 'Vui lòng nhập mô tả',
    'duration': 'Thời gian hiệu lực',
    '15_minutes': '15 phút',
    '30_minutes': '30 phút',
    '1_hour': '1 giờ',
    '3_hours': '3 giờ',
    '6_hours': '6 giờ',
    '12_hours': '12 giờ',
    '24_hours': '24 giờ',
    'submit_report': 'Báo cáo sự cố',
    'please_fill_all_fields': 'Vui lòng điền đầy đủ thông tin',
    'error_reporting': 'Lỗi khi báo cáo',
    'hazard_reported_success': 'Sự cố đã được báo cáo thành công!',

    // Time ago
    'days_ago': 'ngày trước',
    'hours_ago': 'giờ trước',
    'minutes_ago': 'phút trước',
    'just_now': 'Vừa xong',

    // Settings/Language
    'language': 'Ngôn ngữ',
    'change_language': 'Đổi ngôn ngữ',
  },

  'en': {
    // Navigation & Map
    'search_location': 'Search for a location...',
    'from': 'From',
    'to': 'To',
    'your_location': 'Your Location',
    'select_destination': 'Select Destination',
    'calculating': 'Calculating...',
    'km': 'km',
    'minutes': 'minutes',
    'hours': 'hours',
    'eta': 'ETA',
    'shortest_path': 'Shortest Path',
    'total_time': 'Total Time',
    'show_turn_by_turn': 'Show Turn-by-Turn',
    'turn_by_turn_navigation': 'Turn-by-Turn Navigation',
    'close': 'Close',
    'refresh': 'Refresh',
    'details': 'Details',
    'update': 'Update',

    // Data status
    'using_live_data': 'Using Live Data',
    'no_live_data': 'No Live Data (API Unavailable)',

    // Weather
    'weather_details': 'Weather Details',
    'current_weather': 'Current Weather',
    'feels_like': 'Feels like',
    'humidity': 'Humidity',
    'wind': 'Wind',
    'visibility': 'Visibility',
    'uv_index': 'UV Index',
    'pressure': 'Pressure',
    'air_quality': 'Air Quality',
    'good': 'Good',
    'moderate': 'Moderate',
    'unhealthy_sensitive': 'Unhealthy for Sensitive Groups',
    'unhealthy': 'Unhealthy',
    'very_unhealthy': 'Very Unhealthy',
    'hazardous': 'Hazardous',
    'unknown': 'Unknown',
    'no_air_quality_data': 'No air quality data available',

    // Driving conditions
    'driving_conditions': 'Driving Conditions',
    'safe_to_drive': 'Safe to drive',
    'be_careful': 'Be careful when driving',
    'dangerous_weather': 'Dangerous weather - Avoid driving',
    'weather_good_for_driving': 'Weather is good for travel',
    'warnings': 'Warnings',
    'recommendations': 'Recommendations',

    // News
    'local_news': 'Local News',
    'no_news': 'No news available',
    'try_refresh': 'Try refreshing to load new articles',
    'refresh_news': 'Refresh News',
    'unknown_source': 'Unknown source',
    'no_title': 'No title',
    'no_description': 'No description',
    'tap_to_read_more': 'Tap to read more',
    'error_opening_article': 'Could not open article',

    // Popular places
    'popular_places': 'Popular Places',
    'famous_places': 'Famous Places',
    'all': 'All',
    'food': 'Food',
    'shopping': 'Shopping',
    'tourism': 'Tourism',
    'healthcare': 'Healthcare',
    'education': 'Education',
    'transport': 'Transport',
    'banking': 'Banking',
    'fuel': 'Fuel',
    'loading_places': 'Loading places...',
    'no_places_found': 'No places found',
    'try_another_category': 'Try another category or refresh',
    'selected_as_destination': 'Selected "{name}" as destination',

    // Search
    'search_places': 'Search places',
    'enter_street_place': 'Enter street name, place, district...',
    'recent_searches': 'Recent searches',
    'clear_all': 'Clear all',
    'searching': 'Searching...',
    'no_results': 'No results found',
    'try_different_keywords': 'Try searching with different keywords',
    'example_searches': 'E.g. "District 1", "Ben Thanh", "Nguyen Hue"',
    'free_no_api_key': 'Free • No API key needed',
    'results': 'results',

    // Hazards
    'report_hazard': 'Report Hazard',
    'at_current_location': 'At your current location',
    'hazard_type': 'Hazard Type',
    'accident': 'Accident',
    'natural_hazard': 'Natural Hazard',
    'road_work': 'Road Work',
    'other': 'Other',
    'detailed_description': 'Detailed Description',
    'please_enter_description': 'Please enter description',
    'duration': 'Duration',
    '15_minutes': '15 minutes',
    '30_minutes': '30 minutes',
    '1_hour': '1 hour',
    '3_hours': '3 hours',
    '6_hours': '6 hours',
    '12_hours': '12 hours',
    '24_hours': '24 hours',
    'submit_report': 'Submit Report',
    'please_fill_all_fields': 'Please fill all fields',
    'error_reporting': 'Error reporting',
    'hazard_reported_success': 'Hazard reported successfully!',

    // Time ago
    'days_ago': 'days ago',
    'hours_ago': 'hours ago',
    'minutes_ago': 'minutes ago',
    'just_now': 'Just now',

    // Settings/Language
    'language': 'Language',
    'change_language': 'Change Language',
  },
};