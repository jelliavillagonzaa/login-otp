import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:login_otp/api_config.dart';

const Duration apiRequestTimeout = Duration(seconds: 25);
const Duration apiHealthTimeout = Duration(seconds: 8);

Future<http.Response> apiPostJson(
  Uri uri,
  Map<String, dynamic> body,
) async {
  return http
      .post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      )
      .timeout(apiRequestTimeout);
}

/// Returns true if GET /health responds with 200 (no Firestore).
/// Retries once after a short delay (proxy or API slow to answer).
Future<bool> apiHealthCheck(String baseUrl) async {
  Future<bool> once() async {
    final uri = resolveApiUri(baseUrl, 'health');
    final response = await http.get(uri).timeout(apiHealthTimeout);
    return response.statusCode == 200;
  }

  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      if (await once()) return true;
    } catch (_) {
      // Connection errors: retry once.
    }
    if (attempt == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
  return false;
}

String friendlyApiError(Object error, String baseUrl) {
  if (error is TimeoutException) {
    return 'The server did not respond in time.\n'
        'Make sure the API is running and reachable at $baseUrl.';
  }
  final text = error.toString();
  if (text.contains('Failed to fetch') ||
      text.contains('ClientException') ||
      text.contains('Connection refused') ||
      text.contains('SocketException')) {
    return 'Cannot reach the API at $baseUrl.\n\n'
        '1. From the project root, run start_backend.bat, or open login_otp/backend and run: python main.py (or run.bat).\n'
        '2. Confirm http://127.0.0.1:$kApiDefaultPort/health returns JSON in a browser.\n\n'
        'Debug web uses path $baseUrl on the Flutter dev server, which proxies to http://127.0.0.1:8000 (see web_dev_config.yaml).';
  }
  return 'Something went wrong: $error';
}
