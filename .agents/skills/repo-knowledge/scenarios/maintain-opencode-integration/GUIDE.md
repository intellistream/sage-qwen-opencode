# Maintain the OpenCode integration

Use this scenario before changing the pinned OpenCode version, provider module,
SAGE model settings, or compatibility adapter in `install.sh`.

## Accepted integration contract

- The public installer contains no API key. It prompts each user privately and
  stores the value in `~/.config/sage/qwen38-api-key` with mode `0600`.
- The endpoint is `https://openai.sage.org.ai/v1`, the model identifier is
  `Qwen/Qwen3.8-27B`, and the wire protocol is OpenAI Responses.
- The verified runtime pair is `opencode-ai@1.18.33` and
  `@ai-sdk/openai@3.0.88`. Keep both versions pinned.
- `sage-qwen` is a primary agent with a `262144` context limit. Installation
  sets both `default_agent` and the root `model`. The model exposes `low`,
  `medium`, and `xhigh` variants and the agent defaults to `xhigh`.
- `tui.json` maps Shift+Tab to `variant_cycle`, maps ordinary agent cycling to
  Ctrl+T, and sets `agent_cycle_reverse` to `none`; otherwise the stable TUI's
  default Shift+Tab binding competes with variant cycling.
- Existing OpenCode configuration values survive installation. Preserve a
  timestamped copy before normalizing JSONC to JSON and merging our provider.

## Bounded SAGE Responses observation

Observed on 2026-09-30 with `opencode-ai@1.18.33` and
`@ai-sdk/openai@3.0.88`: a small text response worked without adaptation, but a
complete tool loop failed when assistant history was sent in the AI SDK's easy
message form and later included Responses `item_reference` entries.

The verified user-local provider adapter makes two narrow outbound changes:

1. assistant easy messages with content arrays become explicit completed
   Responses `message` items;
2. `item_reference` entries are removed before the next request.

With those transformations, the live endpoint completed a shell create/read
loop and returned its final answer. This is a version-bounded observation, not
an assertion about all SAGE or AI SDK versions. Keep the adapter readable and
fail upgrade validation if its expected request shape changes.

## Upgrade procedure

1. Pin the OpenCode and `@ai-sdk/openai` versions explicitly.
2. Inspect the new provider and Responses history behavior. Remove the local
   adapter only after a real tool loop works without it; otherwise establish a
   new bounded transformation rather than guessing.
3. Inspect TUI keybind defaults and every `fs.watch` call that can run at
   startup. Do not assume a project-watcher environment variable also covers
   direct TUI watchers.
4. Run `bash -n install.sh tests/install-smoke.sh` and
   `./tests/install-smoke.sh`.
5. Run the installer twice in a disposable HOME and confirm existing settings,
   idempotent PATH setup, key permissions, provider discovery, and backups.
6. Against the real SAGE endpoint, verify both a small text response and a
   complete shell-tool call loop. A text-only success is insufficient.
7. Scan the candidate commit for keys, local user paths, and
   credential-bearing URLs before publication.

## Node.js bootstrap

When Node.js 20+ and npm are unavailable, `install.sh` installs the pinned
Node.js LTS archive beneath `~/.local/opt` and links its executables into
`~/.local/bin`. Supported artifacts and their official SHA-256 values are
embedded in the installer; a digest mismatch stops installation. Do not replace
this with an unaudited remote shell pipeline or system package-manager mutation.
Exercise `tests/install-smoke.sh` with the initial `node` command deliberately
unusable whenever bootstrap behavior changes.

Do not use live provider discovery as an installer completion gate. Validate
generated files offline and the CLI binary with `opencode --version`; reserve
live model calls for explicit integration probes.

## Shared-server file watcher

The installer must work for an ordinary Linux user with no sudo access. Stable
OpenCode `1.18.33` consumes `OPENCODE_EXPERIMENTAL_DISABLE_FILEWATCHER`; the
managed Linux launchers set it to `true` unless the caller explicitly supplies
a value. The stable TUI has no direct watcher on the parent of `tui.json`, unlike
the rejected V2 `2.0.20` route whose direct config watcher caused
`EMFILE ... watch '~/.config/opencode'` even after its project watcher was
disabled.

The launcher may raise only its own FD soft limit, bounded by the existing hard
limit. It must never change host-wide sysctls. Doctor output must report
`filewatcher_disable=true` and
`tui_config_watcher=absent-in-opencode-1.18.33`. Reinstallation removes only our
marked wrappers before npm recreates executable links, then recreates and
checks the wrapper.

Keep captured output bounded and never record the real key or request headers.

## Blank TUI after a V2 installation

Observed on 2026-09-30: the pinned 1.18.33 TUI issued terminal capability
queries but never displayed its input box. A bounded `opencode run` exposed
`Database is not empty and has no session table`. Read-only SQLite inspection
found `session_v2` and no `session` in the default `opencode.db`; an older
2.0.20 background service still had that database open. Using a separate
database made the TUI render its SAGE input box. This was a schema mismatch,
not an API-key or file-watcher failure.

The managed Linux launcher now defaults `OPENCODE_DB` to
`sage-opencode-1.db` (relative to OpenCode's data directory), preserving an
explicit nonempty caller override. Never delete, rename, or migrate the old
database to repair this case; keep its history and any old service untouched.
Existing V1 users can explicitly select their compatible original database.
Doctor exposes the selected database name. This separation currently applies
to the managed Linux launcher, not the unwrapped macOS binary.

For a blank TUI, compare a bounded CLI run with a PTY startup; `--version` and
`debug startup` alone did not expose this failure. Give the PTY a real window
size and controlling terminal; wrapping a PTY child in `timeout`/`strace` can
otherwise introduce SIGTTOU stops unrelated to the application. Capture output
to a private artifact and check for the input placeholder and model label,
rather than flooding context with ANSI redraws.
