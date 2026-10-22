import 'package:pocket_bot/models/group_workspace.dart';
import 'package:pocket_bot/services/database_service.dart';

class GroupWorkspaceStore {
  GroupWorkspaceStore({DatabaseService? db}) : _db = db ?? DatabaseService();

  final DatabaseService _db;
  static Future<void>? _ready;

  Future<void> _ensureTable() => _ready ??= _db.execute('''
        CREATE TABLE IF NOT EXISTS group_workspaces (
          group_id TEXT PRIMARY KEY,
          host_id TEXT NOT NULL,
          working_directory TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');

  Future<GroupWorkspace?> get(String groupId) async {
    await _ensureTable();
    final rows = await _db.query(
      'group_workspaces',
      where: 'group_id = ?',
      whereArgs: [groupId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return GroupWorkspace.fromDbMap(rows.first);
  }

  Future<void> save(GroupWorkspace workspace) async {
    await _ensureTable();
    final row = workspace.toDbMap();
    await _db.execute(
      'INSERT OR REPLACE INTO group_workspaces '
      '(group_id, host_id, working_directory, updated_at) VALUES (?, ?, ?, ?)',
      [
        row['group_id'],
        row['host_id'],
        row['working_directory'],
        row['updated_at'],
      ],
    );
  }

  Future<void> clear(String groupId) async {
    await _ensureTable();
    await _db.delete(
      'group_workspaces',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
  }
}
