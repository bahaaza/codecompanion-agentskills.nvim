local Skill = require("codecompanion._extensions.agentskills.skill")
local log = require("codecompanion.utils.log")
local scandir = require("plenary.scandir")
local tools = require("codecompanion._extensions.agentskills.tools")

local Extension = {}

--- Project-level skill paths (relative to cwd)
local DEFAULT_PROJECT_SKILL_PATHS = {
  ".github/skills",
  ".cursor/skills",
  ".claude/skills",
  ".codex/skills",
  ".agents/skills",
}

--- Personal skill paths (relative to home directory)
local DEFAULT_PERSONAL_SKILL_PATHS = {
  "~/.copilot/skills",
  "~/.cursor/skills",
  "~/.claude/skills",
  "~/.codex/skills",
  "~/.agents/skills",
}

---@class CodeCompanion.AgentSkills.Opts
---@field paths (string | { [1]: string, recursive: boolean })[] Additional paths to search for skills
---@field notify_on_discovery boolean Whether to notify about discovered skills (default: false)

---@type CodeCompanion.AgentSkills.Opts
local current_opts = {
  paths = {},
  notify_on_discovery = false,
}

---@type table<string, CodeCompanion.AgentSkills.Skill>?
local skills

---@return (string | { [1]: string, recursive: boolean })[]
local function get_all_paths()
  local paths = {}

  -- Add project-level default paths (relative to cwd)
  local cwd = vim.fn.getcwd()
  for _, rel_path in ipairs(DEFAULT_PROJECT_SKILL_PATHS) do
    table.insert(paths, vim.fs.joinpath(cwd, rel_path))
  end

  -- Add personal default paths
  for _, path in ipairs(DEFAULT_PERSONAL_SKILL_PATHS) do
    table.insert(paths, path)
  end

  -- Add user-configured paths
  for _, path_spec in ipairs(current_opts.paths) do
    table.insert(paths, path_spec)
  end

  return paths
end

local function discover_skills()
  skills = {}
  for _, path_spec in ipairs(get_all_paths()) do
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

    -- Skip non-existent directories
    if not vim.uv.fs_stat(path) then
      log:debug("Skipping non-existent skill path: %s", path)
      goto continue
    end

    log:info("Scanning skills in %s", path_spec)
    local skill_files = scandir.scan_dir(path, {
      search_pattern = function(dir)
        return vim.uv.fs_stat(vim.fs.joinpath(dir, "SKILL.md")) ~= nil
      end,
      depth = recursive and 99 or 1,
      add_dirs = true,
      only_dirs = true,
      hidden = false,
      respect_gitignore = true,
    })
    log:info("Found skill files: %s", skill_files)

    for _, skill_dir in ipairs(skill_files) do
      local ok, skill = pcall(Skill.load, skill_dir)
      if ok and skill and skill.name then
        skills[skill:name()] = skill
      else
        log:warn("Failed to load skill %s: %s", skill_dir, skill)
      end
    end

    ::continue::
  end

  if current_opts.notify_on_discovery then
    local skill_names = vim.tbl_keys(skills)
    if #skill_names > 0 then
      table.sort(skill_names)
      vim.notify(
        string.format(
          "[AgentSkills] Discovered %d skill(s): %s",
          #skill_names,
          table.concat(skill_names, ", ")
        ),
        vim.log.levels.INFO
      )
    else
      vim.notify("[AgentSkills] No skills discovered", vim.log.levels.WARN)
    end
  end
end

---@param opts CodeCompanion.AgentSkills.Opts
function Extension.setup(opts)
  current_opts = vim.tbl_deep_extend("force", current_opts, opts or {})
  discover_skills()

  local cc_config = require("codecompanion.config")
  local tools_config = cc_config.interactions.chat.tools
  tools_config.activate_skill = {
    callback = tools.activate_skill,
    visible = false,
  }
  tools_config.load_skill_file = {
    callback = tools.load_skill_file,
    visible = false,
  }
  tools_config.run_skill_script = {
    callback = tools.run_skill_script,
    opts = {
      allowed_in_yolo_mode = false,
      require_approval_before = true,
      require_cmd_approval = true,
    },
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

Extension.exports = {
  Skill = Skill,
  discover = discover_skills,
  get_skills = Extension.get_skills,
}

return Extension
