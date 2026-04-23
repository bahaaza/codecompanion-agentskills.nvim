local Skill = require("codecompanion._extensions.agentskills.skill")
local log = require("codecompanion.utils.log")

local Extension = {}

---@class CodeCompanion.AgentSkills.Opts
---@field paths (string | { [1]: string, recursive: boolean })[] List of paths to search for skills
---@field ignore_dirs? string[] List of directory names to ignore during skill discovery
---@field script_interpreters? table<string, table> Interpreter-specific configurations
---@field disable_demo_skill? boolean Disable the built-in demo-skill (default: false)
---@field skill_opts? table<string, CodeCompanion.AgentSkills.SkillOpts> Per-skill options

---@type CodeCompanion.AgentSkills.Opts
local current_opts = {
  paths = {},
  ignore_dirs = {},
}

---@type table<string, CodeCompanion.AgentSkills.Skill>?
local skills

---Register all discovered skills as editor context items
local function register_editor_contexts()
  local editor_context = require("codecompanion.config").interactions.shared.editor_context

  -- Clear old skill-* registrations
  for key in pairs(editor_context) do
    if key:match("^skill:") then
      editor_context[key] = nil
    end
  end

  -- Register current skills
  for skill_name, skill in pairs(skills) do
    editor_context["skill:" .. skill_name] = {
      callback = function(ctx)
        local name = ctx.config.name:match("^skill:(.+)$")
        local s = Extension.get_skill(name)
        if not s then
          return "Skill not found: " .. name
        end
        local ok, content = pcall(s.read_content, s)
        if not ok then
          return "Failed to read skill content: " .. content
        end
        return string.format('<agent-skill name="%s">\n%s\n</agent-skill>', name, content)
      end,
      description = skill:description(),
      opts = {
        contains_code = false,
      },
    }
  end
end

local function discover_skills()
  skills = {}
  for _, path_spec in ipairs(current_opts.paths) do
    -- Normalize path specification
    local path, recursive
    if type(path_spec) == "string" then
      path = path_spec
      recursive = false
    else
      path = path_spec[1] or path_spec.path
      recursive = path_spec.recursive or false
    end
    path = vim.fs.normalize(path)

    log:info("Scanning skills in %s", path_spec)
    -- Custom scan to follow symlinked directories
    local function is_dir_or_symlink_dir(p)
      local stat = vim.uv.fs_lstat(p)
      if not stat then
        return false
      end
      if stat.type == "directory" then
        return true
      end
      if stat.type == "link" then
        local target_stat = vim.uv.fs_stat(p)
        return target_stat and target_stat.type == "directory"
      end
      return false
    end

    local function scan_skills(dir, depth, max_depth, result, visited)
      if depth > max_depth then
        return
      end
      local real = vim.uv.fs_realpath(dir)
      if not real or visited[real] then
        return
      end
      visited[real] = true
      if not is_dir_or_symlink_dir(dir) then
        return
      end
      local skill_md = vim.fs.joinpath(dir, "SKILL.md")
      if vim.uv.fs_stat(skill_md) then
        table.insert(result, dir)
      end
      local handle = vim.uv.fs_scandir(dir)
      if not handle then
        return
      end

      while true do
        local name, typ = vim.uv.fs_scandir_next(handle)
        if not name then
          break
        end
        -- Skip hidden directories and commonly ignored directories
        if name:sub(1, 1) ~= "." and not vim.list_contains(current_opts.ignore_dirs, name) then
          local child = vim.fs.joinpath(dir, name)
          if is_dir_or_symlink_dir(child) then
            scan_skills(child, depth + 1, max_depth, result, visited)
          end
        end
      end
    end

    local skill_files = {}
    scan_skills(path, 0, recursive and 99 or 1, skill_files, {})
    log:info("Found skill files: %s", skill_files)

    for _, skill_dir in ipairs(skill_files) do
      local ok, skill = pcall(Skill.load, skill_dir)
      if ok and skill and skill.name then
        skills[skill:name()] = skill
      else
        log:warn("Failed to load skill %s: %s", skill_dir, skill)
      end
    end
  end

  if not current_opts.disable_demo_skill then
    local demo_skill_path = vim.fs.joinpath(
      vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h:h:h"),
      "demo-skill"
    )
    local ok, demo_skill = pcall(Skill.load, demo_skill_path)
    if ok and demo_skill then
      skills[demo_skill:name()] = demo_skill
      log:info("Loaded built-in demo-skill from %s", demo_skill_path)
    else
      log:warn("Failed to load built-in demo-skill from %s: %s", demo_skill_path, demo_skill)
    end
  end

  register_editor_contexts()
end

---@param opts CodeCompanion.AgentSkills.Opts
function Extension.setup(opts)
  current_opts = vim.tbl_deep_extend("force", current_opts, opts or {})

  require("codecompanion._extensions.agentskills.interpreter").setup(
    current_opts.script_interpreters or {}
  )

  -- Detect CodeCompanion version
  local ok, cc = pcall(require, "codecompanion")
  local version = 18
  if ok and cc and cc.version then
    version = tonumber(cc.version():match("^(%d+)")) or 18
  end

  discover_skills()

  -- Apply version compatibility decorator
  local cc_compat = require("codecompanion._extensions.agentskills.cc_compat")
  local tools_module = require("codecompanion._extensions.agentskills.tools")

  local tools_config = require("codecompanion.config").interactions.chat.tools
  tools_config.activate_skill = {
    callback = cc_compat.decorate_tool(tools_module.activate_skill, version),
    visible = false,
  }
  tools_config.load_skill_file = {
    callback = cc_compat.decorate_tool(tools_module.load_skill_file, version),
    visible = false,
  }
  tools_config.run_skill_script = {
    callback = cc_compat.decorate_tool(tools_module.run_skill_script, version),
    visible = false,
  }
  tools_config.groups.agent_skills = {
    description = "Agent Skills",
    tools = { "activate_skill", "load_skill_file", "run_skill_script" },
    opts = { collapse_tools = true },
  }
end

---@return table<string, CodeCompanion.AgentSkills.Skill>?
function Extension.get_skills()
  return skills
end

---@param name string
---@return CodeCompanion.AgentSkills.Skill?
function Extension.get_skill(name)
  return skills and skills[name]
end

---@return CodeCompanion.AgentSkills.Opts
function Extension.get_opts()
  return current_opts
end

Extension.exports = {
  Skill = Skill,
  discover = discover_skills,
  get_skills = Extension.get_skills,
}

return Extension
