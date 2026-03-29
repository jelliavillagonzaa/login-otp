import 'package:flutter/foundation.dart';

/// Set when you run or build: `--dart-define=API_BASE_URL=http://192.168.1.5:8000`
const String _kApiBaseFromEnv = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: '',
);

/// Default API port (must match [web_dev_config.yaml] proxy target if you change it).
const int kApiDefaultPort = 8000;

/// Build a request URI for [pathSegment] (e.g. `health`, `login`) under [baseUrl].
///
/// Root-relative bases like `/api` are resolved with [Uri.base] on web so the path
/// is always correct even when the app is not served from `/` (Flutter dev server).
Uri resolveApiUri(String baseUrl, String pathSegment) {
  final seg =
      pathSegment.startsWith('/') ? pathSegment.substring(1) : pathSegment;
  final abs = baseUrl.startsWith('http://') || baseUrl.startsWith('https://');
  if (abs) {
    final b =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$b/$seg');
  }
  if (kIsWeb && baseUrl.startsWith('/')) {
    final b =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.base.resolve('$b/$seg');
  }
  final b =
      baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
  return Uri.parse('$b/$seg');
}

/// Base URL for the FastAPI backend (no trailing slash).
///
/// On **web debug**, requests go to `/api/...` on the Flutter dev server, which
/// [web_dev_config.yaml] proxies to `http://127.0.0.1:8000/...` (same-origin in
/// the browser, so Chrome does not block private-network fetches).
String resolveApiBaseUrl() {
  final fromEnv = _kApiBaseFromEnv.trim();
  if (fromEnv.isNotEmpty) {
    return fromEnv.endsWith('/')
        ? fromEnv.substring(0, fromEnv.length - 1)
        : fromEnv;
  }
  if (kIsWeb) {
    if (kDebugMode) {
      return '/api';
    }
    // Release/profile web builds: no dev proxy; call the API host directly.
    return 'http://127.0.0.1:$kApiDefaultPort';
  }
  if (defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:$kApiDefaultPort';
  }
  return 'http://127.0.0.1:$kApiDefaultPort';
}
