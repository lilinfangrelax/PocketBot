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

## Test coverage

- `test/services/acp_websocket_service_test.dart`: connection negotiation (protocol version, auth method selection, resume), session attach/resume/load/list/delete, prompt content blocks (text, image, embedded context, resource link), streaming updates (message/thought/tool call/plan/commands/config/mode/usage/session info), permission handling, modes and config options, cursor extensions, fs error mapping, and reconnect behavior.
- `test/services/acp_transport_test.dart`: NDJSON framing and chunk coalescing, remote agent command quoting, stderr/CLIXML exit formatting, remote path handling, and local stdio spawn failures.
- `test/services/acp_registry_test.dart`: registry catalog download, caching, and offline fallback.
- `test/services/cursor_agent_test.dart`: Windows agent resolution, working directory normalization, and command wrapping.

End-to-end protocol behavior is covered by `integration_test/acp_capabilities_test.dart`, which drives the deterministic mock agent (`tool/mock_acp_agent.dart`) through config options, plan updates, `cursor/update_todos`, `available_commands_update`, and client-side `fs/read_text_file` / `fs/write_text_file`. See `docs/E2E_TESTING.md` for how to run it.
