-- Tests for lua/codecompanion/_extensions/agentskills/interpreter/python3.lua
--
-- NOTE: This test uses real Python commands per the mock principle:
-- "Use real local commands, mock third-party dependencies."
-- The venv creation and script execution are intentionally real to ensure
-- correct integration behavior.
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

T["Python3Interpreter"] = new_set({
  hooks = {
    pre_case = function()
      child.lua(
        [[package.loaded["codecompanion._extensions.agentskills.interpreter.python3"] = nil]]
      )
    end,
  },
})

T["Python3Interpreter"]["check_available returns true when uv available"] = function()
  local result = child.lua([[
    local Python3Interpreter = require("codecompanion._extensions.agentskills.interpreter.python3")
    
    -- Mock vim.fn.executable to make uv available, python3 unavailable
    local original_executable = vim.fn.executable
    vim.fn.executable = function(cmd)
      if cmd == "uv" then return 1 end
      if cmd == "python3" then return 0 end
      return original_executable(cmd)
    end
    
    local interp = Python3Interpreter.new()
    local is_available = interp:check_available()
    
    -- Restore
    vim.fn.executable = original_executable
    
    return { is_available = is_available }
  ]])

  h.eq(true, result.is_available)
end

T["Python3Interpreter"]["check_available returns true when python3 available (no uv)"] = function()
  local result = child.lua([[
    local Python3Interpreter = require("codecompanion._extensions.agentskills.interpreter.python3")
    
    -- Mock vim.fn.executable to make python3 available, uv unavailable
    local original_executable = vim.fn.executable
    vim.fn.executable = function(cmd)
      if cmd == "uv" then return 0 end
      if cmd == "python3" then return 1 end
      return original_executable(cmd)
    end
    
    local interp = Python3Interpreter.new()
    local is_available = interp:check_available()
    
    -- Restore
    vim.fn.executable = original_executable
    
    return { is_available = is_available }
  ]])

  h.eq(true, result.is_available)
end

T["Python3Interpreter"]["check_available returns false when neither available"] = function()
  local result = child.lua([[
    local Python3Interpreter = require("codecompanion._extensions.agentskills.interpreter.python3")
    
    -- Mock vim.fn.executable to make both uv and python3 unavailable
    local original_executable = vim.fn.executable
    vim.fn.executable = function(cmd)
      if cmd == "uv" then return 0 end
      if cmd == "python3" then return 0 end
      return original_executable(cmd)
    end
    
    local interp = Python3Interpreter.new()
    local is_available = interp:check_available()
    
    -- Restore
    vim.fn.executable = original_executable
    
    return { is_available = is_available }
  ]])

  h.eq(false, result.is_available)
end

T["Python3Interpreter"]["check_available returns true when both uv and python3 available"] = function()
  local result = child.lua([[
    local Python3Interpreter = require("codecompanion._extensions.agentskills.interpreter.python3")
    
    -- Mock vim.fn.executable to make both uv and python3 available
    local original_executable = vim.fn.executable
    vim.fn.executable = function(cmd)
      if cmd == "uv" then return 1 end
      if cmd == "python3" then return 1 end
      return original_executable(cmd)
    end
    
    local interp = Python3Interpreter.new()
    local is_available = interp:check_available()
    
    -- Restore
    vim.fn.executable = original_executable
    
    return { is_available = is_available }
  ]])

  h.eq(true, result.is_available)
end

T["Python3Interpreter"]["check_available with custom python_cmd checks that command"] = function()
  local result = child.lua([[
    local Python3Interpreter = require("codecompanion._extensions.agentskills.interpreter.python3")
    
    -- Mock vim.fn.executable: uv unavailable, custom python command available
    local original_executable = vim.fn.executable
    vim.fn.executable = function(cmd)
      if cmd == "uv" then return 0 end
      if cmd == "python3.11" then return 1 end
      if cmd == "python3" then return 0 end  -- default python3 not available
      return original_executable(cmd)
    end
    
    local interp = Python3Interpreter.new({ python_cmd = "python3.11" })
    local is_available = interp:check_available()
    
    -- Restore
    vim.fn.executable = original_executable
    
    return { is_available = is_available }
  ]])

  h.eq(true, result.is_available)
end

T["Python3Interpreter"]["support_dependencies is true"] = function()
  local result = child.lua([[
    local Python3Interpreter = require("codecompanion._extensions.agentskills.interpreter.python3")
    local interp = Python3Interpreter.new()
    
    return {
      support_dependencies = interp.support_dependencies,
    }
  ]])

  h.eq(true, result.support_dependencies)
end

T["Python3Interpreter"]["new creates instance with default config"] = function()
  local result = child.lua([[
    local Python3Interpreter = require("codecompanion._extensions.agentskills.interpreter.python3")
    local interp = Python3Interpreter.new()
    
    return {
      prefer_uv = interp.config.prefer_uv,
      python_cmd = interp.config.python_cmd,
      has_default_venv_path = interp.config.default_venv_path ~= nil,
    }
  ]])

  h.eq(true, result.prefer_uv)
  h.eq("python3", result.python_cmd)
  h.eq(true, result.has_default_venv_path)
end

T["Python3Interpreter"]["new accepts custom config"] = function()
  local result = child.lua([[
    local Python3Interpreter = require("codecompanion._extensions.agentskills.interpreter.python3")
    local interp = Python3Interpreter.new({
      prefer_uv = false,
      python_cmd = "python3.11",
      default_venv_path = "/custom/venv/path",
    })
    
    return {
      prefer_uv = interp.config.prefer_uv,
      python_cmd = interp.config.python_cmd,
      default_venv_path = interp.config.default_venv_path,
    }
  ]])

  h.eq(false, result.prefer_uv)
  h.eq("python3.11", result.python_cmd)
  h.eq("/custom/venv/path", result.default_venv_path)
end

T["Python3Interpreter"]["run creates venv if not exists"] = function()
  local result = child.lua([[
    local Python3Interpreter = require("codecompanion._extensions.agentskills.interpreter.python3")
    
    -- Create a temp venv path that doesn't exist
    local temp_venv = vim.fn.tempname() .. "_venv"
    
    local interp = Python3Interpreter.new({
      prefer_uv = false,
      default_venv_path = temp_venv,
    })
    
    -- Check if python3 is available first
    if not interp:check_available() then
      return { skipped = true, reason = "python3 not available" }
    end
    
    -- Create a minimal skill mock
    local skill = {
      path = vim.fn.tempname(),
      meta = { metadata = {} },
    }
    vim.fn.mkdir(skill.path, "p")
    
    -- Create a simple test script
    local script_path = vim.fs.joinpath(skill.path, "test.py")
    vim.fn.writefile({ "print('hello from python')" }, script_path)
    
    local ok, output
    local callback = function(success, out)
      ok = success
      output = out
    end
    
    interp:run(script_path, {}, skill, nil, callback)
    
    -- Wait for async callback
    local waited = vim.wait(30000, function() return ok ~= nil end, 100)
    
    -- Cleanup
    vim.fn.delete(skill.path, "rf")
    vim.fn.delete(temp_venv, "rf")
    
    return {
      success = ok,
      output = output,
      waited = waited,
      skipped = false,
    }
  ]])

  if not result.skipped then
    h.eq(true, result.waited, "Callback should have been called")
    h.eq(true, result.success, "Script should run successfully")
    h.expect_contains("hello from python", result.output)
  end
end

T["Python3Interpreter"]["run reuses existing venv"] = function()
  local result = child.lua([[
    local Python3Interpreter = require("codecompanion._extensions.agentskills.interpreter.python3")
    
    -- Create a temp venv path
    local temp_venv = vim.fn.tempname() .. "_venv"
    
    local interp = Python3Interpreter.new({
      prefer_uv = false,
      default_venv_path = temp_venv,
    })
    
    -- Check if python3 is available first
    if not interp:check_available() then
      return { skipped = true, reason = "python3 not available" }
    end
    
    -- Create a real virtual environment at the temp venv path
    -- Using real Python per mock principle: "Use real local commands"
    local create_result = vim.fn.system({ "python3", "-m", "venv", temp_venv })
    if vim.v.shell_error ~= 0 then
      return { skipped = true, reason = "Failed to create venv: " .. create_result }
    end
    
    -- Create a minimal skill mock
    local skill = {
      path = vim.fn.tempname(),
      meta = { metadata = {} },
    }
    vim.fn.mkdir(skill.path, "p")
    
    -- Create a simple test script
    local script_path = vim.fs.joinpath(skill.path, "test.py")
    vim.fn.writefile({ "print('reused venv')" }, script_path)
    
    local ok, output
    local callback = function(success, out)
      ok = success
      output = out
    end
    
    interp:run(script_path, {}, skill, nil, callback)
    
    -- Wait for async callback
    local waited = vim.wait(30000, function() return ok ~= nil end, 100)
    
    -- Cleanup
    vim.fn.delete(skill.path, "rf")
    vim.fn.delete(temp_venv, "rf")
    
    return {
      success = ok,
      output = output,
      waited = waited,
      skipped = false,
    }
  ]])

  if not result.skipped then
    h.eq(true, result.waited, "Callback should have been called")
    h.eq(true, result.success, "Script should run successfully")
    h.expect_contains("reused venv", result.output)
  end
end

T["Python3Interpreter"]["run installs dependencies"] = function()
  local result = child.lua([[
    local Python3Interpreter = require("codecompanion._extensions.agentskills.interpreter.python3")
    
    -- Create a temp venv path
    local temp_venv = vim.fn.tempname() .. "_venv"
    
    local interp = Python3Interpreter.new({
      prefer_uv = false,
      default_venv_path = temp_venv,
    })
    
    -- Check if python3 is available first
    if not interp:check_available() then
      return { skipped = true, reason = "python3 not available" }
    end
    
    -- Mock vim.system for pip install only (per mock principle: mock third-party deps)
    -- Let other commands (venv creation, python execution) proceed normally
    local orig_system = vim.system
    local system_calls = {}
    
    vim.system = function(cmd, opts, callback)
      table.insert(system_calls, { cmd = vim.deepcopy(cmd), opts = opts })
      
      -- Mock pip/uv install commands
      local cmd_str = table.concat(cmd, " ")
      if cmd_str:match("pip install") or cmd_str:match("uv pip") then
        -- Simulate successful install without network
        local result = { code = 0, stdout = "", stderr = "" }
        if callback then
          callback(result)
          return { wait = function() return result end }
        else
          return { wait = function() return result end }
        end
      end
      
      -- Let other commands (venv creation, python execution) proceed normally
      return orig_system(cmd, opts, callback)
    end
    
    -- Create a minimal skill mock
    local skill = {
      path = vim.fn.tempname(),
      meta = { metadata = {} },
    }
    vim.fn.mkdir(skill.path, "p")
    
    -- Create a test script that prints a message
    -- Note: We don't actually import faker since we mocked the install
    local script_path = vim.fs.joinpath(skill.path, "test_deps.py")
    vim.fn.writefile({ 
      "print('dependencies test')",
    }, script_path)
    
    local ok, output
    local callback = function(success, out)
      ok = success
      output = out
    end
    
    -- Run with a dependency (pip install will be mocked)
    interp:run(script_path, {}, skill, { "faker==40.11.0" }, callback)
    
    -- Wait for async callback
    local waited = vim.wait(30000, function() return ok ~= nil end, 100)
    
    -- Restore vim.system
    vim.system = orig_system
    
    -- Cleanup
    vim.fn.delete(skill.path, "rf")
    vim.fn.delete(temp_venv, "rf")
    
    return {
      success = ok,
      output = output,
      waited = waited,
      skipped = false,
      system_calls = system_calls,
    }
  ]])

  if not result.skipped then
    h.eq(true, result.waited, "Callback should have been called")

    -- Verify that pip install was called with correct package
    local found_pip_install = false
    for _, call in ipairs(result.system_calls) do
      local cmd_str = table.concat(call.cmd, " ")
      if cmd_str:match("pip install") and cmd_str:match("faker==40%.11%.0") then
        found_pip_install = true
        break
      end
    end
    h.eq(true, found_pip_install, "pip install should have been called with faker==40.11.0")
  end
end

T["Python3Interpreter"]["run runs script with correct PYTHONPATH"] = function()
  local result = child.lua([[
    local Python3Interpreter = require("codecompanion._extensions.agentskills.interpreter.python3")
    
    -- Create a temp venv path
    local temp_venv = vim.fn.tempname() .. "_venv"
    
    local interp = Python3Interpreter.new({
      prefer_uv = false,
      default_venv_path = temp_venv,
    })
    
    -- Check if python3 is available first
    if not interp:check_available() then
      return { skipped = true, reason = "python3 not available" }
    end
    
    -- Create a minimal skill mock with a specific path
    local skill_path = vim.fn.tempname() .. "_skill"
    vim.fn.mkdir(skill_path, "p")
    
    local skill = {
      path = skill_path,
      meta = { metadata = {} },
    }
    
    -- Create a test script that prints PYTHONPATH
    local script_path = vim.fs.joinpath(skill_path, "check_path.py")
    vim.fn.writefile({ 
      "import os",
      "import sys",
      "pythonpath = os.environ.get('PYTHONPATH', '')",
      "print('PYTHONPATH:', pythonpath)",
    }, script_path)
    
    local ok, output
    local callback = function(success, out)
      ok = success
      output = out
    end
    
    interp:run(script_path, {}, skill, nil, callback)
    
    -- Wait for async callback
    local waited = vim.wait(30000, function() return ok ~= nil end, 100)
    
    -- Cleanup
    vim.fn.delete(skill_path, "rf")
    vim.fn.delete(temp_venv, "rf")
    
    return {
      success = ok,
      output = output,
      waited = waited,
      skill_path = skill_path,
      skipped = false,
    }
  ]])

  if not result.skipped then
    h.eq(true, result.waited, "Callback should have been called")
    h.eq(true, result.success, "Script should run successfully")
    -- Verify that skill path is in PYTHONPATH
    h.expect_contains(result.skill_path, result.output)
  end
end

T["Python3Interpreter"]["run handles script errors"] = function()
  local result = child.lua([[
    local Python3Interpreter = require("codecompanion._extensions.agentskills.interpreter.python3")
    
    -- Create a temp venv path
    local temp_venv = vim.fn.tempname() .. "_venv"
    
    local interp = Python3Interpreter.new({
      prefer_uv = false,
      default_venv_path = temp_venv,
    })
    
    -- Check if python3 is available first
    if not interp:check_available() then
      return { skipped = true, reason = "python3 not available" }
    end
    
    -- Create a minimal skill mock
    local skill = {
      path = vim.fn.tempname(),
      meta = { metadata = {} },
    }
    vim.fn.mkdir(skill.path, "p")
    
    -- Create a script that raises an error
    local script_path = vim.fs.joinpath(skill.path, "error.py")
    vim.fn.writefile({ 
      "import sys",
      "print('before error', file=sys.stderr)",
      "raise RuntimeError('test error')",
    }, script_path)
    
    local ok, output
    local callback = function(success, out)
      ok = success
      output = out
    end
    
    interp:run(script_path, {}, skill, nil, callback)
    
    -- Wait for async callback
    local waited = vim.wait(30000, function() return ok ~= nil end, 100)
    
    -- Cleanup
    vim.fn.delete(skill.path, "rf")
    vim.fn.delete(temp_venv, "rf")
    
    return {
      success = ok,
      output = output,
      waited = waited,
      skipped = false,
    }
  ]])

  if not result.skipped then
    h.eq(true, result.waited, "Callback should have been called")
    h.eq(false, result.success, "Script should fail")
    h.expect_contains("exited with code", result.output)
  end
end

T["Python3Interpreter"]["run respects custom venv path from skill metadata"] = function()
  local result = child.lua([[
    local Python3Interpreter = require("codecompanion._extensions.agentskills.interpreter.python3")
    
    -- Create a custom venv path
    local custom_venv = vim.fn.tempname() .. "_custom_venv"
    
    local interp = Python3Interpreter.new({
      prefer_uv = false,
    })
    
    -- Check if python3 is available first
    if not interp:check_available() then
      return { skipped = true, reason = "python3 not available" }
    end
    
    -- Create a skill with custom venv path in metadata
    local skill = {
      path = vim.fn.tempname(),
      meta = { 
        metadata = {
          codecompanion_py_venv_path = custom_venv,
        }
      },
    }
    vim.fn.mkdir(skill.path, "p")
    
    -- Create a simple test script
    local script_path = vim.fs.joinpath(skill.path, "test_custom_venv.py")
    vim.fn.writefile({ "print('custom venv test')" }, script_path)
    
    local ok, output
    local callback = function(success, out)
      ok = success
      output = out
    end
    
    interp:run(script_path, {}, skill, nil, callback)
    
    -- Wait for async callback
    local waited = vim.wait(30000, function() return ok ~= nil end, 100)
    
    -- Check if custom venv was created
    local custom_venv_exists = vim.uv.fs_stat(custom_venv) ~= nil
    
    -- Cleanup
    vim.fn.delete(skill.path, "rf")
    vim.fn.delete(custom_venv, "rf")
    
    return {
      success = ok,
      output = output,
      waited = waited,
      custom_venv_exists = custom_venv_exists,
      skipped = false,
    }
  ]])

  if not result.skipped then
    h.eq(true, result.waited, "Callback should have been called")
    h.eq(true, result.success, "Script should run successfully")
    h.eq(true, result.custom_venv_exists, "Custom venv should be created")
  end
end

T["Python3Interpreter"]["run passes arguments to script"] = function()
  local result = child.lua([[
    local Python3Interpreter = require("codecompanion._extensions.agentskills.interpreter.python3")
    
    -- Create a temp venv path
    local temp_venv = vim.fn.tempname() .. "_venv"
    
    local interp = Python3Interpreter.new({
      prefer_uv = false,
      default_venv_path = temp_venv,
    })
    
    -- Check if python3 is available first
    if not interp:check_available() then
      return { skipped = true, reason = "python3 not available" }
    end
    
    -- Create a minimal skill mock
    local skill = {
      path = vim.fn.tempname(),
      meta = { metadata = {} },
    }
    vim.fn.mkdir(skill.path, "p")
    
    -- Create a script that prints arguments
    local script_path = vim.fs.joinpath(skill.path, "args.py")
    vim.fn.writefile({ 
      "import sys",
      "print('Args:', ' '.join(sys.argv[1:]))",
    }, script_path)
    
    local ok, output
    local callback = function(success, out)
      ok = success
      output = out
    end
    
    interp:run(script_path, { "arg1", "arg2", "arg3" }, skill, nil, callback)
    
    -- Wait for async callback
    local waited = vim.wait(30000, function() return ok ~= nil end, 100)
    
    -- Cleanup
    vim.fn.delete(skill.path, "rf")
    vim.fn.delete(temp_venv, "rf")
    
    return {
      success = ok,
      output = output,
      waited = waited,
      skipped = false,
    }
  ]])

  if not result.skipped then
    h.eq(true, result.waited, "Callback should have been called")
    h.eq(true, result.success, "Script should run successfully")
    h.expect_contains("arg1 arg2 arg3", result.output)
  end
end

return T
