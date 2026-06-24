local log = require("codecompanion.utils.log")

---@class CodeCompanion.AgentSkills.Python3InterpreterConfig
---@field prefer_uv boolean prefer uv over pip (default true)
---@field python_cmd string Python command name (default "python3")
---@field default_venv_path string Default virtual environment path

---@class CodeCompanion.AgentSkills.Python3Interpreter : CodeCompanion.AgentSkills.InterpreterHandler
---@field support_dependencies boolean
---@field config CodeCompanion.AgentSkills.Python3InterpreterConfig
local Python3Interpreter = {}
Python3Interpreter.__index = Python3Interpreter

---@param opts? CodeCompanion.AgentSkills.Python3InterpreterConfig
---@return CodeCompanion.AgentSkills.Python3Interpreter
function Python3Interpreter.new(opts)
  local default_venv =
    vim.fs.joinpath(vim.fn.stdpath("cache"), "codecompanion_agentskills", "python_venv")
  return setmetatable({
    support_dependencies = true,
    config = vim.tbl_deep_extend("force", {
      prefer_uv = true,
      python_cmd = "python3",
      default_venv_path = default_venv,
    }, opts or {}),
  }, Python3Interpreter)
end

local function is_cmd_available(cmd)
  return vim.fn.executable(cmd) == 1
end

function Python3Interpreter:check_available()
  return is_cmd_available("uv") or is_cmd_available(self.config.python_cmd)
end

local function get_venv_path(skill, config)
  if skill.meta.metadata and skill.meta.metadata.codecompanion_py_venv_path then
    return skill.meta.metadata.codecompanion_py_venv_path
  end
  return config.default_venv_path
end

local function should_use_uv(config)
  return config.prefer_uv and is_cmd_available("uv")
end

local function run_cmd(cmd, success_msg, error_msg, callback)
  log:info("Running command: %s", cmd)
  vim.system(
    cmd,
    { stdout = true, stderr = true },
    vim.schedule_wrap(function(out)
      if out.code == 0 then
        log:info(success_msg)
        callback(true)
      else
        local msg = string.format(error_msg, out.stderr or "unknown error")
        log:error(msg)
        callback(false, msg)
      end
    end)
  )
end

local function ensure_venv(venv_path, config, callback)
  local python_path = vim.fs.joinpath(venv_path, "bin", "python")
  if vim.uv.fs_stat(python_path) then
    callback(true)
    return
  end

  local cmd, success_msg, error_msg
  if should_use_uv(config) then
    cmd = { "uv", "venv", venv_path }
    success_msg = string.format("Python virtual environment created with uv at %s", venv_path)
    error_msg = "Failed to create Python virtual environment with uv: %s"
  else
    if not is_cmd_available(config.python_cmd) then
      callback(false, "Neither 'uv' nor 'python3' is available")
      return
    end
    cmd = { config.python_cmd, "-m", "venv", venv_path }
    success_msg = string.format("Python virtual environment created with python3 at %s", venv_path)
    error_msg = "Failed to create Python virtual environment with python3: %s"
  end

  run_cmd(cmd, success_msg, error_msg, callback)
end

local function install_dependencies(venv_path, dependencies, config, callback)
  if not dependencies or #dependencies == 0 then
    callback(true)
    return
  end

  local python_path = vim.fs.joinpath(venv_path, "bin", "python")
  local cmd, success_msg, error_msg
  if should_use_uv(config) then
    cmd = { "uv", "pip", "install", "--python", python_path }
    success_msg = "Python dependencies installed with uv: " .. table.concat(dependencies, ", ")
    error_msg = "Failed to install Python dependencies with uv: %s"
  else
    cmd = { python_path, "-m", "pip", "install" }
    success_msg = "Python dependencies installed with pip: " .. table.concat(dependencies, ", ")
    error_msg = "Failed to install Python dependencies with pip: %s"
  end

  vim.list_extend(cmd, dependencies)
  run_cmd(cmd, success_msg, error_msg, callback)
end

---@param script_path string
---@param args string[]
---@param skill CodeCompanion.AgentSkills.Skill
---@param dependencies? string[]
---@param callback fun(ok: boolean, output: string)
function Python3Interpreter:run(script_path, args, skill, dependencies, callback)
  local config = self.config
  local venv_path = get_venv_path(skill, config)

  ensure_venv(venv_path, config, function(ok, err)
    if not ok then
      callback(false, err or "Failed to ensure Python virtual environment exists")
      return
    end

    install_dependencies(venv_path, dependencies, config, function(ok, err)
      if not ok then
        callback(false, err or "Failed to install Python dependencies")
        return
      end

      local python_path = vim.fs.joinpath(venv_path, "bin", "python")
      local cmd = { python_path, script_path }
      vim.list_extend(cmd, args)

      log:info("Running Python script: %s", cmd)
      local env = {
        PYTHONPATH = string.format("%s:%s", skill.path, vim.env.PYTHONPATH or ""),
      }
      vim.system(cmd, { env = env, stdout = true, stderr = true }, function(out)
        log:info("Python script exited with code %d", out.code)
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
    end)
  end)
end

return Python3Interpreter
