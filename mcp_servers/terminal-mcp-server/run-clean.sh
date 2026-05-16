#!/bin/bash

# Clean MCP Server Runner
# This script runs the MCP server in a clean environment without
# loading the problematic shell configuration

echo "🚀 Starting Terminal MCP Server in clean environment..."

# Change to the project directory
cd "$(dirname "$0")"

# Run the MCP server with a clean bash environment
# This bypasses the problematic .bashrc and alias-hub configuration
exec bash --noprofile --norc -c "node build/index.js"