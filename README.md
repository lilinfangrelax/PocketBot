# PocketBot

PocketBot is a Flutter client for agents that implement the [Agent Client Protocol (ACP)](https://agentclientprotocol.com/).

## Features

- ACP Registry: Cursor, Claude, Gemini, Codex, and the other published agents
- Local agent over ACP stdio
- Remote ACP over SSH: log in, install `pocketbot-remote` into `~/.pocketbot`, then start the selected agent. The helper keeps the agent process alive if the SSH connection drops.
- Optional ACP WebSocket transport
- Multiple sessions with local history
- Streaming replies, tool calls, plans, and slash commands
- Dynamic session config options advertised by the agent

## Requirements

- Flutter 3.10 or newer
- For local use: the selected agent installed, or a machine that can download it
- For remote use: SSH access. PocketBot installs a version-matched `pocketbot-remote` binary from GitHub Releases. `npx` agents also need Node.js on that host; `uvx` agents need `uv`. Cursor can fall back to an existing `agent` command if the registry archive cannot be downloaded.

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
