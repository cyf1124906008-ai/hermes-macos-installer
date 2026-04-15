#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
INSTALL_DIR="${HERMES_INSTALL_DIR:-$HERMES_HOME/hermes-agent}"
REPO_SLUG="${HERMES_REPO_SLUG:-NousResearch/hermes-agent}"
REPO_REF="${HERMES_REPO_REF:-main}"
HERMES_SOURCE_DIR="${HERMES_SOURCE_DIR:-}"
HERMES_FORCE_REINSTALL="${HERMES_FORCE_REINSTALL:-0}"
DATAEYES_BASE_URL="${DATAEYES_BASE_URL:-https://cloud.dataeyes.ai/v1}"
PIP_INDEX_URL="${PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"
NODE_DIST_MIRROR="${NODE_DIST_MIRROR:-https://npmmirror.com/mirrors/node}"
HERMES_INSTALL_EXTRAS="${HERMES_INSTALL_EXTRAS:-cli,cron,pty,mcp,acp,web,messaging}"
HERMES_WITH_BROWSER_TOOLS="${HERMES_WITH_BROWSER_TOOLS:-0}"
HERMES_CONFIGURE_GATEWAY="${HERMES_CONFIGURE_GATEWAY:-ask}"
HERMES_START_GATEWAY="${HERMES_START_GATEWAY:-ask}"
HERMES_OPEN_WEBUI="${HERMES_OPEN_WEBUI:-ask}"
LOCAL_BIN="$HOME/.local/bin"

log_info() {
  echo -e "${CYAN}→${NC} $1"
}

log_success() {
  echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
  echo -e "${RED}✗${NC} $1"
}

prompt_secret_tty_into() {
  local __var_name="$1"
  local prompt_text="$2"
  local value=""
  if ! (: < /dev/tty) 2>/dev/null; then
    return 1
  fi
  printf "%s" "$prompt_text" > /dev/tty
  if ! IFS= read -rs value < /dev/tty; then
    printf "\n" > /dev/tty
    return 1
  fi
  printf "\n" > /dev/tty
  printf -v "$__var_name" '%s' "$value"
  return 0
}

prompt_line_tty_into() {
  local __var_name="$1"
  local prompt_text="$2"
  local value=""
  if ! (: < /dev/tty) 2>/dev/null; then
    return 1
  fi
  printf "%s" "$prompt_text" > /dev/tty
  if ! IFS= read -r value < /dev/tty; then
    printf "\n" > /dev/tty
    return 1
  fi
  printf -v "$__var_name" '%s' "$value"
  return 0
}

prompt_yes_no_tty() {
  local prompt_text="$1"
  local default_answer="${2:-Y}"
  local raw=""
  local normalized_default=""

  normalized_default="$(printf '%s' "$default_answer" | tr '[:lower:]' '[:upper:]')"

  if [ ! -r /dev/tty ]; then
    if [ "$normalized_default" = "Y" ]; then
      return 0
    fi
    return 1
  fi

  if ! prompt_line_tty_into raw "$prompt_text"; then
    if [ "$normalized_default" = "Y" ]; then
      return 0
    fi
    return 1
  fi

  raw="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | xargs)"
  if [ -z "$raw" ]; then
    [ "$normalized_default" = "Y" ]
    return $?
  fi
  case "$raw" in
    y|yes) return 0 ;;
    n|no) return 1 ;;
  esac
  [ "$normalized_default" = "Y" ]
}

run_attached_to_tty() {
  if [ -r /dev/tty ]; then
    "$@" </dev/tty >/dev/tty 2>&1
  else
    "$@"
  fi
}

env_decision() {
  local raw="${1:-ask}"
  raw="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$raw" in
    1|y|yes|true|on) echo "yes" ;;
    0|n|no|false|off) echo "no" ;;
    *) echo "ask" ;;
  esac
}

print_banner() {
  echo
  echo -e "${CYAN}${BOLD}Hermes macOS 安装器${NC}"
  echo
}

require_macos() {
  if [ "$(uname -s)" != "Darwin" ]; then
    log_error "这个安装器当前只支持 macOS"
    exit 1
  fi
}

require_basic_tools() {
  local missing=()
  for cmd in curl tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    log_error "缺少基础命令: ${missing[*]}"
    exit 1
  fi
}

ensure_python() {
  local py=""
  if command -v python3 >/dev/null 2>&1; then
    py="$(command -v python3)"
  fi

  if [ -n "$py" ] && "$py" - <<'PY' >/dev/null 2>&1
import sys
raise SystemExit(0 if sys.version_info >= (3, 11) else 1)
PY
  then
    PYTHON_BIN="$py"
    log_success "Python 已就绪: $("$PYTHON_BIN" --version 2>&1)"
    return 0
  fi

  if command -v brew >/dev/null 2>&1; then
    log_warn "当前 python3 版本不足，尝试通过 Homebrew 安装 python@3.11"
    HOMEBREW_BOTTLE_DOMAIN="${HOMEBREW_BOTTLE_DOMAIN:-https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles}" \
      brew install python@3.11
    if [ -x "/opt/homebrew/bin/python3.11" ]; then
      PYTHON_BIN="/opt/homebrew/bin/python3.11"
    elif [ -x "/usr/local/bin/python3.11" ]; then
      PYTHON_BIN="/usr/local/bin/python3.11"
    else
      log_error "python@3.11 安装后仍未找到可执行文件"
      exit 1
    fi
    log_success "Python 已安装: $("$PYTHON_BIN" --version 2>&1)"
    return 0
  fi

  log_error "需要 Python 3.11+。当前系统没有可用版本，且未检测到 Homebrew。"
  log_info "建议先执行: brew install python@3.11"
  exit 1
}

ensure_optional_tools() {
  if command -v rg >/dev/null 2>&1; then
    log_success "ripgrep 已存在: $(rg --version | head -1)"
  elif command -v brew >/dev/null 2>&1; then
    log_info "尝试安装 ripgrep"
    HOMEBREW_BOTTLE_DOMAIN="${HOMEBREW_BOTTLE_DOMAIN:-https://mirrors.tuna.tsinghua.edu.cn/homebrew-bottles}" \
      brew install ripgrep || log_warn "ripgrep 安装失败，继续"
  else
    log_warn "未安装 ripgrep，继续"
  fi
}

download_with_fallbacks() {
  local output="$1"
  shift
  local url
  for url in "$@"; do
    [ -n "$url" ] || continue
    log_info "下载: $url"
    if curl -fL --connect-timeout 15 --retry 2 --retry-delay 1 "$url" -o "$output"; then
      return 0
    fi
  done
  return 1
}

download_repo_archive() {
  local tmp_dir archive_url_primary archive_url_secondary archive_url_raw

  if [ -n "$HERMES_SOURCE_DIR" ]; then
    if [ ! -d "$HERMES_SOURCE_DIR" ] || [ ! -f "$HERMES_SOURCE_DIR/pyproject.toml" ]; then
      log_error "HERMES_SOURCE_DIR 无效: $HERMES_SOURCE_DIR"
      exit 1
    fi
    if [ -d "$INSTALL_DIR" ] && [ "$HERMES_FORCE_REINSTALL" != "1" ]; then
      if [ -x "$INSTALL_DIR/venv/bin/hermes" ] || [ -f "$INSTALL_DIR/pyproject.toml" ]; then
        log_success "检测到现有安装目录，跳过源码覆盖: $INSTALL_DIR"
        return 0
      fi
    fi
    rm -rf "$INSTALL_DIR"
    mkdir -p "$HERMES_HOME"
    cp -R "$HERMES_SOURCE_DIR" "$INSTALL_DIR"
    log_success "已从本地源复制 Hermes: $HERMES_SOURCE_DIR"
    return 0
  fi

  if [ -d "$INSTALL_DIR" ] && [ "$HERMES_FORCE_REINSTALL" != "1" ]; then
    if [ -x "$INSTALL_DIR/venv/bin/hermes" ] || [ -f "$INSTALL_DIR/pyproject.toml" ]; then
      log_success "检测到现有安装目录，跳过源码下载: $INSTALL_DIR"
      return 0
    fi
  fi

  tmp_dir="$(mktemp -d)"
  archive_url_primary="https://ghfast.top/https://codeload.github.com/${REPO_SLUG}/tar.gz/refs/heads/${REPO_REF}"
  archive_url_secondary="https://mirror.ghproxy.com/https://codeload.github.com/${REPO_SLUG}/tar.gz/refs/heads/${REPO_REF}"
  archive_url_raw="https://codeload.github.com/${REPO_SLUG}/tar.gz/refs/heads/${REPO_REF}"

  if ! download_with_fallbacks "$tmp_dir/hermes.tar.gz" \
    "$archive_url_primary" \
    "$archive_url_secondary" \
    "$archive_url_raw"; then
    log_error "Hermes 源码下载失败"
    rm -rf "$tmp_dir"
    exit 1
  fi

  mkdir -p "$tmp_dir/extracted"
  tar -xzf "$tmp_dir/hermes.tar.gz" -C "$tmp_dir/extracted"
  local extracted_root
  extracted_root="$(find "$tmp_dir/extracted" -mindepth 1 -maxdepth 1 -type d | head -1)"
  if [ -z "$extracted_root" ]; then
    log_error "Hermes 源码解压失败"
    rm -rf "$tmp_dir"
    exit 1
  fi

  mkdir -p "$HERMES_HOME"
  if [ -d "$INSTALL_DIR" ]; then
    local backup_dir="${INSTALL_DIR}.backup.$(date +%Y%m%d%H%M%S)"
    log_warn "检测到现有安装，备份到: $backup_dir"
    mv "$INSTALL_DIR" "$backup_dir"
  fi
  mv "$extracted_root" "$INSTALL_DIR"
  rm -rf "$tmp_dir"
  log_success "Hermes 源码已准备好: $INSTALL_DIR"
}

setup_venv() {
  if [ -x "$INSTALL_DIR/venv/bin/hermes" ] && [ "$HERMES_FORCE_REINSTALL" != "1" ]; then
    VENV_PYTHON="$INSTALL_DIR/venv/bin/python"
    VENV_PIP="$INSTALL_DIR/venv/bin/pip"
    log_success "检测到现有虚拟环境，跳过创建"
    return 0
  fi

  log_info "创建虚拟环境"
  rm -rf "$INSTALL_DIR/venv"
  "$PYTHON_BIN" -m venv "$INSTALL_DIR/venv"
  VENV_PYTHON="$INSTALL_DIR/venv/bin/python"
  VENV_PIP="$INSTALL_DIR/venv/bin/pip"
  if ! "$VENV_PIP" install --upgrade pip setuptools wheel -i "$PIP_INDEX_URL" >/dev/null; then
    log_warn "pip 基础组件从镜像安装失败，回退到默认 PyPI"
    "$VENV_PIP" install --upgrade pip setuptools wheel >/dev/null
  fi
  log_success "虚拟环境已创建"
}

install_hermes() {
  if [ -x "$INSTALL_DIR/venv/bin/hermes" ] && [ "$HERMES_FORCE_REINSTALL" != "1" ]; then
    log_success "检测到现有 Hermes 可执行文件，跳过 Python 包重装"
    return 0
  fi

  local extras_spec
  extras_spec="${INSTALL_DIR}[${HERMES_INSTALL_EXTRAS}]"
  log_info "安装 Hermes Python 依赖: [${HERMES_INSTALL_EXTRAS}]"
  if ! "$VENV_PIP" install -e "$extras_spec" -i "$PIP_INDEX_URL"; then
    log_warn "带 extras 的镜像安装失败，尝试默认 PyPI"
    if "$VENV_PIP" install -e "$extras_spec"; then
      log_success "Hermes Python 包安装完成"
      return 0
    fi
    log_warn "带 extras 安装失败，回退到基础安装"
    if ! "$VENV_PIP" install -e "$INSTALL_DIR" -i "$PIP_INDEX_URL"; then
      "$VENV_PIP" install -e "$INSTALL_DIR"
    fi
  fi
  log_success "Hermes Python 包安装完成"
}

ensure_node_for_browser_tools() {
  if [ "$HERMES_WITH_BROWSER_TOOLS" != "1" ]; then
    log_info "默认跳过浏览器工具和 Node 依赖安装"
    return 0
  fi

  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    log_success "Node 已存在: $(node --version)"
    return 0
  fi

  local arch node_arch node_pkg tmp_dir node_url
  arch="$(uname -m)"
  case "$arch" in
    arm64) node_arch="arm64" ;;
    x86_64) node_arch="x64" ;;
    *)
      log_warn "不支持的 Node 架构: $arch，跳过浏览器工具安装"
      return 0
      ;;
  esac

  node_pkg="node-v22.16.0-darwin-${node_arch}.tar.gz"
  node_url="${NODE_DIST_MIRROR}/v22.16.0/${node_pkg}"
  tmp_dir="$(mktemp -d)"
  if ! download_with_fallbacks "$tmp_dir/$node_pkg" "$node_url" "https://nodejs.org/dist/v22.16.0/${node_pkg}"; then
    log_warn "Node 下载失败，跳过浏览器工具安装"
    rm -rf "$tmp_dir"
    return 0
  fi

  tar -xzf "$tmp_dir/$node_pkg" -C "$tmp_dir"
  rm -rf "$HERMES_HOME/node"
  mv "$tmp_dir/node-v22.16.0-darwin-${node_arch}" "$HERMES_HOME/node"
  mkdir -p "$LOCAL_BIN"
  ln -sf "$HERMES_HOME/node/bin/node" "$LOCAL_BIN/node"
  ln -sf "$HERMES_HOME/node/bin/npm" "$LOCAL_BIN/npm"
  ln -sf "$HERMES_HOME/node/bin/npx" "$LOCAL_BIN/npx"
  export PATH="$LOCAL_BIN:$HERMES_HOME/node/bin:$PATH"
  rm -rf "$tmp_dir"
  log_success "Node 已安装到 $HERMES_HOME/node"
}

install_browser_tools() {
  if [ "$HERMES_WITH_BROWSER_TOOLS" != "1" ]; then
    return 0
  fi

  ensure_node_for_browser_tools
  if ! command -v npm >/dev/null 2>&1; then
    log_warn "没有 npm，跳过浏览器工具安装"
    return 0
  fi

  if [ -f "$INSTALL_DIR/package.json" ]; then
    log_info "安装可选 Node 依赖"
    (cd "$INSTALL_DIR" && npm install --silent --registry=https://registry.npmmirror.com) || \
      log_warn "根目录 npm install 失败，继续"
  fi
}

setup_command() {
  mkdir -p "$LOCAL_BIN"
  ln -sf "$INSTALL_DIR/venv/bin/hermes" "$LOCAL_BIN/hermes"
  HERMES_CMD="$LOCAL_BIN/hermes"
  log_success "hermes 命令已链接到 $LOCAL_BIN/hermes"
}

ensure_shell_path() {
  local line='export PATH="$HOME/.local/bin:$PATH"'
  local file
  for file in "$HOME/.zprofile" "$HOME/.zshrc"; do
    [ -f "$file" ] || touch "$file"
    if ! grep -Fq "$line" "$file"; then
      printf '\n%s\n' "$line" >> "$file"
      log_success "已更新 PATH: $file"
    fi
  done
}

resolve_configure_helper() {
  local helper_path
  helper_path="$SCRIPT_DIR/scripts/configure_dataeyes.py"
  if [ -f "$helper_path" ]; then
    echo "$helper_path"
    return 0
  fi

  helper_path="$(mktemp -t hermes-dataeyes-configure).py"
  cat > "$helper_path" <<'PY'
#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import urllib.error
import urllib.request
from pathlib import Path
import sys

import yaml

FALLBACK_MODELS = [
    "claude-sonnet-4-6",
    "claude-sonnet-4-5-20250929",
    "claude-sonnet-4-20250514-thinking",
    "claude-opus-4-20250514",
    "claude-sonnet-4-20250514",
    "claude-opus-4-6",
    "claude-opus-4-5-20251101-thinking",
    "claude-opus-4-20250514-thinking",
    "claude-haiku-4-5-20251001",
    "claude-opus-4-5-20251101",
    "claude-sonnet-4-5-20250929-thinking",
]


def load_yaml(path: Path) -> dict:
    if not path.exists():
        return {}
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    return data if isinstance(data, dict) else {}


def save_yaml(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(data, allow_unicode=True, sort_keys=False), encoding="utf-8")


def fetch_models(base_url: str, api_key: str, timeout: int = 20) -> list[str]:
    req = urllib.request.Request(
        f"{base_url.rstrip('/')}/models",
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        method="GET",
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        payload = json.loads(response.read().decode("utf-8"))
    models: list[str] = []
    if isinstance(payload, dict) and isinstance(payload.get("data"), list):
        for item in payload["data"]:
            if isinstance(item, dict):
                model_id = str(item.get("id") or "").strip()
                if model_id:
                    models.append(model_id)
    return sorted(dict.fromkeys(models))


def choose_model(models: list[str], default_model: str | None) -> str:
    if default_model and default_model in models:
        print(f"使用预设模型: {default_model}")
        return default_model
    print(f"可用模型 ({len(models)}):")
    for idx, model in enumerate(models, start=1):
        print(f"  {idx}. {model}")
    input_stream = sys.stdin
    if not input_stream.isatty():
        try:
            input_stream = open("/dev/tty", "r", encoding="utf-8")
        except OSError:
            input_stream = sys.stdin
    while True:
        print("请选择模型编号，或直接输入模型名: ", end="", flush=True)
        raw = input_stream.readline()
        if raw == "":
            raise SystemExit("无法读取终端输入，请设置 DATAEYES_MODEL 后重试。")
        raw = raw.strip()
        if not raw:
            if default_model:
                return default_model
            continue
        if raw.isdigit():
            idx = int(raw)
            if 1 <= idx <= len(models):
                return models[idx - 1]
        if raw in models:
            return raw
        print("输入无效，请重试。")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", required=True)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--api-key")
    parser.add_argument("--default-model")
    args = parser.parse_args()

    config_path = Path(args.config).expanduser()
    config = load_yaml(config_path)
    model_cfg = config.get("model", {}) if isinstance(config.get("model"), dict) else {}
    current_model = model_cfg.get("default")
    current_key = model_cfg.get("api_key")
    current_base_url = model_cfg.get("base_url")
    effective_key = args.api_key or current_key

    if not effective_key:
        print("未提供 DataEyes API Key，跳过模型配置。")
        return 0

    try:
        models = fetch_models(args.base_url, effective_key)
        print(f"已验证 endpoint: {args.base_url}/models")
    except urllib.error.HTTPError as exc:
        print(f"警告: /models 请求失败，HTTP {exc.code}，使用内置候选模型列表。")
        models = FALLBACK_MODELS[:]
    except Exception as exc:  # noqa: BLE001
        print(f"警告: /models 请求失败 ({exc})，使用内置候选模型列表。")
        models = FALLBACK_MODELS[:]

    if not models:
        models = FALLBACK_MODELS[:]

    if current_model and current_key == effective_key and current_base_url == args.base_url and current_model in models:
        chosen_model = current_model
        print(f"检测到已有 DataEyes 配置，保留模型: {chosen_model}")
    else:
        chosen_model = choose_model(models, args.default_model)

    model_cfg = config.setdefault("model", {})
    model_cfg["provider"] = "custom"
    model_cfg["base_url"] = args.base_url
    model_cfg["api_key"] = effective_key
    model_cfg["default"] = chosen_model

    save_yaml(config_path, config)
    print(f"已写入配置: {config_path}")
    print("provider=custom")
    print(f"base_url={args.base_url}")
    print(f"model={chosen_model}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY
  chmod +x "$helper_path"
  echo "$helper_path"
}

configure_dataeyes() {
  local api_key helper
  local -a helper_args
  local existing_key=""
  api_key="${DATAEYES_API_KEY:-}"
  if [ -f "$HERMES_HOME/config.yaml" ]; then
    existing_key="$(awk '/^[[:space:]]*api_key:[[:space:]]*/ {print $2; exit}' "$HERMES_HOME/config.yaml" 2>/dev/null || true)"
  fi
  if [ -z "$api_key" ]; then
    log_info "如果已有 DataEyes 配置，将自动复用；否则会提示输入 API Key"
    if [ -z "$existing_key" ]; then
      if ! prompt_secret_tty_into api_key "请输入 DataEyes API Key: "; then
        log_error "无法从当前终端读取 DataEyes API Key。"
        log_info "请用环境变量方式执行安装命令，例如："
        log_info "  DATAEYES_API_KEY='你的key' /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/cyf1124906008-ai/hermes-macos-installer/main/install.sh)\""
        exit 1
      fi
      if [ -z "$api_key" ]; then
        log_error "DataEyes API Key 不能为空。"
        exit 1
      fi
    fi
  fi

  helper="$(resolve_configure_helper)"
  helper_args=(
    --config "$HERMES_HOME/config.yaml"
    --base-url "$DATAEYES_BASE_URL"
  )
  if [ -n "$api_key" ]; then
    helper_args+=(--api-key "$api_key")
  fi
  if [ -n "${DATAEYES_MODEL:-}" ]; then
    helper_args+=(--default-model "$DATAEYES_MODEL")
  fi

  "$VENV_PYTHON" "$helper" "${helper_args[@]}"
}

maybe_configure_gateway() {
  case "$(env_decision "$HERMES_CONFIGURE_GATEWAY")" in
    no) return 0 ;;
    yes) ;;
    ask)
      if ! prompt_yes_no_tty "现在配置消息网关吗？[Y/n] " "Y"; then
        return 0
      fi
      ;;
  esac
  if [ ! -r /dev/tty ]; then
    log_warn "当前不是交互终端，跳过网关配置。可稍后执行: hermes gateway setup"
    return 0
  fi
  log_info "启动 Hermes 网关配置向导"
  run_attached_to_tty "$HERMES_CMD" gateway setup
}

maybe_start_gateway_service() {
  case "$(env_decision "$HERMES_START_GATEWAY")" in
    no) return 0 ;;
    yes) ;;
    ask)
      if ! prompt_yes_no_tty "现在启动消息网关服务吗？[Y/n] " "Y"; then
        return 0
      fi
      ;;
  esac
  log_info "启动网关服务"
  "$HERMES_CMD" gateway start || log_warn "网关服务启动失败，请稍后手动执行: hermes gateway start"
}

start_dashboard_background() {
  mkdir -p "$HERMES_HOME/logs"
  if lsof -iTCP:9119 -sTCP:LISTEN >/dev/null 2>&1; then
    log_success "检测到 Web UI 已在运行: http://127.0.0.1:9119"
    return 0
  fi
  nohup "$HERMES_CMD" dashboard --no-open >"$HERMES_HOME/logs/dashboard.log" 2>&1 &
  sleep 2
  if lsof -iTCP:9119 -sTCP:LISTEN >/dev/null 2>&1; then
    log_success "Web UI 已启动: http://127.0.0.1:9119"
    return 0
  fi
  log_warn "Web UI 启动可能失败，请查看: $HERMES_HOME/logs/dashboard.log"
  return 1
}

maybe_open_webui() {
  case "$(env_decision "$HERMES_OPEN_WEBUI")" in
    no) return 0 ;;
    yes) ;;
    ask)
      if ! prompt_yes_no_tty "现在启动 Web UI 并打开浏览器吗？[Y/n] " "Y"; then
        return 0
      fi
      ;;
  esac
  if start_dashboard_background; then
    open http://127.0.0.1:9119 || log_warn "浏览器打开失败，请手动访问: http://127.0.0.1:9119"
  fi
}

print_next_steps() {
  echo
  log_success "安装完成"
  echo
  echo "下一步："
  echo "  source ~/.zprofile"
  echo "  source ~/.zshrc"
  echo "  hermes"
  echo
  echo "Web UI:"
  echo "  hermes dashboard --no-open"
  echo
  echo "Gateway:"
  echo "  hermes gateway start"
  echo
}

main() {
  print_banner
  require_macos
  require_basic_tools
  ensure_python
  ensure_optional_tools
  download_repo_archive
  setup_venv
  install_hermes
  install_browser_tools
  setup_command
  ensure_shell_path
  configure_dataeyes
  maybe_configure_gateway
  maybe_start_gateway_service
  maybe_open_webui
  print_next_steps
}

main "$@"
