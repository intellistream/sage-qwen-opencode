# Maintain the OpenCode integration

Use this scenario before changing the pinned OpenCode version, provider module,
SAGE model settings, or compatibility patch in `install.sh`.

## Accepted integration contract

- The public installer contains no API key. It prompts each user privately and
  stores the value in `~/.config/sage/qwen38-api-key` with mode `0600`.
- The endpoint is `https://openai.sage.org.ai/v1`, the model identifier is
  `Qwen/Qwen3.8-27B`, and the wire protocol is OpenAI Responses.
- `sage-qwen` is a primary agent with a `262144` context limit. Because OpenCode
  V2 stores the session model separately from the primary agent, installation
  sets both `default_agent` and the root `model` for new sessions. Reasoning
  effort is set to `xhigh` at model level; the named variant remains available
  for explicit CLI selection. The model exposes `low`, `medium`, and `xhigh`;
  `cli.json` maps Shift+Tab to `variant.cycle` and moves agent cycling to
  Ctrl+T. Users can still switch either choice.
- Existing OpenCode configuration values must survive installation. Preserve a
  timestamped copy before normalizing JSONC to JSON and merging our provider.

## Bounded compatibility observation

Observed on 2026-09-30 with OpenCode V2 `2.0.20` and matching
`@opencode/ai@2.0.20`: text generation succeeded, but SAGE function-call stream
items supplied `namespace: null`. The OpenCode Responses protocol schema
accepted only a string or omission, and downstream propagation retained the
null value.

The verified narrow repair changes exactly two schema sites to accept null and
exactly four propagation sites to normalize null to `undefined`. The installer
supports only the exact unpatched or exact patched shape and fails closed for
anything else. Do not loosen those counts to make a new upstream version pass.

This is a version-bounded observation, not a permanent claim about SAGE or
OpenCode.

OpenCode V2 `2.0.20` also preserves an agent's declared model in discovery but
does not apply it when selecting a primary agent for a new session. Therefore,
do not remove the root model default merely because `opencode debug agents`
shows the expected agent model. Verify the provider/model stored on the actual
assistant message of a new session.

## Upgrade procedure

1. Pin `@opencode/cli` and `@opencode/ai` to the same version.
2. Inspect the new Responses provider/protocol source. Remove the local patch
   if upstream now handles nullable namespace correctly; otherwise establish a
   new exact shape rather than guessing.
3. Run `bash -n install.sh tests/install-smoke.sh` and
   `./tests/install-smoke.sh`.
4. Run the installer twice in a disposable HOME and confirm existing settings,
   idempotent PATH setup, key permissions, provider discovery, and backups.
5. Against the real SAGE endpoint, verify both a small text response and a
   complete shell-tool call loop. A text-only success is insufficient.
6. Scan the candidate commit for keys, local user paths, and credential-bearing
   URLs before publication.

## Node.js bootstrap

When Node.js 20+ and npm are unavailable, `install.sh` installs the pinned
Node.js LTS archive beneath `~/.local/opt` and links its executables into
`~/.local/bin`. Supported artifacts and their official SHA-256 values are
embedded in the installer; a digest mismatch must stop installation. Do not
replace this with an unaudited remote shell pipeline or system package-manager
mutation. Exercise `tests/install-smoke.sh` with the initial `node` command
deliberately unusable whenever bootstrap behavior changes.

Do not use `opencode debug agents` as an installer completion gate. On a
pristine HOME, OpenCode 2.0.20 can time out while starting its background
service even though the CLI and configuration are valid. Validate generated
files offline and the CLI binary with `opencode --version`; reserve live agent
discovery and model calls for explicit integration probes.

## Shared-server file watcher

OpenCode can fail with `EMFILE: too many open files, watch` when Linux inotify
user instances are exhausted. This has been observed upstream even when the
process file-descriptor limit itself is not the binding resource. Do not mutate
host-wide `sysctl` values from this user installer. The managed `opencode` and
`opencode2` launchers set the upstream-supported
`OPENCODE_FILEWATCHER_DISABLE=1` on Linux while preserving either implemented
variable when explicitly supplied by an administrator. In the exact V2.0.20
source, `packages/cli/src/server-process.ts` maps this variable (falling back to
`OPENCODE_DISABLE_FILEWATCHER`) to `fs.filewatcher: false`, and
`packages/server/src/routes.ts` maps that option to
`Watcher.configured({ enabled: false })`. The similarly named
`OPENCODE_EXPERIMENTAL_DISABLE_FILEWATCHER` appears in that tag's documentation
but is not consumed by its CLI source; do not use it for this pinned version.
Reinstalling must remove only our marked wrapper before npm recreates its
executable links, recreate the wrapper, verify it with
`--sage-opencode-doctor`, and stop any old watcher-enabled background service.

Keep captured output bounded and never record the real key or request headers.
