#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

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
    path.write_text(
        yaml.safe_dump(data, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )


def fetch_models(base_url: str, api_key: str, timeout: int = 20) -> list[str]:
    req = urllib.request.Request(
        f"{base_url.rstrip('/')}/models",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="GET",
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        payload = json.loads(response.read().decode("utf-8"))

    models: list[str] = []
    if isinstance(payload, dict):
        items = payload.get("data")
        if isinstance(items, list):
            for item in items:
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

    current_model = (
        config.get("model", {}).get("default")
        if isinstance(config.get("model"), dict)
        else None
    )
    current_key = (
        config.get("model", {}).get("api_key")
        if isinstance(config.get("model"), dict)
        else None
    )
    current_base_url = (
        config.get("model", {}).get("base_url")
        if isinstance(config.get("model"), dict)
        else None
    )
    effective_api_key = args.api_key or current_key

    if not effective_api_key:
        print("未提供 DataEyes API Key，跳过模型配置。")
        return 0

    models: list[str]
    try:
        models = fetch_models(args.base_url, effective_api_key)
        print(f"已验证 endpoint: {args.base_url}/models")
    except urllib.error.HTTPError as exc:
        print(f"警告: /models 请求失败，HTTP {exc.code}，使用内置候选模型列表。")
        models = FALLBACK_MODELS[:]
    except Exception as exc:  # noqa: BLE001
        print(f"警告: /models 请求失败 ({exc})，使用内置候选模型列表。")
        models = FALLBACK_MODELS[:]

    if not models:
        models = FALLBACK_MODELS[:]

    if (
        current_model
        and current_key == effective_api_key
        and current_base_url == args.base_url
        and current_model in models
    ):
        chosen_model = current_model
        print(f"检测到已有 DataEyes 配置，保留模型: {chosen_model}")
    else:
        chosen_model = choose_model(models, args.default_model)

    model_cfg = config.setdefault("model", {})
    model_cfg["provider"] = "custom"
    model_cfg["base_url"] = args.base_url
    model_cfg["api_key"] = effective_api_key
    model_cfg["default"] = chosen_model

    save_yaml(config_path, config)
    print(f"已写入配置: {config_path}")
    print(f"provider=custom")
    print(f"base_url={args.base_url}")
    print(f"model={chosen_model}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
