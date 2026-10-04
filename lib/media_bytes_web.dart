import 'dart:typed_data';
import 'package:http/http.dart' as http;

Future<Uint8List?> readMediaBytes(String path) async {
  try {
    final response = await http.get(Uri.parse(path));
    if (response.statusCode >= 200 && response.statusCode < 300) return response.bodyBytes;
  } catch (_) {}
  return null;
}
