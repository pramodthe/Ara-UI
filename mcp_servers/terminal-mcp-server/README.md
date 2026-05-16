# Terminal MCP Server

[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](https://choosealicense.com/licenses/mit/)
[![npm version](https://badge.fury.io/js/terminal-mcp-server.svg)](https://badge.fury.io/js/terminal-mcp-server)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.3+-blue.svg)](https://www.typescriptlang.org/)

Terminal MCP Server is a robust Model Context Protocol (MCP) server designed for executing commands on local and remote hosts via SSH. It provides a simple yet powerful interface for AI models and other applications to execute system commands with enhanced session management, error handling, and reliability features.

> **Note**: This is a maintained fork of the original project with significant robustness improvements and new features.

## Table of Contents

- [Features](#features)
- [Available Resources](#available-resources)
- [Installation](#installation)
  - [Installing via Smithery](#installing-via-smithery)
  - [Manual Installation](#manual-installation)
- [Usage](#usage)
  - [Starting the Server](#starting-the-server)
  - [Server Configuration](#server-configuration)
  - [Testing with MCP Inspector](#testing-with-mcp-inspector)
  - [Available NPM Scripts](#available-npm-scripts)
- [The execute_command Tool](#the-execute_command-tool)
  - [Parameters](#parameters)
  - [Examples](#examples)
- [Configuring with AI Assistants](#configuring-with-ai-assistants)
  - [Configuring with Roo Code](#configuring-with-roo-code)
  - [Configuring with Cline](#configuring-with-cline)
  - [Configuring with Claude Desktop](#configuring-with-claude-desktop)
- [Best Practices](#best-practices)
  - [Command Execution](#command-execution)
  - [SSH Connection](#ssh-connection)
  - [Session Management](#session-management)
  - [Error Handling](#error-handling)
  - [Working Directory Management](#working-directory-management)
  - [Timeout Management](#timeout-management)
- [Output Format](#output-format)
- [Troubleshooting](#troubleshooting)
- [Important Notes](#important-notes)
- [Robustness Features](#robustness-features)

## Features

- **Local Command Execution**: Execute commands directly on the local machine
- **Remote Command Execution**: Execute commands on remote hosts via SSH with automatic retry and connection health checks
- **Session Persistence**: Support for persistent sessions that reuse the same terminal environment for a specified time (default 20 minutes)
- **Working Directory Management**: Set and persist working directories across commands in sessions
- **Environment Variables**: Set custom environment variables for commands with persistence across session
- **Configurable Timeouts**: Set custom command timeouts (1-600 seconds) with proper timeout handling
- **Enhanced Error Handling**: Detailed error messages with automatic retry mechanisms for SSH connections
- **Robust Session Management**: Automatic connection pooling, reconnection, and graceful cleanup
- **Exit Code Reporting**: Commands return proper exit codes for better error detection
- **Stdio Connection**: Connect via standard input/output for direct integration
- **Security Features**: Command validation, dangerous pattern detection, output size limits, session limits, rate limiting
- **File Transfers**: Upload and download files via SFTP, local file copy operations
- **RTK Integration**: Intelligent command rewriting and output summarization to optimize token usage for AI contexts

## RTK Integration

Terminal MCP Server integrates with [rtk](https://local-runtime) to significantly reduce token consumption and improve context efficiency.

### Command Rewriting
The server automatically attempts to rewrite common commands into their `rtk` optimized equivalents (e.g., `ls` -> `rtk ls`).
- **Local**: Rewriting is performed if `rtk` is found in your `PATH` or specified via `RTK_BIN`.
- **Remote**: If `rtk` is installed on the remote host, commands are wrapped in a shell-level rewriter (`RTK_CMD=$(rtk rewrite "cmd" || echo "cmd"); eval "$RTK_CMD"`) to optimize remote output without extra roundtrips.

### Output Summarization
For extremely large outputs (exceeding 10,000 characters), the server automatically utilizes `rtk smart` or `rtk log` to provide a concise technical summary instead of the raw data.
- The response object includes an `rtkSummarized` boolean flag when this happens.
- Original output length is preserved in the summary header.

### Configuration
| Variable | Default | Description |
|----------|---------|-------------|
| `RTK_BIN` | (rtk in PATH) | Path to the `rtk` binary if not in system PATH |
| `RTK_MCP_REWRITE` | true | Set to `false` to disable all `rtk` optimizations |

## Available Resources

Terminal MCP Server provides **8 key resources** that enhance reliability and performance by providing system visibility, session management, and terminal multiplexing capabilities:

### `terminal://sessions/status`
Returns comprehensive information about active terminal sessions, including connection health, working directories, environment variables, and session timeouts.

**Resource Details:**
- **Purpose**: Monitor active sessions and their health status
- **Benefits**: Enables better session management, troubleshooting, and resource cleanup
- **Performance Impact**: Minimal - cached session data with lightweight health checks
- **Reliability**: Helps prevent session conflicts and enables proactive session management

**Response Format:**
```json
{
  "summary": {
    "totalSessions": 3,
    "activeSessions": 2,
    "healthySessions": 2,
    "localSessions": 1,
    "remoteSessions": 1
  },
  "sessions": {
    "local": [
      {
        "sessionKey": "local-default",
        "host": "local",
        "isActive": true,
        "isHealthy": true,
        "workingDirectory": "/home/user/projects",
        "environmentVariables": ["PATH", "HOME", "SHELL"],
        "lastActivity": "2025-11-02T17:09:14.866Z",
        "timeUntilExpiry": 1200000,
        "shellReady": true,
        "retryCount": 0,
        "maxRetries": 3
      }
    ],
    "remote": [
      {
        "sessionKey": "remote-server-default",
        "host": "remote-server",
        "username": "user",
        "isActive": true,
        "isHealthy": true,
        "workingDirectory": "/var/www",
        "environmentVariables": ["NODE_ENV", "PORT"],
        "lastActivity": "2025-11-02T17:08:45.123Z",
        "timeUntilExpiry": 1180000,
        "shellReady": true,
        "retryCount": 1,
        "maxRetries": 3
      }
    ]
  },
  "configuration": {
    "sessionTimeoutMinutes": 20,
    "maxRetries": 3,
    "connectionTimeoutMs": 30000
  },
  "timestamp": "2025-11-02T17:09:14.866Z"
}
```

### `terminal://config`
Returns current server configuration including security settings, limits, and timeouts.

**Resource Details:**
- **Purpose**: View active security and resource limit configuration
- **Benefits**: Verify configuration settings, troubleshoot limit issues
- **Performance Impact**: Minimal - returns cached configuration

**Response Format:**
```json
{
  "sessionTimeout": 1200000,
  "maxRetries": 3,
  "connectionTimeout": 30000,
  "maxConcurrentSessions": 10,
  "maxOutputSize": 5242880,
  "enableCommandValidation": true,
  "commandBlacklist": [],
  "allowedWorkingDirectories": null,
  "description": {
    "sessionTimeout": "Session inactivity timeout in milliseconds (env: SESSION_TIMEOUT_MS)",
    "maxConcurrentSessions": "Maximum number of concurrent sessions allowed (env: MAX_CONCURRENT_SESSIONS)",
    ...
  },
  "timestamp": "2025-11-02T17:09:14.866Z"
}
```

### `terminal://system/info`
Provides basic system information to help with command execution planning and troubleshooting.

**Resource Details:**
- **Purpose**: System environment information for better command execution
- **Benefits**: Helps determine appropriate commands and paths for the current system
- **Performance Impact**: Very low - static system information
- **Reliability**: Provides context for command execution and error diagnosis

**Response Format:**
```json
{
  "platform": "linux",
  "arch": "x64",
  "nodeVersion": "v18.17.0",
  "uptime": 3600.5,
  "memory": {
    "rss": 52428800,
    "heapTotal": 20971520,
    "heapUsed": 10485760,
    "external": 2048000
  },
  "cwd": "/home/user/projects/terminal-mcp-server",
  "env": {
    "SHELL": "/bin/bash",
    "USER": "user",
    "HOME": "/home/user"
  },
  "timestamp": "2025-11-02T17:09:14.866Z"
}
```

### `terminal://tmux/info`
Returns information about tmux availability, version, and server statistics including active sessions, windows, and panes.

**Resource Details:**
- **Purpose**: Check tmux installation and server status
- **Benefits**: Enables tmux-aware terminal management and multiplexing capabilities
- **Performance Impact**: Minimal - quick version and server status checks
- **Reliability**: Helps determine tmux availability before using tmux features

**Response Format:**
```json
{
  "available": true,
  "version": "3.5a",
  "serverInfo": {
    "version": "next-3.5",
    "sessions": 2,
    "windows": 4,
    "panes": 8
  },
  "timestamp": "2025-11-02T17:09:14.866Z"
}
```

### `terminal://tmux/sessions`
Lists all active tmux sessions with window counts, creation dates, and attachment status.

**Resource Details:**
- **Purpose**: Monitor and manage tmux sessions
- **Benefits**: Provides overview of all tmux sessions and their status
- **Performance Impact**: Low - uses tmux list-sessions command
- **Reliability**: Shows real-time session information with creation timestamps

**Response Format:**
```json
{
  "sessions": [
    {
      "name": "development",
      "windows": 3,
      "created": "Sun Nov  3 10:30:45 2025",
      "flags": "",
      "attached": true
    }
  ],
  "count": 1,
  "timestamp": "2025-11-02T17:09:14.866Z"
}
```

### `terminal://tmux/windows/{session}`
Lists all windows within a specific tmux session with activity indicators and layout information.

**Resource Details:**
- **Purpose**: Monitor windows within a specific tmux session
- **Benefits**: Enables window management and navigation within sessions
- **Performance Impact**: Low - uses tmux list-windows command
- **Reliability**: Shows window activity status and layout flags

**Response Format:**
```json
{
  "session": "development",
  "windows": [
    {
      "index": 0,
      "name": "editor",
      "flags": "*",
      "active": true,
      "last": false,
      "zoomed": false
    }
  ],
  "count": 1,
  "timestamp": "2025-11-02T17:09:14.866Z"
}
```

### `terminal://tmux/panes/{session}`
Lists all panes within a tmux session or specific window with size, history, and activity status.

**Resource Details:**
- **Purpose**: Monitor pane layout and status within sessions
- **Benefits**: Enables pane management and multi-tasking visibility
- **Performance Impact**: Low - uses tmux list-panes command
- **Reliability**: Shows pane dimensions, scrollback history, and activity

**Response Format:**
```json
{
  "session": "development",
  "panes": [
    {
      "index": 0,
      "size": "120x30",
      "history": 2000,
      "flags": "(active)",
      "active": true
    }
  ],
  "count": 1,
  "timestamp": "2025-11-02T17:09:14.866Z"
}
```

### `terminal://tmux/panes/{session}/{window}`
Lists panes within a specific tmux window with detailed pane information.

**Resource Details:**
- **Purpose**: Monitor panes within a specific window
- **Benefits**: Enables focused pane management within windows
- **Performance Impact**: Low - uses tmux list-panes with target specification
- **Reliability**: Provides window-specific pane information

**Response Format:**
```json
{
  "session": "development",
  "window": 0,
  "panes": [
    {
      "index": 0,
      "size": "120x30",
      "history": 2000,
      "flags": "(active)",
      "active": true
    }
  ],
  "count": 1,
  "timestamp": "2025-11-02T17:09:14.866Z"
}
```

## Installation

### Manual Installation
```bash
# Clone the repository
git clone local-runtime.git
cd terminal-mcp-server

# Install dependencies
npm install

# Build the project
npm run build
```

## Usage

### Starting the Server

#### Standard Mode
```bash
# Start the server using stdio (default mode)
npm start

# Or run the built file directly
node build/index.js
```

#### Clean Environment Mode (Recommended)
If you experience shell configuration errors like:
```
--: eval: line 8551: syntax error near unexpected token `('
--: eval: line 8551: `back () '
--: line 1: dump_bash_state: command not found
```

Use the clean environment runner to bypass problematic shell configurations:

```bash
# Use the clean runner script
./run-clean.sh

# Or use npm script
npm run start:clean

# Or manually with clean bash
bash --noprofile --norc -c "node build/index.js"
```

The clean environment mode uses `bash --noprofile --norc` to avoid loading `.bashrc`, `.bash_profile`, and other shell configuration files that might contain malformed functions or aliases.

### Server Configuration

The server runs in stdio mode by default, which is perfect for direct integration with MCP clients. You can enable debug logging by setting the `DEBUG` environment variable:

```bash
# Run with debug logging
DEBUG=true node build/index.js

# Or set it as an environment variable
export DEBUG=true
node build/index.js
```

### Testing with MCP Inspector

```bash
# Start the MCP Inspector tool
npm run inspector
```

### Available NPM Scripts

```bash
# Build the project
npm run build

# Start the server (standard mode)
npm start

# Start the server in clean environment (recommended)
npm run start:clean

# Start with file watching for development
npm run watch

# Run the MCP Inspector for testing
npm run inspector

# Run tests
npm test
```

## Available Tools

### execute_command

The execute_command tool is the core functionality provided by Terminal MCP Server, used to execute commands on local or remote hosts with enhanced robustness and reliability.

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| command | string | Yes | The command to execute |
| host | string | No | The remote host to connect to. If not provided, the command will be executed locally |
| username | string | Required when host is specified | The username for SSH connection |
| session | string | No | Session name, defaults to "default". The same session name will reuse the same terminal environment for 20 minutes |
| env | object | No | Environment variables, defaults to an empty object |
| workingDirectory | string | No | Working directory for command execution (optional) |
| timeout | number | No | Command timeout in milliseconds (default: 30000, range: 1000-300000) |

### Examples

#### Executing a Command Locally

```json
{
  "command": "ls -la",
  "session": "my-local-session",
  "env": {
    "NODE_ENV": "development"
  }
}
```

#### Executing a Command with Working Directory

```json
{
  "command": "pwd && ls -la",
  "workingDirectory": "/tmp",
  "session": "my-session",
  "timeout": 10000
}
```

#### Executing a Command on a Remote Host

```json
{
  "host": "example.com",
  "username": "user",
  "command": "ls -la",
  "session": "my-remote-session",
  "env": {
    "NODE_ENV": "production"
  },
  "timeout": 15000
}
```

#### Long-running Command with Custom Timeout

```json
{
  "command": "sleep 10 && echo 'Task completed'",
  "timeout": 15000,
  "session": "long-running-task"
}
```

### transfer_file

The transfer_file tool enables file transfers between local and remote hosts via SFTP, as well as local file copy operations.

#### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| source | string | Yes | Source file path |
| destination | string | Yes | Destination file path |
| direction | string | Yes | Transfer direction: 'upload', 'download', or 'local' |
| host | string | For remote | Remote host (required for upload/download) |
| username | string | For remote | SSH username (required for upload/download) |
| session | string | No | Session name for connection reuse (default: 'default') |
| overwrite | boolean | No | Overwrite destination if exists (default: false) |

#### Examples

##### Upload File to Remote Host

```json
{
  "source": "/local/path/file.txt",
  "destination": "/remote/path/file.txt",
  "direction": "upload",
  "host": "example.com",
  "username": "user",
  "overwrite": true
}
```

##### Download File from Remote Host

```json
{
  "source": "/remote/path/file.txt",
  "destination": "/local/path/file.txt",
  "direction": "download",
  "host": "example.com",
  "username": "user"
}
```

##### Local File Copy

```json
{
  "source": "/path/to/source.txt",
  "destination": "/path/to/destination.txt",
  "direction": "local",
  "overwrite": false
}
```

## Configuring with AI Assistants

### Configuring with Roo Code

1. Open VSCode and install the Roo Code extension
2. Open the Roo Code settings file: `~/Library/Application Support/Code/User/globalStorage/rooveterinaryinc.roo-cline/settings/cline_mcp_settings.json`
3. Add the following configuration:

#### For stdio mode (local connection)

```json
{
  "mcpServers": {
    "terminal-mcp": {
      "command": "node",
      "args": ["/path/to/terminal-mcp-server/build/index.js"],
      "env": {}
    }
  }
}
```


### Configuring with Cline

1. Open the Cline settings file: `~/.cline/config.json`
2. Add the following configuration:

#### For stdio mode (local connection)

```json
{
  "mcpServers": {
    "terminal-mcp": {
      "command": "node",
      "args": ["/path/to/terminal-mcp-server/build/index.js"],
      "env": {}
    }
  }
}
```


### Configuring with Claude Desktop

1. Open the Claude Desktop settings file: `~/Library/Application Support/Claude/claude_desktop_config.json`
2. Add the following configuration:

#### For stdio mode (local connection)

```json
{
  "mcpServers": {
    "terminal-mcp": {
      "command": "node",
      "args": ["/path/to/terminal-mcp-server/build/index.js"],
      "env": {}
    }
  }
}
```


## Best Practices

### Command Execution

- Before running commands, it's best to determine the system type (Mac, Linux, etc.)
- Use full paths to avoid path-related issues
- For command sequences that need to maintain environment, use `&&` to connect multiple commands
- For long-running commands, use the `timeout` parameter to set appropriate limits
- Check exit codes in the response to verify command success

### SSH Connection

- Ensure SSH key-based authentication is set up
- If connection fails, check if the key file exists (default path: `~/.ssh/id_rsa`)
- Make sure the SSH service is running on the remote host
- The server automatically retries failed connections with exponential backoff
- Connection health is monitored and sessions are automatically reconnected when needed

### Session Management

- Use the session parameter to maintain environment and working directory between related commands
- For operations requiring specific environments, use the same session name
- Working directories persist across commands in the same session
- Environment variables set in one command persist for subsequent commands in the same session
- Sessions automatically close after 20 minutes of inactivity

### Error Handling

- Command execution results include structured output with command, working directory, exit code, stdout, and stderr
- Check the exit code to determine if the command executed successfully (0 = success, non-zero = error)
- The server provides detailed error messages for connection issues, timeouts, and validation errors
- For complex operations, add verification steps to ensure success
- Use appropriate timeout values for long-running commands

### Working Directory Management

- Use the `workingDirectory` parameter to execute commands in specific directories
- Working directories are remembered across commands in the same session
- Paths are automatically validated and errors are reported clearly

### Timeout Management

- Set appropriate timeout values based on your command's expected duration
- Default timeout is 30 seconds, configurable from 1 to 300 seconds
- Commands that exceed the timeout will return exit code 124
- Use longer timeouts for operations like package installation or compilation

## Output Format

The `execute_command` tool returns structured output in the following format:

```json
{
  "command": "ls -la",
  "executedCommand": "rtk ls -la",
  "exitCode": 0,
  "stdout": "...",
  "stderr": "...",
  "rtkSummarized": true,
  "workingDirectory": "/path/to/dir"
}
```

### Exit Codes

- **0**: Command executed successfully
- **Non-zero**: Command failed or encountered an error
- **124**: Command timed out (when using timeout parameter)

## Troubleshooting

### Shell Configuration Errors

If you encounter errors like:
```
--: eval: line 8551: syntax error near unexpected token `('
--: eval: line 8551: `back () '
--: line 1: dump_bash_state: command not found
```

These errors are caused by problematic shell configurations (oh-my-bash, alias-hub, or custom functions). Use the clean environment mode:

```bash
# Recommended solution
./run-clean.sh

# Alternative solutions
npm run start:clean
bash --noprofile --norc -c "node build/index.js"
```

### SSH Connection Issues

For SSH connection problems:

1. **Check SSH key permissions**:
   ```bash
   chmod 600 ~/.ssh/id_rsa
   chmod 644 ~/.ssh/id_rsa.pub
   ```

2. **Test SSH connection manually**:
   ```bash
   ssh -i ~/.ssh/id_rsa username@hostname
   ```

3. **Enable debug logging**:
   ```bash
   DEBUG=true npm run start:clean
   ```

### Environment Variable Issues

If environment variables aren't persisting:

1. **Check export command syntax**:
   ```bash
   # Correct
   export VAR=value
   
   # Incorrect (will be intercepted)
   export VAR=value; ls
   ```

2. **Use proper quoting**:
   ```bash
   export VAR="value with spaces"
   ```

## Important Notes

- For remote command execution, SSH key-based authentication must be set up in advance
- For local command execution, commands will run in the context of the user who started the server
- Session timeout is 20 minutes, after which the connection will be automatically closed
- The server automatically handles connection failures and retries with exponential backoff
- All sessions are properly cleaned up on server shutdown
- Working directories and environment variables persist within the same session
- Timeout values must be between 1 and 300 seconds (1000-300000 milliseconds)

## Security Features

This implementation includes comprehensive security measures:

### Command Validation

Dangerous command patterns are automatically detected and blocked:
- `rm -rf /` and similar destructive commands
- Fork bombs like `:(){ :|:& };:`
- Pipe to shell patterns like `curl ... | bash`
- Direct writes to system directories (`/etc/`, `/boot/`)
- Device operations (`dd of=/dev/...`, `mkfs`)

To disable command validation (not recommended):
```bash
ENABLE_COMMAND_VALIDATION=false node build/index.js
```

### Resource Limits

- **Output Size Limit**: Large command outputs are automatically truncated (default 5MB)
- **Session Limit**: Maximum concurrent sessions prevents resource exhaustion (default 10)
- **Session Timeout**: Inactive sessions are automatically cleaned up (default 20 minutes)
- **Rate Limiting**: Commands per session are rate limited (default 60/minute)
- **File Transfer Size**: Maximum file size for SFTP transfers (default 100MB)

### Input Validation

- Session names must be 1-64 alphanumeric characters (with underscores/hyphens)
- Working directories are validated to exist for local commands
- Hostnames and usernames are validated for proper format
- Optional directory whitelist restricts where commands can execute

## Configuration

All limits and timeouts are configurable via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `SESSION_TIMEOUT_MS` | 1200000 | Session inactivity timeout in milliseconds (20 min) |
| `MAX_RETRIES` | 3 | Maximum SSH connection retry attempts |
| `CONNECTION_TIMEOUT_MS` | 30000 | SSH connection timeout in milliseconds |
| `MAX_CONCURRENT_SESSIONS` | 10 | Maximum number of concurrent sessions |
| `MAX_OUTPUT_SIZE` | 5242880 | Maximum output size in bytes (5MB) |
| `ENABLE_COMMAND_VALIDATION` | true | Enable dangerous command pattern blocking |
| `COMMAND_BLACKLIST` | (empty) | Comma-separated list of blacklisted command prefixes |
| `ALLOWED_WORKING_DIRECTORIES` | (all) | Comma-separated list of allowed directory prefixes |
| `RATE_LIMIT_PER_MINUTE` | 60 | Maximum commands per minute per session |
| `RATE_LIMIT_ENABLED` | true | Enable/disable rate limiting |
| `MAX_FILE_TRANSFER_SIZE` | 104857600 | Maximum file size for transfers (100MB) |
| `SSH_KEY_PATH` | ~/.ssh/id_rsa | Path to SSH private key |
| `RTK_BIN` | (rtk in PATH) | Path to `rtk` binary |
| `RTK_MCP_REWRITE` | true | Enable/disable `rtk` token optimizations |
| `DEBUG` | false | Enable debug logging |

### Example Configuration

```bash
# Restrictive configuration for production
export MAX_CONCURRENT_SESSIONS=5
export MAX_OUTPUT_SIZE=1048576  # 1MB
export ALLOWED_WORKING_DIRECTORIES="/home/user/projects,/tmp"
export COMMAND_BLACKLIST="shutdown,reboot,poweroff"
node build/index.js

# Permissive configuration for development
export ENABLE_COMMAND_VALIDATION=false
export MAX_OUTPUT_SIZE=52428800  # 50MB
export MAX_CONCURRENT_SESSIONS=50
node build/index.js
```

## Robustness Features

This implementation includes several enterprise-grade robustness features:

- **Automatic Retry Logic**: Failed SSH connections are automatically retried with exponential backoff
- **Connection Health Monitoring**: Active connections are monitored and automatically reconnected when needed
- **Graceful Shutdown**: Proper signal handling ensures all sessions are cleaned up on server termination
- **Input Validation**: All parameters are validated with clear error messages
- **Resource Management**: Sessions are properly managed with automatic cleanup of inactive connections
- **Error Recovery**: The server continues operating even after individual command failures
- **Output Truncation**: Large outputs are safely truncated to prevent memory issues
