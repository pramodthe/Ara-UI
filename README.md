# AraUI — macOS AI Assistant

AraUI is a native macOS AI assistant that can see your screen, hear your voice, and execute tasks on your Mac. It combines a SwiftUI chat interface with a locally-running AI agent backend powered by Google ADK, LiteLLM, and MCP tool servers.

---

## What It Does

- Chat with an AI agent via text or voice
- Agent reads text from your frontmost window as context (via macOS Accessibility API)
- Agent captures screenshots of your active window
- Agent executes real tasks on your Mac — run terminal commands, send messages, manage notes, browse Safari, and more
- Responses are spoken aloud through Qwen3 TTS Flash
- Generate images from screen clips using Qwen Image 2.0 Pro

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│              macOS Swift App (SwiftUI)           │
│                                                  │
│  FloatingIconPanel  ←→  AppVisibilityController  │
│         ↕                                        │
│  ContentView  →  ChatViewModel  →  BackendClient │
│                       ↕               ↕          │
│          AccessibilityCaptureService  HTTP POST   │
│          SpeechRecognitionService     localhost   │
│          SpeechSynthesisService       :8000       │
│          ScreenSnippingService                   │
│          ImageGenerationService → BackendClient  │
└──────────────────────────┬──────────────────────┘
                           │ HTTP (SSE)
                           ▼
┌─────────────────────────────────────────────────┐
│         Python Backend — Google ADK             │
│                                                  │
│  LlmAgent (araui_assistant)                      │
│    └─ LiteLlm → DashScope/Qwen Plus             │
│                                                  │
│  MCPToolset ──→ Terminal MCP Server (Node.js)    │
│  MCPToolset ──→ Apple MCP Server (Bun/TS)        │
│  MCPToolset ──→ Apple Notes MCP (Python)         │
└─────────────────────────────────────────────────┘
```

### Swift App

| Component | Role |
|---|---|
| `AppDelegate` | Registers global hotkeys (Carbon API), initialises backend session on launch |
| `ChatViewModel` | Central `@MainActor ObservableObject` — owns all app state, orchestrates every subsystem |
| `BackendClient` | HTTP client; creates ADK session on launch, POSTs messages to `/run_sse`, parses SSE response |
| `AccessibilityCaptureService` | Polls AX API every 2 s; captures frontmost window text (max 8 000 chars) and screenshots via ScreenCaptureKit |
| `SpeechRecognitionService` | Apple Speech framework — streams partial + final transcripts |
| `SpeechSynthesisService` | Plays Qwen3 TTS Flash audio returned by the backend |
| `ScreenSnippingService` | CGEvent tap for ⌥C — runs `screencapture -i` for interactive snip |
| `ImageGenerationService` | Sends screen clips to the local backend for Qwen Image 2.0 Pro generation/editing |
| `AppVisibilityController` | Manages collapsed ↔ expanded state; persists floating icon position |
| `FloatingIconPanel` | Borderless `NSPanel` at `.statusBar` level, visible across all Spaces |
| `ScreenGlowController` | Ambient glow effect while the agent is processing or listening |

### Python Backend

Built on **Google ADK** (`google-adk[extensions]`). A single `LlmAgent` named `araui_assistant` runs in the `multi_tool_agent` app.

**Model provider:**
```
LlmAgent → LiteLlm → DashScope OpenAI-compatible API → qwen-plus
```
DashScope is configured through LiteLLM with model string `openai/qwen-plus`. Override with `DASHSCOPE_CHAT_MODEL` if needed.

**Request pipeline:**
1. Swift app `POST /apps/multi_tool_agent/users/u/sessions/{id}` — creates session on launch
2. Swift app `POST /run_sse` — sends message with optional image and hidden context
3. ADK routes to `araui_assistant`, which calls MCP tools as needed
4. SSE response streamed back; Swift parses `data:` lines and returns the last non-empty text

---

## MCP Servers

| Server | Language | Path | Capability |
|---|---|---|---|
| **Terminal MCP** | TypeScript (Node.js) | `mcp_servers/terminal-mcp-server/` | Full macOS shell access — run any command |
| **Apple MCP** | TypeScript (Bun) | `mcp_servers/apple-mcp/` | Contacts, Messages, Reminders, Calendar, Safari automation |
| **Apple Notes MCP** | Python | `mcp_servers/mcp-apple-notes/` | Create, read, update, delete notes and folders |

All three connect to the ADK agent via **stdio** (`StdioConnectionParams`). The agent discovers and calls their tools automatically.

### Terminal MCP
Gives the agent unrestricted shell access. Used for file operations, running scripts, searching the filesystem, downloading files, and anything else expressible as a shell command.

### Apple MCP
AppleScript-backed integration with native macOS apps:
- **Contacts** — search by name (tries full name, first name, last name)
- **Messages** — send iMessages; requires phone number in `+1XXXXXXXXXX` format (agent looks up contact first)
- **Reminders** — create and list reminders
- **Calendar** — create and query events
- **Safari** — DuckDuckGo search, page navigation, click elements, read page content

### Apple Notes MCP
Python-based server that reads and writes Apple Notes via AppleScript. Supports folders, note creation/editing/deletion, and search.

---

## Global Hotkeys

| Shortcut | Action |
|---|---|
| `⌥X` | Toggle voice capture (speak → auto-send) |
| `⌘⇧C` | Capture selected text from frontmost app as context |
| `⌘⌥M` | Toggle AraUI window visibility |
| `⌥C` | Interactive screen snip (saved for image generation) |

---

## Setup

### 1. Python Backend

```bash
cd ted_gemini
pip install -r requirements.txt
cp ../.env.example ../.env   # fill in your keys
uvicorn server:app --host 127.0.0.1 --port 8000
```

**`.env` variables:**

| Variable | Required | Description |
|---|---|---|
| `DASHSCOPE_API_KEY` | Yes | DashScope API key for Qwen models |
| `DASHSCOPE_BASE_URL` | No | Defaults to `https://dashscope-intl.aliyuncs.com/compatible-mode/v1` |
| `DASHSCOPE_CHAT_MODEL` | No | Defaults to `qwen-plus` |
| `DASHSCOPE_IMAGE_MODEL` | No | Defaults to `qwen-image-2.0-pro` |
| `DASHSCOPE_TTS_MODEL` | No | Defaults to `qwen3-tts-flash` |
| `GOOGLE_OAUTH_CREDENTIALS` | No | Path to OAuth JSON (Google Calendar — currently disabled) |

### 2. MCP Servers

```bash
# Terminal MCP
cd mcp_servers/terminal-mcp-server
npm install && npm run build

# Apple MCP
cd mcp_servers/apple-mcp
bun install && bun run build

# Apple Notes MCP
cd mcp_servers/mcp-apple-notes
python -m venv .venv && source .venv/bin/activate && pip install -e .
```

### 3. Swift App

Open `araui.xcodeproj` in Xcode and run. On first launch, macOS will prompt for:
- **Accessibility** — required for reading text from other apps
- **Microphone** — required for voice input
- **Speech Recognition** — required for voice transcription
- **Screen Recording** — required for window screenshots

### 4. AI Providers

Chat, image generation, and voice output are handled by the local backend using DashScope/Qwen. Keep `DASHSCOPE_API_KEY` in `.env`; the Swift app does not store the DashScope key in macOS Keychain. Voice input remains Apple Speech Recognition.

---

## Tech Stack

| Layer | Technology |
|---|---|
| macOS frontend | Swift, SwiftUI, AppKit |
| AI agent framework | Google ADK (`google-adk[extensions]`) |
| LLM provider | LiteLLM + DashScope/Qwen Plus |
| Tool protocol | Model Context Protocol (MCP) |
| Terminal tools | Node.js / TypeScript |
| Apple app tools | Bun / TypeScript + AppleScript |
| Notes tools | Python + AppleScript |
| Screen capture | ScreenCaptureKit (macOS 12.3+) |
| Accessibility | macOS Accessibility API (AXUIElement) |
| Voice input | Apple Speech framework |
| Voice output | Qwen3 TTS Flash + AVAudioPlayer |
| Image generation | Qwen Image 2.0 Pro |
| Secret storage | `.env` loaded by the backend |
