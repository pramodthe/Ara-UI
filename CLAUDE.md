# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

AraUI is a two-component macOS AI assistant:
1. **Swift macOS app** (`araui/`) — SwiftUI + AppKit frontend with a floating icon, chat window, voice input/output, and screen capture
2. **Python ADK backend** (`ted_gemini/`) — Google ADK agent running locally at `http://localhost:8000` that executes tasks via MCP tool servers

The Swift app communicates exclusively with the local Python backend for chat, image generation/editing, and voice output. Voice input stays local through Apple Speech Recognition.

## Running the Backend

```bash
cd ted_gemini
pip install -r requirements.txt    # google-adk[extensions], certifi
uvicorn server:app --host 127.0.0.1 --port 8000
```

Environment variables required in `.env` (at repo root):
- `DASHSCOPE_API_KEY` — DashScope key for Qwen models
- `DASHSCOPE_BASE_URL` — defaults to `https://dashscope-intl.aliyuncs.com/compatible-mode/v1`
- `DASHSCOPE_CHAT_MODEL` — defaults to `qwen-plus`
- `DASHSCOPE_IMAGE_MODEL` — defaults to `qwen-image-2.0-pro`
- `DASHSCOPE_TTS_MODEL` — defaults to `qwen3-tts-flash`
- `GOOGLE_OAUTH_CREDENTIALS` — path to OAuth JSON (for Google Calendar, currently disabled)

## Running the Swift App

Open `araui.xcodeproj` in Xcode and run. The app requires the Python backend to be running first.

Required macOS permissions (prompted on first use):
- Accessibility — AX API text capture from frontmost app
- Microphone — voice input
- Speech Recognition — Apple Speech framework
- Screen Recording — ScreenCaptureKit screenshots

## MCP Servers

The backend agent connects to three MCP servers at startup:

| Server | Path | Build |
|---|---|---|
| Terminal | `mcp_servers/terminal-mcp-server/build/index.js` | `cd mcp_servers/terminal-mcp-server && npm install && npm run build` |
| Apple MCP (Contacts, Messages, Calendar, Safari) | `mcp_servers/apple-mcp/dist/index.js` | `cd mcp_servers/apple-mcp && bun install && bun run build` |
| Apple Notes | `mcp_servers/mcp-apple-notes/` | Python venv at `.venv/` — `pip install -e .` |

Paths can be overridden via env vars: `TERMINAL_MCP_PATH`, `APPLE_NOTES_MCP_PYTHON`.

## Architecture

### Swift App

**Single shared `ChatViewModel`** — Created once in `AppDelegate`, injected as `@EnvironmentObject` through the entire view hierarchy. All state lives here.

**Request flow:**
1. User types/speaks → `ChatViewModel.send()` calls `BackendClient.sendMessage()`
2. `BackendClient` POSTs to `http://localhost:8000/run_sse` with session ID, message parts (text + optional image + optional hidden context)
3. Response is SSE-formatted; `BackendClient` parses `data:` lines and returns the last non-empty text fragment
4. `ChatViewModel` writes the reply into `messages[]` and passes it to `SpeechSynthesisService`

**Session management** — `BackendClient` creates a new UUID session on each app launch via `POST /apps/multi_tool_agent/users/u/sessions/{id}`. Session is recreated if the task is cancelled.

**Context capture** — `AccessibilityCaptureService` polls the frontmost app's AX tree every 2 seconds, hashing content to avoid redundant callbacks. Max 8000 chars captured. When auto-capture is off, context is captured on-demand (⌘⇧C / hotkey).

**Screenshot capture** — Uses `ScreenCaptureKit` (macOS 12.3+) to capture the focused window of the frontmost app. Stored in `~/Library/Application Support/AraUI/Screenshots/`. Attached as `image/jpeg` in the next message to the backend.

**Windowing system** — Two windows exist at runtime:
- Main chat window (standard SwiftUI `WindowGroup`)
- Floating icon (`FloatingIconPanel` — borderless `NSPanel` at `.statusBar` level, persists across all Spaces)

`AppVisibilityController.shared` controls collapsed/expanded state and persists icon position in `UserDefaults`.

**Global hotkeys:**
- `⌥X` — toggle voice capture mode (registered via Carbon `RegisterEventHotKey`)
- `⌘⇧C` — capture selected text as context
- `⌘⌥M` — toggle window visibility
- `⌥C` — screen snip (via `CGEvent.tapCreate`)

**Image generation** — Separate from chat in the Swift UI, but it uses the same local backend. `ImageGenerationService` sends the screen clip and prompt to `POST /araui/image-generation`, which calls DashScope `qwen-image-2.0-pro`. Input image comes from `~/Documents/AraUI/clip.png` saved by `ScreenSnippingService`.

**Voice output** — `SpeechSynthesisService` sends assistant replies to `POST /araui/tts`, receives Qwen3 TTS Flash audio, and plays it with `AVAudioPlayer`. Apple Speech Recognition still handles microphone transcription.

### Python Backend

`ted_gemini/app/multi_tool_agent/agent.py` defines a single `root_agent` (`LlmAgent`) using:
- **Model**: `LiteLlm(model="openai/qwen-plus")` against the DashScope OpenAI-compatible endpoint
- **Tools**: Three `MCPToolset` instances connected via stdio to the MCP servers above

The agent name is `araui_assistant`; app name for ADK routing is `multi_tool_agent`.

### File Naming Note

`araui/Networking/GeminiClient.swift` is actually `BackendClient` — the file was renamed to connect to the local ADK backend but the filename wasn't updated.
