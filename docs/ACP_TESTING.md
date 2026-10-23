# ACP connection testing

PocketBot talks to ACP agents with JSON-RPC 2.0.

## Transports

1. **Local stdio**: spawn `agent acp` as a child process and exchange NDJSON on stdin/stdout.
2. **SSH stdio**: open SSH, start the same agent command on the remote host, and reuse that session.
3. **WebSocket** (optional): connect to `ws[s]://HOST:PORT/acp` with one JSON-RPC message per text frame.

## Minimum flow

1. PocketBot sends `initialize` with `protocolVersion: 1`.
2. The agent returns ACP v1 capabilities. If `authMethods` is non-empty, PocketBot sends `authenticate`. Codex advertises API-key auth first; when that call reports that `CODEX_API_KEY` and `OPENAI_API_KEY` are unset, PocketBot continues with ChatGPT device-code login (or browser login when device code is not offered).
3. PocketBot sends `session/new` with an absolute `cwd` and an empty `mcpServers` list.
4. The agent returns a `sessionId`.
5. PocketBot sends `session/prompt` with ACP content blocks.
6. The agent streams `session/update` notifications containing `agent_message_chunk` updates.
7. The agent completes the prompt request with a `stopReason`.

## Client capabilities

PocketBot advertises `fs`, `elicitation: {form, url}`, session config options, notices and compaction on `initialize`. `fs` and `terminal` are advertised per transport: they are enabled only when the client can reach the agent's environment (local stdio), so SSH and WebSocket connections report `false`.

### Elicitation

Agent-initiated `elicitation/create` requests are answered with `action: accept | decline | cancel`:

- **Form mode** renders the flat JSON Schema (`string` with `enum`/`oneOf`, `number`, `integer`, `boolean`, and arrays with `minItems`/`maxItems`) in a dialog and returns typed `content`.
- **URL mode** shows the target host and the full URL, requires explicit consent, then opens it in the system browser. A following `elicitation/complete` notification adds a system notice to the session.
- Without an attached chat UI, PocketBot shows the elicitation on the app navigator. If that navigator is not available it replies `cancel`. Unsupported or malformed modes get JSON-RPC error `-32602`.

### Terminal

Agents can ask the client to run commands with `terminal/create`, then poll `terminal/output`, block on `terminal/wait_for_exit`, stop with `terminal/kill`, and free resources with `terminal/release`. PocketBot runs them through `LocalAcpTerminalHost` in the session working directory, with the agent supplied `env` merged over the inherited one. Output is capped by `outputByteLimit` (1 MiB default) keeping only the tail; `terminal/output` reports `truncated` and adds `exitStatus` once the process exited. `terminal/kill` ends the whole process tree on Windows (`taskkill /T /F`), because the direct child is usually a shell; elsewhere it signals the process and `terminal/release` uses `SIGKILL`. `wait_for_exit` settles as soon as the process exits plus a short pipe-drain grace, so a surviving grandchild cannot hang the agent. Terminals are released when the session is deleted, the connection closes, or the transport is torn down. Unknown or already released ids get `-32602`, and missing capability gets `-32601`.

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

- `test/services/acp_websocket_service_test.dart`: connection negotiation (protocol version, auth method selection, resume), session attach/resume/load/list/delete, prompt content blocks (text, image, embedded context, resource link), streaming updates (message/thought/tool call/plan/commands/config/mode/usage/session info), permission handling (auto-approve and remembered `allow_always` per tool kind), grouped select config options, elicitation (form/url responses, completion notices, unsupported modes), logout, prompt stop reasons, modes and config options, cursor extensions, fs error mapping, and reconnect behavior.
- `test/services/acp_terminal_test.dart`: command capture and exit codes, environment and working directory, byte-limit tail truncation, zero limit, kill, and release.
- `test/models/acp_tool_call_test.dart`: `rawOutput` fallback used when a tool call has no text content.
- `test/widgets/elicitation_dialog_test.dart`: form field types, required-field validation, typed `content`, decline, and URL consent/host display.
- `test/services/acp_transport_test.dart`: NDJSON framing and chunk coalescing, remote agent command quoting, stderr/CLIXML exit formatting, remote path handling, and local stdio spawn failures.
- `test/services/acp_registry_test.dart`: registry catalog download, caching, and offline fallback.
- `test/services/cursor_agent_test.dart`: Windows agent resolution, working directory normalization, and command wrapping.

End-to-end protocol behavior is covered by `integration_test/acp_capabilities_test.dart`, which drives the deterministic mock agent (`tool/mock_acp_agent.dart`) through config options, plan updates, `cursor/update_todos`, `available_commands_update`, and client-side `fs/read_text_file` / `fs/write_text_file`. Elicitation is covered by `integration_test/elicitation_test.dart` (form submission and URL consent), and client terminal support by `integration_test/terminal_test.dart` (create, wait for exit, read output, release). See `docs/E2E_TESTING.md` for how to run them.
