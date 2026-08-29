import 'dart:async';
import 'package:pocket_bot/models/message.dart';
import 'package:pocket_bot/config/session_storage.dart';
import 'package:pocket_bot/services/websocket_service.dart';
import 'package:pocket_bot/utils/logger.dart';

class SessionSyncService {
  final WebSocketService wsService;
  final Duration syncInterval;
  Timer? _syncTimer;

  SessionSyncService({
    required this.wsService,
    this.syncInterval = const Duration(seconds: 30),
  });

  void start() {
    if (_syncTimer != null) {
      return;
    }

    Logger.info('[SessionSync] Starting with interval: $syncInterval');
    _syncTimer = Timer.periodic(syncInterval, (_) => syncAll());
  }

  void stop() {
    _syncTimer?.cancel();
    _syncTimer = null;
    Logger.info('[SessionSync] Stopped');
  }

  Future<void> syncAll() async {
    if (!wsService.isConnected) {
      Logger.debug('[SessionSync] Not connected, skipping sync');
      return;
    }

    try {
      Logger.debug('[SessionSync] Starting sync...');
      final gatewaySessions = await wsService.getGatewaySessions();

      for (final gSession in gatewaySessions) {
        final localSession = await SessionStorage.loadSession(gSession.key);

        if (localSession == null) {
          await SessionStorage.saveSession(gSession);
          Logger.info('[SessionSync] Imported session: ${gSession.key}');
        } else if (gSession.lastUpdated.isAfter(localSession.lastUpdated)) {
          _mergeSessions(localSession, gSession);
          await SessionStorage.saveSession(localSession);
          Logger.info('[SessionSync] Merged session: ${gSession.key}');
        }
      }

      Logger.debug('[SessionSync] Sync completed');
    } catch (e) {
      Logger.warning('[SessionSync] Failed: $e');
    }
  }

  void _mergeSessions(ChatSession local, ChatSession gateway) {
    final localIds = local.messages.map((m) => m.id).toSet();
    final newMessages =
        gateway.messages.where((m) => !localIds.contains(m.id)).toList();

    if (newMessages.isNotEmpty) {
      local.messages.addAll(newMessages);
      local.lastUpdated = DateTime.now();

      if (newMessages.isNotEmpty) {
        local.lastMessagePreview =
            newMessages.last.text.length > 100
                ? newMessages.last.text.substring(0, 100) + '...'
                : newMessages.last.text;
      }
    }

    if (gateway.isGatewaySession && !local.isGatewaySession) {
      local.isGatewaySession = true;
    }

    // Merge token usage from Gateway (these are authoritative)
    if (gateway.totalTokens > 0) {
      local.inputTokens = gateway.inputTokens;
      local.outputTokens = gateway.outputTokens;
      local.totalTokens = gateway.totalTokens;
      local.contextTokens = gateway.contextTokens;
      local.model = gateway.model;
    }
  }

  Future<void> syncSession(String sessionKey) async {
    if (!wsService.isConnected) {
      throw Exception('Not connected to Gateway');
    }

    try {
      final gatewaySessions = await wsService.getGatewaySessions();
      final targetSession =
          gatewaySessions.firstWhere((s) => s.key == sessionKey);

      final localSession = await SessionStorage.loadSession(sessionKey);
      if (localSession == null ||
          targetSession.lastUpdated.isAfter(localSession.lastUpdated)) {
        _mergeSessions(localSession ?? targetSession, targetSession);
        await SessionStorage.saveSession(localSession ?? targetSession);
        Logger.info('[SessionSync] Synced session: $sessionKey');
      }
    } catch (e) {
      Logger.warning('[SessionSync] Failed to sync $sessionKey: $e');
      rethrow;
    }
  }

  Future<void> importGatewaySession(String sessionKey) async {
    if (!wsService.isConnected) {
      throw Exception('Not connected to Gateway');
    }

    try {
      final gatewaySessions = await wsService.getGatewaySessions();
      final session =
          gatewaySessions.firstWhere((s) => s.key == sessionKey);

      session.isGatewaySession = true;
      await SessionStorage.saveSession(session);
      Logger.info('[SessionSync] Imported session: $sessionKey');
    } catch (e) {
      Logger.warning('[SessionSync] Failed to import $sessionKey: $e');
      rethrow;
    }
  }

  Future<void> cleanupOldSessions({int keepLatest = 50}) async {
    final sessions = await SessionStorage.loadAllSessions();
    if (sessions.length <= keepLatest) return;

    sessions.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
    final toDelete = sessions.skip(keepLatest).map((s) => s.key).toList();

    for (final key in toDelete) {
      await SessionStorage.deleteSession(key);
    }

    Logger.info('[SessionSync] Cleaned up ${toDelete.length} old sessions');
  }

  void dispose() {
    stop();
  }
}
