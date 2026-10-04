import 'dart:typed_data';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  static SupabaseClient get client => Supabase.instance.client;
  static User? get user => client.auth.currentUser;
  static String? get accessToken => client.auth.currentSession?.accessToken;
  static String get preferredLanguage => (user?.userMetadata?['language'] as String?)?.trim().isNotEmpty == true ? user!.userMetadata!['language'] as String : 'es';
  static Stream<AuthState> get changes => client.auth.onAuthStateChange;

  static Future<void> signIn(String email, String password) => client.auth.signInWithPassword(email: email.trim(), password: password);
  static Future<void> signUp(String email, String password) => client.auth.signUp(email: email.trim(), password: password);
  static Future<void> signOut() => client.auth.signOut();

  static Future<User?> updateProfile({String? displayName, String? email, String? avatarUrl, String? language}) async {
    final current = user;
    if (current == null) return null;
    final metadata = <String, dynamic>{...current.userMetadata ?? {}};
    if (displayName != null && displayName.trim().isNotEmpty) {
      metadata['display_name'] = displayName.trim();
      metadata['full_name'] = displayName.trim();
    }
    if (avatarUrl != null && avatarUrl.isNotEmpty) metadata['avatar_url'] = avatarUrl;
    if (language != null && language.isNotEmpty) metadata['language'] = language;
    final updated = await client.auth.updateUser(UserAttributes(email: email?.trim().isEmpty == true ? null : email?.trim(), data: metadata));
    await client.from('profiles').upsert({
      'id': current.id,
      if (displayName != null && displayName.trim().isNotEmpty) 'display_name': displayName.trim(),
      if (avatarUrl != null && avatarUrl.isNotEmpty) 'avatar_url': avatarUrl,
      if (language != null && language.isNotEmpty) 'locale': language,
    });
    return updated.user;
  }

  static Future<User?> updatePassword(String password) async {
    final result = await client.auth.updateUser(UserAttributes(password: password));
    return result.user;
  }

  static Future<String> uploadAvatar(Uint8List bytes, {String extension = 'jpg', String contentType = 'image/jpeg'}) async {
    final current = user;
    if (current == null) throw const AuthException('No hay una sesión activa.');
    final path = '${current.id}/avatar.$extension';
    await client.storage.from('avatars').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: contentType, upsert: true));
    return client.storage.from('avatars').getPublicUrl(path);
  }

  static Future<Map<String, dynamic>?> subscription() async {
    final current = user;
    if (current == null) return null;
    final row = await client.from('subscriptions').select().eq('user_id', current.id).maybeSingle();
    return row;
  }

  static Future<bool> isFounder() async {
    final current = user;
    if (current == null) return false;
    final row = await client.from('profiles').select('role').eq('id', current.id).maybeSingle();
    return row?['role'] == 'founder';
  }

  static Future<bool> aiProcessingEnabled() async {
    final current = user;
    if (current == null) return true;
    final row = await client.from('profiles').select('ai_processing_enabled').eq('id', current.id).maybeSingle();
    return row?['ai_processing_enabled'] as bool? ?? true;
  }

  static Future<void> setAiProcessingEnabled(bool enabled) async {
    final current = user;
    if (current == null) return;
    await client.from('profiles').update({'ai_processing_enabled': enabled}).eq('id', current.id);
  }

  static Future<String> exportUserData() async {
    final current = user;
    if (current == null) throw const AuthException('No hay una sesión activa.');
    final profile = await client.from('profiles').select().eq('id', current.id).maybeSingle();
    final plan = await client.from('subscriptions').select().eq('user_id', current.id).maybeSingle();
    final notes = await client.from('notes').select('id,title,source_type,status,language,summary,created_at,updated_at').eq('user_id', current.id);
    return const JsonEncoder.withIndent('  ').convert({'account': {'id': current.id, 'email': current.email}, 'profile': profile, 'subscription': plan, 'notes': notes});
  }

  static Future<void> deleteUserData() async {
    final current = user;
    if (current == null) return;
    await client.from('chat_messages').delete().eq('user_id', current.id);
    await client.from('flashcards').delete().eq('user_id', current.id);
    await client.from('quizzes').delete().eq('user_id', current.id);
    await client.from('notes').delete().eq('user_id', current.id);
    await client.from('subscriptions').delete().eq('user_id', current.id);
    await client.from('profiles').delete().eq('id', current.id);
  }
}
