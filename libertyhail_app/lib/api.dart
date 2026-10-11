import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class Api {
  static String? token;
  static Map<String, dynamic>? user;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    token = p.getString('token');
    final u = p.getString('user');
    user = u == null ? null : jsonDecode(u) as Map<String, dynamic>;
  }

  static Future<void> _save(String t, Map<String, dynamic> u) async {
    token = t;
    user = u;
    final p = await SharedPreferences.getInstance();
    await p.setString('token', t);
    await p.setString('user', jsonEncode(u));
  }

  static Future<void> logout() async {
    token = null;
    user = null;
    final p = await SharedPreferences.getInstance();
    await p.remove('token');
    await p.remove('user');
  }

  static Future<Map<String, dynamic>> _req(String method, String path, [Map<String, dynamic>? body]) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = {
      'content-type': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
    };
    http.Response r;
    try {
      switch (method) {
        case 'POST':
          r = await http.post(uri, headers: headers, body: jsonEncode(body ?? {}));
          break;
        case 'PATCH':
          r = await http.patch(uri, headers: headers, body: jsonEncode(body ?? {}));
          break;
        default:
          r = await http.get(uri, headers: headers);
      }
    } catch (_) {
      throw ApiException('Cannot reach server ($baseUrl). Check Wi-Fi / VPN / firewall.');
    }
    final data = r.body.isEmpty ? <String, dynamic>{} : jsonDecode(r.body) as Map<String, dynamic>;
    if (r.statusCode >= 400) {
      throw ApiException((data['message'] ?? data['error'] ?? 'Error ${r.statusCode}').toString());
    }
    return data;
  }

  static Future<Map<String, dynamic>> get(String path) => _req('GET', path);
  static Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body]) => _req('POST', path, body);
  static Future<Map<String, dynamic>> patch(String path, [Map<String, dynamic>? body]) => _req('PATCH', path, body);

  static Future<void> login(String email, String password) async {
    final r = await post('/api/auth/login', {'email': email.trim(), 'password': password});
    await _save(r['token'] as String, r['user'] as Map<String, dynamic>);
  }

  static Future<void> register(String name, String email, String password) async {
    final r = await post('/api/auth/register', {'name': name.trim(), 'email': email.trim(), 'password': password});
    await _save(r['token'] as String, r['user'] as Map<String, dynamic>);
  }
}
