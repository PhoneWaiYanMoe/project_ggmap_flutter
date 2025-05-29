import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class NewsService {
  static final String _apiKey = "dc570a07990e4479b2f011474f64b402";
  static const String _baseUrl = 'https://newsapi.org/v2/everything';
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);

  Future<List<Map<String, dynamic>>> getNewsForLocation({
    LatLng? location,
    String? placeName,
    String language = 'vi',
    int pageSize = 5,
    String sortBy = 'publishedAt', // sort by most recent
  }) async {
    String query = placeName ?? 'Việt Nam';
    if (location != null && placeName == null) {
      query = 'tin tức Việt Nam';
    }

    if (_apiKey.isEmpty) {
      print('Error: NEWS_API_KEY is missing at ${DateTime.now()}');
      return [];
    }

    final url = Uri.parse(
      '$_baseUrl?q=${Uri.encodeComponent(query)}&language=$language&pageSize=$pageSize&sortBy=$sortBy&apiKey=$_apiKey',
    );

    int attempt = 0;
    while (attempt < _maxRetries) {
      try {
        print('Fetching news with query: $query (Attempt ${attempt + 1}/$_maxRetries) at ${DateTime.now()}');
        final response = await http.get(url).timeout(Duration(seconds: 10));

        if (response.statusCode != 200) {
          print('Failed to fetch news: Status ${response.statusCode}, Body: ${response.body} at ${DateTime.now()}');
          throw Exception('Non-200 status code: ${response.statusCode}');
        }

        final newsJson = jsonDecode(response.body);
        if (newsJson['status'] != 'ok') {
          print('Error: NewsAPI returned status ${newsJson['status']}: ${newsJson['message']} at ${DateTime.now()}');
          throw Exception('Invalid NewsAPI response');
        }

        final articles = newsJson['articles'] as List<dynamic>?;
        if (articles == null || articles.isEmpty) {
          print('No news articles found for query: $query at ${DateTime.now()}');
          return [];
        }

        final filteredArticles = articles.map((article) => {
          'title': article['title']?.toString() ?? 'Không có tiêu đề',
          'description': article['description']?.toString() ?? 'Không có mô tả',
          'url': article['url']?.toString() ?? '',
          'source': article['source']?['name']?.toString() ?? 'Không rõ nguồn',
          'publishedAt': article['publishedAt']?.toString() ?? '',
        }).toList();

        return filteredArticles;
      } catch (e) {
        attempt++;
        if (attempt == _maxRetries) {
          print('Max retries reached. Error: $e at ${DateTime.now()}');
          return [];
        }
        await Future.delayed(_retryDelay);
      }
    }

    return [];
  }
}
