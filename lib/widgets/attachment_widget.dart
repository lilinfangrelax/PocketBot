import 'package:flutter/material.dart';
import 'package:pocket_bot/models/attachment.dart';
import 'package:pocket_bot/services/file_download_service.dart';
import 'package:pocket_bot/utils/logger.dart';

/// Widget for displaying a single attachment in chat
class AttachmentWidget extends StatelessWidget {
  final Attachment attachment;
  final bool isUser;
  final bool isDarkMode;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final GlobalKey? widgetKey;

  const AttachmentWidget({
    super.key,
    required this.attachment,
    this.isUser = false,
    this.isDarkMode = false,
    this.onTap,
    this.onRemove,
    this.widgetKey,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isUser 
            ? (isDarkMode ? Colors.white.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.2))
            : (isDarkMode ? const Color(0xFF3A3A3A) : Colors.grey[100]),
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: isUser ? onTap : () => _handleTap(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // File icon
              Icon(
                _getIcon(),
                size: 32,
                color: isUser ? Colors.white : (isDarkMode ? Colors.grey[300] : Colors.grey[700]),
              ),
              const SizedBox(width: 12),
              // File info
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      attachment.filename,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isUser ? Colors.white : (isDarkMode ? Colors.white : Colors.black87),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${attachment.sizeString} • ${attachment.mimeType.split('/').last.toUpperCase()}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isUser ? Colors.white70 : (isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                      ),
                    ),
                  ],
                ),
              ),
              // Remove button (only for user attachments)
              if (onRemove != null && isUser)
                IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 18,
                    color: isUser ? Colors.white70 : Colors.grey[500],
                  ),
                  onPressed: onRemove,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              // Download indicator (for received attachments)
              if (!isUser && (attachment.url != null || attachment.data != null))
                const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// Handle tap on received attachment - download and open
  Future<void> _handleTap(BuildContext context) async {
    // Check if already downloaded (has local file path)
    if (attachment.filePath != null) {
      // Open existing file
      await FileDownloadService.openFile(attachment.filePath!);
      return;
    }

    // Show loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('正在下载 ${attachment.filename}…'),
        duration: const Duration(seconds: 30),
      ),
    );

    // Download the file
    final filePath = await FileDownloadService.downloadFile(attachment);

    // Hide loading indicator
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    
    if (filePath != null) {
      // Show success and open option
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已保存到：$filePath'),
          action: SnackBarAction(
            label: '打开',
            onPressed: () => FileDownloadService.openFile(filePath),
          ),
        ),
      );
      Logger.info('File downloaded: $filePath');
    } else {
      // Show error
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('文件下载失败'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  IconData _getIcon() {
    if (attachment.isImage) return Icons.image;
    if (attachment.isPdf) return Icons.picture_as_pdf;
    if (attachment.isVideo) return Icons.videocam;
    if (attachment.isAudio) return Icons.audiotrack;
    if (attachment.filename.endsWith('.zip') || attachment.filename.endsWith('.rar')) return Icons.archive;
    if (attachment.filename.endsWith('.doc') || attachment.filename.endsWith('.docx')) return Icons.description;
    if (attachment.filename.endsWith('.xls') || attachment.filename.endsWith('.xlsx')) return Icons.table_chart;
    return Icons.insert_drive_file;
  }
}

/// Compact attachment chip for showing multiple attachments
class AttachmentChip extends StatelessWidget {
  final Attachment attachment;
  final VoidCallback? onTap;

  const AttachmentChip({
    super.key,
    required this.attachment,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(
        _getIcon(),
        size: 18,
        color: Theme.of(context).colorScheme.primary,
      ),
      label: Text(
        attachment.filename,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onPressed: onTap ?? () {},
      padding: EdgeInsets.zero,
    );
  }

  IconData _getIcon() {
    if (attachment.isImage) return Icons.image;
    if (attachment.isPdf) return Icons.picture_as_pdf;
    if (attachment.isVideo) return Icons.videocam;
    if (attachment.isAudio) return Icons.audiotrack;
    return Icons.attach_file;
  }
}

/// Row of attachment chips
class AttachmentRow extends StatelessWidget {
  final List<Attachment> attachments;
  final bool isUser;
  final bool isDarkMode;

  const AttachmentRow({
    super.key,
    required this.attachments,
    this.isUser = false,
    this.isDarkMode = false,
  });

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: attachments.map((attachment) {
        return AttachmentWidget(
          attachment: attachment,
          isUser: isUser,
          isDarkMode: isDarkMode,
        );
      }).toList(),
    );
  }
}
