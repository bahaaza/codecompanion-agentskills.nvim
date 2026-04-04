-- Test helpers for mini.test
local Helpers = {}

-- Extend with expectations
Helpers = vim.tbl_extend("error", Helpers, require("tests.expectations"))

---Start a child Neovim process for testing
---@param child table MiniTest child neovim instance
function Helpers.child_start(child)
  child.restart({ "-u", "tests/minimal_init.lua" })
  child.o.statusline = ""
  child.o.laststatus = 0
  child.o.cmdheight = 0
end

---Setup codecompanion in child process
---@param child table
---@param config? table Optional config overrides to merge with base test config
function Helpers.setup_codecompanion(child, config)
  config = config or {}
  child.lua(
    [[
    local overrides = ...
    local config = require("tests.config")
    if overrides and next(overrides) ~= nil then
      config = vim.tbl_deep_extend("force", config, overrides)
    end
    require("codecompanion").setup(config)
  ]],
    { config }
  )
end

---Setup agentskills extension in child process
---@param child table
---@param opts? table agentskills options
function Helpers.setup_agentskills(child, opts)
  opts = opts or {}
  child.lua(
    [[
    local opts = ...
    local config = require("tests.config")
    config.extensions = config.extensions or {}
    config.extensions.agentskills = vim.tbl_deep_extend("force", 
      config.extensions.agentskills or {}, 
      { opts = opts }
    )
    require("codecompanion").setup(config)
  ]],
    { opts }
  )
end

---Create a temporary directory
---@return string path
function Helpers.temp_dir()
  local path = vim.fn.tempname()
  vim.fn.mkdir(path, "p")
  return path
end

---Clean up a directory
---@param path string
function Helpers.cleanup_dir(path)
  if path and vim.uv.fs_stat(path) then
    vim.fn.delete(path, "rf")
  end
end

---Create a test skill directory with SKILL.md
---@param base_dir string Base directory to create skill in
---@param name string Skill name
---@param skill_md_content string Content for SKILL.md
---@param extra_files? table<string, string> Additional files to create {relative_path: content}
---@return string skill_dir Path to created skill directory
function Helpers.create_test_skill(base_dir, name, skill_md_content, extra_files)
  local skill_dir = vim.fs.joinpath(base_dir, name)
  vim.fn.mkdir(skill_dir, "p")

  -- Create SKILL.md
  local skill_md = vim.fs.joinpath(skill_dir, "SKILL.md")
  vim.fn.writefile(vim.split(skill_md_content, "\n"), skill_md)

  -- Create extra files if provided
  if extra_files then
    for rel_path, content in pairs(extra_files) do
      local file_path = vim.fs.joinpath(skill_dir, rel_path)
      local parent = vim.fs.dirname(file_path)
      vim.fn.mkdir(parent, "p")
      vim.fn.writefile(vim.split(content, "\n"), file_path)
    end
  end

  return skill_dir
end

---Create a minimal valid SKILL.md content
---@param name string Skill name
---@param description string Skill description
---@param body? string Optional body content
---@return string content
function Helpers.make_skill_md(name, description, body)
  local content = string.format(
    [[---
name: %s
description: %s
---
%s]],
    name,
    description,
    body or ""
  )
  return content
end

---Mock vim.fn.executable for testing command availability
---@param available_commands table<string, boolean> Commands that should return 1 (available)
---@return function restore
function Helpers.mock_executable(available_commands)
  local original_executable = vim.fn.executable

  ---@diagnostic disable-next-line: duplicate-set-field
  vim.fn.executable = function(cmd)
    if available_commands[cmd] then
      return 1
    end
    return 0
  end

  return function()
    vim.fn.executable = original_executable
  end
end

---Mock vim.system for testing
---@param responses table[] Array of response tables {code: number, stdout: string, stderr: string}
---@return function restore, table calls
function Helpers.mock_vim_system(responses)
  local call_count = 0
  local calls_made = {}
  local original_system = vim.system

  ---@diagnostic disable-next-line: duplicate-set-field
  vim.system = function(cmd, opts, callback)
    call_count = call_count + 1
    table.insert(calls_made, { cmd = cmd, opts = opts })

    local response = responses[call_count] or { code = 0, stdout = "", stderr = "" }

    if callback then
      vim.schedule(function()
        callback(response)
      end)
      return {}
    else
      return {
        wait = function()
          return response
        end,
      }
    end
  end

  return function()
    vim.system = original_system
  end, calls_made
end

---Wait for a condition to be true
---@param condition function Condition to check
---@param timeout? number Timeout in milliseconds (default 1000)
---@param interval? number Check interval in milliseconds (default 50)
---@return boolean success
function Helpers.wait_for(condition, timeout, interval)
  timeout = timeout or 1000
  interval = interval or 50
  local start = vim.uv.hrtime() / 1e6

  while (vim.uv.hrtime() / 1e6) - start < timeout do
    if condition() then
      return true
    end
    vim.wait(interval)
  end

  return false
end

return Helpers
