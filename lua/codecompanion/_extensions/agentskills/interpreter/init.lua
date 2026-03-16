local log = require("codecompanion.utils.log")

local M = {}

---@class CodeCompanion.AgentSkills.InterpreterHandler
---@field support_dependencies boolean
---@field check_available fun(self: CodeCompanion.AgentSkills.InterpreterHandler): boolean
---@field run fun(self: CodeCompanion.AgentSkills.InterpreterHandler, script_path: string, args: string[], skill: CodeCompanion.AgentSkills.Skill, dependencies?: string[], callback: fun(ok: boolean, output: string))

---@class CodeCompanion.AgentSkills.InterpreterEntry
---@field handler CodeCompanion.AgentSkills.InterpreterHandler
---@field enabled boolean? nil=unchecked, true=available, false=unavailable

---@type table<string, CodeCompanion.AgentSkills.InterpreterEntry>
local handlers = {}

---@param name string
---@param handler CodeCompanion.AgentSkills.InterpreterHandler
local function register(name, handler)
  handlers[name] = { handler = handler }
end

---@param opts table<string, table> interpreter config, e.g. { python3 = { ... } }
function M.setup(opts)
  local Python3Interpreter = require("codecompanion._extensions.agentskills.interpreter.python3")
  local SimpleInterpreter = require("codecompanion._extensions.agentskills.interpreter.simple")
  register("python3", Python3Interpreter.new(opts and opts.python3 or {}))
  register("node", SimpleInterpreter.new("node"))
  register("bash", SimpleInterpreter.new("bash"))
end

---@return table<string, CodeCompanion.AgentSkills.InterpreterHandler>
function M.get_enabled_interpreters()
  local result = {}
  for name, entry in pairs(handlers) do
    if entry.enabled == nil then
      entry.enabled = entry.handler:check_available()
      log:info(
        entry.enabled and "Interpreter '%s' is enabled"
          or "Interpreter '%s' is disabled (not available)",
        name
      )
    end
    if entry.enabled then
      result[name] = entry.handler
    end
  end
  return result
end

---@param interpreter string
---@param skill CodeCompanion.AgentSkills.Skill
---@param script_path string
---@param args string[]
---@param dependencies? string[]
---@param callback fun(ok: boolean, output: string)
function M.run(interpreter, skill, script_path, args, dependencies, callback)
  local entry = handlers[interpreter]
  if not entry then
    callback(false, string.format("Interpreter '%s' is not registered", interpreter))
    return
  end

  if entry.enabled == nil then
    entry.enabled = entry.handler:check_available()
  end

  if not entry.enabled then
    callback(
      false,
      string.format("Interpreter '%s' is not available in current environment", interpreter)
    )
    return
  end

  entry.handler:run(script_path, args, skill, dependencies, callback)
end

return M
