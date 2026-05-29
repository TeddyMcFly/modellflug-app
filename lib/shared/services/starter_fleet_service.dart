import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/fleet_state.dart';

const starterFleetAssetPath = 'assets/demo/starter_fleet.json';
const starterFleetFileName = 'starter_fleet.json';
const _starterFleetOverrideKey = 'modellflug_starter_fleet_json';

Future<String> loadBundledStarterFleetJson() {
  return rootBundle.loadString(starterFleetAssetPath);
}

Future<String> loadEffectiveStarterFleetJson() async {
  final preferences = await SharedPreferences.getInstance();
  final override = preferences.getString(_starterFleetOverrideKey)?.trim();
  if (override != null && override.isNotEmpty) {
    return override;
  }
  return loadBundledStarterFleetJson();
}

Future<bool> hasStarterFleetOverride() async {
  final preferences = await SharedPreferences.getInstance();
  final override = preferences.getString(_starterFleetOverrideKey)?.trim();
  return override != null && override.isNotEmpty;
}

Future<void> saveStarterFleetOverrideJson(String content) async {
  final normalized = normalizeStarterFleetJson(content);
  final preferences = await SharedPreferences.getInstance();
  await preferences.setString(_starterFleetOverrideKey, normalized);
}

Future<void> clearStarterFleetOverride() async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.remove(_starterFleetOverrideKey);
}

Future<FleetState> loadStarterFleetState() async {
  return parseStarterFleetState(await loadEffectiveStarterFleetJson());
}

FleetState parseStarterFleetState(String content) {
  final decoded = jsonDecode(content) as Map<String, dynamic>;
  return FleetState.fromJson(decoded).copyWith(isLoaded: true);
}

String normalizeStarterFleetJson(String content) {
  final decoded = jsonDecode(content);
  return const JsonEncoder.withIndent('  ').convert(decoded);
}

String starterFleetJsonFromState(FleetState state) {
  return const JsonEncoder.withIndent('  ').convert(state.toJson());
}
