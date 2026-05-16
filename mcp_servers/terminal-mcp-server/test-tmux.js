#!/usr/bin/env node

// Simple test script for tmux resources
import { spawn } from 'child_process';

async function testTmuxResources() {
  console.log('Testing tmux resources...');

  // Start tmux server if not running
  try {
    const tmuxStart = spawn('tmux', ['new-session', '-d', '-s', 'test-session'], {
      stdio: 'pipe'
    });

    await new Promise((resolve, reject) => {
      tmuxStart.on('close', (code) => {
        if (code === 0) {
          console.log('Created test tmux session');
          resolve();
        } else {
          reject(new Error(`Failed to create tmux session: ${code}`));
        }
      });
      tmuxStart.on('error', reject);
    });
  } catch (error) {
    console.log('Tmux session might already exist, continuing...');
  }

  // Test our MCP server with tmux resources
  const server = spawn('node', ['build/index.js'], {
    stdio: ['pipe', 'pipe', 'inherit']
  });

  let responseBuffer = '';

  server.stdout.on('data', (data) => {
    responseBuffer += data.toString();
  });

  // Send initialize request
  const initRequest = {
    jsonrpc: "2.0",
    id: 1,
    method: "initialize",
    params: {
      protocolVersion: "2024-11-05",
      capabilities: {
        resources: {}
      },
      clientInfo: {
        name: "test-client",
        version: "1.0.0"
      }
    }
  };

  server.stdin.write(JSON.stringify(initRequest) + '\n');

  // Wait a bit then test resources
  setTimeout(() => {
    // Test list resources
    const listResourcesRequest = {
      jsonrpc: "2.0",
      id: 2,
      method: "resources/list",
      params: {}
    };

    server.stdin.write(JSON.stringify(listResourcesRequest) + '\n');

    // Wait for response
    setTimeout(() => {
      console.log('Response received:', responseBuffer.substring(0, 1000) + '...');

      // Test tmux info resource
      const tmuxInfoRequest = {
        jsonrpc: "2.0",
        id: 3,
        method: "resources/read",
        params: {
          uri: "terminal://tmux/info"
        }
      };

      server.stdin.write(JSON.stringify(tmuxInfoRequest) + '\n');

      // Clean up
      setTimeout(() => {
        server.kill();

        // Clean up test session
        try {
          const cleanup = spawn('tmux', ['kill-session', '-t', 'test-session'], {
            stdio: 'ignore'
          });
          cleanup.on('close', () => {
            console.log('Cleaned up test session');
          });
        } catch (e) {
          // Ignore cleanup errors
        }

        console.log('Test completed');
      }, 2000);
    }, 1000);
  }, 500);
}

testTmuxResources().catch(console.error);
