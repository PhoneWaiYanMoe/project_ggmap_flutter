import 'package:flutter/material.dart';
import 'map_model.dart';
import 'map_controller.dart';
import 'map_view.dart';

class MapScreen extends StatelessWidget {
  final MapModel model = MapModel();
  late final MapController controller;

  MapScreen() {
    controller = MapController(model);
  }

  @override
  Widget build(BuildContext context) {
    return MapView(model: model, controller: controller);
  }
}