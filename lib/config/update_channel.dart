/// GitHub Releases source and update channels. Kept Flutter-free for unit tests.
class UpdateConstants {
  static const githubOwner = 'lilinfangrelax';
  static const githubRepo = 'PocketBot';

  static String get repoUrl => 'https://github.com/$githubOwner/$githubRepo';
}

enum UpdateChannel {
  stable,
  beta;

  String get id => name;

  String get displayName => switch (this) {
        UpdateChannel.stable => '正式版',
        UpdateChannel.beta => 'Beta',
      };

  String get description => switch (this) {
        UpdateChannel.stable => '仅接收正式发布版本',
        UpdateChannel.beta => '接收最新测试版本',
      };

  static UpdateChannel fromId(String? id) {
    for (final channel in UpdateChannel.values) {
      if (channel.id == id) return channel;
    }
    return UpdateChannel.stable;
  }
}
