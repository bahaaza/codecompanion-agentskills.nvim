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

-- ==================== editor_context tests ====================

T["Editor Context"] = new_set()

T["Editor Context"]["#{skill:test-skill} injects SKILL.md content"] = function()
  -- Setup Chat with agentskills and a test skill
  h.setup_chat_with_agentskills(child, {
    skills = {
      ["test-skill"] = {
        description = "A test skill for editor_context",
        content = "# Test Skill Content\n\nThis is the skill body for editor_context test.",
      },
    },
  })

-- Add a message with #{skill:test-skill} and parse editor context
  child.lua([[
    local chat = _G._test_chat
    -- Add user message with editor context
    table.insert(chat.messages, { role = "user", content = "#{skill:test-skill} Please help me with this skill" })
    local message = chat.messages[#chat.messages]
    -- Parse editor context
    chat.editor_context:parse(chat, message)
  ]])

  -- Verify SKILL.md content was added to messages
  local result = child.lua([[
    local chat = _G._test_chat
    -- Find the message with skill content (added by editor_context)
    local skill_msg = nil
    for _, msg in ipairs(chat.messages) do
      if msg._meta and msg._meta.source == "editor_context" and msg._meta.tag == "skill:test-skill" then
        skill_msg = msg
        break
      end
    end
    return {
      found = skill_msg ~= nil,
      content = skill_msg and skill_msg.content or "",
      visible = skill_msg and skill_msg.opts and skill_msg.opts.visible,
    }
  ]])

  h.is_true(result.found, "Skill content message should be added")
  h.expect_contains('<agent-skill name="test-skill">', result.content)
  h.expect_contains("Test Skill Content", result.content)
  h.expect_contains("skill body for editor_context test", result.content)
  h.expect_contains('</agent-skill>', result.content)
  h.eq(false, result.visible, "Skill content message should be hidden")
end

T["Editor Context"]["#{skill:nonexistent} returns error message"] = function()
  -- Setup Chat with agentskills but no skills
  h.setup_chat_with_agentskills(child, {
    skills = {}, -- No skills available
  })

  -- Manually register a skill editor_context that will fail
  child.lua([[
    local config = require("codecompanion.config")
    config.interactions.shared.editor_context["skill:nonexistent"] = {
      callback = function(ctx)
        local name = ctx.config.name:match("^skill:(.+)$")
        local Extension = require("codecompanion._extensions.agentskills")
        local s = Extension.get_skill(name)
        if not s then
          return "Skill not found: " .. name
        end
        return s:read_content()
      end,
      description = "Non-existent skill",
      opts = { contains_code = false },
    }

    local chat = _G._test_chat
    -- Recreate editor_context with the new registration
    local EditorContext = require("codecompanion.interactions.shared.editor_context")
    chat.editor_context = EditorContext.new("chat")

    -- Add user message with editor context
    table.insert(chat.messages, { role = "user", content = "#{skill:nonexistent} Please help" })
    local message = chat.messages[#chat.messages]
    -- Parse editor context
    chat.editor_context:parse(chat, message)
  ]])

  -- Verify error message was added
  local result = child.lua([[
    local chat = _G._test_chat
    -- Find the message with error content
    local error_msg = nil
    for _, msg in ipairs(chat.messages) do
      if msg._meta and msg._meta.source == "editor_context" and msg._meta.tag == "skill:nonexistent" then
        error_msg = msg
        break
      end
    end
    return {
      found = error_msg ~= nil,
      content = error_msg and error_msg.content or "",
    }
  ]])

  h.is_true(result.found, "Error message should be added")
  h.expect_contains("Skill not found", result.content)
  h.expect_contains("nonexistent", result.content)
end

T["Editor Context"]["Extension.discover() updates editor_context registrations"] = function()
  -- Create two temp directories with different skills
  local temp_dir_a = h.temp_dir()
  local temp_dir_b = h.temp_dir()

  -- Create skill A
  h.create_test_skill(temp_dir_a, "skill-a", h.make_skill_md("skill-a", "Skill A", "# Skill A Content"))

  -- Create skill B
  h.create_test_skill(temp_dir_b, "skill-b", h.make_skill_md("skill-b", "Skill B", "# Skill B Content"))

  -- Setup with skill A
  child.lua([[
    local temp_dir_a = ...
    local config = require("tests.config")
    config.extensions = config.extensions or {}
    config.extensions.agentskills = {
      opts = {
        paths = { temp_dir_a },
        disable_demo_skill = true,
      },
    }
    require("codecompanion").setup(config)

    local config_after = require("codecompanion.config")
    _G.editor_context_a = config_after.interactions.shared.editor_context["skill:skill-a"] ~= nil
    _G.editor_context_b_before = config_after.interactions.shared.editor_context["skill:skill-b"] ~= nil
  ]], { temp_dir_a })

  -- Verify skill A is registered
  h.is_true(child.lua_get([[_G.editor_context_a]]), "skill-a should be registered initially")
  h.is_false(child.lua_get([[_G.editor_context_b_before]]), "skill-b should not be registered initially")

  -- Re-setup with skill B's path (this calls discover_skills internally)
  child.lua([[
    local temp_dir_b = ...
    local AS = require("codecompanion._extensions.agentskills")
    AS.setup({
      paths = { temp_dir_b },
      disable_demo_skill = true,
    })

    local config_after = require("codecompanion.config")
    _G.editor_context_a_after = config_after.interactions.shared.editor_context["skill:skill-a"] ~= nil
    _G.editor_context_b_after = config_after.interactions.shared.editor_context["skill:skill-b"] ~= nil
  ]], { temp_dir_b })

  -- Verify skill A is removed and skill B is added
  h.is_false(child.lua_get([[_G.editor_context_a_after]]), "skill-a should be removed after discover")
  h.is_true(child.lua_get([[_G.editor_context_b_after]]), "skill-b should be registered after discover")

  -- Cleanup
  h.cleanup_dir(temp_dir_a)
  h.cleanup_dir(temp_dir_b)
end

return T
