#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
node_bin_dir="$(dirname "$(command -v node)")"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

fake_home="$fixture/home"
fake_bin="$fixture/bin"
prefix="$fake_home/.local"
mkdir -p "$fake_home/.config/sage" "$fake_home/.config/opencode" "$fake_bin"
printf '%s\n' 'fixture-key-not-a-real-secret' > "$fake_home/.config/sage/qwen38-api-key"
chmod 0600 "$fake_home/.config/sage/qwen38-api-key"

cat > "$fake_home/.config/opencode/opencode.jsonc" <<'EOF'
{
  // Existing user setting must survive the merge.
  "theme": "system",
  "providers": {
    "kept-provider": { "name": "keep me" },
  },
}
EOF

cat > "$fake_bin/npm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
prefix=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--prefix" ]]; then prefix="$2"; shift 2; else shift; fi
done
[[ -n "$prefix" ]]
runtime="$prefix/lib/node_modules/@opencode/ai"
mkdir -p "$runtime/dist/providers" "$runtime/dist/protocols" "$prefix/bin"
: > "$runtime/dist/providers/openai-compatible-responses.js"
{
  printf '%s\n' 'namespace: Schema.optional(Schema.String),'
  printf '%s\n' 'namespace: Schema.optional(Schema.String),'
  for _ in 1 2 3 4; do printf '%s\n' 'namespace: item.namespace,'; done
} > "$runtime/dist/protocols/open-responses.js"
cat > "$prefix/bin/opencode" <<'OPENCODE'
#!/usr/bin/env bash
if [[ "${1:-}" == debug && "${2:-}" == agents ]]; then
  printf '%s\n' '[{"id":"sage-qwen","mode":"primary","model":{"providerID":"sage-qwen38","id":"Qwen/Qwen3.8-27B","variant":"xhigh"}}]'
else
  printf '%s\n' 'OpenCode fixture'
fi
OPENCODE
chmod +x "$prefix/bin/opencode"
EOF
chmod +x "$fake_bin/npm"

run_installer() {
  HOME="$fake_home" \
  SHELL=/bin/bash \
  XDG_CONFIG_HOME="$fake_home/.config" \
  XDG_STATE_HOME="$fake_home/.local/state" \
  SAGE_OPENCODE_INSTALL_PREFIX="$prefix" \
  PATH="$fake_bin:$node_bin_dir:/usr/bin:/bin:/usr/sbin:/sbin" \
    "$repo_root/install.sh"
}

run_installer >/dev/null
run_installer >/dev/null

node --input-type=module - "$fake_home/.config/opencode/opencode.jsonc" <<'NODE'
import fs from "node:fs";
const config = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (config.theme !== "system") throw new Error("existing setting was lost");
if (config.providers?.["kept-provider"]?.name !== "keep me") {
  throw new Error("existing provider was lost");
}
const sage = config.providers?.["sage-qwen38"];
if (!sage) throw new Error("SAGE provider is missing");
if (config.model !== "sage-qwen38/Qwen/Qwen3.8-27B") {
  throw new Error("SAGE is not the default model for new sessions");
}
if (config.default_agent !== "sage-qwen") {
  throw new Error("sage-qwen is not the default primary agent");
}
if (sage.models?.["Qwen/Qwen3.8-27B"]?.limit?.context !== 262144) {
  throw new Error("context window is wrong");
}
if (sage.models?.["Qwen/Qwen3.8-27B"]?.settings?.reasoningEffort !== "xhigh") {
  throw new Error("reasoning effort is wrong");
}
if (!sage.settings?.apiKey?.includes("qwen38-api-key")) {
  throw new Error("secret file reference is missing");
}
NODE

protocol="$prefix/lib/node_modules/@opencode/ai/dist/protocols/open-responses.js"
[[ "$(grep -Fc 'namespace: Schema.optional(Schema.NullOr(Schema.String)),' "$protocol")" -eq 2 ]]
[[ "$(grep -Fc 'namespace: item.namespace ?? undefined,' "$protocol")" -eq 4 ]]
[[ "$(grep -Fc '# >>> sage-opencode path' "$fake_home/.bashrc")" -eq 1 ]]
[[ "$(stat -f '%Lp' "$fake_home/.config/sage/qwen38-api-key" 2>/dev/null || stat -c '%a' "$fake_home/.config/sage/qwen38-api-key")" == 600 ]]

printf '%s\n' 'install smoke test: PASS'
