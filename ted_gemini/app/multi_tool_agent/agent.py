from google.adk.agents import LlmAgent
from google.adk.models.lite_llm import LiteLlm
from google.adk.tools.mcp_tool.mcp_toolset import MCPToolset
from google.adk.tools.mcp_tool.mcp_session_manager import StdioConnectionParams
from mcp import StdioServerParameters
from google.genai import types
import logging
import os
import warnings
from pathlib import Path

# Suppress only the specific authentication warnings from Google ADK
class AuthWarningFilter(logging.Filter):
    def filter(self, record):
        return 'auth_config or auth_config.auth_scheme is missing' not in record.getMessage()

# Apply filter to all google.adk loggers that might show this warning
for logger_name in ['base_authenticated_tool', 'google_adk.tools.base_authenticated_tool']:
    auth_logger = logging.getLogger(logger_name)
    auth_logger.addFilter(AuthWarningFilter())

REPO_ROOT = Path(__file__).resolve().parents[3]

# Terminal MCP Server path
TERMINAL_MCP_PATH = os.getenv(
    "TERMINAL_MCP_PATH",
    str(REPO_ROOT / "mcp_servers/terminal-mcp-server/build/index.js"),
)

# Google Calendar OAuth credentials path
GOOGLE_OAUTH_CREDENTIALS = os.getenv("GOOGLE_OAUTH_CREDENTIALS")

TOKENROUTER_BASE_URL = os.getenv("TOKENROUTER_BASE_URL", "https://api.tokenrouter.io/v1")
TOKENROUTER_MODEL = os.getenv("TOKENROUTER_MODEL", "auto:balance")
TOKENROUTER_API_KEY = os.getenv("TOKENROUTER_API_KEY")
LITELLM_MODEL = TOKENROUTER_MODEL if "/" in TOKENROUTER_MODEL else f"openai/{TOKENROUTER_MODEL}"

llm_model = LiteLlm(
    model=LITELLM_MODEL,
    api_base=TOKENROUTER_BASE_URL,
    api_key=TOKENROUTER_API_KEY,
    drop_params=True,
)

root_agent = LlmAgent(
    model=llm_model,
    name='araui_assistant',
    instruction=(
        "You are AraUI - a macOS personal assistant who can execute tasks on the user's computer using available tools. "
        "You have access to:\n"
        "- Terminal commands (full macOS command-line access)\n"
        "- Google Calendar (manage events and schedules)\n"
        "- Apple Notes (create, read, update, delete, organize notes and folders)\n"
        "- Apple apps (Contacts, Messages, Reminders, Calendar)\n"
        "- Safari browser automation (with careful, step-by-step verification)\n"
        "- Image analysis capabilities\n\n"
        "Guidelines:\n"
        "- Be concise and direct. Keep responses brief unless the user asks for detailed explanations.\n"
        "- Execute tasks efficiently without unnecessary commentary.\n"
        "- Only analyze images if explicitly requested (e.g., 'what's in this image?', 'describe this picture').\n"
        "- Focus on the user's text prompt; don't assume image context unless asked.\n"
        "- Use macOS-specific commands and understand the macOS file system structure.\n\n"
        "- When user asks to open the pdf, make sure you do download - make sure you download the pdf first before opening it. Do not say it's open in safari."
        "CRITICAL - Contacts & Messages Best Practices:\n"
        "2. When searching contacts: Try different variations (first name only, last name only, full name)\n"
        "3. If contact not found with full name, try just first name or last name separately\n"
        "4. For messages: ALWAYS look up the contact first to get their phone number (EXCEPT hardcoded contacts)\n"
        "5. Messages require phone numbers in format +1234567890 (with country code)\n"
        "6. Workflow for sending messages: Search contact → Get phone number → Send message\n"
        "7. If contact search fails, ask user for the phone number directly\n"
        "8. When user says 'send message to [name]', first search contacts for that name (UNLESS it's a hardcoded contact)\n"
        "9. Report contact details (name and number) before sending messages for confirmation\n\n"
        "CRITICAL - Terminal & File Operations Best Practices:\n"
        "1. When searching for files: Use 'find' command with proper paths (e.g., 'find ~/Downloads -name \"*pattern*\" -type f')\n"
        "2. Search file contents: Use 'grep -r \"search_term\" /path/' or 'ag' (silver searcher) if available\n"
        "3. For fuzzy search: Try multiple variations of filenames with wildcards (*pattern*, *partial*)\n"
        "4. Check common locations: ~/Downloads, ~/Documents, ~/Desktop, current directory\n"
        "5. List directory contents with 'ls -la' to see hidden files\n"
        "6. When opening files: Use 'open' command (e.g., 'open file.pdf' or 'open -a Preview file.pdf')\n"
        "7. Before acting, verify the file exists with 'ls -l path/to/file' or 'test -f path/to/file && echo found'\n"
        "8. Be thorough: if first search fails, try broader patterns or different search methods\n"
        "9. Report search results to user before taking action on files\n\n"
        
        "CRITICAL - Safari Browser Workflow:\n"
        "1. DuckDuckGo Search workflow:\n"
        "   e) CRITICAL: On arxiv.org, you MUST click the 'View PDF' link/button before attempting downloads. Verify the PDF opens in Safari.\n"
        "   a) search_duckduckgo with query\n"
        "   b) read_page to see results\n"
        "   c) click_element with text='first' to click first result (preferred default)\n"
        "   d) read_page to see the opened page content\n"
        "2. ALWAYS read_page after ANY navigation to verify page content\n"
        "3. Work step-by-step: Navigate → Read → Verify → Act → Read again\n"
        "4. To click first DuckDuckGo result: use click_element with text='first'\n"
        "5. Report what you see on each page so the user can verify your actions"
    ),
    tools=[
        # Terminal MCP Server
        MCPToolset(
            connection_params=StdioConnectionParams(
                server_params=StdioServerParameters(
                    command='node',
                    args=[TERMINAL_MCP_PATH],
                ),
                timeout=60.0,  # Increase timeout to 60 seconds
            ),
        ),
        # # Google Calendar MCP Server - DISABLED
        # MCPToolset(
        #     connection_params=StdioConnectionParams(
        #         server_params=StdioServerParameters(
        #             command='npx',
        #             args=[
        #                 '-y',  # Auto-confirm npx install
        #                 '@cocal/google-calendar-mcp'
        #             ],
        #             env={
        #                 'GOOGLE_OAUTH_CREDENTIALS': GOOGLE_OAUTH_CREDENTIALS
        #             },
        #         ),
        #         timeout=60.0,  # Increase timeout to 60 seconds
        #     ),
        # ),
        # Apple Notes MCP Server - Local version with reduced feature set
        MCPToolset(
            connection_params=StdioConnectionParams(
                server_params=StdioServerParameters(
                    command='uv',
                    args=[
                        'run',
                        '--directory',
                        str(REPO_ROOT / 'mcp_servers/mcp-apple-notes'),
                        'mcp-apple-notes'
                    ],
                ),
                timeout=60.0,  # Increase timeout to 60 seconds
            ),
        ),
        # Apple MCP Server (Contacts, Messages, Reminders, Calendar, Safari) - Local version with safety improvements
        MCPToolset(
            connection_params=StdioConnectionParams(
                server_params=StdioServerParameters(
                    command='node',
                    args=[str(REPO_ROOT / 'mcp_servers/apple-mcp/dist/index.js')],
                ),
                timeout=60.0,  # Increase timeout to 60 seconds
            ),
        )
    ],
)

def ask_with_image(prompt: str, image_path: str):
    """Send a question to the agent with an image as context."""
    with open(image_path, 'rb') as f:
        image_bytes = f.read()
    
    # Determine MIME type from file extension
    mime_type = 'image/jpeg'
    if image_path.lower().endswith('.png'):
        mime_type = 'image/png'
    elif image_path.lower().endswith('.gif'):
        mime_type = 'image/gif'
    elif image_path.lower().endswith('.webp'):
        mime_type = 'image/webp'
    
    return root_agent.send_message(
        content=[
            types.Part.from_bytes(data=image_bytes, mime_type=mime_type),
            prompt
        ]
    )
