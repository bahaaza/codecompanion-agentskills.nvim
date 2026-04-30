-- Tests for lua/codecompanion/_extensions/agentskills/init.lua
local h = require("tests.helpers")
local new_set = MiniTest.new_set
local child = MiniTest.new_child_neovim()

local T = new_set({
  hooks = {
    pre_once = function()
      h.child_start(child)
    end,
    post_once = child.stop,
  },
})

-- Helper to restart child and setup fresh environment
local function setup_fresh(opts)
  opts = opts or {}
  child.restart({ "-u", "tests/minimal_init.lua" })
  child.o.statusline = ""
  child.o.laststatus = 0
  child.o.cmdheight = 0

  -- Store opts in global variable
  child.env.AGENTSKILLS_OPTS = vim.json.encode(opts)

  -- Setup with test configuration
  child.lua([[
    local opts = vim.json.decode(vim.env.AGENTSKILLS_OPTS or "{}")
    local config = require("tests.config")
    config.extensions = config.extensions or {}
    config.extensions.agentskills = {
      enabled = true,
      opts = opts,
    }
    require("codecompanion").setup(config)
  ]])
end

T["Extension.setup"] = new_set()

T["Extension.setup"]["discovers skills from configured paths"] = function()
  local temp_dir = h.temp_dir()
  local skill_md = h.make_skill_md("discovered-skill", "A discovered skill", "# Discovered")
  h.create_test_skill(temp_dir, "discovered-skill", skill_md)

  setup_fresh({ paths = { temp_dir }, disable_demo_skill = true })

  child.lua([[
    local AS = require("codecompanion._extensions.agentskills")
    local skills = AS.get_skills()
    _G.test_result = skills and skills["discovered-skill"] ~= nil
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq(true, result)

  h.cleanup_dir(temp_dir)
end

T["Extension.setup"]["handles recursive path scanning"] = function()
  local temp_dir = h.temp_dir()

  -- Create nested skill structure
  local skill1_md = h.make_skill_md("nested-skill-1", "First nested skill", "# Nested 1")
  h.create_test_skill(temp_dir, "level1/nested-skill-1", skill1_md)

  local skill2_md = h.make_skill_md("nested-skill-2", "Second nested skill", "# Nested 2")
  h.create_test_skill(temp_dir, "level1/level2/nested-skill-2", skill2_md)

  -- Use { path = ..., recursive = true } format for JSON compatibility
  setup_fresh({ paths = { { path = temp_dir, recursive = true } }, disable_demo_skill = true })

  child.lua([[
    local AS = require("codecompanion._extensions.agentskills")
    local skills = AS.get_skills()
    _G.test_result = {
      has_skill1 = skills and skills["nested-skill-1"] ~= nil,
      has_skill2 = skills and skills["nested-skill-2"] ~= nil,
    }
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq(true, result.has_skill1)
  h.eq(true, result.has_skill2)

  h.cleanup_dir(temp_dir)
end

T["Extension.setup"]["ignores hidden directories (starting with .)"] = function()
  local temp_dir = h.temp_dir()

  -- Create visible skill
  local visible_md = h.make_skill_md("visible-skill", "Visible skill", "# Visible")
  h.create_test_skill(temp_dir, "visible-skill", visible_md)

  -- Create hidden skill (should be ignored)
  local hidden_md = h.make_skill_md("hidden-skill", "Hidden skill", "# Hidden")
  h.create_test_skill(temp_dir, ".hidden-skill", hidden_md)

  -- Create skill in hidden directory (should be ignored)
  h.create_test_skill(temp_dir, ".hidden-dir/hidden-dir-skill", hidden_md)

  -- Use { path = ..., recursive = true } format for JSON compatibility
  setup_fresh({ paths = { { path = temp_dir, recursive = true } }, disable_demo_skill = true })

  child.lua([[
    local AS = require("codecompanion._extensions.agentskills")
    local skills = AS.get_skills() or {}
    _G.test_result = {
      has_visible = skills["visible-skill"] ~= nil,
      has_hidden = skills["hidden-skill"] ~= nil,
      has_hidden_dir = skills["hidden-dir-skill"] ~= nil,
    }
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq(true, result.has_visible)
  h.eq(false, result.has_hidden)
  h.eq(false, result.has_hidden_dir)

  h.cleanup_dir(temp_dir)
end

T["Extension.setup"]["loads demo-skill by default"] = function()
  setup_fresh({ paths = {}, disable_demo_skill = false })

  child.lua([[
    local AS = require("codecompanion._extensions.agentskills")
    local skills = AS.get_skills()
    _G.test_result = skills and skills["demo-skill"] ~= nil
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq(true, result)
end

T["Extension.setup"]["respects disable_demo_skill option"] = function()
  setup_fresh({ paths = {}, disable_demo_skill = true })

  child.lua([[
    local AS = require("codecompanion._extensions.agentskills")
    local skills = AS.get_skills()
    _G.test_result = skills and skills["demo-skill"] ~= nil
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq(false, result)
end

T["Extension.setup"]["registers tools with codecompanion config"] = function()
  setup_fresh({ paths = {}, disable_demo_skill = true })

  child.lua([[
    local tools_config = require("codecompanion.config").interactions.chat.tools
    _G.test_result = {
      has_activate_skill = tools_config.activate_skill ~= nil,
      has_load_skill_file = tools_config.load_skill_file ~= nil,
      has_run_skill_script = tools_config.run_skill_script ~= nil,
      has_agent_skills_group = tools_config.groups and tools_config.groups.agent_skills ~= nil,
    }
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq(true, result.has_activate_skill)
  h.eq(true, result.has_load_skill_file)
  h.eq(true, result.has_run_skill_script)
  h.eq(true, result.has_agent_skills_group)
end

T["Extension.get_skills"] = new_set()

T["Extension.get_skills"]["returns discovered skills table"] = function()
  local temp_dir = h.temp_dir()
  local skill_md = h.make_skill_md("get-skills-test", "Test get_skills", "# Test")
  h.create_test_skill(temp_dir, "get-skills-test", skill_md)

  setup_fresh({ paths = { temp_dir }, disable_demo_skill = true })

  child.lua([[
    local AS = require("codecompanion._extensions.agentskills")
    local skills = AS.get_skills()
    local names = {}
    for name, _ in pairs(skills or {}) do
      table.insert(names, name)
    end
    table.sort(names)
    _G.test_result = names
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq({ "get-skills-test" }, result)

  h.cleanup_dir(temp_dir)
end

T["Extension.get_skill"] = new_set()

T["Extension.get_skill"]["returns skill by name"] = function()
  local temp_dir = h.temp_dir()
  local skill_md = h.make_skill_md("get-skill-test", "Test get_skill", "# Test")
  h.create_test_skill(temp_dir, "get-skill-test", skill_md)

  setup_fresh({ paths = { temp_dir }, disable_demo_skill = true })

  child.lua([[
    local AS = require("codecompanion._extensions.agentskills")
    local skill = AS.get_skill("get-skill-test")
    if skill then
      _G.test_result = {
        name = skill:name(),
        description = skill:description(),
      }
    else
      _G.test_result = nil
    end
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq("get-skill-test", result.name)
  h.eq("Test get_skill", result.description)

  h.cleanup_dir(temp_dir)
end

T["Extension.get_skill"]["returns nil for unknown skill"] = function()
  setup_fresh({ paths = {}, disable_demo_skill = true })

  child.lua([[
    local AS = require("codecompanion._extensions.agentskills")
    local result = AS.get_skill("non-existent-skill")
    _G.test_result = result == nil
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq(true, result)
end

T["Extension.get_opts"] = new_set()

T["Extension.get_opts"]["returns current configuration"] = function()
  setup_fresh({
    paths = { "/custom/path" },
    ignore_dirs = { "node_modules", ".git" },
    disable_demo_skill = true,
    skill_opts = { ["test-skill"] = { scripts_require_approval = false } },
  })

  child.lua([[
    local AS = require("codecompanion._extensions.agentskills")
    local opts = AS.get_opts()
    _G.test_result = {
      has_paths = opts.paths ~= nil,
      has_ignore_dirs = opts.ignore_dirs ~= nil,
      has_skill_opts = opts.skill_opts ~= nil,
      ignore_dirs_has_node_modules = vim.list_contains(opts.ignore_dirs, "node_modules"),
      skill_opts_has_test = opts.skill_opts and opts.skill_opts["test-skill"] ~= nil,
    }
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq(true, result.has_paths)
  h.eq(true, result.has_ignore_dirs)
  h.eq(true, result.has_skill_opts)
  h.eq(true, result.ignore_dirs_has_node_modules)
  h.eq(true, result.skill_opts_has_test)
end

T["Extension.get_opts"]["returns default values when not configured"] = function()
  setup_fresh({ paths = {}, disable_demo_skill = true })

  child.lua([[
    local AS = require("codecompanion._extensions.agentskills")
    local opts = AS.get_opts()
    _G.test_result = {
      paths_is_table = type(opts.paths) == "table",
      ignore_dirs_is_table = type(opts.ignore_dirs) == "table",
      disable_demo_skill = opts.disable_demo_skill,
    }
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq(true, result.paths_is_table)
  h.eq(true, result.ignore_dirs_is_table)
  h.eq(true, result.disable_demo_skill)
end

T["Extension.setup"]["respects ignore_dirs configuration"] = function()
  local temp_dir = h.temp_dir()

  -- Create skill in normal directory
  local normal_md = h.make_skill_md("normal-skill", "Normal skill", "# Normal")
  h.create_test_skill(temp_dir, "normal-skill", normal_md)

  -- Create skill in node_modules (should be ignored)
  local ignored_md = h.make_skill_md("ignored-skill", "Ignored skill", "# Ignored")
  h.create_test_skill(temp_dir, "node_modules/ignored-skill", ignored_md)

  -- Create skill in build directory (should be ignored)
  h.create_test_skill(temp_dir, "build/another-ignored-skill", ignored_md)

  setup_fresh({
    paths = { { path = temp_dir, recursive = true } },
    ignore_dirs = { "node_modules", "build" },
    disable_demo_skill = true,
  })

  child.lua([[
    local AS = require("codecompanion._extensions.agentskills")
    local skills = AS.get_skills() or {}
    _G.test_result = {
      has_normal = skills["normal-skill"] ~= nil,
      has_ignored = skills["ignored-skill"] ~= nil,
      has_another_ignored = skills["another-ignored-skill"] ~= nil,
    }
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq(true, result.has_normal)
  h.eq(false, result.has_ignored)
  h.eq(false, result.has_another_ignored)

  h.cleanup_dir(temp_dir)
end

T["Extension.setup"]["scans all directories when ignore_dirs is empty"] = function()
  local temp_dir = h.temp_dir()

  -- Create skill in normal directory
  local normal_md = h.make_skill_md("all-skill", "All skill", "# All")
  h.create_test_skill(temp_dir, "subdir/all-skill", normal_md)

  setup_fresh({
    paths = { { path = temp_dir, recursive = true } },
    ignore_dirs = {}, -- Empty ignore_dirs
    disable_demo_skill = true,
  })

  child.lua([[
    local AS = require("codecompanion._extensions.agentskills")
    local skills = AS.get_skills() or {}
    _G.test_result = skills["all-skill"] ~= nil
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq(true, result)

  h.cleanup_dir(temp_dir)
end

T["Extension.setup"]["passes skill_opts to loaded skills"] = function()
  local temp_dir = h.temp_dir()
  local skill_md = h.make_skill_md("opts-test-skill", "Test skill opts", "# Test")
  h.create_test_skill(temp_dir, "opts-test-skill", skill_md)

  setup_fresh({
    paths = { temp_dir },
    disable_demo_skill = true,
    skill_opts = {
      ["opts-test-skill"] = {
        scripts_require_approval = false,
      },
    },
  })

  child.lua([[
    local AS = require("codecompanion._extensions.agentskills")
    local skill = AS.get_skill("opts-test-skill")
    _G.test_result = {
      has_opts = skill and skill.opts ~= nil,
      scripts_require_approval = skill and skill.opts and skill.opts.scripts_require_approval,
    }
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq(true, result.has_opts)
  h.eq(false, result.scripts_require_approval)

  h.cleanup_dir(temp_dir)
end

T["Extension.setup"]["uses default opts for skills without custom opts"] = function()
  local temp_dir = h.temp_dir()
  local skill_md = h.make_skill_md("default-opts-skill", "Test default opts", "# Test")
  h.create_test_skill(temp_dir, "default-opts-skill", skill_md)

  setup_fresh({
    paths = { temp_dir },
    disable_demo_skill = true,
    -- No skill_opts configured for default-opts-skill
  })

  child.lua([[
    local AS = require("codecompanion._extensions.agentskills")
    local skill = AS.get_skill("default-opts-skill")
    _G.test_result = {
      has_opts = skill and skill.opts ~= nil,
      scripts_require_approval = skill and skill.opts and skill.opts.scripts_require_approval,
    }
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq(true, result.has_opts)
  h.eq(true, result.scripts_require_approval) -- Default is true

  h.cleanup_dir(temp_dir)
end

T["Extension.setup"]["configures script_interpreters"] = function()
  setup_fresh({
    paths = {},
    disable_demo_skill = true,
    script_interpreters = {
      python3 = { prefer_uv = false },
    },
  })

  child.lua([[
    local interpreter = require("codecompanion._extensions.agentskills.interpreter")
    local enabled = interpreter.get_enabled_interpreters()
    _G.test_result = {
      has_python3 = enabled["python3"] ~= nil,
      has_bash = enabled["bash"] ~= nil,
      has_node = enabled["node"] ~= nil,
    }
  ]])
  local result = child.lua_get("_G.test_result")

  -- Verify interpreters are registered
  h.eq(true, result.has_bash)
  h.eq(true, result.has_node)
  -- python3 may not be available if python3 is not installed
end

-- Editor Context Tests
T["editor_context"] = new_set()

T["editor_context"]["setup registers skills as editor_context"] = function()
  local temp_dir = h.temp_dir()
  local skill_md = h.make_skill_md("test-skill", "Test skill for editor_context", "# Test Skill Content")
  h.create_test_skill(temp_dir, "test-skill", skill_md)

  setup_fresh({ paths = { temp_dir }, disable_demo_skill = true })

  child.lua([[
    local config = require("codecompanion.config")
    local editor_context = config.interactions.shared.editor_context
    _G.test_result = {
      has_test_skill = editor_context["skill:test-skill"] ~= nil,
    }
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq(true, result.has_test_skill)

  h.cleanup_dir(temp_dir)
end

T["editor_context"]["setup registers multiple skills"] = function()
  local temp_dir = h.temp_dir()
  local skill1_md = h.make_skill_md("skill-one", "First skill", "# Skill One")
  h.create_test_skill(temp_dir, "skill-one", skill1_md)
  local skill2_md = h.make_skill_md("skill-two", "Second skill", "# Skill Two")
  h.create_test_skill(temp_dir, "skill-two", skill2_md)

  setup_fresh({ paths = { temp_dir }, disable_demo_skill = true })

  child.lua([[
    local config = require("codecompanion.config")
    local editor_context = config.interactions.shared.editor_context
    _G.test_result = {
      has_skill_one = editor_context["skill:skill-one"] ~= nil,
      has_skill_two = editor_context["skill:skill-two"] ~= nil,
    }
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq(true, result.has_skill_one)
  h.eq(true, result.has_skill_two)

  h.cleanup_dir(temp_dir)
end

T["editor_context"]["demo-skill is registered by default"] = function()
  setup_fresh({ paths = {}, disable_demo_skill = false })

  child.lua([[
    local config = require("codecompanion.config")
    local editor_context = config.interactions.shared.editor_context
    _G.test_result = editor_context["skill:demo-skill"] ~= nil
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq(true, result)
end

T["editor_context"]["demo-skill is not registered when disabled"] = function()
  setup_fresh({ paths = {}, disable_demo_skill = true })

  child.lua([[
    local config = require("codecompanion.config")
    local editor_context = config.interactions.shared.editor_context
    _G.test_result = editor_context["skill:demo-skill"] ~= nil
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq(false, result)
end

T["editor_context"]["callback returns SKILL.md content"] = function()
  local temp_dir = h.temp_dir()
  local skill_md = h.make_skill_md("callback-test", "Callback test skill", "# Callback Test Content\n\nThis is test content.")
  h.create_test_skill(temp_dir, "callback-test", skill_md)

  setup_fresh({ paths = { temp_dir }, disable_demo_skill = true })

  child.lua([[
    local config = require("codecompanion.config")
    local editor_context = config.interactions.shared.editor_context
    local ctx_config = editor_context["skill:callback-test"]
    if ctx_config and ctx_config.callback then
    local ctx = { config = { name = "skill:callback-test" } }
      _G.test_result = ctx_config.callback(ctx)
    else
      _G.test_result = nil
    end
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq(true, result ~= nil)
  h.eq(true, result:find('<agent%-skill name="callback%-test">') ~= nil, "Should have opening tag")
  h.eq(true, result:find("Callback Test Content") ~= nil, "Should contain skill content")
  h.eq(true, result:find('</agent%-skill>') ~= nil, "Should have closing tag")

  h.cleanup_dir(temp_dir)
end

T["editor_context"]["callback returns error for non-existent skill"] = function()
  local temp_dir = h.temp_dir()
  local skill_md = h.make_skill_md("existing-skill", "Existing skill", "# Existing")
  h.create_test_skill(temp_dir, "existing-skill", skill_md)

  setup_fresh({ paths = { temp_dir }, disable_demo_skill = true })

  child.lua([[
    local config = require("codecompanion.config")
    local editor_context = config.interactions.shared.editor_context
    local callback = editor_context["skill:existing-skill"].callback
    local ctx = { config = { name = "skill:non-existent" } }
    _G.test_result = callback(ctx)
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq("Skill not found: non-existent", result)

  h.cleanup_dir(temp_dir)
end

T["editor_context"]["register_editor_contexts clears old registrations"] = function()
  local temp_dir1 = h.temp_dir()
  local skill_md1 = h.make_skill_md("old-skill", "Old skill", "# Old")
  h.create_test_skill(temp_dir1, "old-skill", skill_md1)

  setup_fresh({ paths = { temp_dir1 }, disable_demo_skill = true })

  -- Verify old-skill is registered
  child.lua([[
    local config = require("codecompanion.config")
    local editor_context = config.interactions.shared.editor_context
    _G.test_result_before = editor_context["skill:old-skill"] ~= nil
  ]])
  local result_before = child.lua_get("_G.test_result_before")
  h.eq(true, result_before)

  -- Now discover new skills (without old-skill)
  local temp_dir2 = h.temp_dir()
  local skill_md2 = h.make_skill_md("new-skill", "New skill", "# New")
  h.create_test_skill(temp_dir2, "new-skill", skill_md2)

  child.lua([[
    local AS = require("codecompanion._extensions.agentskills")
    local opts = {
      paths = { ... },
      disable_demo_skill = true,
    }
    AS.setup(opts)
  ]], { temp_dir2 })

  -- Verify old-skill is removed and new-skill is registered
  child.lua([[
    local config = require("codecompanion.config")
    local editor_context = config.interactions.shared.editor_context
    _G.test_result_after = {
      has_old = editor_context["skill:old-skill"] ~= nil,
      has_new = editor_context["skill:new-skill"] ~= nil,
    }
  ]])
  local result_after = child.lua_get("_G.test_result_after")

  h.eq(false, result_after.has_old)
  h.eq(true, result_after.has_new)

  h.cleanup_dir(temp_dir1)
  h.cleanup_dir(temp_dir2)
end

T["editor_context"]["description is set correctly"] = function()
  local temp_dir = h.temp_dir()
  local skill_md = h.make_skill_md("desc-test", "Description test skill", "# Desc Test")
  h.create_test_skill(temp_dir, "desc-test", skill_md)

  setup_fresh({ paths = { temp_dir }, disable_demo_skill = true })

  child.lua([[
    local config = require("codecompanion.config")
    local editor_context = config.interactions.shared.editor_context
    local AS = require("codecompanion._extensions.agentskills")
    local skill = AS.get_skill("desc-test")
    local ctx_config = editor_context["skill:desc-test"]
    _G.test_result = {
      has_description = ctx_config and ctx_config.description ~= nil,
      description_matches = ctx_config and skill and ctx_config.description == skill:description(),
    }
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq(true, result.has_description)
  h.eq(true, result.description_matches)

  h.cleanup_dir(temp_dir)
end

T["editor_context"]["opts.contains_code is false"] = function()
  local temp_dir = h.temp_dir()
  local skill_md = h.make_skill_md("opts-test", "Opts test skill", "# Opts Test")
  h.create_test_skill(temp_dir, "opts-test", skill_md)

  setup_fresh({ paths = { temp_dir }, disable_demo_skill = true })

  child.lua([[
    local config = require("codecompanion.config")
    local editor_context = config.interactions.shared.editor_context
    local ctx_config = editor_context["skill:opts-test"]
    _G.test_result = ctx_config and ctx_config.opts and ctx_config.opts.contains_code
  ]])
  local result = child.lua_get("_G.test_result")

  h.eq(false, result)

  h.cleanup_dir(temp_dir)
end

return T
