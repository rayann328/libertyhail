// Server address.
// - Chrome / Windows desktop, same PC as the backend: localhost:3000
// - Android emulator: 10.0.2.2:3000
// - Real phone: your PC's LAN IP, e.g. 192.168.0.104:3000 (same Wi-Fi)
const String serverHost = 'localhost:3000';

String get baseUrl => 'http://$serverHost';
String get wsUrl => 'ws://$serverHost';
