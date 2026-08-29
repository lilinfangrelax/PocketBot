import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/utils/logger.dart';

/// Session history storage - saves chat sessions locally
class SessionStorage {
  static const _storage = FlutterSecureStorage();
  static const _keySessions = 'chat_sessions';
  static const _keyCurrentSession = 'current_session';
  static Future<void>? _pendingWrite; // Step 5 fix: write lock
  static Timer? _saveDebounce;
  static final Map<String, ChatSession> _dirty = {};

  /// Save a chat session
  static Future<void> saveSession(ChatSession session) async {
    _dirty[session.key] = session;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_flushDirty());
    });
  }

  static Future<void> _flushDirty() async {
    if (_dirty.isEmpty) return;
    Logger.debug('[Storage] flush ${_dirty.length} session(s)');
    while (_pendingWrite != null) {
      await _pendingWrite;
    }
    if (_dirty.isEmpty) return;
    final completer = Completer<void>();
    _pendingWrite = completer.future;
    final pending = Map<String, ChatSession>.from(_dirty);
    _dirty.clear();

    try {
      final sessions = await _readAllSessions();
      final byKey = {for (final session in sessions) session.key: session};
      byKey.addAll(pending);
      await _storage.write(
        key: _keySessions,
        value: jsonEncode(byKey.values.map((s) => s.toJson()).toList()),
      );
    } catch (e) {
      Logger.warning('[Storage] Error saving session: $e');
      for (final entry in pending.entries) {
        _dirty.putIfAbsent(entry.key, () => entry.value);
      }
    } finally {
      _pendingWrite = null;
      completer.complete();
    }
  }

  /// Load all saved sessions
  static Future<List<ChatSession>> loadAllSessions() async {
    return await _loadAllSessions();
  }

  static Future<void> flush() => _flushDirty();

  /// Internal load all sessions
  static Future<List<ChatSession>> _loadAllSessions() async {
    await _flushDirty();
    return _readAllSessions();
  }

  static Future<List<ChatSession>> _readAllSessions() async {
    try {
      final json = await _storage.read(key: _keySessions);
      if (json != null) {
        final List<dynamic> decoded = jsonDecode(json);
        return decoded.map((s) => ChatSession.fromJson(s)).toList()
          ..sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
      }
    } catch (e) {
      Logger.warning('Error loading sessions: $e');
    }
    return [];
  }

  /// Load a specific session by key
  static Future<ChatSession?> loadSession(String key) async {
    final sessions = await _loadAllSessions();
    try {
      return sessions.firstWhere((s) => s.key == key);
    } catch (e) {
      return null;
    }
  }

  /// Delete a session
  static Future<void> deleteSession(String key) async {
    _dirty.remove(key);
    try {
      final sessions = await _loadAllSessions();
      sessions.removeWhere((s) => s.key == key);
      await _storage.write(
        key: _keySessions,
        value: jsonEncode(sessions.map((s) => s.toJson()).toList()),
      );
      Logger.info('Session deleted: $key');
    } catch (e) {
      Logger.warning('Error deleting session: $e');
    }
  }

  /// Clear all sessions
  static Future<void> clearAllSessions() async {
    _saveDebounce?.cancel();
    _dirty.clear();
    await _storage.delete(key: _keySessions);
    Logger.info('All sessions cleared');
  }

  /// Save current session key
  static Future<void> saveCurrentSessionKey(String? key) async {
    if (key != null) {
      await _storage.write(key: _keyCurrentSession, value: key);
    } else {
      await _storage.delete(key: _keyCurrentSession);
    }
  }

  /// Load current session key
  static Future<String?> loadCurrentSessionKey() async {
    return await _storage.read(key: _keyCurrentSession);
  }

  /// Add a message to a session (updates session with new message)
  static Future<void> addMessageToSession(
    String sessionKey,
    Message message,
  ) async {
    final session = await loadSession(sessionKey);
    if (session != null) {
      session.addMessage(message);
      await saveSession(session);
    }
  }

  /// Update session title
  static Future<void> updateSessionTitle(
    String sessionKey,
    String title,
  ) async {
    final session = await loadSession(sessionKey);
    if (session != null) {
      session.title = title;
      await saveSession(session);
    }
  }

  /// Get list of all session keys
  static Future<List<String>> getSessionKeys() async {
    final sessions = await _loadAllSessions();
    return sessions.map((s) => s.key).toList();
  }

  /// Check if any sessions exist
  static Future<bool> hasSessions() async {
    final json = await _storage.read(key: _keySessions);
    return json != null && json.isNotEmpty;
  }

  /// Save sessions in bulk (efficient for batch updates)
  static Future<void> saveSessionsBulk(List<ChatSession> sessions) async {
    try {
      final existing = await _loadAllSessions();
      final existingMap = {for (var s in existing) s.key: s};

      for (final s in sessions) {
        existingMap[s.key] = s;
      }

      await _storage.write(
        key: _keySessions,
        value: jsonEncode(existingMap.values.map((s) => s.toJson()).toList()),
      );

      Logger.info('Bulk saved ${sessions.length} sessions');
    } catch (e) {
      Logger.warning('Error bulk saving sessions: $e');
    }
  }

  /// Delete multiple sessions at once
  static Future<void> deleteSessionsBulk(List<String> keys) async {
    try {
      final sessions = await _loadAllSessions();
      sessions.removeWhere((s) => keys.contains(s.key));
      await _storage.write(
        key: _keySessions,
        value: jsonEncode(sessions.map((s) => s.toJson()).toList()),
      );
      Logger.info('Bulk deleted ${keys.length} sessions');
    } catch (e) {
      Logger.warning('Error bulk deleting sessions: $e');
    }
  }

  /// Get total number of sessions
  static Future<int> getSessionCount() async {
    final sessions = await _loadAllSessions();
    return sessions.length;
  }

  /// Cleanup old sessions, keeping only the latest N sessions
  static Future<void> cleanupOldSessions({int keepLatest = 50}) async {
    try {
      final sessions = await _loadAllSessions();
      if (sessions.length <= keepLatest) return;

      sessions.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
      final toDelete = sessions.skip(keepLatest).map((s) => s.key).toList();

      for (final key in toDelete) {
        await deleteSession(key);
      }

      Logger.info('Cleaned up ${toDelete.length} old sessions');
    } catch (e) {
      Logger.warning('Error cleaning up sessions: $e');
    }
  }
}
