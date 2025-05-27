import 'package:flutter/material.dart';
import 'map_model.dart';
import 'map_controller.dart';
import 'map_view.dart';

class MapScreen extends StatefulWidget {
  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late final MapModel model;
  late final MapController controller;

  @override
  void initState() {
    super.initState();
    model = MapModel();
    controller = MapController(model);
  }

  @override
  void dispose() {
    model.dispose(); // Clean up MapModel resources
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MapView(model: model, controller: controller);
  }
}