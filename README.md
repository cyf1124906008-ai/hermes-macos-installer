# Hermes macOS 安装器

面向 macOS 的 Hermes 一键安装器，目标是：

- 自动识别当前环境
- 已安装的依赖和配置自动跳过
- 缺失项才下载安装
- 默认把模型提供商配置为 DataEyes 自定义 OpenAI 兼容接口
- 根据 API Key 自动请求 `https://cloud.dataeyes.ai/v1/models` 获取模型列表给用户选择
- 尽量优先使用国内更稳的下载源和镜像

## 一行安装

最稳定的方式是显式传入 `DATAEYES_API_KEY`：

```bash
DATAEYES_API_KEY='你的key' /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/cyf1124906008-ai/hermes-macos-installer/main/install.sh)"
```

如果你已经在当前机器配置过 DataEyes，也可以直接运行：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/cyf1124906008-ai/hermes-macos-installer/main/install.sh)"
```

## 支持的安装行为

- 检测 macOS 和 CPU 架构
- 检测 `python3 >= 3.11`
- 检测并复用已有 `~/.hermes`
- 通过 GitHub 镜像或 codeload 下载 Hermes 源码
- 使用 `venv + pip` 安装 Hermes
- 自动创建 `~/.local/bin/hermes`
- 自动把 `~/.local/bin` 加到 `zprofile` / `zshrc`
- 自动配置：
  - `provider: custom`
  - `base_url: https://cloud.dataeyes.ai/v1`
  - `api_key: <你的 key>`
  - `default: <从 /models 获取后选择的模型>`

## 可选环境变量

适合静默安装或 CI，也是最推荐的调用方式：

```bash
DATAEYES_API_KEY=sk-xxx \
DATAEYES_MODEL=claude-opus-4-6 \
bash install.sh
```

可选变量：

- `DATAEYES_API_KEY`
- `DATAEYES_MODEL`
- `DATAEYES_BASE_URL`
- `HERMES_INSTALL_DIR`
- `HERMES_HOME`
- `HERMES_REPO_REF`
- `HERMES_REPO_SLUG`
- `PIP_INDEX_URL`
- `HERMES_INSTALL_EXTRAS`
- `HERMES_WITH_BROWSER_TOOLS=1`

## 默认安装策略

默认优先保证这些能力可用：

- CLI
- gateway
- dashboard 运行时
- DataEyes 模型配置

默认不会主动安装浏览器自动化依赖和 WhatsApp 相关 Node 依赖，避免国内网络下载慢和失败率高。需要时可以设置：

```bash
HERMES_WITH_BROWSER_TOOLS=1 bash install.sh
```

## 本地打包为 `.pkg`

仓库里附带一个本地构建脚本：

```bash
./scripts/build-pkg.sh
```

它会生成一个未签名的 `.pkg`，用于企业内部分发或本机测试。  
注意：这不是 Apple notarized 包，公网分发前仍建议你自行签名和公证。
