import 'dart:convert';
import 'dart:math';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import '../utils/logger.dart';

/// Represents a single route alternative with scoring metadata
class RouteOption {
  final String routeId;
  final double distanceKm;
  final double estimatedTimeMinutes;
  final double? durationInTrafficMinutes;
  final String summary;
  final String distanceText;
  final String durationText;
  final String encodedPolyline;
  final List<LatLng> polylinePoints;
  final List<RouteStep> steps;
  final double score;
  final String startAddress;
  final String endAddress;

  RouteOption({
    required this.routeId,
    required this.distanceKm,
    required this.estimatedTimeMinutes,
    this.durationInTrafficMinutes,
    required this.summary,
    required this.distanceText,
    required this.durationText,
    required this.encodedPolyline,
    required this.polylinePoints,
    required this.steps,
    required this.score,
    this.startAddress = '',
    this.endAddress = '',
  });
}

/// A single routing step (turn-by-turn instruction)
class RouteStep {
  final String instruction;
  final int distanceMeters;
  final int durationSeconds;
  final String maneuver;

  RouteStep({
    required this.instruction,
    required this.distanceMeters,
    required this.durationSeconds,
    this.maneuver = '',
  });
}

/// Result of the optimal route selection
class OptimalRouteResult {
  final RouteOption selectedRoute;
  final List<RouteOption> allRoutes;
  final int alternativesEvaluated;
  final String reason;
  final double straightLineKm;
  final double routeEfficiency;
  final double processingTimeMs;

  OptimalRouteResult({
    required this.selectedRoute,
    required this.allRoutes,
    required this.alternativesEvaluated,
    required this.reason,
    required this.straightLineKm,
    required this.routeEfficiency,
    required this.processingTimeMs,
  });
}

/// Intelligent ambulance routing service.
///
/// Fetches multiple alternative routes from Google Directions API,
/// scores them based on distance, travel time, and road quality,
/// then returns the optimal route for emergency dispatch.
class SmartRouteService {
  static final SmartRouteService _instance = SmartRouteService._internal();
  factory SmartRouteService() => _instance;
  SmartRouteService._internal();

  static const String _apiKey = 'AIzaSyB4P99kVH_B4Y1sdLmIEvVjrpO-cZFrFKY';

  /// Get the optimal emergency route from ambulance to accident location.
  ///
  /// Fetches up to 3 alternative routes from Google Directions API
  /// and selects the best one using weighted scoring.
  Future<OptimalRouteResult> getOptimalRoute({
    required LatLng ambulanceLocation,
    required LatLng accidentLocation,
  }) async {
    final stopwatch = Stopwatch()..start();

    Log.d('[SmartRoute] Finding optimal route: '
        '(${ambulanceLocation.latitude},${ambulanceLocation.longitude}) → '
        '(${accidentLocation.latitude},${accidentLocation.longitude})');

    // 1. Fetch alternative routes from Google Directions
    final routes = await _fetchAlternativeRoutes(
      origin: ambulanceLocation,
      destination: accidentLocation,
    );

    if (routes.isEmpty) {
      throw Exception('No routes found between the locations');
    }

    Log.d('[SmartRoute] Found ${routes.length} alternative route(s)');
    for (final r in routes) {
      Log.d('   → ${r.routeId}: ${r.distanceKm} km, '
          '${r.estimatedTimeMinutes.toStringAsFixed(1)} min '
          'via ${r.summary} (score: ${r.score.toStringAsFixed(2)})');
    }

    // 2. Select the best route (already sorted by score)
    final best = routes.first;

    // 3. Build reasoning
    String reason;
    if (routes.length == 1) {
      reason = 'Only available route';
    } else {
      final parts = <String>[];
      final second = routes[1];
      final distDiff = second.distanceKm - best.distanceKm;
      final timeDiff = second.estimatedTimeMinutes - best.estimatedTimeMinutes;

      if (distDiff > 0.5) parts.add('${distDiff.toStringAsFixed(1)} km shorter than alternative');
      if (timeDiff > 1) parts.add('${timeDiff.toStringAsFixed(0)} min faster than alternative');
      if (best.summary.isNotEmpty) parts.add('Via ${best.summary}');
      if (parts.isEmpty) parts.add('Shortest and fastest route for ambulance dispatch');
      reason = parts.join('; ');
    }

    // 4. Calculate straight-line distance for efficiency metric
    final straightLineKm = _haversineDistance(
      ambulanceLocation.latitude, ambulanceLocation.longitude,
      accidentLocation.latitude, accidentLocation.longitude,
    );
    final efficiency = (straightLineKm / max(best.distanceKm, 0.01)) * 100;

    stopwatch.stop();

    Log.d('[SmartRoute] ✅ Selected ${best.routeId}: '
        '${best.distanceKm} km, ${best.estimatedTimeMinutes.toStringAsFixed(1)} min '
        '(score: ${best.score.toStringAsFixed(2)}) in ${stopwatch.elapsedMilliseconds}ms');

    return OptimalRouteResult(
      selectedRoute: best,
      allRoutes: routes,
      alternativesEvaluated: routes.length,
      reason: reason,
      straightLineKm: straightLineKm,
      routeEfficiency: efficiency,
      processingTimeMs: stopwatch.elapsedMilliseconds.toDouble(),
    );
  }

  /// Fetch alternative routes from Google Directions API, parse and score them.
  Future<List<RouteOption>> _fetchAlternativeRoutes({
    required LatLng origin,
    required LatLng destination,
  }) async {
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json?'
      'origin=${origin.latitude},${origin.longitude}&'
      'destination=${destination.latitude},${destination.longitude}&'
      'mode=driving&'
      'alternatives=true&'
      'departure_time=now&'
      'key=$_apiKey',
    );

    final response = await http.get(url).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Google Directions API HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body);
    final status = data['status'] as String?;

    if (status != 'OK') {
      throw Exception('Google Directions API error: $status');
    }

    final rawRoutes = data['routes'] as List<dynamic>? ?? [];
    final routes = <RouteOption>[];

    for (int i = 0; i < rawRoutes.length; i++) {
      final raw = rawRoutes[i];
      final legs = raw['legs'] as List<dynamic>? ?? [];
      if (legs.isEmpty) continue;

      final leg = legs[0];
      final distanceM = (leg['distance']?['value'] as num?)?.toDouble() ?? 0;
      final durationS = (leg['duration']?['value'] as num?)?.toDouble() ?? 0;
      final durationTrafficS = (leg['duration_in_traffic']?['value'] as num?)?.toDouble();

      // Parse steps
      final rawSteps = leg['steps'] as List<dynamic>? ?? [];
      final steps = rawSteps.map((s) => RouteStep(
        instruction: (s['html_instructions'] as String?)?.replaceAll(RegExp(r'<[^>]*>'), '') ?? '',
        distanceMeters: (s['distance']?['value'] as num?)?.toInt() ?? 0,
        durationSeconds: (s['duration']?['value'] as num?)?.toInt() ?? 0,
        maneuver: s['maneuver'] as String? ?? '',
      )).toList();

      // Decode polyline
      final encodedPolyline = raw['overview_polyline']?['points'] as String? ?? '';
      final polylinePoints = _decodePolyline(encodedPolyline);

      final distanceKm = distanceM / 1000;
      final durationMin = durationS / 60;
      final durationTrafficMin = durationTrafficS != null ? durationTrafficS / 60 : null;
      final summary = raw['summary'] as String? ?? '';

      // Score the route
      final score = _scoreRoute(
        distanceKm: distanceKm,
        durationMin: durationMin,
        durationTrafficMin: durationTrafficMin,
        summary: summary,
      );

      routes.add(RouteOption(
        routeId: 'route_$i',
        distanceKm: double.parse(distanceKm.toStringAsFixed(2)),
        estimatedTimeMinutes: double.parse(durationMin.toStringAsFixed(1)),
        durationInTrafficMinutes: durationTrafficMin != null
            ? double.parse(durationTrafficMin.toStringAsFixed(1))
            : null,
        summary: summary,
        distanceText: leg['distance']?['text'] ?? '',
        durationText: leg['duration']?['text'] ?? '',
        encodedPolyline: encodedPolyline,
        polylinePoints: polylinePoints,
        steps: steps,
        score: score,
        startAddress: leg['start_address'] ?? '',
        endAddress: leg['end_address'] ?? '',
      ));
    }

    // Sort by score (lower = better)
    routes.sort((a, b) => a.score.compareTo(b.score));
    return routes;
  }

  /// Score a route for emergency ambulance dispatch.
  /// Lower score = better route.
  ///
  /// Weights:
  ///   - Distance (km): 40%
  ///   - Duration (min): 50%
  ///   - Road quality: 10%
  double _scoreRoute({
    required double distanceKm,
    required double durationMin,
    double? durationTrafficMin,
    required String summary,
  }) {
    final summaryLower = summary.toLowerCase();

    // Highway bonus
    double roadBonus = 0;
    final highwayKeywords = [
      'highway', 'expressway', 'nh', 'sh', 'national',
      'bypass', 'ring road', 'motorway', 'outer ring',
    ];
    if (highwayKeywords.any((kw) => summaryLower.contains(kw))) {
      roadBonus = -2.0; // Reward
    }

    // Penalty for bad roads
    final avoidKeywords = ['residential', 'service road', 'narrow', 'unpaved'];
    if (avoidKeywords.any((kw) => summaryLower.contains(kw))) {
      roadBonus += 3.0;
    }

    // Traffic penalty
    if (durationTrafficMin != null && durationTrafficMin > durationMin * 1.3) {
      roadBonus += 5.0;
    }

    return (distanceKm * 0.4) + (durationMin * 0.5) + roadBonus;
  }

  /// Decode an encoded Google polyline string into LatLng points.
  List<LatLng> _decodePolyline(String encoded) {
    if (encoded.isEmpty) return [];
    final points = <LatLng>[];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int shift = 0;
      int result = 0;
      int byte;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1F) << shift;
        shift += 5;
      } while (byte >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      shift = 0;
      result = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1F) << shift;
        shift += 5;
      } while (byte >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  /// Haversine distance between two GPS coordinates (in km).
  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0;
    final dlat = _toRadians(lat2 - lat1);
    final dlon = _toRadians(lon2 - lon1);
    final a = sin(dlat / 2) * sin(dlat / 2) +
        cos(_toRadians(lat1)) * cos(_toRadians(lat2)) *
        sin(dlon / 2) * sin(dlon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _toRadians(double degrees) => degrees * pi / 180;
}
