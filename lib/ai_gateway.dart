import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'backend_contract.dart';
import 'auth_service.dart';

class AiGateway {
  static String? lastCodexError;
  static String? lastCodexUserCode;
  static String? lastCodexVerificationUrl;
  static Map<String, String> get _authHeaders => {if (AuthService.accessToken != null) 'authorization': 'Bearer ${AuthService.accessToken}'};
  static Future<List<Map<String, dynamic>>> notes({required String ownerId}) async {
    final response = await http.get(Uri.parse('${LumenoteBackendConfig.aiGatewayUrl}/api/notes'), headers: _authHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('No se pudieron cargar las notas.');
    return ((jsonDecode(response.body) as Map<String, dynamic>)['notes'] as List).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> topics() async {
    final response = await http.get(Uri.parse('${LumenoteBackendConfig.aiGatewayUrl}/api/topics'), headers: _authHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('No se pudieron cargar los temas.');
    return ((jsonDecode(response.body) as Map<String, dynamic>)['topics'] as List).cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>?> branding() async {
    final response = await http.get(Uri.parse('${LumenoteBackendConfig.aiGatewayUrl}/api/branding'), headers: _authHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    return (jsonDecode(response.body) as Map<String, dynamic>)['branding'] as Map<String, dynamic>?;
  }

  static Future<Map<String, dynamic>> createTopic(String title, {String description = ''}) async {
    final response = await http.post(Uri.parse('${LumenoteBackendConfig.aiGatewayUrl}/api/topics'), headers: {'content-type': 'application/json', ..._authHeaders}, body: jsonEncode({'title': title, 'description': description}));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('No se pudo crear el tema.');
    return (jsonDecode(response.body) as Map<String, dynamic>)['topic'] as Map<String, dynamic>;
  }

  static Future<void> updateTopic(String id, String title, {String description = ''}) async {
    final response = await http.patch(Uri.parse('${LumenoteBackendConfig.aiGatewayUrl}/api/topics/$id'), headers: {'content-type': 'application/json', ..._authHeaders}, body: jsonEncode({'title': title, 'description': description}));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('No se pudo actualizar el tema.');
  }

  static Future<void> assignTopic(String noteId, String? topicId) async {
    final response = await http.patch(Uri.parse('${LumenoteBackendConfig.aiGatewayUrl}/api/notes/$noteId/topic'), headers: {'content-type': 'application/json', ..._authHeaders}, body: jsonEncode({'topic_id': topicId}));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('No se pudo organizar la nota.');
  }

  static Future<void> updateNote(String id, String title) async {
    final response = await http.patch(Uri.parse('${LumenoteBackendConfig.aiGatewayUrl}/api/notes/$id'), headers: {'content-type': 'application/json', ..._authHeaders}, body: jsonEncode({'title': title}));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('No se pudo actualizar la nota.');
  }

  static Future<Map<String, dynamic>> createNote({required String ownerId, required String title, required String source, String? mediaType, String? storagePath, String? topicId, String speakerMode = 'single', int speakerCount = 1}) async {
    final response = await http.post(Uri.parse('${LumenoteBackendConfig.aiGatewayUrl}/api/notes'), headers: {'content-type': 'application/json', ..._authHeaders}, body: jsonEncode({'title': title, 'source': source, 'media_type': mediaType, 'storage_path': storagePath, 'topic_id': topicId, 'speaker_mode': speakerMode, 'speaker_count': speakerCount}));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('No se pudo guardar la nota.');
    return (jsonDecode(response.body) as Map<String, dynamic>)['note'] as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> transcribeBytes({required List<int> bytes, required String filename, String? noteId}) async {
    final request = http.MultipartRequest('POST', Uri.parse('${LumenoteBackendConfig.aiGatewayUrl}/api/ai/transcribe'));
    request.headers.addAll(_authHeaders);
    if (noteId != null) request.fields['note_id'] = noteId;
    request.fields['language'] = AuthService.preferredLanguage;
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('No se pudo transcribir el audio.');
    return jsonDecode(body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> processMedia({required String noteId, required List<int> bytes, required String filename, String? mediaType, String speakerMode = 'single', int speakerCount = 1}) async {
    final request = http.MultipartRequest('POST', Uri.parse('${LumenoteBackendConfig.aiGatewayUrl}/api/notes/$noteId/process-media'));
    request.headers.addAll(_authHeaders);
    if (mediaType != null) request.fields['media_type'] = mediaType;
    request.fields['language'] = AuthService.preferredLanguage;
    request.fields['speaker_mode'] = speakerMode;
    request.fields['speaker_count'] = '$speakerCount';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('No se pudo procesar la captura.');
    return jsonDecode(body) as Map<String, dynamic>;
  }

  static Future<void> processText({required String noteId, required String text}) async {
    final response = await http.post(Uri.parse('${LumenoteBackendConfig.aiGatewayUrl}/api/notes/$noteId/process-text'), headers: {'content-type': 'application/json', ..._authHeaders}, body: jsonEncode({'text': text}));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('No se pudo procesar el texto.');
  }

  static Future<Map<String, dynamic>?> noteInsights(String noteId) async {
    final response = await http.get(Uri.parse('${LumenoteBackendConfig.aiGatewayUrl}/api/notes/$noteId/insights'), headers: _authHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    return (jsonDecode(response.body) as Map<String, dynamic>)['insights'] as Map<String, dynamic>?;
  }

  static Future<void> reprocess(String noteId) async {
    final response = await http.post(Uri.parse('${LumenoteBackendConfig.aiGatewayUrl}/api/notes/$noteId/reprocess'), headers: _authHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('No se pudo reintentar el procesamiento.');
  }

  static Future<Uint8List> noteMedia(String noteId) async {
    final response = await http.get(Uri.parse('${LumenoteBackendConfig.aiGatewayUrl}/api/notes/$noteId/media'), headers: _authHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception('No se pudo cargar el audio guardado.');
    return response.bodyBytes;
  }


  static Future<void> deleteNote(String id) async {
    final response = await http.delete(Uri.parse('${LumenoteBackendConfig.aiGatewayUrl}/api/notes/$id'), headers: _authHeaders);
    if (response.statusCode != 204) throw Exception('No se pudo eliminar la nota.');
  }

  static Future<bool> connectCodex({String ownerId = 'anonymous'}) async {
    try {
      lastCodexError = null;
      lastCodexUserCode = null;
      final response = await http.get(Uri.parse('${LumenoteBackendConfig.aiGatewayUrl}/api/codex/auth/oauth-start'), headers: _authHeaders);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        try { lastCodexError = (jsonDecode(response.body) as Map<String, dynamic>)['error'] as String?; } catch (_) {}
        lastCodexError ??= 'El servidor Codex no está configurado.';
        return false;
      }
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      lastCodexUserCode = data['user_code'] as String?;
      lastCodexVerificationUrl = data['authorization_url'] as String?;
      final uri = Uri.tryParse(data['authorization_url'] as String? ?? '');
      return uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (error) {
      lastCodexError = error.toString();
      return false;
    }
  }

  static Future<bool> codexDeviceStatus() async {
    try {
      final response = await http.get(Uri.parse('${LumenoteBackendConfig.aiGatewayUrl}/api/codex/auth/device-status'), headers: _authHeaders);
      if (response.statusCode < 200 || response.statusCode >= 300) return false;
      return (jsonDecode(response.body) as Map<String, dynamic>)['connected'] == true;
    } catch (_) { return false; }
  }

  static Future<bool> codexConnected({String ownerId = 'anonymous'}) async {
    try {
      final response = await http.get(Uri.parse('${LumenoteBackendConfig.aiGatewayUrl}/api/codex/auth/status'), headers: _authHeaders);
      if (response.statusCode < 200 || response.statusCode >= 300) return false;
      return (jsonDecode(response.body) as Map<String, dynamic>)['connected'] == true;
    } catch (_) { return false; }
  }

  static Future<Map<String, String>?> codexChat({required String message, String? threadId, String? noteId, String ownerId = 'anonymous'}) async {
    try {
      final response = await http.post(Uri.parse('${LumenoteBackendConfig.aiGatewayUrl}/api/codex/chat'), headers: {'content-type': 'application/json', ..._authHeaders}, body: jsonEncode({'message': message, 'thread_id': threadId, 'note_id': noteId}));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return {'answer': data['answer'] as String? ?? '', 'threadId': data['threadId'] as String? ?? ''};
    } catch (_) { return null; }
  }

  static Future<String?> chat({required String message, required List<String> history, String noteContext = ''}) async {
    try {
      final response = await http.post(
        Uri.parse('${LumenoteBackendConfig.aiGatewayUrl}/api/ai/chat'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'message': message, 'noteContext': noteContext, 'history': history.map((content) => {'role': 'user', 'content': content}).toList()}),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['answer'] as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> founderUsers() async {
    final response = await http.get(Uri.parse('${LumenoteBackendConfig.aiGatewayUrl}/api/founder/users'), headers: _authHeaders);
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception((jsonDecode(response.body) as Map<String, dynamic>)['error'] ?? 'No se pudieron cargar los perfiles.');
    return ((jsonDecode(response.body) as Map<String, dynamic>)['users'] as List).cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> membershipPlans() async {
    final response = await http.get(Uri.parse('${LumenoteBackendConfig.aiGatewayUrl}/api/membership/plans'), headers: _authHeaders);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(body['error'] ?? 'No se pudieron cargar los planes.');
    }
    return (body['plans'] as List).cast<Map<String, dynamic>>();
  }

  static Future<void> founderCreateUser({required String name, required String nickname, required String email, required String password, required String plan, required String role}) async {
    final response = await http.post(Uri.parse('${LumenoteBackendConfig.aiGatewayUrl}/api/founder/users'), headers: {'content-type': 'application/json', ..._authHeaders}, body: jsonEncode({'display_name': name, 'nickname': nickname, 'email': email, 'password': password, 'plan': plan, 'role': role}));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception((jsonDecode(response.body) as Map<String, dynamic>)['error'] ?? 'No se pudo crear el perfil.');
  }

  static Future<void> founderAssignMembership({required String userId, required String plan, required String status}) async {
    final response = await http.patch(Uri.parse('${LumenoteBackendConfig.aiGatewayUrl}/api/founder/users/$userId/membership'), headers: {'content-type': 'application/json', ..._authHeaders}, body: jsonEncode({'plan': plan, 'status': status}));
    if (response.statusCode < 200 || response.statusCode >= 300) throw Exception((jsonDecode(response.body) as Map<String, dynamic>)['error'] ?? 'No se pudo actualizar la membresía.');
  }
}
