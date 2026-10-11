import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

const fallbackPos = LatLng(33.8938, 35.5018); // Beirut

const statusLabels = {
  'ASSIGNED': 'Driver assigned',
  'EN_ROUTE_TO_PICKUP': 'Driver is on the way to you',
  'ARRIVED': 'Driver has arrived',
  'PASSENGER_ONBOARD': 'Trip started',
  'EN_ROUTE_TO_DESTINATION': 'On the way to destination',
  'COMPLETED': 'Trip completed',
  'CANCELLED': 'Trip cancelled',
  'EMERGENCY': 'Emergency reported',
};

String statusLabel(String s) => statusLabels[s] ?? s;

double num2d(dynamic v) => (v as num).toDouble();

LatLng? latLngOf(dynamic lat, dynamic lng) =>
    (lat == null || lng == null) ? null : LatLng(num2d(lat), num2d(lng));

TileLayer osmTiles() => TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.example.libertyhail',
    );

Marker pin(LatLng p, IconData icon, Color color, {double size = 40}) =>
    Marker(point: p, width: size, height: size, child: Icon(icon, color: color, size: size));

Future<Position?> currentPosition() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 8)),
    );
  } catch (_) {
    return null;
  }
}

Future<LatLng> currentLatLng() async {
  final p = await currentPosition();
  return p == null ? fallbackPos : LatLng(p.latitude, p.longitude);
}

void snack(BuildContext c, String msg) {
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg)));
}
