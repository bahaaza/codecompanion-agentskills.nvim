-- Integration tests for agentskills with CodeCompanion Chat
-- Tests the full pipeline: LLM response → tool execution → chat messages
local h = require("tests.helpers")
local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_once = function()
      h.child_start(child)
      h.setup_codecompanion(child)
    end,
    post_once = child.stop,
  },
})

T["Chat Integration"] = new_set()

-- ==================== activate_skill tests ====================

T["Chat Integration"]["activate_skill success - skill content in chat messages"] = function()
  -- Step 1-3: Create skill files and setup Chat with agentskills tools
  h.setup_chat_with_agentskills(child, {
    skills = {
      ["test-skill"] = {
        description = "A test skill",
        content = "# Test Skill Content\n\nThis is the skill body.",
      },
    },
  })

  -- Step 4: Add user message
  child.lua([[
    local chat = _G._test_chat
    chat:add_buf_message({ role = "user", content = "Please activate the test skill" })
  ]])

  -- Step 5: Queue mock response with tool_call
  h.queue_tool_call_response(child, {
    {
      ["function"] = {
        name = "activate_skill",
        arguments = { skill_name = "test-skill" },
      },
      id = "call_test_001",
      type = "function",
    },
  }, "I'll activate the test skill")

  -- Step 6: Submit chat
  child.lua([[
    local chat = _G._test_chat
    chat:submit()
  ]])

  -- Step 7: Wait for completion and verify
  local success = h.wait_for_tool_completion(child)
  h.is_true(success, "Tool execution should complete")

  local tool_msgs = h.get_tool_output_messages(child)
  h.eq(1, #tool_msgs, "Should have one tool output message")
  h.expect_contains("Test Skill Content", tool_msgs[1].content)
end

T["Chat Integration"]["activate_skill error - error message in chat messages"] = function()
  -- Step 1-3: Setup Chat with agentskills tools (no skills configured)
  h.setup_chat_with_agentskills(child, {
    skills = {}, -- No skills available
  })

  -- Step 4: Add user message
  child.lua([[
    local chat = _G._test_chat
    chat:add_buf_message({ role = "user", content = "Please activate a non-existent skill" })
  ]])

  -- Step 5: Queue mock response with tool_call for non-existent skill
  h.queue_tool_call_response(child, {
    {
      ["function"] = {
        name = "activate_skill",
        arguments = { skill_name = "nonexistent-skill" },
      },
      id = "call_test_002",
      type = "function",
    },
  }, "I'll try to activate the skill")

  -- Step 6: Submit chat
  child.lua([[
    local chat = _G._test_chat
    chat:submit()
  ]])

  -- Step 7: Wait for completion and verify
  local success = h.wait_for_tool_completion(child)
  h.is_true(success, "Tool execution should complete")

  local tool_msgs = h.get_tool_output_messages(child)
  h.eq(1, #tool_msgs, "Should have one tool output message")
  h.expect_contains("Skill not found", tool_msgs[1].content)
  h.expect_contains("nonexistent-skill", tool_msgs[1].content)
end

-- ==================== load_skill_file tests ====================

T["Chat Integration"]["load_skill_file success - file content in chat messages"] = function()
  -- Step 1-3: Create skill with files and setup Chat
  h.setup_chat_with_agentskills(child, {
    skills = {
      ["test-skill"] = {
        description = "A test skill",
        content = "# Test Skill",
        files = {
          ["docs/guide.md"] = "# Guide Content\n\nThis is a test guide.",
        },
      },
    },
  })

  -- Step 4: Add user message
  child.lua([[
    local chat = _G._test_chat
    chat:add_buf_message({ role = "user", content = "Please load the guide file" })
  ]])

  -- Step 5: Queue mock response with tool_call
  h.queue_tool_call_response(child, {
    {
      ["function"] = {
        name = "load_skill_file",
        arguments = { skill_name = "test-skill", file_path = "docs/guide.md" },
      },
      id = "call_test_003",
      type = "function",
    },
  }, "I'll load the file")

  -- Step 6: Submit chat
  child.lua([[
    local chat = _G._test_chat
    chat:submit()
  ]])

  -- Step 7: Wait for completion and verify
  local success = h.wait_for_tool_completion(child)
  h.is_true(success, "Tool execution should complete")

  local tool_msgs = h.get_tool_output_messages(child)
  h.eq(1, #tool_msgs, "Should have one tool output message")
  h.expect_contains("Guide Content", tool_msgs[1].content)
end

T["Chat Integration"]["load_skill_file error - error message in chat messages"] = function()
  -- Step 1-3: Create skill with empty files and setup Chat
  h.setup_chat_with_agentskills(child, {
    skills = {
      ["test-skill"] = {
        description = "A test skill",
        content = "# Test Skill",
        files = {}, -- No files available
      },
    },
  })

  -- Step 4: Add user message
  child.lua([[
    local chat = _G._test_chat
    chat:add_buf_message({ role = "user", content = "Please load a non-existent file" })
  ]])

  -- Step 5: Queue mock response with tool_call
  h.queue_tool_call_response(child, {
    {
      ["function"] = {
        name = "load_skill_file",
        arguments = { skill_name = "test-skill", file_path = "nonexistent.md" },
      },
      id = "call_test_004",
      type = "function",
    },
  }, "I'll try to load the file")

  -- Step 6: Submit chat
  child.lua([[
    local chat = _G._test_chat
    chat:submit()
  ]])

  -- Step 7: Wait for completion and verify
  local success = h.wait_for_tool_completion(child)
  h.is_true(success, "Tool execution should complete")

  local tool_msgs = h.get_tool_output_messages(child)
  h.eq(1, #tool_msgs, "Should have one tool output message")
  h.expect_contains("Failed to read file", tool_msgs[1].content)
end

-- ==================== run_skill_script tests ====================

T["Chat Integration"]["run_skill_script success - script output in chat messages"] = function()
  -- Step 1-3: Create skill with script files and setup Chat
  h.setup_chat_with_agentskills(child, {
    skills = {
      ["test-skill"] = {
        description = "A test skill",
        content = "# Test Skill",
        opts = { scripts_require_approval = false },
        files = {
          ["scripts/test.sh"] = "#!/bin/bash\necho 'mock script output'",
        },
      },
    },
  })

  -- Mock vim.system for script execution
  child.lua([[
    vim.system = function(cmd, opts, callback)
      vim.schedule(function()
        callback({ code = 0, stdout = "mock script output", stderr = "" })
      end)
      return {}
    end
  ]])

  -- Step 4: Add user message
  child.lua([[
    local chat = _G._test_chat
    chat:add_buf_message({ role = "user", content = "Please run the script" })
  ]])

  -- Step 5: Queue mock response with tool_call
  h.queue_tool_call_response(child, {
    {
      ["function"] = {
        name = "run_skill_script",
        arguments = { skill_name = "test-skill", script_path = "scripts/test.sh", interpreter = "bash" },
      },
      id = "call_test_005",
      type = "function",
    },
  }, "I'll run the script")

  -- Step 6: Submit chat
  child.lua([[
    local chat = _G._test_chat
    chat:submit()
  ]])

  -- Step 7: Wait for completion and verify
  local success = h.wait_for_tool_completion(child, nil, 3000)
  h.is_true(success, "Tool execution should complete")

  local tool_msgs = h.get_tool_output_messages(child)
  h.eq(1, #tool_msgs, "Should have one tool output message")
  h.expect_contains("mock script output", tool_msgs[1].content)
end

T["Chat Integration"]["run_skill_script error - error output in chat messages"] = function()
  -- Step 1-3: Create skill and setup Chat
  h.setup_chat_with_agentskills(child, {
    skills = {
      ["test-skill"] = {
        description = "A test skill",
        content = "# Test Skill",
        opts = { scripts_require_approval = false },
      },
    },
  })

  -- Mock vim.system for script execution failure
  child.lua([[
    vim.system = function(cmd, opts, callback)
      vim.schedule(function()
        callback({ code = 1, stdout = "", stderr = "mock error output" })
      end)
      return {}
    end
  ]])

  -- Step 4: Add user message
  child.lua([[
    local chat = _G._test_chat
    chat:add_buf_message({ role = "user", content = "Please run the failing script" })
  ]])

  -- Step 5: Queue mock response with tool_call
  h.queue_tool_call_response(child, {
    {
      ["function"] = {
        name = "run_skill_script",
        arguments = { skill_name = "test-skill", script_path = "scripts/fail.sh", interpreter = "bash" },
      },
      id = "call_test_006",
      type = "function",
    },
  }, "I'll run the script")

  -- Step 6: Submit chat
  child.lua([[
    local chat = _G._test_chat
    chat:submit()
  ]])

  -- Step 7: Wait for completion and verify
  local success = h.wait_for_tool_completion(child, nil, 3000)
  h.is_true(success, "Tool execution should complete")

  local tool_msgs = h.get_tool_output_messages(child)
  h.eq(1, #tool_msgs, "Should have one tool output message")
  h.expect_contains("mock error output", tool_msgs[1].content)
end

-- ==================== multiple tool calls tests ====================

T["Chat Integration"]["multiple tool calls - all outputs in chat messages"] = function()
  -- Step 1-3: Create skills and setup Chat
  h.setup_chat_with_agentskills(child, {
    skills = {
      ["skill-a"] = {
        description = "First skill",
        content = "# Skill A Content",
      },
      ["skill-b"] = {
        description = "Second skill",
        content = "# Skill B Content",
      },
    },
  })

  -- Step 4: Add user message
  child.lua([[
    local chat = _G._test_chat
    chat:add_buf_message({ role = "user", content = "Please activate both skills" })
  ]])

  -- Step 5: Queue mock response with multiple tool_calls
  h.queue_tool_call_response(child, {
    {
      ["function"] = {
        name = "activate_skill",
        arguments = { skill_name = "skill-a" },
      },
      id = "call_multi_001",
      type = "function",
    },
    {
      ["function"] = {
        name = "activate_skill",
        arguments = { skill_name = "skill-b" },
      },
      id = "call_multi_002",
      type = "function",
    },
  }, "I'll activate both skills")

  -- Step 6: Submit chat
  child.lua([[
    local chat = _G._test_chat
    chat:submit()
  ]])

  -- Step 7: Wait for completion and verify
  local success = h.wait_for_tool_completion(child, nil, 3000)
  h.is_true(success, "Tool execution should complete")

  local tool_msgs = h.get_tool_output_messages(child)
  h.eq(2, #tool_msgs, "Should have two tool output messages")

  -- Check that both skill contents are present (order may vary)
  local all_content = tool_msgs[1].content .. " " .. tool_msgs[2].content
  h.expect_contains("Skill A Content", all_content)
  h.expect_contains("Skill B Content", all_content)
end

return T
