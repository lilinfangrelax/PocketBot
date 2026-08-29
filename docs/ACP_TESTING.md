# ACP connection testing

PocketBot talks to ACP agents with JSON-RPC 2.0.

## Transports

1. **Local stdio**: spawn `agent acp` as a child process and exchange NDJSON on stdin/stdout.
2. **SSH stdio**: open SSH, start the same agent command on the remote host, and reuse that session.
3. **WebSocket** (optional): connect to `ws[s]://HOST:PORT/acp` with one JSON-RPC message per text frame.

## Minimum flow

1. PocketBot sends `initialize` with `protocolVersion: 1`.
2. The agent returns ACP v1 capabilities. If `authMethods` is non-empty, PocketBot sends `authenticate`.
3. PocketBot sends `session/new` with an absolute `cwd` and an empty `mcpServers` list.
4. The agent returns a `sessionId`.
5. PocketBot sends `session/prompt` with ACP content blocks.
6. The agent streams `session/update` notifications containing `agent_message_chunk` updates.
7. The agent completes the prompt request with a `stopReason`.

Example initialization request:

```json
{
  "jsonrpc": "2.0",
  "id": "1",
  "method": "initialize",
  "params": {
    "protocolVersion": 1,
    "clientCapabilities": {},
    "clientInfo": {
      "name": "pocketbot",
      "title": "PocketBot",
      "version": "1.1.0"
    }
  }
}
```

Run static and unit checks with:

```bash
flutter analyze
flutter test
```
