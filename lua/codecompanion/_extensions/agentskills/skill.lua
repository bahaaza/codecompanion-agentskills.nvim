local log = require("codecompanion.utils.log")
local yaml = require("codecompanion._extensions.agentskills.3rd.yaml")

local MD_YAML_FRONTMATTER_QUERY =
  vim.treesitter.query.parse("markdown", "(document (minus_metadata) @yaml_frontmatter)")

---@param path string path to the SKILL.md
---@return table<string, any>
local function parse_skill_meta(path)
  local content = vim.fn.readblob(path)
  local md_parser = vim.treesitter.get_string_parser(content, "markdown")
  md_parser:parse()
  local tree = md_parser:trees()[1]
  return vim
    .iter(MD_YAML_FRONTMATTER_QUERY:iter_captures(tree:root()))
    :map(function(capture_id, node)
      if MD_YAML_FRONTMATTER_QUERY.captures[capture_id] ~= "yaml_frontmatter" then
        return
      end
      local yaml_text = vim.treesitter.get_node_text(node, content)
      local ok, meta = pcall(yaml.eval, yaml_text)
      if ok then
        return meta
      end
    end)
    :next()
end

---@class CodeCompanion.AgentSkills.Skill
---@field path string
---@field meta CodeCompanion.AgentSkills.SkillMeta

---@class CodeCompanion.AgentSkills.SkillMeta
---@field name string Skill identifier
---@field description string Describes what the skill does and when to use it
---@field license? string License name or reference to a bundled license file
---@field compatibility? table Environment requirements (system packages, network access, etc.)
---@field metadata? table<string, any> Arbitrary key-value mapping for additional metadata
---@field ["disable-model-invocation"]? boolean When true, skill is only included when explicitly invoked
---@field ["user-invokable"]? boolean Controls whether the skill appears as a slash command (default: true)
---@field ["argument-hint"]? string Hint text shown when the skill is invoked as a slash command
---@field tools? string[] List of tool/tool group names to inject when the skill is activated
local Skill = {
  SKILL_DIR_PLACEHOLDER = "${SKILL_DIR}",
}
Skill.__index = Skill

---@param path string
function Skill.load(path)
  path = vim.fs.normalize(path)
  local meta = parse_skill_meta(vim.fs.joinpath(path, "SKILL.md"))
  if meta == nil then
    error("Failed to parse SKILL.md frontmatter at " .. path)
  end
  return setmetatable({
    path = path,
    meta = meta,
  }, Skill)
end

---@return string
function Skill:name()
  return vim.trim(self.meta.name)
end

---@return string
function Skill:description()
  return vim.trim(self.meta.description)
end

---@return string?
function Skill:license()
  return self.meta.license
end

---@return table?
function Skill:compatibility()
  return self.meta.compatibility
end

---@return table<string, any>?
function Skill:metadata()
  return self.meta.metadata
end

---@return boolean
function Skill:is_auto_invocation_disabled()
  return self.meta["disable-model-invocation"] == true
end

---@return boolean
function Skill:is_user_invokable()
  return self.meta["user-invokable"] ~= false
end

---@return string?
function Skill:argument_hint()
  return self.meta["argument-hint"]
end

---@return string[]
function Skill:tools()
  return self.meta.tools or {}
end

function Skill:_normalize_path_in_skill(path_in_skill)
  local p = vim.fs.normalize(vim.fs.joinpath(self.path, path_in_skill))
  if vim.fs.relpath(self.path, p) == nil then
    error("Attempted to access file outside of skill directory: " .. path_in_skill)
  end
  return p
end

---@return string
function Skill:read_content()
  return self:read_file("SKILL.md")
end

---@param path_in_skill string
---@return string
function Skill:read_file(path_in_skill)
  return vim.fn.readblob(self:_normalize_path_in_skill(path_in_skill))
end

---@param script string
---@param args string[]
---@param callback fun(ok: boolean, output_or_error: string)
function Skill:run_script(script, args, callback)
  local cmd = { self:_normalize_path_in_skill(script) }
  local placeholder_pattern = vim.pesc(self.SKILL_DIR_PLACEHOLDER)
  for _, arg in ipairs(args or {}) do
    arg = string.gsub(arg, placeholder_pattern, self.path)
    table.insert(cmd, arg)
  end
  log:info("Running skill script: %s", cmd)
  vim.system(cmd, {
    stdout = true,
    stderr = true,
  }, function(out)
    log:info("Skill script exited with code %d: %s", out.code, cmd)
    callback = vim.schedule_wrap(callback)
    if out.code == 0 then
      callback(true, out.stdout)
    else
      local msg
      if out.signal and out.signal ~= 0 then
        msg = string.format("Script terminated with signal %d", out.signal)
      else
        msg = string.format("Script exited with code %d", out.code)
      end
      local output = { msg }
      if out.stdout and out.stdout ~= "" then
        table.insert(output, "Standard Output:")
        table.insert(output, out.stdout)
      end
      if out.stderr and out.stderr ~= "" then
        table.insert(output, "Standard Error:")
        table.insert(output, out.stderr)
      end
      callback(false, table.concat(output, "\n"))
    end
  end)
end

return Skill
