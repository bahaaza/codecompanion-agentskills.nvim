local log = require("codecompanion.utils.log")

---@class CodeCompanion.AgentSkills.SimpleInterpreter : CodeCompanion.AgentSkills.InterpreterHandler
---@field cmd string interpreter command
---@field support_dependencies boolean
local SimpleInterpreter = {}
SimpleInterpreter.__index = SimpleInterpreter

---@param cmd string
---@return CodeCompanion.AgentSkills.SimpleInterpreter
function SimpleInterpreter.new(cmd)
  return setmetatable({ cmd = cmd, support_dependencies = false }, SimpleInterpreter)
end

function SimpleInterpreter:check_available()
  return vim.fn.executable(self.cmd) == 1
end

---@param script_path string
---@param args string[]
---@param _skill CodeCompanion.AgentSkills.Skill
---@param dependencies? string[]
---@param callback fun(ok: boolean, output: string)
function SimpleInterpreter:run(script_path, args, _skill, dependencies, callback)
  if dependencies and #dependencies > 0 then
    callback(false, string.format("Dependencies are not supported for '%s' interpreter.", self.cmd))
    return
  end

  local full_cmd = { self.cmd, script_path }
  vim.list_extend(full_cmd, args)

  log:info("Running script with interpreter '%s': %s", self.cmd, full_cmd)
  vim.system(full_cmd, { stdout = true, stderr = true }, function(out)
    log:info("Script exited with code %d: %s", out.code, full_cmd)
    if out.code == 0 then
      callback(true, out.stdout)
    else
      local msg = out.signal
          and out.signal ~= 0
          and string.format("Script terminated with signal %d", out.signal)
        or string.format("Script exited with code %d", out.code)
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

return SimpleInterpreter
