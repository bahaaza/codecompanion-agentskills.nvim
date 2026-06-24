-- Tests for lua/codecompanion/_extensions/agentskills/skill.lua
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

T["Skill.load"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[package.loaded["codecompanion._extensions.agentskills.skill"] = nil]])
    end,
  },
})

T["Skill.load"]["parses valid SKILL.md with YAML frontmatter"] = function()
  local temp_dir = h.temp_dir()
  local skill_md = h.make_skill_md(
    "test-skill",
    "A test skill for unit testing",
    "# Test Skill\n\nThis is a test."
  )
  h.create_test_skill(temp_dir, "test-skill", skill_md)

  -- Use environment variable to pass temp_dir
  child.env.TEST_TEMP_DIR = temp_dir
  child.lua([[
    local temp_dir = vim.env.TEST_TEMP_DIR
    local Skill = require("codecompanion._extensions.agentskills.skill")
    local skill = Skill.load(temp_dir .. "/test-skill")
    _G.test_result = {
      name = skill:name(),
      description = skill:description(),
      path = skill.path,
    }
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq("test-skill", result.name)
  h.eq("A test skill for unit testing", result.description)
  h.expect_contains("test-skill", result.path)

  h.cleanup_dir(temp_dir)
end

T["Skill.load"]["errors on missing YAML frontmatter"] = function()
  local temp_dir = h.temp_dir()
  -- Create skill without YAML frontmatter
  h.create_test_skill(temp_dir, "no-frontmatter", "# Test Skill\n\nNo frontmatter here.")

  h.expect.error(function()
    child.lua(
      [[
      local temp_dir = ...
      local Skill = require("codecompanion._extensions.agentskills.skill")
      Skill.load(temp_dir .. "/no-frontmatter")
    ]],
      { temp_dir }
    )
  end)

  h.cleanup_dir(temp_dir)
end

T["Skill.load"]["errors on invalid YAML syntax"] = function()
  local temp_dir = h.temp_dir()
  local invalid_yaml = [[---
name: [invalid yaml
description: missing closing bracket
---
# Test]]
  h.create_test_skill(temp_dir, "invalid-yaml", invalid_yaml)

  h.expect.error(function()
    child.lua(
      [[
      local temp_dir = ...
      local Skill = require("codecompanion._extensions.agentskills.skill")
      Skill.load(temp_dir .. "/invalid-yaml")
    ]],
      { temp_dir }
    )
  end)

  h.cleanup_dir(temp_dir)
end

T["Skill.load"]["handles skill with metadata"] = function()
  local temp_dir = h.temp_dir()
  local skill_md = [[---
name: meta-skill
description: Skill with metadata
metadata:
  codecompanion_py_venv_path: /custom/venv/path
---
# Meta Skill]]
  h.create_test_skill(temp_dir, "meta-skill", skill_md)

  local result = child.lua(
    [[
    local temp_dir = ...
    local Skill = require("codecompanion._extensions.agentskills.skill")
    local skill = Skill.load(temp_dir .. "/meta-skill")
    return skill.meta
  ]],
    { temp_dir }
  )

  h.eq("meta-skill", result.name)
  h.eq("Skill with metadata", result.description)
  h.eq("/custom/venv/path", result.metadata.codecompanion_py_venv_path)

  h.cleanup_dir(temp_dir)
end

T["Skill:read_file"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[package.loaded["codecompanion._extensions.agentskills.skill"] = nil]])
    end,
  },
})

T["Skill:read_file"]["reads file within skill directory"] = function()
  local temp_dir = h.temp_dir()
  local skill_md = h.make_skill_md("read-skill", "Test read file", "# Read Test")
  h.create_test_skill(temp_dir, "read-skill", skill_md, {
    ["references/usage.md"] = "# Usage\n\nThis is usage documentation.",
  })

  local result = child.lua(
    [[
    local temp_dir = ...
    local Skill = require("codecompanion._extensions.agentskills.skill")
    local skill = Skill.load(temp_dir .. "/read-skill")
    return skill:read_file("references/usage.md")
  ]],
    { temp_dir }
  )

  h.expect_contains("Usage", result)
  h.expect_contains("usage documentation", result)

  h.cleanup_dir(temp_dir)
end

T["Skill:read_file"]["errors on path traversal attempt"] = function()
  local temp_dir = h.temp_dir()
  local skill_md = h.make_skill_md("traversal-skill", "Test path traversal", "# Test")
  h.create_test_skill(temp_dir, "traversal-skill", skill_md)

  h.expect.error(function()
    child.lua(
      [[
      local temp_dir = ...
      local Skill = require("codecompanion._extensions.agentskills.skill")
      local skill = Skill.load(temp_dir .. "/traversal-skill")
      skill:read_file("../../../etc/passwd")
    ]],
      { temp_dir }
    )
  end)

  h.cleanup_dir(temp_dir)
end

T["Skill:read_content"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[package.loaded["codecompanion._extensions.agentskills.skill"] = nil]])
    end,
  },
})

T["Skill:read_content"]["returns full SKILL.md content"] = function()
  local temp_dir = h.temp_dir()
  local skill_md =
    h.make_skill_md("content-skill", "Test read content", "# Content Test\n\nSome body content.")
  h.create_test_skill(temp_dir, "content-skill", skill_md)

  local result = child.lua(
    [[
    local temp_dir = ...
    local Skill = require("codecompanion._extensions.agentskills.skill")
    local skill = Skill.load(temp_dir .. "/content-skill")
    return skill:read_content()
  ]],
    { temp_dir }
  )

  h.expect_contains("content-skill", result)
  h.expect_contains("Content Test", result)
  h.expect_contains("Some body content", result)

  h.cleanup_dir(temp_dir)
end

T["Skill:run_script"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[package.loaded["codecompanion._extensions.agentskills.skill"] = nil]])
      child.lua([[package.loaded["codecompanion._extensions.agentskills.interpreter"] = nil]])
    end,
  },
})

T["Skill:run_script"]["replaces ${SKILL_DIR} placeholder in arguments"] = function()
  local temp_dir = h.temp_dir()
  local skill_md = h.make_skill_md("script-skill", "Test script", "# Script Test")
  h.create_test_skill(temp_dir, "script-skill", skill_md, {
    ["scripts/test.sh"] = "#!/bin/bash\necho $1",
  })

  local result = child.lua(
    [[
    local temp_dir = ...
    local Skill = require("codecompanion._extensions.agentskills.skill")
    local skill = Skill.load(temp_dir .. "/script-skill")
    
    -- Test that the placeholder replacement logic works
    local placeholder = Skill.SKILL_DIR_PLACEHOLDER
    local pattern = vim.pesc(placeholder)
    local test_arg = placeholder .. "/some/path"
    local processed = string.gsub(test_arg, pattern, skill.path)
    
    return {
      placeholder = placeholder,
      skill_path = skill.path,
      processed = processed,
    }
  ]],
    { temp_dir }
  )

  h.eq("${SKILL_DIR}", result.placeholder)
  h.expect_contains("script-skill", result.skill_path)
  h.expect_contains("script-skill", result.processed)
  h.eq(false, result.processed:find("${SKILL_DIR}", 1, true) ~= nil)

  h.cleanup_dir(temp_dir)
end

T["Skill.opts"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[package.loaded["codecompanion._extensions.agentskills.skill"] = nil]])
      child.lua([[package.loaded["codecompanion._extensions.agentskills"] = nil]])
    end,
  },
})

T["Skill.opts"]["loads opts from global skill_opts configuration"] = function()
  local temp_dir = h.temp_dir()
  local skill_md = h.make_skill_md("opts-skill", "Test opts", "# Test")
  h.create_test_skill(temp_dir, "opts-skill", skill_md)

  -- Setup with skill_opts
  child.env.TEST_TEMP_DIR = temp_dir
  child.lua([[
    local temp_dir = vim.env.TEST_TEMP_DIR
    
    -- Mock the AS module with skill_opts
    package.loaded["codecompanion._extensions.agentskills"] = {
      get_opts = function()
        return {
          skill_opts = {
            ["opts-skill"] = {
              scripts_require_approval = false,
            },
          },
        }
      end,
    }
    
    local Skill = require("codecompanion._extensions.agentskills.skill")
    local skill = Skill.load(temp_dir .. "/opts-skill")
    
    _G.test_result = {
      has_opts = skill.opts ~= nil,
      scripts_require_approval = skill.opts.scripts_require_approval,
    }
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq(true, result.has_opts)
  h.eq(false, result.scripts_require_approval)

  h.cleanup_dir(temp_dir)
end

T["Skill.opts"]["uses default values when no skill_opts configured"] = function()
  local temp_dir = h.temp_dir()
  local skill_md = h.make_skill_md("default-opts-skill", "Test default", "# Test")
  h.create_test_skill(temp_dir, "default-opts-skill", skill_md)

  child.env.TEST_TEMP_DIR = temp_dir
  child.lua([[
    local temp_dir = vim.env.TEST_TEMP_DIR
    
    -- Mock the AS module without skill_opts for this skill
    package.loaded["codecompanion._extensions.agentskills"] = {
      get_opts = function()
        return { skill_opts = {} }
      end,
    }
    
    local Skill = require("codecompanion._extensions.agentskills.skill")
    local skill = Skill.load(temp_dir .. "/default-opts-skill")
    
    _G.test_result = {
      has_opts = skill.opts ~= nil,
      scripts_require_approval = skill.opts.scripts_require_approval,
    }
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq(true, result.has_opts)
  h.eq(true, result.scripts_require_approval) -- Default is true

  h.cleanup_dir(temp_dir)
end

T["Skill:run_script with interpreter"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[package.loaded["codecompanion._extensions.agentskills.skill"] = nil]])
      child.lua([[package.loaded["codecompanion._extensions.agentskills.interpreter"] = nil]])
    end,
  },
})

T["Skill:run_script with interpreter"]["calls interpreter.run with correct arguments"] = function()
  local temp_dir = h.temp_dir()
  local skill_md = h.make_skill_md("run-script-skill", "Test run script", "# Test")
  h.create_test_skill(temp_dir, "run-script-skill", skill_md, {
    ["scripts/test.sh"] = "#!/bin/bash\necho test",
  })

  child.env.TEST_TEMP_DIR = temp_dir
  child.lua([[
    local temp_dir = vim.env.TEST_TEMP_DIR
    
    -- Mock interpreter module
    local captured_args = {}
    package.loaded["codecompanion._extensions.agentskills.interpreter"] = {
      run = function(interpreter, skill, script_path, args, dependencies, callback)
        captured_args = {
          interpreter = interpreter,
          script_path = script_path,
          args = args,
          dependencies = dependencies,
        }
        callback(true, "test output")
      end,
    }
    
    local Skill = require("codecompanion._extensions.agentskills.skill")
    local skill = Skill.load(temp_dir .. "/run-script-skill")
    
    local callback_called = false
    skill:run_script("bash", "scripts/test.sh", {"--verbose", "arg1"}, nil, function(ok, output)
      callback_called = true
      _G.callback_result = { ok = ok, output = output }
    end)
    
    _G.test_result = {
      interpreter = captured_args.interpreter,
      has_script_path = captured_args.script_path ~= nil,
      args_count = captured_args.args and #captured_args.args,
      callback_called = callback_called,
    }
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq("bash", result.interpreter)
  h.eq(true, result.has_script_path)
  h.eq(2, result.args_count)
  h.eq(true, result.callback_called)

  h.cleanup_dir(temp_dir)
end

T["Skill:run_script with interpreter"]["passes dependencies to interpreter"] = function()
  local temp_dir = h.temp_dir()
  local skill_md = h.make_skill_md("deps-skill", "Test deps", "# Test")
  h.create_test_skill(temp_dir, "deps-skill", skill_md, {
    ["scripts/test.py"] = "print('test')",
  })

  child.env.TEST_TEMP_DIR = temp_dir
  child.lua([[
    local temp_dir = vim.env.TEST_TEMP_DIR
    
    -- Mock interpreter module
    local captured_deps = nil
    package.loaded["codecompanion._extensions.agentskills.interpreter"] = {
      run = function(interpreter, skill, script_path, args, dependencies, callback)
        captured_deps = dependencies
        callback(true, "test output")
      end,
    }
    
    local Skill = require("codecompanion._extensions.agentskills.skill")
    local skill = Skill.load(temp_dir .. "/deps-skill")
    
    skill:run_script("python3", "scripts/test.py", {}, {"requests", "numpy>=1.20"}, function(ok, output)
      -- callback
    end)
    
    _G.test_result = {
      deps = captured_deps,
      deps_count = captured_deps and #captured_deps,
    }
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq(2, result.deps_count)
  h.eq("requests", result.deps[1])
  h.eq("numpy>=1.20", result.deps[2])

  h.cleanup_dir(temp_dir)
end

T["Skill:run_script with interpreter"]["handles nil args and dependencies"] = function()
  local temp_dir = h.temp_dir()
  local skill_md = h.make_skill_md("nil-args-skill", "Test nil args", "# Test")
  h.create_test_skill(temp_dir, "nil-args-skill", skill_md, {
    ["scripts/test.sh"] = "#!/bin/bash\necho test",
  })

  child.env.TEST_TEMP_DIR = temp_dir
  child.lua([[
    local temp_dir = vim.env.TEST_TEMP_DIR
    
    -- Mock interpreter module
    local captured = {}
    package.loaded["codecompanion._extensions.agentskills.interpreter"] = {
      run = function(interpreter, skill, script_path, args, dependencies, callback)
        captured = {
          args = args,
          dependencies = dependencies,
        }
        callback(true, "test output")
      end,
    }
    
    local Skill = require("codecompanion._extensions.agentskills.skill")
    local skill = Skill.load(temp_dir .. "/nil-args-skill")
    
    skill:run_script("bash", "scripts/test.sh", nil, nil, function(ok, output)
      -- callback
    end)
    
    _G.test_result = {
      args = captured.args,
      dependencies = captured.dependencies,
    }
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq({}, result.args)
  h.eq(nil, result.dependencies)

  h.cleanup_dir(temp_dir)
end

return T
