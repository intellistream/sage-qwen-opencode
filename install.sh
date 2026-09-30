#!/usr/bin/env bash
set -euo pipefail

opencode_version="2.0.20"
node_version="24.21.0"
replace_key=0
install_prefix="${SAGE_OPENCODE_INSTALL_PREFIX:-$HOME/.local}"

usage() {
  cat <<'EOF'
Usage: ./install.sh [--replace-key]

Install the IntelliStream SAGE Qwen profile for OpenCode V2.

Options:
  --replace-key  Prompt for a new personal API key even if one is configured.
  -h, --help     Show this help.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --replace-key) replace_key=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

os_name="$(uname -s)"
case "$os_name" in
  Darwin|Linux) ;;
  *)
    printf 'Please run this script on macOS, Linux, or Windows WSL.\n' >&2
    exit 1
    ;;
esac

node_is_usable() {
  command -v node >/dev/null 2>&1 &&
    command -v npm >/dev/null 2>&1 &&
    node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 20 ? 0 : 1)' \
      >/dev/null 2>&1
}

download_file() {
  local url="$1"
  local output="$2"
  if command -v curl >/dev/null 2>&1; then
    curl --fail --location --silent --show-error --output "$output" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget --quiet --output-document="$output" "$url"
  else
    printf 'curl or wget is required to download Node.js.\n' >&2
    return 1
  fi
}

sha256_file() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$path" | awk '{print $NF}'
  else
    printf 'sha256sum, shasum, or openssl is required to verify Node.js.\n' >&2
    return 1
  fi
}

install_node() {
  local arch platform artifact expected_sha actual_sha base url
  case "$(uname -m)" in
    x86_64|amd64) arch="x64" ;;
    arm64|aarch64) arch="arm64" ;;
    *)
      printf 'Automatic Node.js installation does not support architecture: %s\n' "$(uname -m)" >&2
      return 1
      ;;
  esac

  case "$os_name" in
    Darwin) platform="darwin-$arch" ;;
    Linux)
      platform="linux-$arch"
      if ldd --version 2>&1 | grep -qi musl; then
        if [[ "$arch" != "x64" ]]; then
          printf 'Automatic Node.js installation does not support Linux musl on %s.\n' "$arch" >&2
          return 1
        fi
        platform="linux-x64-musl"
      fi
      ;;
  esac

  artifact="node-v${node_version}-${platform}.tar.gz"
  case "$artifact" in
    node-v24.21.0-darwin-arm64.tar.gz) expected_sha="bed7eea5325e1108f32ce5228ddd6a5f0f08a499ee42aa7442aea583702f6057" ;;
    node-v24.21.0-darwin-x64.tar.gz) expected_sha="1462cb3b3046b815cf8ea436d3da450ec1a9f11dac7e5a46b0ada5305d7e8097" ;;
    node-v24.21.0-linux-arm64.tar.gz) expected_sha="724282c3b43aec998aa9527380465b45d229e021b58035f5f4f63095eabfe5d5" ;;
    node-v24.21.0-linux-x64-musl.tar.gz) expected_sha="3d63405fc65a0d2d2976c1f0bc2fd27bb0bd07212469e705aac3f03ae5ab4c9c" ;;
    node-v24.21.0-linux-x64.tar.gz) expected_sha="6e1db87ef58b8819e5d5402eff1536491b18edd8eb7bee5ef7897876e88dc5ff" ;;
    *) printf 'No pinned checksum is available for %s.\n' "$artifact" >&2; return 1 ;;
  esac
  # Test fixtures may override the source and expected digest. Production uses
  # the pinned official Node.js URL and published digest above.
  expected_sha="${SAGE_NODE_ARCHIVE_SHA256:-$expected_sha}"
  url="${SAGE_NODE_DIST_BASE_URL:-https://nodejs.org/dist/v$node_version}/$artifact"
  base="${artifact%.tar.gz}"

  local temp_root node_temp_dir archive_path node_home
  temp_root="${TMPDIR:-/tmp}"
  node_temp_dir="$(mktemp -d "$temp_root/sage-node.XXXXXX")"
  archive_path="$node_temp_dir/$artifact"
  node_home="$install_prefix/opt/$base"

  cleanup_node_download() {
    if [[ -n "${node_temp_dir:-}" && "$node_temp_dir" == "$temp_root"/sage-node.* ]]; then
      rm -rf -- "$node_temp_dir"
    fi
  }
  trap cleanup_node_download EXIT INT TERM

  printf 'Node.js is missing or too old; installing Node.js %s LTS in %s ...\n' \
    "$node_version" "$install_prefix"
  download_file "$url" "$archive_path"
  actual_sha="$(sha256_file "$archive_path")"
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    printf 'Node.js checksum verification failed for %s.\n' "$artifact" >&2
    return 1
  fi

  mkdir -p "$install_prefix/opt" "$install_prefix/bin"
  if [[ -e "$node_home" && ! -x "$node_home/bin/node" ]]; then
    printf 'Existing incomplete Node.js directory: %s\n' "$node_home" >&2
    return 1
  fi
  if [[ ! -x "$node_home/bin/node" ]]; then
    tar -xzf "$archive_path" -C "$install_prefix/opt"
  fi
  for executable in node npm npx corepack; do
    [[ -e "$node_home/bin/$executable" ]] || continue
    ln -sfn "../opt/$base/bin/$executable" "$install_prefix/bin/$executable"
  done

  cleanup_node_download
  trap - EXIT INT TERM
  export PATH="$install_prefix/bin:$PATH"
  node_is_usable || {
    printf 'The local Node.js installation did not become usable.\n' >&2
    return 1
  }
}

if ! node_is_usable; then
  install_node
fi

runtime_root="$install_prefix/lib/node_modules/@opencode/ai"
provider_module="$runtime_root/dist/providers/openai-compatible-responses.js"
protocol_module="$runtime_root/dist/protocols/open-responses.js"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
agent_home="$config_home/agents"
cli_config="$config_home/cli.json"
secret_dir="${XDG_CONFIG_HOME:-$HOME/.config}/sage"
secret_file="$secret_dir/qwen38-api-key"
backup_root="${XDG_STATE_HOME:-$HOME/.local/state}/sage-opencode/backups/$(date '+%Y%m%d-%H%M%S')-$$"
cli_binary="$install_prefix/lib/node_modules/@opencode/cli/bin/opencode.exe"

# npm cannot replace our regular-file launchers with package symlinks on every
# platform. Remove only launchers carrying our exact marker before reinstalling.
for launcher_name in opencode opencode2; do
  launcher_path="$install_prefix/bin/$launcher_name"
  if [[ -f "$launcher_path" && ! -L "$launcher_path" ]] &&
      grep -Fq '# sage-opencode Linux launcher' "$launcher_path"; then
    unlink "$launcher_path"
  fi
done

printf 'Installing OpenCode V2 %s in %s ...\n' "$opencode_version" "$install_prefix"
npm install --global --prefix "$install_prefix" \
  "@opencode/cli@$opencode_version" \
  "@opencode/ai@$opencode_version"

[[ -x "$install_prefix/bin/opencode" ]] || {
  printf 'OpenCode installation did not create %s/bin/opencode\n' "$install_prefix" >&2
  exit 1
}
[[ -x "$cli_binary" ]] || {
  printf 'OpenCode installation did not create %s\n' "$cli_binary" >&2
  exit 1
}
[[ -f "$provider_module" && -f "$protocol_module" ]] || {
  printf 'The pinned OpenCode provider runtime is incomplete.\n' >&2
  exit 1
}

# OpenCode's Linux file watcher can exhaust inotify instances and crash with
# EMFILE on shared servers. Use the upstream-supported opt-out in a launcher
# rather than mutating host-wide sysctl settings. An explicit environment value
# still wins, so administrators can re-enable watching after raising limits.
disable_filewatcher="${SAGE_OPENCODE_DISABLE_FILEWATCHER:-auto}"
if [[ "$disable_filewatcher" == auto ]]; then
  [[ "$os_name" == Linux ]] && disable_filewatcher=1 || disable_filewatcher=0
fi
case "$disable_filewatcher" in
  0|1) ;;
  *) printf 'SAGE_OPENCODE_DISABLE_FILEWATCHER must be auto, 0, or 1.\n' >&2; exit 1 ;;
esac
if [[ "$disable_filewatcher" == 1 ]]; then
  for launcher_name in opencode opencode2; do
    launcher_path="$install_prefix/bin/$launcher_name"
    [[ ! -e "$launcher_path" && ! -L "$launcher_path" ]] || unlink "$launcher_path"
    {
      printf '#!/usr/bin/env bash\n'
      printf '# sage-opencode Linux launcher\n'
      printf 'export OPENCODE_EXPERIMENTAL_DISABLE_FILEWATCHER="${OPENCODE_EXPERIMENTAL_DISABLE_FILEWATCHER:-1}"\n'
      printf 'exec %q "$@"\n' "$cli_binary"
    } > "$launcher_path"
    chmod 0755 "$launcher_path"
  done
fi

# The SAGE endpoint currently emits namespace:null for Responses function-call
# items. OpenCode 2.0.20 accepts a string or an omitted field. Patch only the
# six known sites and fail closed if the pinned runtime changes shape.
node --input-type=module - "$protocol_module" <<'NODE'
import fs from "node:fs";

const path = process.argv[2];
let source = fs.readFileSync(path, "utf8");

function replaceExact(oldText, newText, expected) {
  const oldCount = source.split(oldText).length - 1;
  const newCount = source.split(newText).length - 1;
  if (oldCount === expected && newCount === 0) {
    source = source.split(oldText).join(newText);
    return;
  }
  if (oldCount === 0 && newCount === expected) return;
  throw new Error(
    `Unexpected OpenCode runtime shape for ${oldText}: old=${oldCount}, patched=${newCount}`,
  );
}

replaceExact(
  "namespace: Schema.optional(Schema.String),",
  "namespace: Schema.optional(Schema.NullOr(Schema.String)),",
  2,
);
replaceExact(
  "namespace: item.namespace,",
  "namespace: item.namespace ?? undefined,",
  4,
);
fs.writeFileSync(path, source);
NODE

mkdir -p "$secret_dir"
chmod 0700 "$secret_dir"
if [[ ! -s "$secret_file" || "$replace_key" -eq 1 ]]; then
  if [[ ! -t 0 ]]; then
    printf 'Run this script in an interactive terminal so it can securely ask for your API key.\n' >&2
    exit 1
  fi
  printf 'Paste your personal SAGE API key (input is hidden): ' >&2
  IFS= read -r -s sage_key
  printf '\n' >&2
  [[ -n "$sage_key" ]] || {
    printf 'The API key cannot be empty.\n' >&2
    exit 1
  }
  case "$sage_key" in
    *[[:space:]]*)
      printf 'The API key must not contain whitespace.\n' >&2
      unset sage_key
      exit 1
      ;;
  esac
  umask 077
  printf '%s\n' "$sage_key" > "$secret_file"
  unset sage_key
fi
chmod 0600 "$secret_file"

backup_if_present() {
  local path="$1"
  [[ -e "$path" ]] || return 0
  mkdir -p "$backup_root"
  cp -p "$path" "$backup_root/$(basename "$path")"
  printf 'Backed up %s -> %s\n' "$path" "$backup_root/$(basename "$path")"
}

case "${SHELL##*/}" in
  zsh) shell_rc="$HOME/.zshrc" ;;
  bash) shell_rc="$HOME/.bashrc" ;;
  *) shell_rc="$HOME/.profile" ;;
esac
path_start="# >>> sage-opencode path"
path_end="# <<< sage-opencode path"
if ! grep -Fq "$path_start" "$shell_rc" 2>/dev/null; then
  backup_if_present "$shell_rc"
  {
    [[ ! -s "$shell_rc" ]] || printf '\n'
    printf '%s\n' "$path_start"
    printf 'case ":$PATH:" in\n'
    printf '  *":$HOME/.local/bin:"*) ;;\n'
    printf '  *) export PATH="$HOME/.local/bin:$PATH" ;;\n'
    printf 'esac\n'
    printf '%s\n' "$path_end"
  } >> "$shell_rc"
fi

mkdir -p "$config_home" "$agent_home"
backup_if_present "$config_home/opencode.jsonc"
backup_if_present "$agent_home/sage-qwen.md"
backup_if_present "$cli_config"

# Merge the provider into any existing JSON/JSONC configuration. Other values
# are retained. The original file (including comments and formatting) is kept
# in the timestamped backup because the merged file is normalized as JSON.
node --input-type=module - \
  "$config_home/opencode.jsonc" "$provider_module" "$secret_file" "$cli_config" <<'NODE'
import fs from "node:fs";
import { pathToFileURL } from "node:url";

const [target, providerPath, secretPath, cliTarget] = process.argv.slice(2);

function stripJSONC(source) {
  let out = "";
  let state = "code";
  for (let i = 0; i < source.length; i += 1) {
    const c = source[i];
    const n = source[i + 1];
    if (state === "string") {
      out += c;
      if (c === "\\") {
        if (n !== undefined) out += source[++i];
      } else if (c === '"') state = "code";
    } else if (state === "line") {
      if (c === "\n") { out += c; state = "code"; }
    } else if (state === "block") {
      if (c === "*" && n === "/") { i += 1; state = "code"; }
      else if (c === "\n") out += c;
    } else if (c === '"') {
      out += c; state = "string";
    } else if (c === "/" && n === "/") {
      i += 1; state = "line";
    } else if (c === "/" && n === "*") {
      i += 1; state = "block";
    } else {
      out += c;
    }
  }
  if (state === "string" || state === "block") {
    throw new Error("Unterminated string or block comment in existing OpenCode config");
  }

  let normalized = "";
  state = "code";
  for (let i = 0; i < out.length; i += 1) {
    const c = out[i];
    if (state === "string") {
      normalized += c;
      if (c === "\\" && out[i + 1] !== undefined) normalized += out[++i];
      else if (c === '"') state = "code";
      continue;
    }
    if (c === '"') { normalized += c; state = "string"; continue; }
    if (c === ",") {
      let j = i + 1;
      while (/\s/.test(out[j] ?? "")) j += 1;
      if (out[j] === "}" || out[j] === "]") continue;
    }
    normalized += c;
  }
  return normalized;
}

let config = {};
if (fs.existsSync(target) && fs.statSync(target).size > 0) {
  config = JSON.parse(stripJSONC(fs.readFileSync(target, "utf8")));
  if (!config || Array.isArray(config) || typeof config !== "object") {
    throw new Error("Existing OpenCode config must be a JSON object");
  }
}

config.$schema ??= "https://opencode.ai/config.json";
// OpenCode V2 stores the session model separately from the selected primary
// agent. Set both defaults so a fresh session actually uses SAGE; users can
// still switch either choice interactively.
config.model = "sage-qwen38/Qwen/Qwen3.8-27B";
config.default_agent = "sage-qwen";
config.providers ??= {};
if (!config.providers || Array.isArray(config.providers) || typeof config.providers !== "object") {
  throw new Error("Existing OpenCode providers setting must be an object");
}
config.providers["sage-qwen38"] = {
  name: "SAGE Qwen3.8-27B",
  package: pathToFileURL(providerPath).href,
  settings: {
    baseURL: "https://openai.sage.org.ai/v1",
    apiKey: `{file:${secretPath}}`,
  },
  models: {
    "Qwen/Qwen3.8-27B": {
      name: "Qwen3.8-27B",
      capabilities: {
        tools: true,
        input: ["text"],
        output: ["text"],
      },
      limit: { context: 262144, output: 32768 },
      settings: { reasoningEffort: "xhigh" },
      variants: [
        { id: "low", settings: { reasoningEffort: "low" } },
        { id: "medium", settings: { reasoningEffort: "medium" } },
        { id: "xhigh", settings: { reasoningEffort: "xhigh" } },
      ],
    },
  },
};
fs.writeFileSync(target, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });

let cli = {};
if (fs.existsSync(cliTarget) && fs.statSync(cliTarget).size > 0) {
  cli = JSON.parse(stripJSONC(fs.readFileSync(cliTarget, "utf8")));
  if (!cli || Array.isArray(cli) || typeof cli !== "object") {
    throw new Error("Existing OpenCode CLI config must be a JSON object");
  }
}
cli.$schema ??= "https://opencode.ai/v2/cli.json";
cli.keybinds ??= {};
if (!cli.keybinds || Array.isArray(cli.keybinds) || typeof cli.keybinds !== "object") {
  throw new Error("Existing OpenCode CLI keybinds setting must be an object");
}
// Shift+Tab normally cycles agents in OpenCode V2. For this course profile it
// cycles low/medium/xhigh reasoning instead; Ctrl+T keeps agent cycling handy.
cli.keybinds["variant.cycle"] = "shift+tab";
cli.keybinds["agent.cycle"] = "ctrl+t";
fs.writeFileSync(cliTarget, `${JSON.stringify(cli, null, 2)}\n`, { mode: 0o600 });
NODE

cat > "$agent_home/sage-qwen.md" <<'EOF'
---
description: Full coding agent backed by the course SAGE Qwen service.
mode: primary
model: sage-qwen38/Qwen/Qwen3.8-27B#xhigh
---

You are a coding agent. Follow repository instructions and inspect relevant
files before editing. Use tools directly, preserve unrelated changes, and run
relevant tests. Answer concisely with the changes, validation, and any material
limitations.
EOF
chmod 0600 "$config_home/opencode.jsonc" "$cli_config"
chmod 0644 "$agent_home/sage-qwen.md"

# Validate the generated profile without starting OpenCode's background
# service. A pristine HOME can take long enough to initialize that service to
# make an otherwise successful first installation look like a failure.
node --input-type=module - \
  "$config_home/opencode.jsonc" "$agent_home/sage-qwen.md" <<'NODE'
import fs from "node:fs";
const [configPath, agentPath] = process.argv.slice(2);
const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
if (config.model !== "sage-qwen38/Qwen/Qwen3.8-27B") {
  throw new Error(`Unexpected default model: ${config.model}`);
}
if (config.default_agent !== "sage-qwen") {
  throw new Error(`Unexpected default agent: ${config.default_agent}`);
}
const agent = fs.readFileSync(agentPath, "utf8");
if (!/^mode: primary$/m.test(agent) ||
    !/^model: sage-qwen38\/Qwen\/Qwen3\.8-27B#xhigh$/m.test(agent)) {
  throw new Error("The sage-qwen agent profile is invalid");
}
NODE
"$install_prefix/bin/opencode" --version >/dev/null

cat <<EOF

Installation complete.

Open a new terminal, then run:
  opencode

New sessions default to the "sage-qwen" agent and SAGE Qwen model.

One-shot usage:
  opencode run --agent sage-qwen --model 'sage-qwen38/Qwen/Qwen3.8-27B#xhigh' "请阅读当前项目并说明它的结构"

Your API key is stored only in:
  $secret_file
EOF
