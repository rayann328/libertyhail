import 'package:flutter/material.dart';
import 'api.dart';
import 'common.dart';
import 'customer.dart';
import 'driver.dart';

Widget homeFor() => Api.user?['role'] == 'driver' ? const DriverHome() : const CustomerHome();

void goHome(BuildContext c) {
  Navigator.of(c).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => homeFor()), (_) => false);
}

Future<void> doLogout(BuildContext c) async {
  await Api.logout();
  if (c.mounted) {
    Navigator.of(c).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final name = TextEditingController();
  final email = TextEditingController();
  final pass = TextEditingController();
  bool register = false, busy = false;

  Future<void> _submit() async {
    setState(() => busy = true);
    try {
      if (register) {
        await Api.register(name.text, email.text, pass.text);
      } else {
        await Api.login(email.text, pass.text);
      }
      if (mounted) goHome(context);
    } catch (e) {
      if (mounted) snack(context, '$e');
    }
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.local_taxi, size: 64, color: Colors.indigo),
                  const SizedBox(height: 8),
                  const Text('LibertyHail', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 24),
                  if (register) ...[
                    TextField(controller: name, decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())),
                    const SizedBox(height: 12),
                  ],
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pass,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: busy ? null : _submit,
                      child: busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(register ? 'Create account' : 'Login'),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => register = !register),
                    child: Text(register ? 'I already have an account' : 'Create a customer account'),
                  ),
                  const SizedBox(height: 8),
                  const Text('Test: customer@test.com / driver@test.com\nPassword: 123456',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
