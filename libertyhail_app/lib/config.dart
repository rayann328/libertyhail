// Server address. Use your PC's LAN IP (shown by the backend: "Server listening at http://192.168.x.x:3000").
// Works for a real phone (same Wi-Fi), the Android emulator, and Chrome.
const String serverHost = '192.168.0.104:3000';

String get baseUrl => 'http://$serverHost';
String get wsUrl => 'ws://$serverHost';
