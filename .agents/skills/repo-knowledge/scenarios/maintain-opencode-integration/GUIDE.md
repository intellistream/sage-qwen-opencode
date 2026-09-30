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

Keep captured output bounded and never record the real key or request headers.
