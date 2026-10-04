import 'dart:io';
import 'dart:typed_data';

Future<Uint8List?> readMediaBytes(String path) async {
  try {
    return await File(path).readAsBytes();
  } catch (_) {
    return null;
  }
}
