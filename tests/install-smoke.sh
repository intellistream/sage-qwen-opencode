#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
real_node="$(command -v node)"
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
cat > "$fake_home/.config/opencode/cli.json" <<'EOF'
{
  "theme": { "mode": "dark" }
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

case "$(uname -s)" in
  Darwin) node_platform="darwin" ;;
  Linux) node_platform="linux" ;;
  *) printf 'unsupported fixture OS\n' >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64|amd64) node_arch="x64" ;;
  arm64|aarch64) node_arch="arm64" ;;
  *) printf 'unsupported fixture architecture\n' >&2; exit 1 ;;
esac
if [[ "$node_platform" == linux ]] && ldd --version 2>&1 | grep -qi musl; then
  node_arch="${node_arch}-musl"
fi
node_base="node-v24.21.0-${node_platform}-${node_arch}"
node_dist="$fixture/node-dist"
node_payload="$fixture/node-payload/$node_base/bin"
mkdir -p "$node_dist" "$node_payload"
printf '#!/usr/bin/env bash\nexec %q "$@"\n' "$real_node" > "$node_payload/node"
cp "$fake_bin/npm" "$node_payload/npm"
chmod +x "$node_payload/node" "$node_payload/npm"
tar -czf "$node_dist/$node_base.tar.gz" -C "$fixture/node-payload" "$node_base"
fake_node_sha="$($real_node --input-type=module - "$node_dist/$node_base.tar.gz" <<'NODE'
import crypto from "node:crypto";
import fs from "node:fs";
console.log(crypto.createHash("sha256").update(fs.readFileSync(process.argv[2])).digest("hex"));
NODE
)"

cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=""
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output|-o) output="$2"; shift 2 ;;
    http://*|https://*|file://*) url="$1"; shift ;;
    *) shift ;;
  esac
done
[[ -n "$output" && -n "$url" ]]
cp "$FAKE_NODE_DIST/${url##*/}" "$output"
EOF
cat > "$fake_bin/node" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
chmod +x "$fake_bin/curl" "$fake_bin/node"

run_installer() {
  HOME="$fake_home" \
  SHELL=/bin/bash \
  XDG_CONFIG_HOME="$fake_home/.config" \
  XDG_STATE_HOME="$fake_home/.local/state" \
  SAGE_OPENCODE_INSTALL_PREFIX="$prefix" \
  SAGE_NODE_DIST_BASE_URL="https://fixture.invalid" \
  SAGE_NODE_ARCHIVE_SHA256="$fake_node_sha" \
  FAKE_NODE_DIST="$node_dist" \
  PATH="$fake_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
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
const variants = sage.models?.["Qwen/Qwen3.8-27B"]?.variants ?? [];
if (JSON.stringify(variants.map((v) => v.id)) !== JSON.stringify(["low", "medium", "xhigh"])) {
  throw new Error(`reasoning variants are wrong: ${JSON.stringify(variants)}`);
}
if (!sage.settings?.apiKey?.includes("qwen38-api-key")) {
  throw new Error("secret file reference is missing");
}
NODE

node --input-type=module - "$fake_home/.config/opencode/cli.json" <<'NODE'
import fs from "node:fs";
const config = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
if (config.theme?.mode !== "dark") throw new Error("existing CLI setting was lost");
if (config.keybinds?.["variant.cycle"] !== "shift+tab") {
  throw new Error("Shift+Tab variant binding is missing");
}
if (config.keybinds?.["agent.cycle"] !== "ctrl+t") {
  throw new Error("replacement agent-cycle binding is missing");
}
NODE

protocol="$prefix/lib/node_modules/@opencode/ai/dist/protocols/open-responses.js"
[[ "$(grep -Fc 'namespace: Schema.optional(Schema.NullOr(Schema.String)),' "$protocol")" -eq 2 ]]
[[ "$(grep -Fc 'namespace: item.namespace ?? undefined,' "$protocol")" -eq 4 ]]
[[ "$(grep -Fc '# >>> sage-opencode path' "$fake_home/.bashrc")" -eq 1 ]]
[[ "$(stat -f '%Lp' "$fake_home/.config/sage/qwen38-api-key" 2>/dev/null || stat -c '%a' "$fake_home/.config/sage/qwen38-api-key")" == 600 ]]
[[ -x "$prefix/opt/$node_base/bin/node" ]]
[[ -L "$prefix/bin/node" ]]

printf '%s\n' 'install smoke test (including Node bootstrap): PASS'
