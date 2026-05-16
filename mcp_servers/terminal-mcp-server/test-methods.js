#!/usr/bin/env node

// Direct test of tmux methods
import { CommandExecutor } from './build/executor.js';

async function testTmuxMethods() {
  console.log('Testing tmux methods directly...');

  const executor = new CommandExecutor();

  try {
    // Test tmux info
    console.log('\n1. Testing tmux info:');
    const tmuxInfo = await executor.getTmuxInfo();
    console.log(JSON.stringify(tmuxInfo, null, 2));

    // Test tmux sessions
    console.log('\n2. Testing tmux sessions:');
    const tmuxSessions = await executor.getTmuxSessions();
    console.log(JSON.stringify(tmuxSessions, null, 2));

    if (tmuxSessions.sessions && tmuxSessions.sessions.length > 0) {
      const sessionName = tmuxSessions.sessions[0].name;

      // Test tmux windows
      console.log(`\n3. Testing tmux windows for session '${sessionName}':`);
      const tmuxWindows = await executor.getTmuxWindows(sessionName);
      console.log(JSON.stringify(tmuxWindows, null, 2));

      // Test tmux panes for session
      console.log(`\n4. Testing tmux panes for session '${sessionName}':`);
      const tmuxPanes = await executor.getTmuxPanes(sessionName);
      console.log(JSON.stringify(tmuxPanes, null, 2));

      if (tmuxWindows.windows && tmuxWindows.windows.length > 0) {
        const windowIndex = tmuxWindows.windows[0].index;

        // Test tmux panes for specific window
        console.log(`\n5. Testing tmux panes for session '${sessionName}' window ${windowIndex}:`);
        const tmuxWindowPanes = await executor.getTmuxPanes(sessionName, windowIndex);
        console.log(JSON.stringify(tmuxWindowPanes, null, 2));
      }
    }

  } catch (error) {
    console.error('Test failed:', error);
  } finally {
    // Cleanup
    await executor.disconnect();
  }
}

testTmuxMethods().catch(console.error);
