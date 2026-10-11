import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'api.dart';
import 'common.dart';
import 'login.dart';

const toPickup = ['ASSIGNED', 'EN_ROUTE_TO_PICKUP', 'ARRIVED'];

// current status -> [next status, button label]
const nextStep = {
  'ASSIGNED': ['EN_ROUTE_TO_PICKUP', 'Start going to pickup'],
  'EN_ROUTE_TO_PICKUP': ['ARRIVED', 'I have arrived'],
  'ARRIVED': ['PASSENGER_ONBOARD', 'Passenger on board'],
  'PASSENGER_ONBOARD': ['EN_ROUTE_TO_DESTINATION', 'Start trip to destination'],
  'EN_ROUTE_TO_DESTINATION': ['COMPLETED', 'Complete trip'],
  'EMERGENCY': ['COMPLETED', 'Complete trip'],
};

class DriverHome extends StatefulWidget {
  const DriverHome({super.key});
  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  final map = MapController();
  bool online = false, sim = false, busy = false, ticking = false, ready = false;
  Timer? timer;
  LatLng? pos, simPos;
  Map<String, dynamic>? trip;
  String? error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      final r = await Api.get('/api/drivers/me/active-trip');
      trip = r['trip'] as Map<String, dynamic>?;
      if (trip != null) {
        online = true;
        _startTimer();
      } else {
        await Api.patch('/api/drivers/me/status', {'status': 'OFFLINE'});
      }
      pos = await currentLatLng();
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => ready = true);
  }

  void _startTimer() {
    timer?.cancel();
    _tick();
    timer = Timer.periodic(const Duration(seconds: 3), (_) => _tick());
  }

  LatLng? _target() {
    if (trip == null) return null;
    final st = trip!['status'] as String;
    return toPickup.contains(st)
        ? LatLng(num2d(trip!['pickupLatitude']), num2d(trip!['pickupLongitude']))
        : LatLng(num2d(trip!['destinationLatitude']), num2d(trip!['destinationLongitude']));
  }

  // Demo mode: the "car" drives toward the target while the driver is en route.
  LatLng _simStep() {
    final target = _target();
    if (trip == null) {
      simPos = null;
      return pos ?? fallbackPos;
    }
    simPos ??= LatLng(target!.latitude + 0.02, target.longitude + 0.02);
    final st = trip!['status'] as String;
    if (st == 'EN_ROUTE_TO_PICKUP' || st == 'EN_ROUTE_TO_DESTINATION') {
      final dLat = target!.latitude - simPos!.latitude;
      final dLng = target.longitude - simPos!.longitude;
      final d = sqrt(dLat * dLat + dLng * dLng);
      final step = max(d * 0.2, 0.0008);
      simPos = step >= d ? target : LatLng(simPos!.latitude + dLat * step / d, simPos!.longitude + dLng * step / d);
    }
    return simPos!;
  }

  Future<void> _tick() async {
    if (!online || ticking) return;
    ticking = true;
    try {
      double speed = 0, heading = 0, accuracy = 0;
      LatLng p;
      if (sim) {
        p = _simStep();
        speed = 8;
      } else {
        final g = await currentPosition();
        if (g == null) throw ApiException('Location unavailable. Turn on GPS / allow permission, or enable Simulation.');
        p = LatLng(g.latitude, g.longitude);
        speed = max(0, g.speed);
        heading = g.heading.clamp(0, 360).toDouble();
        accuracy = max(0, g.accuracy);
      }
      pos = p;
      await Api.post('/api/drivers/location', {
        'latitude': p.latitude,
        'longitude': p.longitude,
        'speed': speed,
        'heading': heading,
        'accuracy': accuracy,
      });
      final r = await Api.get('/api/drivers/me/active-trip');
      trip = r['trip'] as Map<String, dynamic>?;
      error = null;
      try {
        map.move(p, map.camera.zoom);
      } catch (_) {}
    } catch (e) {
      error = '$e';
    }
    ticking = false;
    if (mounted) setState(() {});
  }

  Future<void> _toggleOnline(bool v) async {
    if (!v && trip != null) {
      snack(context, 'Finish your current trip first');
      return;
    }
    try {
      await Api.patch('/api/drivers/me/status', {'status': v ? 'AVAILABLE' : 'OFFLINE'});
      setState(() => online = v);
      if (v) {
        _startTimer();
      } else {
        timer?.cancel();
      }
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
  }

  Future<void> _changeStatus(String status) async {
    if (trip == null) return;
    setState(() => busy = true);
    try {
      await Api.patch('/api/trips/${trip!['id']}/status', {
        'status': status,
        if (pos != null) 'latitude': pos!.latitude,
        if (pos != null) 'longitude': pos!.longitude,
      });
      final r = await Api.get('/api/drivers/me/active-trip');
      trip = r['trip'] as Map<String, dynamic>?;
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  Widget _tripCard() {
    if (trip == null) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(online ? 'Waiting for trips…' : 'You are offline', style: const TextStyle(fontSize: 16)),
      );
    }
    final st = trip!['status'] as String;
    final next = nextStep[st];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Trip #${trip!['id']} • ${statusLabel(st)}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      if (next != null)
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(onPressed: busy ? null : () => _changeStatus(next[0]), child: Text(next[1])),
        ),
      if (st != 'EMERGENCY' && st != 'COMPLETED')
        TextButton.icon(
          onPressed: busy ? null : () => _changeStatus('EMERGENCY'),
          icon: const Icon(Icons.warning, color: Colors.red),
          label: const Text('Emergency', style: TextStyle(color: Colors.red)),
        ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final target = _target();
    return Scaffold(
      appBar: AppBar(
        title: Text('Driver • ${Api.user?['name'] ?? ''}'),
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => doLogout(context))],
      ),
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Expanded(
                child: FlutterMap(
                  mapController: map,
                  options: MapOptions(initialCenter: pos ?? fallbackPos, initialZoom: 14),
                  children: [
                    osmTiles(),
                    MarkerLayer(markers: [
                      if (target != null)
                        pin(target, toPickup.contains(trip!['status']) ? Icons.person_pin_circle : Icons.flag,
                            toPickup.contains(trip!['status']) ? Colors.green : Colors.red),
                      if (pos != null) pin(pos!, Icons.directions_car, Colors.indigo, size: 44),
                    ]),
                  ],
                ),
              ),
              Card(
                margin: EdgeInsets.zero,
                elevation: 8,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(online ? 'Online' : 'Offline'),
                      value: online,
                      onChanged: _toggleOnline,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Simulate movement (demo)'),
                      value: sim,
                      onChanged: (v) => setState(() {
                        sim = v;
                        simPos = null;
                      }),
                    ),
                    if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
                    _tripCard(),
                  ]),
                ),
              ),
            ]),
    );
  }
}
