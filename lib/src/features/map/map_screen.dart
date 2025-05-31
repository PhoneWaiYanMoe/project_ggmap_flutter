import 'package:flutter/material.dart';
import 'map_model.dart';
import 'map_controller.dart';
import 'map_view.dart';
import '../../services/language_service.dart';

class MapScreen extends StatefulWidget {
  final LanguageService? languageService;

  const MapScreen({super.key, this.languageService});

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late final MapModel model;
  late final MapController controller;
  late final LanguageService languageService;

  @override
  void initState() {
    super.initState();
    languageService = widget.languageService ?? LanguageService();
    model = MapModel();
    controller = MapController(model, languageService);
  }

  @override
  void dispose() {
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MapView(
      model: model,
      controller: controller,
      languageService: languageService,
    );
  }
}