import 'package:flutter/material.dart';
import 'package:pocket_bot/models/contact.dart';
import 'package:pocket_bot/services/contact_service.dart';

/// @提及选择器组件
/// 在消息输入框中输入 @ 时显示联系人选择列表
class AtSelector extends StatefulWidget {
  /// 选择联系人后的回调
  final Function(Contact contact) onContactSelected;
  
  /// 当前输入框的文本控制器
  final TextEditingController textController;
  
  /// 触发显示的位置（光标位置）
  final Offset position;

  const AtSelector({
    super.key,
    required this.onContactSelected,
    required this.textController,
    required this.position,
  });

  @override
  State<AtSelector> createState() => _AtSelectorState();
}

class _AtSelectorState extends State<AtSelector> {
  final ContactService _contactService = ContactService();
  List<Contact> _aiContacts = [];
  List<Contact> _filteredContacts = [];
  String _filterText = '';
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final contacts = await _contactService.getAllContacts();
    // 只显示AI联系人
    final aiContacts = contacts.where((c) => c.isAI).toList();
    setState(() {
      _aiContacts = aiContacts;
      _filteredContacts = aiContacts;
    });
  }

  void _filterContacts(String text) {
    setState(() {
      _filterText = text;
      if (text.isEmpty) {
        _filteredContacts = _aiContacts;
      } else {
        _filteredContacts = _aiContacts.where((c) {
          return c.name.toLowerCase().contains(text.toLowerCase()) ||
              (c.atName?.toLowerCase().contains(text.toLowerCase()) ?? false);
        }).toList();
      }
    });
  }

  void _selectContact(Contact contact) {
    // 在输入框中插入 @名称
    final text = widget.textController.text;
    final selection = widget.textController.selection;
    
    // 找到 @ 的位置并替换
    final atIndex = text.lastIndexOf('@', selection.baseOffset - 1);
    if (atIndex != -1) {
      final newText = text.substring(0, atIndex) + 
                      '@${contact.atName ?? contact.name} ' + 
                      text.substring(selection.baseOffset);
      widget.textController.text = newText;
      // 设置光标位置
      widget.textController.selection = TextSelection.collapsed(
        offset: atIndex + (contact.atName?.length ?? contact.name.length) + 2,
      );
    }
    
    widget.onContactSelected(contact);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 200, maxWidth: 300),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 搜索框
            if (_aiContacts.length > 1)
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: '搜索联系人...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  onChanged: _filterContacts,
                ),
              ),
            // 联系人列表
            Flexible(
              child: _filteredContacts.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('没有匹配的联系人'),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _filteredContacts.length,
                      itemBuilder: (context, index) {
                        final contact = _filteredContacts[index];
                        return _ContactListTile(
                          contact: contact,
                          onTap: () => _selectContact(contact),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 显示 @ 选择器浮层
  static void show({
    required BuildContext context,
    required TextEditingController textController,
    required Function(Contact) onContactSelected,
  }) {
    final overlay = Overlay.of(context);
    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    
    final position = renderBox.localToGlobal(Offset.zero);
    
    final overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: position.dx,
        top: position.dy - 200, // 显示在上方
        child: AtSelector(
          onContactSelected: onContactSelected,
          textController: textController,
          position: position,
        ),
      ),
    );
    
    overlay.insert(overlayEntry);
  }
}

class _ContactListTile extends StatelessWidget {
  final Contact contact;
  final VoidCallback onTap;

  const _ContactListTile({required this.contact, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundImage: 
            contact.avatar != null ? NetworkImage(contact.avatar!) : null,
        child: contact.avatar == null 
            ? Text(contact.name[0], style: const TextStyle(fontSize: 12))
            : null,
      ),
      title: Text(contact.name),
      subtitle: contact.atName != null 
          ? Text('@${contact.atName}', style: TextStyle(color: Colors.grey[600]))
          : null,
      onTap: onTap,
    );
  }
}

/// @选择器控制器
/// 在聊天输入框中监听 @ 符号触发选择器
class AtSelectorController {
  TextEditingController? _textController;
  bool _isAtSelectorVisible = false;
  OverlayEntry? _overlayEntry;

  /// 初始化控制器
  void attach(TextEditingController textController) {
    _textController = textController;
    _textController?.addListener(_onTextChanged);
  }

  /// 释放资源
  void dispose() {
    _textController?.removeListener(_onTextChanged);
    _hideSelector();
  }

  void _onTextChanged() {
    if (_textController == null) return;
    
    final text = _textController!.text;
    final selection = _textController!.selection;
    
    // 检查是否刚刚输入了 @
    if (selection.isCollapsed && selection.baseOffset > 0) {
      final charBefore = text[selection.baseOffset - 1];
      if (charBefore == '@' && !_isAtSelectorVisible) {
        _showSelector();
      }
    }
    
    // 检查是否删除了 @
    if (!_isAtSelectorVisible && text.isEmpty) {
      // do nothing
    }
  }

  void _showSelector() {
    _isAtSelectorVisible = true;
    // TODO: 显示选择器浮层
  }

  void _hideSelector() {
    _isAtSelectorVisible = false;
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}
