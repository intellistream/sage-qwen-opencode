# Repository Instructions

This repository distributes a small, auditable OpenCode installer for the
IntelliStream SAGE Qwen service.

- Never add API keys, tokens, credential-bearing URLs, or real user config.
- Keep `./install.sh` as the single documented installation entrypoint.
- Preserve unrelated existing OpenCode settings and create recoverable backups
  before modifying user files.
- Keep OpenCode and provider-runtime versions pinned together. When upgrading,
  revalidate text generation and a complete shell-tool call loop against the
  SAGE endpoint before publication.
- Keep the fallback Node.js LTS release and per-platform checksums pinned. Test
  installation with `node` and `npm` absent from the initial executable path.
- Keep Linux's OpenCode launcher wrapper idempotent. It disables the upstream
  file watcher by default to avoid EMFILE crashes on shared hosts, but must
  use the environment variable actually read by the pinned V2 source, preserve
  an explicit administrator-provided value, and expose a bounded doctor check.
- Compatibility patches must be narrow and fail closed when upstream source no
  longer matches the verified shape.
- Run `tests/install-smoke.sh` before committing installer changes.
