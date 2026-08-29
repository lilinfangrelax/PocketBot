import 'package:flutter/material.dart';
import 'package:pocket_bot/services/acp_transport.dart';
import 'package:pocket_bot/services/ssh_remote_session.dart';

/// Browse a remote SSH host and pick the working directory for `agent acp`.
class RemoteDirectoryPicker extends StatefulWidget {
  const RemoteDirectoryPicker({
    super.key,
    required this.source,
    required this.hostLabel,
    this.initialPath = '',
  });

  final RemoteDirectorySource source;
  final String hostLabel;
  final String initialPath;

  @override
  State<RemoteDirectoryPicker> createState() => _RemoteDirectoryPickerState();
}

class _RemoteDirectoryPickerState extends State<RemoteDirectoryPicker> {
  final _pathController = TextEditingController();
  String _path = '';
  List<SshRemoteEntry> _entries = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _openInitial();
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _openInitial() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final path = await widget.source.resolveStartPath(widget.initialPath);
      await _load(path);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _load(String path) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await widget.source.listDirectory(path);
      if (!mounted) return;
      setState(() {
        _path = path;
        _pathController.text = path;
        _entries = entries;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '无法列出目录: ${error.toString().replaceFirst('Exception: ', '')}';
      });
    }
  }

  void _goUp() {
    if (isRemoteRoot(_path)) return;
    _load(parentRemotePath(_path));
  }

  void _open(SshRemoteEntry entry) {
    if (!entry.isDirectory) return;
    _load(joinRemotePath(_path, entry.name));
  }

  void _confirm() {
    Navigator.pop(context, _path);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('选择工作目录'),
        actions: [
          IconButton(
            tooltip: '上级目录',
            onPressed: _loading || isRemoteRoot(_path) ? null : _goUp,
            icon: const Icon(Icons.arrow_upward),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.hostLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _pathController,
                  decoration: InputDecoration(
                    labelText: '当前目录',
                    isDense: true,
                    suffixIcon: IconButton(
                      tooltip: '前往',
                      icon: const Icon(Icons.keyboard_return),
                      onPressed: _loading
                          ? null
                          : () => _load(_pathController.text.trim()),
                    ),
                  ),
                  onSubmitted: (value) => _load(value.trim()),
                ),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Colors.red.shade700, fontSize: 13),
              ),
            ),
          Expanded(
            child: !_loading && _entries.isEmpty && _error == null
                ? Center(
                    child: Text(
                      '这个目录是空的',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  )
                : ListView.builder(
                    itemCount: _entries.length,
                    itemBuilder: (context, index) {
                      final entry = _entries[index];
                      return ListTile(
                        leading: const Icon(Icons.folder),
                        title: Text(entry.name),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _open(entry),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _loading || _path.isEmpty ? null : _confirm,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('在此目录启动 Agent'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
