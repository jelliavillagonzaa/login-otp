import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:login_otp/api_config.dart'
    show kApiDefaultPort, resolveApiBaseUrl, resolveApiUri;
import 'package:login_otp/api_http.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Login OTP',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final String _baseUrl = resolveApiBaseUrl();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  bool _otpSent = false;
  bool _loading = false;
  bool _hidePassword = true;
  String _message = '';
  bool _isSuccess = false;
  String _welcomeName = '';

  /// null = checking, true = reachable, false = not reachable
  bool? _apiReachable;

  @override
  void initState() {
    super.initState();
    _checkApi();
  }

  Future<void> _checkApi() async {
    setState(() => _apiReachable = null);
    try {
      final ok = await apiHealthCheck(_baseUrl);
      if (mounted) setState(() => _apiReachable = ok);
    } catch (_) {
      if (mounted) setState(() => _apiReachable = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  String _extractErrorBody(String raw, int statusCode) {
    if (raw.isEmpty) return 'Request failed: $statusCode';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        final message = decoded['message'];
        if (detail is String && detail.isNotEmpty) return detail;
        if (message is String && message.isNotEmpty) return message;
      }
    } catch (_) {
      // Non-JSON error response
    }
    return 'Request failed ($statusCode): $raw';
  }

  Future<void> _sendOtp() async {
    setState(() {
      _loading = true;
      _message = '';
    });

    try {
      final response = await apiPostJson(
        resolveApiUri(_baseUrl, 'login'),
        {
          'email': _emailController.text.trim(),
          'password': _passwordController.text,
        },
      );

      if (response.statusCode == 200) {
        Map<String, dynamic> body = {};
        try {
          if (response.body.isNotEmpty) {
            body = jsonDecode(response.body) as Map<String, dynamic>;
          }
        } catch (_) {
          body = {};
        }
        setState(() {
          _otpSent = true;
          _message = (body['message'] ?? 'OTP sent.') as String;
          _isSuccess = true;
          _apiReachable = true;
        });
      } else {
        setState(() {
          _message = _extractErrorBody(response.body, response.statusCode);
          _isSuccess = false;
        });
      }
    } catch (e) {
      setState(() {
        _message = friendlyApiError(e, _baseUrl);
        _isSuccess = false;
        _apiReachable = false;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyOtp() async {
    setState(() {
      _loading = true;
      _message = '';
    });

    try {
      final response = await apiPostJson(
        resolveApiUri(_baseUrl, 'verify-otp'),
        {
          'email': _emailController.text.trim(),
          'otp_code': _otpController.text.trim(),
        },
      );

      if (response.statusCode == 200) {
        Map<String, dynamic> body = {};
        try {
          if (response.body.isNotEmpty) {
            body = jsonDecode(response.body) as Map<String, dynamic>;
          }
        } catch (_) {
          body = {};
        }
        final email = _emailController.text.trim();
        final namePart = email.contains('@') ? email.split('@').first : email;

        setState(() {
          _isSuccess = true;
          _welcomeName = namePart;
          _message = (body['message'] ?? 'Login successful.') as String;
          _apiReachable = true;
        });
      } else {
        setState(() {
          _message = _extractErrorBody(response.body, response.statusCode);
          _isSuccess = false;
        });
      }
    } catch (e) {
      setState(() {
        _message = friendlyApiError(e, _baseUrl);
        _isSuccess = false;
        _apiReachable = false;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _logout() {
    setState(() {
      _otpSent = false;
      _isSuccess = false;
      _welcomeName = '';
      _message = '';
      _passwordController.clear();
      _otpController.clear();
    });
    _checkApi();
  }

  Widget _apiStatusBanner() {
    if (_apiReachable == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.deepPurple.shade400,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'Checking API at $_baseUrl…',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
          ],
        ),
      );
    }
    if (_apiReachable == true) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Icon(Icons.cloud_done_outlined, color: Colors.green.shade700, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _baseUrl.startsWith('/')
                    ? 'API reachable (debug: $_baseUrl → http://127.0.0.1:$kApiDefaultPort)'
                    : 'API reachable at $_baseUrl',
                style: TextStyle(color: Colors.green.shade800, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
    return Material(
      color: Colors.orange.shade50,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Walay connection sa API ($_baseUrl).\n'
                    '(No connection to the API.)',
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'I-run ang backend una: `start_backend.bat` sa project root, o `backend` → run.bat / python main.py.\n'
              'Ang web (debug) naga-proxy /api → http://127.0.0.1:$kApiDefaultPort — kinahanglan gihapon nga naka-run ang API.\n'
              'Susiha: http://127.0.0.1:$kApiDefaultPort/health',
              style: TextStyle(color: Colors.orange.shade900, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _loading ? null : _checkApi,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Susiha pag-usab / Check again'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isSuccess && _welcomeName.isNotEmpty) {
      return Scaffold(
        body: Center(
          child: Container(
            width: 320,
            padding: const EdgeInsets.all(24),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF6EEF9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.deepPurple,
                  child: Icon(Icons.check, color: Colors.white, size: 30),
                ),
                const SizedBox(height: 16),
                Text(
                  'Welcome, $_welcomeName!',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text('You have successfully logged in.'),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Log out'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            width: 420,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F2FA),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.deepPurple.shade100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Login',
                  style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter your email and password. OTP will be sent to your email.',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 16),
                _apiStatusBanner(),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: _hidePassword,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(() => _hidePassword = !_hidePassword);
                      },
                      icon: Icon(
                        _hidePassword ? Icons.visibility : Icons.visibility_off,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loading ? null : _sendOtp,
                  child: Text(_loading ? 'Sending...' : 'Send OTP to my email'),
                ),
                if (_otpSent) ...[
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text('OTP (from email)'),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.pin_outlined),
                      hintText: 'Enter 6-digit OTP',
                    ),
                  ),
                  FilledButton(
                    onPressed: _loading ? null : _verifyOtp,
                    child: Text(
                      _loading ? 'Verifying...' : 'Verify OTP & log in',
                    ),
                  ),
                ],
                if (_message.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isSuccess
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _isSuccess
                            ? Colors.green.shade300
                            : Colors.red.shade300,
                      ),
                    ),
                    child: Text(
                      _message,
                      style: TextStyle(
                        color: _isSuccess
                            ? Colors.green.shade800
                            : Colors.red.shade800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
