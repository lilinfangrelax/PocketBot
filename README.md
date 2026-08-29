# PocketBot

PocketBot is a Flutter client for agents that implement the [Agent Client Protocol (ACP)](https://agentclientprotocol.com/).

## Features

- Local Cursor Agent over ACP stdio (`agent acp`)
- Remote ACP over SSH: log in, pick a working directory, then start the same agent
- Optional ACP WebSocket transport
- Multiple sessions with local history
- Streaming replies, tool calls, plans, and slash commands
- Dynamic session config options advertised by the agent

## Requirements

- Flutter 3.10 or newer
- For local use: Cursor CLI (`agent`) installed and logged in
- For remote use: SSH access to a host that already has `agent acp`

## Run

```bash
flutter pub get
flutter run
```

On the home screen:

- **This computer**: choose a working directory and start the local agent
- **SSH**: enter host, user, and password or private key, then pick a remote folder

Credentials are stored on-device with Flutter Secure Storage. They are never sent in git.

## Development

```bash
flutter analyze
flutter test
```

See [ACP testing](docs/ACP_TESTING.md) for the expected JSON-RPC flow.

## Security

- Prefer SSH keys over passwords when connecting to remote hosts.
- Do not commit SSH private keys, tokens, or `android/local.properties`.
- PocketBot does not log secrets. Session history stays on the device.

## License

MIT
