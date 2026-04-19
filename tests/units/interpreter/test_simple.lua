-- Tests for lua/codecompanion/_extensions/agentskills/interpreter/simple.lua
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

T["SimpleInterpreter"] = new_set({
  hooks = {
    pre_case = function()
      child.lua(
        [[package.loaded["codecompanion._extensions.agentskills.interpreter.simple"] = nil]]
      )
    end,
  },
})

T["SimpleInterpreter"]["check_available returns true when command exists"] = function()
  local result = child.lua([[
    local SimpleInterpreter = require("codecompanion._extensions.agentskills.interpreter.simple")
    local bash_interp = SimpleInterpreter.new("bash")
    
    return {
      cmd = bash_interp.cmd,
      is_available = bash_interp:check_available(),
    }
  ]])

  h.eq("bash", result.cmd)
  h.eq(true, result.is_available)
end

T["SimpleInterpreter"]["check_available returns false when command missing"] = function()
  local result = child.lua([[
    local SimpleInterpreter = require("codecompanion._extensions.agentskills.interpreter.simple")
    local fake_interp = SimpleInterpreter.new("nonexistent_command_xyz123")
    
    return {
      cmd = fake_interp.cmd,
      is_available = fake_interp:check_available(),
    }
  ]])

  h.eq("nonexistent_command_xyz123", result.cmd)
  h.eq(false, result.is_available)
end

T["SimpleInterpreter"]["support_dependencies is false"] = function()
  local result = child.lua([[
    local SimpleInterpreter = require("codecompanion._extensions.agentskills.interpreter.simple")
    local interp = SimpleInterpreter.new("bash")
    
    return {
      support_dependencies = interp.support_dependencies,
    }
  ]])

  h.eq(false, result.support_dependencies)
end

T["SimpleInterpreter"]["run executes command and returns output"] = function()
  local result = child.lua([[
    local SimpleInterpreter = require("codecompanion._extensions.agentskills.interpreter.simple")
    local bash_interp = SimpleInterpreter.new("bash")
    
    -- Create a simple test script
    local temp_file = vim.fn.tempname() .. ".sh"
    vim.fn.writefile({ "#!/bin/bash", "echo 'test output 123'" }, temp_file)
    
    local ok, output
    local callback = function(success, out)
      ok = success
      output = out
    end
    
    bash_interp:run(temp_file, {}, nil, nil, callback)
    
    -- Wait for async callback
    vim.wait(2000, function() return ok ~= nil end)
    
    -- Cleanup
    vim.fn.delete(temp_file)
    
    return {
      success = ok,
      output = output,
    }
  ]])

  h.eq(true, result.success)
  h.expect_contains("test output 123", result.output)
end

T["SimpleInterpreter"]["run handles non-zero exit code"] = function()
  local result = child.lua([[
    local SimpleInterpreter = require("codecompanion._extensions.agentskills.interpreter.simple")
    local bash_interp = SimpleInterpreter.new("bash")
    
    -- Create a script that exits with non-zero code
    local temp_file = vim.fn.tempname() .. ".sh"
    vim.fn.writefile({ "#!/bin/bash", "echo 'error message' >&2", "exit 1" }, temp_file)
    
    local ok, output
    local callback = function(success, out)
      ok = success
      output = out
    end
    
    bash_interp:run(temp_file, {}, nil, nil, callback)
    
    -- Wait for async callback
    vim.wait(2000, function() return ok ~= nil end)
    
    -- Cleanup
    vim.fn.delete(temp_file)
    
    return {
      success = ok,
      output = output,
    }
  ]])

  h.eq(false, result.success)
  h.expect_contains("exited with code 1", result.output)
  h.expect_contains("error message", result.output)
end

T["SimpleInterpreter"]["run errors when dependencies provided"] = function()
  local result = child.lua([[
    local SimpleInterpreter = require("codecompanion._extensions.agentskills.interpreter.simple")
    local bash_interp = SimpleInterpreter.new("bash")
    
    local ok, output
    local callback = function(success, out)
      ok = success
      output = out
    end
    
    bash_interp:run("dummy.sh", {}, nil, { "requests", "numpy" }, callback)
    
    -- This should be synchronous (error case)
    vim.wait(100, function() return ok ~= nil end)
    
    return {
      success = ok,
      output = output,
    }
  ]])

  h.eq(false, result.success)
  h.expect_contains("Dependencies are not supported", result.output)
  h.expect_contains("bash", result.output)
end

T["SimpleInterpreter"]["run passes arguments to script"] = function()
  local result = child.lua([[
    local SimpleInterpreter = require("codecompanion._extensions.agentskills.interpreter.simple")
    local bash_interp = SimpleInterpreter.new("bash")
    
    -- Create a script that echoes its arguments
    local temp_file = vim.fn.tempname() .. ".sh"
    vim.fn.writefile({ "#!/bin/bash", "echo \"Args: $1 $2 $3\"" }, temp_file)
    
    local ok, output
    local callback = function(success, out)
      ok = success
      output = out
    end
    
    bash_interp:run(temp_file, { "arg1", "arg2", "arg3" }, nil, nil, callback)
    
    -- Wait for async callback
    vim.wait(2000, function() return ok ~= nil end)
    
    -- Cleanup
    vim.fn.delete(temp_file)
    
    return {
      success = ok,
      output = output,
    }
  ]])

  h.eq(true, result.success)
  h.expect_contains("arg1 arg2 arg3", result.output)
end

T["SimpleInterpreter"]["new creates instance with correct command"] = function()
  local result = child.lua([[
    local SimpleInterpreter = require("codecompanion._extensions.agentskills.interpreter.simple")
    
    local node_interp = SimpleInterpreter.new("node")
    local bash_interp = SimpleInterpreter.new("bash")
    
    return {
      node_cmd = node_interp.cmd,
      bash_cmd = bash_interp.cmd,
      node_support_deps = node_interp.support_dependencies,
      bash_support_deps = bash_interp.support_dependencies,
    }
  ]])

  h.eq("node", result.node_cmd)
  h.eq("bash", result.bash_cmd)
  h.eq(false, result.node_support_deps)
  h.eq(false, result.bash_support_deps)
end

return T
