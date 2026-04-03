# LlamaBarn

LlamaBarn is a macOS menu bar app for running local LLMs.

[Watch a 2-minute intro](https://www.youtube.com/watch?v=7AieF7rZUTc) 📽️

<br>

![LlamaBarn](https://github.com/user-attachments/assets/b447a485-9bbe-4290-ba42-5481aafa4af5)

<br>

## Install

Install with `brew install --cask llamabarn` or download from [Releases](https://github.com/ggml-org/LlamaBarn/releases).

### Requirements

- macOS 15.0+ (Sequoia or later)
- `llama-server` installed via Homebrew: `brew install llama.cpp`

## How it works

LlamaBarn runs a local server at `http://localhost:2276/v1` using `llama-server` from your Homebrew installation.

- **Install models** — from the built-in catalog or any GGUF in your HF cache
- **Connect any app** — chat UIs, editors, CLI tools, scripts
- **Models load when requested** — and unload when idle

## Features

- **100% local** — Models run on your device; no data leaves your Mac
- **Small footprint** — `12 MB` native macOS app
- **Zero configuration** — models are auto-configured with optimal settings for your Mac
- **Dynamic model discovery** — automatically detects all GGUF models in `~/.cache/huggingface/hub/`, not just catalog entries
- **Smart model catalog** — shows what fits your Mac, with quantized fallbacks for what doesn't
- **Self-contained** — all models and config stored in `~/.llamabarn` (configurable)
- **Built on llama.cpp** — from the GGML org, developed alongside llama.cpp

## Works with

LlamaBarn works with any OpenAI-compatible client.

- **Chat UIs** — Chatbox, Open WebUI, BoltAI ([instructions](https://github.com/ggml-org/LlamaBarn/discussions/40))
- **Editors** — VS Code, Zed, Xcode ([instructions](https://github.com/ggml-org/LlamaBarn/discussions/43))
- **Editor extensions** — Cline, Continue
- **CLI tools** — OpenCode ([instructions](https://github.com/ggml-org/LlamaBarn/discussions/44)), Claude Code ([instructions](https://github.com/ggml-org/LlamaBarn/discussions/45))
- **Custom scripts** — curl, AI SDK, etc.

You can also use the built-in WebUI at http://localhost:2276 while LlamaBarn is running.

## API examples

```sh
# list installed models
curl http://localhost:2276/v1/models
```

```sh
# chat with Gemma 3 4B (assuming it's installed)
curl http://localhost:2276/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model": "gemma-3-4b", "messages": [{"role": "user", "content": "Hello"}]}'
```

Replace `gemma-3-4b` with any model ID from `http://localhost:2276/v1/models`.

See complete API reference in `llama-server` [docs](https://github.com/ggml-org/llama.cpp/tree/master/tools/server#api-endpoints).

## Experimental settings

**Expose to network** — By default, the server is only accessible from your Mac (`localhost`). This option allows connections from other devices on your local network. Only enable this if you understand the security risks.

```sh
# bind to all interfaces (0.0.0.0)
defaults write app.llamabarn.LlamaBarn exposeToNetwork -bool YES

# or bind to a specific IP (e.g., for Tailscale)
defaults write app.llamabarn.LlamaBarn exposeToNetwork -string "100.x.x.x"

# disable (default)
defaults delete app.llamabarn.LlamaBarn exposeToNetwork
```

## Development

### Prerequisites

- macOS 15.0+ (Sonoma or later)
- Xcode 16.0+
- `llama-server` via Homebrew: `brew install llama.cpp`

### Building

```sh
git clone https://github.com/ggml-org/LlamaBarn.git
cd LlamaBarn
```

#### From Xcode

```sh
open LlamaBarn.xcodeproj
```

Select the `LlamaBarn` scheme and build with `Cmd+B`.

#### From command line

```sh
xcodebuild -project LlamaBarn.xcodeproj \
  -scheme LlamaBarn \
  -configuration Debug \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build
```

#### Install script

```sh
./install.command
```

This resolves dependencies, builds Release, and installs to `~/Applications/`.

### Running locally

- Configuration and models are stored in `~/.llamabarn/`
- The server starts automatically on `http://localhost:2276`
- Access the built-in WebUI at `http://localhost:2276`

## Roadmap

- [ ] Support for loading multiple models at the same time
- [ ] Support for multiple configurations per model (e.g., multiple context lengths)
