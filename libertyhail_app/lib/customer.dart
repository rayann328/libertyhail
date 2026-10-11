import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api.dart';
import 'common.dart';
import 'config.dart';
import 'login.dart';

const cancellable = ['ASSIGNED', 'EN_ROUTE_TO_PICKUP', 'ARRIVED'];

class CustomerHome extends StatefulWidget {
  const CustomerHome({super.key});
  @override
  State<CustomerHome> createState() => _CustomerHomeState();
}

class _CustomerHomeState extends State<CustomerHome> {
  final map = MapController();
  LatLng? pickup, dest, car;
  Map<String, dynamic>? trip;
  int? eta;
  double? dist;
  WebSocketChannel? ch;
  StreamSubscription? sub;
  bool busy = false, ready = false, closing = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    closing = true;
    _disconnect();
    super.dispose();
  }

  Future<void> _init() async {
    pickup = await currentLatLng();
    try {
      final r = await Api.get('/api/trips/active/me');
      if (r['trip'] != null) {
        _setTrip(r['trip'] as Map<String, dynamic>, e: r['eta_minutes'], d: r['distance_km']);
      }
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
    if (mounted) setState(() => ready = true);
  }

  void _setTrip(Map<String, dynamic> t, {dynamic e, dynamic d}) {
    trip = Map<String, dynamic>.from(t);
    eta = (e as num?)?.toInt();
    dist = (d as num?)?.toDouble();
    final drv = t['driver'];
    car = drv == null ? null : latLngOf(drv['lastLatitude'], drv['lastLongitude']);
    pickup = LatLng(num2d(t['pickupLatitude']), num2d(t['pickupLongitude']));
    dest = LatLng(num2d(t['destinationLatitude']), num2d(t['destinationLongitude']));
    _connect();
  }

  void _connect() {
    _disconnect();
    final id = trip!['id'];
    final c = WebSocketChannel.connect(Uri.parse('$wsUrl/ws?token=${Api.token}&trip_id=$id'));
    ch = c;
    sub = c.stream.listen(
      _onMsg,
      onError: (_) {},
      onDone: () {
        if (closing || trip == null || ch != c) return;
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && trip != null && ch == c) _connect();
        });
      },
    );
  }

  void _disconnect() {
    sub?.cancel();
    sub = null;
    ch?.sink.close();
    ch = null;
  }

  void _onMsg(dynamic raw) {
    if (trip == null) return;
    final m = jsonDecode(raw as String) as Map<String, dynamic>;
    final ev = m['event'];
    if (ev == 'snapshot' || ev == 'vehicle.location.updated') {
      final p = latLngOf(m['latitude'], m['longitude']);
      if (p != null) car = p;
      if (m['status'] != null) trip!['status'] = m['status'];
      eta = (m['eta_minutes'] as num?)?.toInt();
      dist = (m['distance_km'] as num?)?.toDouble();
      if (mounted) setState(() {});
      _follow();
    } else if (ev == 'trip.status.updated') {
      final s = m['status'] as String;
      trip!['status'] = s;
      if (mounted) setState(() {});
      if (s == 'COMPLETED' || s == 'CANCELLED') _finish(s);
    }
  }

  void _follow() {
    if (car == null) return;
    try {
      map.move(car!, map.camera.zoom);
    } catch (_) {}
  }

  void _finish(String s) {
    if (trip == null) return;
    _disconnect();
    trip = null;
    car = null;
    eta = null;
    dist = null;
    dest = null;
    if (!mounted) return;
    setState(() {});
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(statusLabel(s)),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  Future<void> _request() async {
    if (dest == null || pickup == null) return;
    setState(() => busy = true);
    try {
      final r = await Api.post('/api/trips', {
        'pickup_latitude': pickup!.latitude,
        'pickup_longitude': pickup!.longitude,
        'destination_latitude': dest!.latitude,
        'destination_longitude': dest!.longitude,
      });
      _setTrip(r['trip'] as Map<String, dynamic>);
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _cancel() async {
    if (trip == null) return;
    setState(() => busy = true);
    try {
      await Api.post('/api/trips/${trip!['id']}/cancel');
      _finish('CANCELLED');
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  Widget _panel() {
    if (trip == null) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Text(dest == null ? 'Tap the map to choose your destination' : 'Destination selected',
            style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: (dest == null || busy) ? null : _request,
            child: busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Request ride'),
          ),
        ),
      ]);
    }
    final t = trip!;
    final status = t['status'] as String;
    final v = t['vehicle'];
    final d = t['driver'];
    final driverName = d?['user']?['name'] ?? 'Driver';
    final carText = v == null ? '' : '${v['color'] ?? ''} ${v['make']} ${v['model']} • ${v['plateNumber']}';
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(statusLabel(status), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      Text('$driverName  •  $carText'),
      if (eta != null && dist != null) ...[
        const SizedBox(height: 6),
        Text('ETA: $eta min  •  ${dist!.toStringAsFixed(1)} km'),
      ],
      if (cancellable.contains(status)) ...[
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(onPressed: busy ? null : _cancel, child: const Text('Cancel trip')),
        ),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LibertyHail'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryScreen())),
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: () => doLogout(context)),
        ],
      ),
      body: !ready
          ? const Center(child: CircularProgressIndicator())
          : Stack(children: [
              FlutterMap(
                mapController: map,
                options: MapOptions(
                  initialCenter: pickup ?? fallbackPos,
                  initialZoom: 14,
                  onTap: trip == null ? (tp, ll) => setState(() => dest = ll) : null,
                ),
                children: [
                  osmTiles(),
                  MarkerLayer(markers: [
                    if (pickup != null) pin(pickup!, Icons.person_pin_circle, Colors.green),
                    if (dest != null) pin(dest!, Icons.flag, Colors.red),
                    if (car != null) pin(car!, Icons.directions_car, Colors.indigo, size: 44),
                  ]),
                ],
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Card(
                  elevation: 6,
                  child: Padding(padding: const EdgeInsets.all(16), child: _panel()),
                ),
              ),
            ]),
    );
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<dynamic>? trips;
  String? error;

  @override
  void initState() {
    super.initState();
    Api.get('/api/trips').then((r) {
      if (mounted) setState(() => trips = r['trips'] as List<dynamic>);
    }).catchError((e) {
      if (mounted) setState(() => error = '$e');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My trips')),
      body: error != null
          ? Center(child: Text(error!))
          : trips == null
              ? const Center(child: CircularProgressIndicator())
              : trips!.isEmpty
                  ? const Center(child: Text('No trips yet'))
                  : ListView.separated(
                      itemCount: trips!.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final t = trips![i] as Map<String, dynamic>;
                        final when = DateTime.tryParse('${t['requestedAt']}')?.toLocal();
                        return ListTile(
                          leading: const Icon(Icons.local_taxi),
                          title: Text(statusLabel(t['status'] as String)),
                          subtitle: Text(
                              '${when == null ? '' : when.toString().substring(0, 16)}\nTrip #${t['id']}  •  ${t['vehicle']?['plateNumber'] ?? ''}'),
                          isThreeLine: true,
                        );
                      },
                    ),
    );
  }
}
