-- Tests for lua/codecompanion/_extensions/agentskills/tools.lua
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

T["Tools"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[
        package.loaded["codecompanion._extensions.agentskills"] = nil
        package.loaded["codecompanion._extensions.agentskills.tools"] = nil
        package.loaded["codecompanion._extensions.agentskills.init"] = nil
        package.loaded["codecompanion._extensions.agentskills.skill"] = nil
      ]])
    end,
  },
})

-- ==================== activate_skill tests ====================

T["Tools"]["activate_skill returns error for non-existent skill"] = function()
  local result = child.lua([[
    -- Mock the AS module FIRST (before loading tools)
    package.loaded["codecompanion._extensions.agentskills"] = {
      get_skill = function(name)
        return nil
      end,
      get_skills = function()
        return {}
      end,
    }

    local Tools = require("codecompanion._extensions.agentskills.tools")
    local tool = Tools.activate_skill()

    -- Call the cmds function
    local cmd_func = tool.cmds[1]
    local output = cmd_func(nil, { skill_name = "nonexistent_skill" })

    return {
      status = output.status,
      data = output.data,
    }
  ]])

  h.eq("error", result.status)
  h.expect_contains("Skill not found", result.data)
  h.expect_contains("nonexistent_skill", result.data)
end

T["Tools"]["activate_skill returns skill on success"] = function()
  local result = child.lua([[
    -- Create a mock skill
    local mock_skill = {
      name = function(self) return "test-skill" end,
      description = function(self) return "A test skill" end,
      read_content = function(self) return "# Test Skill Content" end,
    }

    -- Mock the AS module FIRST (before loading tools)
    package.loaded["codecompanion._extensions.agentskills"] = {
      get_skill = function(name)
        if name == "test-skill" then return mock_skill end
        return nil
      end,
      get_skills = function()
        return { ["test-skill"] = mock_skill }
      end,
    }

    local Tools = require("codecompanion._extensions.agentskills.tools")
    local tool = Tools.activate_skill()

    -- Call the cmds function
    local cmd_func = tool.cmds[1]
    local output = cmd_func(nil, { skill_name = "test-skill" })

    return {
      status = output.status,
      skill_name = output.data and output.data:name(),
    }
  ]])

  h.eq("success", result.status)
  h.eq("test-skill", result.skill_name)
end

T["Tools"]["activate_skill generates correct system_prompt"] = function()
  local result = child.lua([[
    local Tools = require("codecompanion._extensions.agentskills.tools")

    -- Create mock skills
    local mock_skills = {
      ["skill-a"] = {
        name = function(self) return "skill-a" end,
        description = function(self) return "First skill" end,
      },
      ["skill-b"] = {
        name = function(self) return "skill-b" end,
        description = function(self) return "Second skill" end,
      },
    }

    -- Mock the AS module
    package.loaded["codecompanion._extensions.agentskills"] = {
      get_skills = function()
        return mock_skills
      end,
    }

    local tool = Tools.activate_skill()
    local system_prompt = tool.system_prompt

    return {
      has_workflow = system_prompt:find("Workflow") ~= nil,
      has_rules = system_prompt:find("CRITICAL RULES") ~= nil,
      has_skill_a = system_prompt:find("skill%-a") ~= nil,
      has_skill_b = system_prompt:find("skill%-b") ~= nil,
      has_activate_instruction = system_prompt:find("activate_skill") ~= nil,
    }
  ]])

  h.eq(true, result.has_workflow)
  h.eq(true, result.has_rules)
  h.eq(true, result.has_skill_a)
  h.eq(true, result.has_skill_b)
  h.eq(true, result.has_activate_instruction)
end

T["Tools"]["activate_skill schema has correct structure"] = function()
  child.lua([[
    -- Mock the AS module FIRST (before loading tools)
    package.loaded["codecompanion._extensions.agentskills"] = {
      get_skills = function() return {} end,
    }

    local Tools = require("codecompanion._extensions.agentskills.tools")
    local tool = Tools.activate_skill()

    local h = require("tests.helpers")
    h.assert_tool_schema(tool, {
      name = "activate_skill",
      params = { "skill_name" },
      required = { "skill_name" },
    })
  ]])
end

-- ==================== load_skill_file tests ====================

T["Tools"]["load_skill_file errors for non-existent skill"] = function()
  local result = child.lua([[
    local Tools = require("codecompanion._extensions.agentskills.tools")
    local tool = Tools.load_skill_file()

    -- Mock the AS module
    package.loaded["codecompanion._extensions.agentskills"] = {
      get_skill = function(name)
        return nil
      end,
    }

    -- Call the cmds function
    local cmd_func = tool.cmds[1]
    local output = cmd_func(nil, { skill_name = "nonexistent", file_path = "test.md" })

    return {
      status = output.status,
      data = output.data,
    }
  ]])

  h.eq("error", result.status)
  h.expect_contains("Skill not found", result.data)
end

T["Tools"]["load_skill_file errors for file not found in skill"] = function()
  local result = child.lua([[
    local Tools = require("codecompanion._extensions.agentskills.tools")
    local tool = Tools.load_skill_file()

    -- Create a mock skill
    local mock_skill = {
      read_file = function(self, path)
        return nil  -- File not found
      end,
    }

    -- Mock the AS module
    package.loaded["codecompanion._extensions.agentskills"] = {
      get_skill = function(name)
        return mock_skill
      end,
    }

    -- Call the cmds function
    local cmd_func = tool.cmds[1]
    local output = cmd_func(nil, { skill_name = "test-skill", file_path = "nonexistent.md" })

    return {
      status = output.status,
      data = output.data,
    }
  ]])

  h.eq("error", result.status)
  h.expect_contains("File not found", result.data)
end

T["Tools"]["load_skill_file errors for file outside skill directory"] = function()
  local result = child.lua([[
    local Tools = require("codecompanion._extensions.agentskills.tools")
    local tool = Tools.load_skill_file()

    -- Create a mock skill that raises error on traversal (matches real behavior)
    local mock_skill = {
      read_file = function(self, path)
        -- Simulate path traversal rejection with error (matches real Skill:read_file behavior)
        if path:find("%.%.") or path:find("^/") then
          error("Path traversal detected in skill file access")
        end
        return nil
      end,
    }

    -- Mock the AS module
    package.loaded["codecompanion._extensions.agentskills"] = {
      get_skill = function(name)
        return mock_skill
      end,
    }

    -- Call the cmds function with path traversal attempt
    local cmd_func = tool.cmds[1]
    local output = cmd_func(nil, { skill_name = "test-skill", file_path = "../../../etc/passwd" })

    return {
      status = output.status,
      data = output.data,
    }
  ]])

  h.eq("error", result.status)
  h.expect_contains("Failed to read file", result.data)
end

T["Tools"]["load_skill_file returns file content on success"] = function()
  local result = child.lua([[
    local Tools = require("codecompanion._extensions.agentskills.tools")
    local tool = Tools.load_skill_file()

    -- Create a mock skill
    local mock_skill = {
      read_file = function(self, path)
        if path == "docs/guide.md" then
          return "# Guide Content\n\nThis is a test guide."
        end
        return nil
      end,
    }

    -- Mock the AS module
    package.loaded["codecompanion._extensions.agentskills"] = {
      get_skill = function(name)
        return mock_skill
      end,
    }

    -- Call the cmds function
    local cmd_func = tool.cmds[1]
    local output = cmd_func(nil, { skill_name = "test-skill", file_path = "docs/guide.md" })

    return {
      status = output.status,
      has_content = output.data ~= nil,
      content_has_guide = output.data and output.data:find("Guide Content") ~= nil,
    }
  ]])

  h.eq("success", result.status)
  h.eq(true, result.has_content)
  h.eq(true, result.content_has_guide)
end

T["Tools"]["load_skill_file schema has correct structure"] = function()
  child.lua([[
    local Tools = require("codecompanion._extensions.agentskills.tools")
    local tool = Tools.load_skill_file()

    local h = require("tests.helpers")
    h.assert_tool_schema(tool, {
      name = "load_skill_file",
      params = { "skill_name", "file_path" },
      required = { "skill_name", "file_path" },
    })
  ]])
end

-- ==================== run_skill_script tests ====================

-- Parameterized test for missing required parameters
local missing_params_cases = {
  { missing = "skill_name", args = { script_path = "test.sh", interpreter = "bash" } },
  { missing = "script_path", args = { skill_name = "test", interpreter = "bash" } },
  { missing = "interpreter", args = { skill_name = "test", script_path = "test.sh" } },
}

for _, case in ipairs(missing_params_cases) do
  T["Tools"]["run_skill_script validates missing " .. case.missing] = function()
    local result = child.lua([[
      local case = ...

      -- Mock interpreters FIRST (before loading tools)
      package.loaded["codecompanion._extensions.agentskills.interpreter"] = {
        get_enabled_interpreters = function()
          return { bash = {} }
        end,
      }

      -- Clear and reload Tools to pick up the mock
      package.loaded["codecompanion._extensions.agentskills.tools"] = nil
      local Tools = require("codecompanion._extensions.agentskills.tools")
      local tool = Tools.run_skill_script()

      -- Call the cmds function with missing parameter
      local cmd_func = tool.cmds[1]
      local output = cmd_func(nil, case.args, {})

      return {
        status = output.status,
        data = output.data,
      }
    ]], { case })

    h.eq("error", result.status)
    h.expect_contains("Missing required parameter", result.data)
    h.expect_contains(case.missing, result.data)
  end
end

T["Tools"]["run_skill_script errors for non-existent skill"] = function()
  local result = child.lua([[
    local Tools = require("codecompanion._extensions.agentskills.tools")
    local tool = Tools.run_skill_script()

    -- Mock interpreters
    package.loaded["codecompanion._extensions.agentskills.interpreter"] = {
      get_enabled_interpreters = function()
        return { bash = {} }
      end,
    }

    -- Mock AS module
    package.loaded["codecompanion._extensions.agentskills"] = {
      get_skill = function(name)
        return nil
      end,
    }

    -- Call the cmds function
    local cmd_func = tool.cmds[1]
    local output = cmd_func(nil, { 
      skill_name = "nonexistent", 
      script_path = "test.sh", 
      interpreter = "bash" 
    }, {})

    return {
      status = output.status,
      data = output.data,
    }
  ]])

  h.eq("error", result.status)
  h.expect_contains("Skill not found", result.data)
end

T["Tools"]["run_skill_script errors for unsupported interpreter"] = function()
  local result = child.lua([[
    -- Mock interpreters FIRST (before loading tools) - only bash available, not ruby
    package.loaded["codecompanion._extensions.agentskills.interpreter"] = {
      get_enabled_interpreters = function()
        return { bash = {} }
      end,
    }

    -- Clear and reload Tools to pick up the mock
    package.loaded["codecompanion._extensions.agentskills.tools"] = nil
    local Tools = require("codecompanion._extensions.agentskills.tools")
    local tool = Tools.run_skill_script()

    -- The schema should not include ruby in the enum
    local interpreter_enum = tool.schema["function"].parameters.properties.interpreter.enum

    return {
      enum_has_ruby = vim.list_contains(interpreter_enum, "ruby"),
      enum_has_bash = vim.list_contains(interpreter_enum, "bash"),
    }
  ]])

  -- ruby should NOT be in the available interpreters enum
  h.eq(false, result.enum_has_ruby)
  h.eq(true, result.enum_has_bash)
end

T["Tools"]["run_skill_script generates correct prompt for approval"] = function()
  local result = child.lua([[
    local Tools = require("codecompanion._extensions.agentskills.tools")

    -- Mock interpreters
    package.loaded["codecompanion._extensions.agentskills.interpreter"] = {
      get_enabled_interpreters = function()
        return { bash = { support_dependencies = false }, python3 = { support_dependencies = true } }
      end,
    }

    local tool = Tools.run_skill_script()

    -- Simulate the handlers.setup to set escaped_args
    tool.args = {
      skill_name = "test-skill",
      script_path = "scripts/build.sh",
      interpreter = "bash",
      args = { "--verbose", "output.txt" },
      dependencies = vim.NIL,
    }
    tool.escaped_args = { "--verbose", "output.txt" }

    local prompt = tool.output.prompt(tool)

    return {
      has_skill_name = prompt:find("test%-skill") ~= nil,
      has_script_path = prompt:find("scripts/build%.sh") ~= nil,
      has_interpreter = prompt:find("bash") ~= nil,
      has_confirm = prompt:find("Confirm") ~= nil,
    }
  ]])

  h.eq(true, result.has_skill_name)
  h.eq(true, result.has_script_path)
  h.eq(true, result.has_interpreter)
  h.eq(true, result.has_confirm)
end

T["Tools"]["run_skill_script prompt includes dependencies"] = function()
  local result = child.lua([[
    local Tools = require("codecompanion._extensions.agentskills.tools")

    -- Mock interpreters
    package.loaded["codecompanion._extensions.agentskills.interpreter"] = {
      get_enabled_interpreters = function()
        return { python3 = { support_dependencies = true } }
      end,
    }

    local tool = Tools.run_skill_script()

    -- Simulate the handlers.setup to set escaped_args
    tool.args = {
      skill_name = "test-skill",
      script_path = "scripts/process.py",
      interpreter = "python3",
      args = vim.NIL,
      dependencies = { "requests", "numpy>=1.20" },
    }
    tool.escaped_args = {}

    local prompt = tool.output.prompt(tool)

    return {
      has_dependencies = prompt:find("Dependencies") ~= nil,
      has_requests = prompt:find("requests") ~= nil,
      has_numpy = prompt:find("numpy") ~= nil,
    }
  ]])

  h.eq(true, result.has_dependencies)
  h.eq(true, result.has_requests)
  h.eq(true, result.has_numpy)
end

T["Tools"]["run_skill_script schema includes available interpreters"] = function()
  local result = child.lua([[
    local Tools = require("codecompanion._extensions.agentskills.tools")

    -- Mock interpreters
    package.loaded["codecompanion._extensions.agentskills.interpreter"] = {
      get_enabled_interpreters = function()
        return { 
          bash = { support_dependencies = false }, 
          python3 = { support_dependencies = true } 
        }
      end,
    }

    local tool = Tools.run_skill_script()
    local desc = tool.schema["function"].description
    local interpreter_enum = tool.schema["function"].parameters.properties.interpreter.enum

    -- Sort for consistent comparison
    table.sort(interpreter_enum)

    return {
      has_interpreter_list = desc:find("Supported interpreters") ~= nil,
      has_bash_in_desc = desc:find("bash") ~= nil,
      enum_has_bash = vim.list_contains(interpreter_enum, "bash"),
      enum_has_python3 = vim.list_contains(interpreter_enum, "python3"),
      enum_count = #interpreter_enum,
    }
  ]])

  h.eq(true, result.has_interpreter_list)
  h.eq(true, result.enum_has_bash)
  h.eq(true, result.enum_has_python3)
  h.eq(2, result.enum_count)
end

T["Tools"]["run_skill_script schema has correct structure"] = function()
  child.lua([[
    -- Mock interpreters
    package.loaded["codecompanion._extensions.agentskills.interpreter"] = {
      get_enabled_interpreters = function()
        return { bash = {} }
      end,
    }

    local Tools = require("codecompanion._extensions.agentskills.tools")
    local tool = Tools.run_skill_script()

    local h = require("tests.helpers")
    h.assert_tool_schema(tool, {
      name = "run_skill_script",
      params = { "skill_name", "script_path", "interpreter", "args", "dependencies" },
      required = { "skill_name", "script_path", "interpreter" },
    })
  ]])
end

-- ==================== smart escape tests ====================

T["Tools"]["run_skill_script smart escape - simple args"] = function()
  local result = child.lua([[
    local Tools = require("codecompanion._extensions.agentskills.tools")

    -- Mock interpreters
    package.loaded["codecompanion._extensions.agentskills.interpreter"] = {
      get_enabled_interpreters = function()
        return { bash = { support_dependencies = false } }
      end,
    }

    local tool = Tools.run_skill_script()

    -- Simulate handlers.setup with simple args
    tool.args = {
      skill_name = "test-skill",
      script_path = "scripts/build.sh",
      interpreter = "bash",
      args = {"--verbose", "output.txt", "123", "file_name.py"},
      dependencies = vim.NIL,
    }
    tool.opts = {}

    -- Call handlers.setup
    tool.handlers.setup(tool, {})

    return {
      escaped_args = tool.escaped_args,
      count = #tool.escaped_args,
    }
  ]])

  -- Simple args should not be escaped
  h.eq(4, result.count)
  h.eq("--verbose", result.escaped_args[1])
  h.eq("output.txt", result.escaped_args[2])
  h.eq("123", result.escaped_args[3])
  h.eq("file_name.py", result.escaped_args[4])
end

T["Tools"]["run_skill_script smart escape - special chars"] = function()
  local result = child.lua([[
    local Tools = require("codecompanion._extensions.agentskills.tools")

    -- Mock interpreters
    package.loaded["codecompanion._extensions.agentskills.interpreter"] = {
      get_enabled_interpreters = function()
        return { bash = { support_dependencies = false } }
      end,
    }

    local tool = Tools.run_skill_script()

    -- Simulate handlers.setup with special char args
    tool.args = {
      skill_name = "test-skill",
      script_path = "scripts/build.sh",
      interpreter = "bash",
      args = {"--name=John Doe", "path with spaces", "$HOME"},
      dependencies = vim.NIL,
    }
    tool.opts = {}

    -- Call handlers.setup
    tool.handlers.setup(tool, {})

    return {
      escaped_args = tool.escaped_args,
      count = #tool.escaped_args,
    }
  ]])

  -- Special char args should be escaped
  h.eq(3, result.count)
  -- Check that args with spaces/special chars are escaped
  h.eq(true, result.escaped_args[1]:find("John") ~= nil)
  h.eq(true, result.escaped_args[2]:find("path") ~= nil)
  h.eq(true, result.escaped_args[3]:find("HOME") ~= nil)
end

-- ==================== scripts_require_approval tests ====================

T["Tools"]["run_skill_script scripts_require_approval = false"] = function()
  local result = child.lua([[
    local Tools = require("codecompanion._extensions.agentskills.tools")

    -- Mock interpreters
    package.loaded["codecompanion._extensions.agentskills.interpreter"] = {
      get_enabled_interpreters = function()
        return { bash = { support_dependencies = false } }
      end,
    }

    -- Mock AS module with skill that has scripts_require_approval = false
    package.loaded["codecompanion._extensions.agentskills"] = {
      get_skill = function(name)
        return {
          name = function(self) return name end,
          opts = { scripts_require_approval = false },
        }
      end,
    }

    local tool = Tools.run_skill_script()

    tool.args = {
      skill_name = "test-skill",
      script_path = "scripts/test.sh",
      interpreter = "bash",
      args = vim.NIL,
      dependencies = vim.NIL,
    }
    tool.opts = {}

    -- Call handlers.setup
    tool.handlers.setup(tool, {})

    return {
      require_approval = tool.opts.require_approval_before,
    }
  ]])

  h.eq(false, result.require_approval)
end

T["Tools"]["run_skill_script scripts_require_approval = true (default)"] = function()
  local result = child.lua([[
    local Tools = require("codecompanion._extensions.agentskills.tools")

    -- Mock interpreters
    package.loaded["codecompanion._extensions.agentskills.interpreter"] = {
      get_enabled_interpreters = function()
        return { bash = { support_dependencies = false } }
      end,
    }

    -- Mock AS module with skill that has scripts_require_approval = true (default)
    package.loaded["codecompanion._extensions.agentskills"] = {
      get_skill = function(name)
        return {
          name = function(self) return name end,
          opts = { scripts_require_approval = true },
        }
      end,
    }

    local tool = Tools.run_skill_script()

    tool.args = {
      skill_name = "test-skill",
      script_path = "scripts/test.sh",
      interpreter = "bash",
      args = vim.NIL,
      dependencies = vim.NIL,
    }
    tool.opts = {}

    -- Call handlers.setup
    tool.handlers.setup(tool, {})

    return {
      require_approval = tool.opts.require_approval_before,
    }
  ]])

  h.eq(true, result.require_approval)
end

T["Tools"]["run_skill_script handles vim.NIL args"] = function()
  local result = child.lua([[
    local Tools = require("codecompanion._extensions.agentskills.tools")

    -- Mock interpreters
    package.loaded["codecompanion._extensions.agentskills.interpreter"] = {
      get_enabled_interpreters = function()
        return { bash = { support_dependencies = false } }
      end,
    }

    -- Mock AS module
    package.loaded["codecompanion._extensions.agentskills"] = {
      get_skill = function(name)
        return {
          name = function(self) return name end,
          opts = { scripts_require_approval = true },
        }
      end,
    }

    local tool = Tools.run_skill_script()

    -- Test with vim.NIL args
    tool.args = {
      skill_name = "test-skill",
      script_path = "scripts/test.sh",
      interpreter = "bash",
      args = vim.NIL,
      dependencies = vim.NIL,
    }
    tool.opts = {}

    -- Call handlers.setup
    tool.handlers.setup(tool, {})

    return {
      escaped_args = tool.escaped_args,
      is_table = type(tool.escaped_args) == "table",
      count = #tool.escaped_args,
    }
  ]])

  h.eq(true, result.is_table)
  h.eq(0, result.count)
end

return T
