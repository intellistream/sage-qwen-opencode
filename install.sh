#!/usr/bin/env bash
set -euo pipefail

opencode_version="2.0.20"
replace_key=0

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

case "$(uname -s)" in
  Darwin|Linux) ;;
  *)
    printf 'Please run this script on macOS, Linux, or Windows WSL.\n' >&2
    exit 1
    ;;
esac

for command_name in node npm; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf '%s is required. Install the current Node.js LTS release, reopen the terminal, and run this script again.\n' \
      "$command_name" >&2
    exit 1
  fi
done

install_prefix="${SAGE_OPENCODE_INSTALL_PREFIX:-$HOME/.local}"
runtime_root="$install_prefix/lib/node_modules/@opencode/ai"
provider_module="$runtime_root/dist/providers/openai-compatible-responses.js"
protocol_module="$runtime_root/dist/protocols/open-responses.js"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
agent_home="$config_home/agents"
secret_dir="${XDG_CONFIG_HOME:-$HOME/.config}/sage"
secret_file="$secret_dir/qwen38-api-key"
backup_root="${XDG_STATE_HOME:-$HOME/.local/state}/sage-opencode/backups/$(date '+%Y%m%d-%H%M%S')-$$"

printf 'Installing OpenCode V2 %s in %s ...\n' "$opencode_version" "$install_prefix"
npm install --global --prefix "$install_prefix" \
  "@opencode/cli@$opencode_version" \
  "@opencode/ai@$opencode_version"

[[ -x "$install_prefix/bin/opencode" ]] || {
  printf 'OpenCode installation did not create %s/bin/opencode\n' "$install_prefix" >&2
  exit 1
}
[[ -f "$provider_module" && -f "$protocol_module" ]] || {
  printf 'The pinned OpenCode provider runtime is incomplete.\n' >&2
  exit 1
}

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

# Merge the provider into any existing JSON/JSONC configuration. Other values
# are retained. The original file (including comments and formatting) is kept
# in the timestamped backup because the merged file is normalized as JSON.
node --input-type=module - \
  "$config_home/opencode.jsonc" "$provider_module" "$secret_file" <<'NODE'
import fs from "node:fs";
import { pathToFileURL } from "node:url";

const [target, providerPath, secretPath] = process.argv.slice(2);

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
        { id: "xhigh", settings: { reasoningEffort: "xhigh" } },
      ],
    },
  },
};
fs.writeFileSync(target, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });
NODE

cat > "$agent_home/sage-qwen.md" <<'EOF'
---
description: Full coding agent backed by the course SAGE Qwen service.
mode: primary
model: sage-qwen38/Qwen/Qwen3.8-27B#xhigh
---

Own the requested work end to end. Inspect nearby source before guessing, use
tools directly, preserve unrelated changes, and run bounded relevant checks.
Keep progress clear and return a concise account of the result, validation,
and any material remaining uncertainty.
EOF
chmod 0600 "$config_home/opencode.jsonc"
chmod 0644 "$agent_home/sage-qwen.md"

agent_check() {
  local agent_summary
  agent_summary="$($install_prefix/bin/opencode debug agents)"
  node --input-type=module - "$agent_summary" <<'NODE'
const agents = JSON.parse(process.argv[2]);
const agent = agents.find((candidate) => candidate.id === "sage-qwen");
if (!agent) process.exit(1);
if (agent.mode !== "primary") throw new Error(`Unexpected agent mode: ${agent.mode}`);
if (agent.model?.providerID !== "sage-qwen38" ||
    agent.model?.id !== "Qwen/Qwen3.8-27B" ||
    agent.model?.variant !== "xhigh") {
  throw new Error(`Unexpected agent model: ${JSON.stringify(agent.model)}`);
}
NODE
}

# A fresh OpenCode installation can return only its built-in agents on the
# first debug invocation while it initializes local state. Retry once, then
# fail rather than reporting an installation that OpenCode cannot discover.
if ! agent_check; then
  sleep 1
  agent_check || {
    printf 'OpenCode did not discover the sage-qwen agent.\n' >&2
    exit 1
  }
fi

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
