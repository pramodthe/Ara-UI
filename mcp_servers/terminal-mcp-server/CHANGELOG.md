# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-01-24

### Added
- **Rate Limiting**: Per-session command rate limiting to prevent abuse (default: 60 commands/minute)
  - Configurable via RATE_LIMIT_PER_MINUTE env var
  - Can be disabled with RATE_LIMIT_ENABLED=false
- **File Transfer Tool**: New `transfer_file` tool for SFTP file transfers
  - Upload files from local to remote host
  - Download files from remote to local
  - Local file copy operation
  - Size limits configurable via MAX_FILE_TRANSFER_SIZE (default: 100MB)
  - Overwrite protection with optional override
- **RateLimitError**: New error type for rate limit violations

### Environment Variables
- `RATE_LIMIT_PER_MINUTE` - Maximum commands per minute per session (default: 60)
- `RATE_LIMIT_ENABLED` - Enable/disable rate limiting (default: true)
- `MAX_FILE_TRANSFER_SIZE` - Maximum file size for transfers in bytes (default: 104857600 = 100MB)

## [1.1.0] - 2026-01-24

### Added
- **Command Validation**: Dangerous command patterns are now detected and blocked by default (can be disabled with ENABLE_COMMAND_VALIDATION=false)
- **Output Size Limits**: Large outputs are automatically truncated to prevent memory exhaustion (configurable via MAX_OUTPUT_SIZE, default 5MB)
- **Session Limits**: Maximum concurrent sessions limit to prevent resource exhaustion (configurable via MAX_CONCURRENT_SESSIONS, default 10)
- **Session Name Validation**: Session names must be 1-64 alphanumeric characters (with underscores and hyphens)
- **Working Directory Validation**: Working directories are validated to exist before command execution (local only)
- **Allowed Directories**: Optionally restrict working directories to a whitelist (ALLOWED_WORKING_DIRECTORIES)
- **Command Blacklist**: Optionally blacklist specific command prefixes (COMMAND_BLACKLIST)
- **Configuration Resource**: New `terminal://config` resource to view current server configuration
- **New Error Types**: ValidationError, SecurityError, ResourceLimitError for better error handling

### Changed
- **SSH Health Check**: Replaced unreliable subsys-based health check with exec-based check
- **Timeout Limit**: Increased maximum timeout from 300s to 600s (10 minutes)
- **Configuration**: All limits and timeouts are now configurable via environment variables

### Security
- **Dangerous Pattern Detection**: Blocks commands like `rm -rf /`, fork bombs, curl pipe to shell, etc.
- **Input Sanitization**: Improved validation of session names, hostnames, usernames
- **Resource Protection**: Limits on sessions and output size prevent denial of service

### Environment Variables
- `SESSION_TIMEOUT_MS` - Session inactivity timeout (default: 1200000 = 20 minutes)
- `MAX_RETRIES` - SSH connection retry attempts (default: 3)
- `CONNECTION_TIMEOUT_MS` - SSH connection timeout (default: 30000)
- `MAX_CONCURRENT_SESSIONS` - Maximum concurrent sessions (default: 10)
- `MAX_OUTPUT_SIZE` - Maximum output size in bytes (default: 5242880 = 5MB)
- `ENABLE_COMMAND_VALIDATION` - Enable dangerous command blocking (default: true)
- `COMMAND_BLACKLIST` - Comma-separated blacklisted command prefixes
- `ALLOWED_WORKING_DIRECTORIES` - Comma-separated allowed directory prefixes

## [1.0.0] - 2025-01-XX

### Added
- **Working Directory Management**: Commands can now execute in specified working directories with persistence across sessions
- **Configurable Timeouts**: Custom command timeouts (1-300 seconds) with proper timeout handling
- **Enhanced Error Handling**: Detailed error messages with automatic retry mechanisms for SSH connections
- **Exit Code Reporting**: Commands now return proper exit codes for better error detection
- **Structured Output**: Better formatted output with command, working directory, exit code, stdout, and stderr
- **Clean Environment Mode**: Added `./run-clean.sh` script and `npm run start:clean` to bypass problematic shell configurations
- **NPM Scripts**: Added convenient npm scripts for development and deployment
- **MIT License**: Added proper MIT license for open source distribution
- **Comprehensive .gitignore**: Added proper gitignore file for Node.js projects
- **Enhanced package.json**: Updated with proper metadata, keywords, and repository information

### Changed
- **Version**: Bumped from 0.1.0 to 1.0.0 to reflect major robustness improvements
- **Description**: Updated package description to reflect enhanced capabilities
- **Repository**: Updated to new maintainer's repository
- **Documentation**: Removed unnecessary Chinese documentation and AI project info files

### Fixed
- **Export Command Parsing**: Fixed critical bug where export commands with chained commands (e.g., `export FOO=bar; ls`) were incorrectly handled, preventing subsequent commands from executing. Now properly detects chained commands and allows shell to handle them normally while still intercepting standalone export commands for session persistence.
- **Quote Removal Logic**: Fixed unsafe quote removal that could corrupt environment variable values. Now only removes quotes when they form proper matching pairs at the beginning and end of values, preventing corruption of values like `"foo'` or `hello"`.
- **Shell Configuration Errors**: Added clean environment mode to bypass problematic shell configurations (oh-my-bash, alias-hub) that cause syntax errors. Users can now use `./run-clean.sh` or `npm run start:clean` to run the server without shell interference.
- **Session Persistence**: Fixed environment variable persistence across commands by implementing proper export command handling in local execution
- **SSH Connection Health**: Improved connection health monitoring and automatic reconnection
- **Memory Management**: Better session lifecycle management and cleanup
- **Type Safety**: Improved TypeScript typing throughout the codebase with proper null checks

### Security
- **SSH Security**: Enhanced SSH key validation and modern algorithm support (RSA, Ed25519, ECDSA)
- **Input Validation**: Better parameter validation with meaningful error messages

### Removed
- **Unnecessary Files**: Removed PROJ_INFO_4AI.md, README_CN.md, and PR_DESCRIPTION.md
- **Old References**: Removed references to original maintainer and updated repository URLs

## [0.1.0] - Original Release

### Added
- Basic MCP server functionality
- SSH connection support
- Session persistence
- Local and remote command execution
- Environment variable support
