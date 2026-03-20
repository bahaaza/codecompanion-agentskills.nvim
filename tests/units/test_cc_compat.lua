-- Tests for lua/codecompanion/_extensions/agentskills/cc_compat.lua
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

T["CCCompat.decorate_tool"] = new_set({
  hooks = {
    pre_case = function()
      child.lua([[package.loaded["codecompanion._extensions.agentskills.cc_compat"] = nil]])
    end,
  },
})

T["CCCompat.decorate_tool"]["returns original function for v19+"] = function()
  local result = child.lua([[
    local CCCompat = require("codecompanion._extensions.agentskills.cc_compat")
    
    local call_count = 0
    local original_tool = function()
      call_count = call_count + 1
      return { name = "test_tool", call_count = call_count }
    end
    
    local decorated = CCCompat.decorate_tool(original_tool, 19)
    
    -- For v19+, should return the exact same function
    local is_same = decorated == original_tool
    
    -- Verify it still works
    local tool = decorated()
    
    return {
      is_same_function = is_same,
      tool_name = tool.name,
      call_count = tool.call_count,
    }
  ]])

  h.eq(true, result.is_same_function)
  h.eq("test_tool", result.tool_name)
  h.eq(1, result.call_count)
end

T["CCCompat.decorate_tool"]["returns original function for v20+"] = function()
  local result = child.lua([[
    local CCCompat = require("codecompanion._extensions.agentskills.cc_compat")
    
    local original_tool = function()
      return { name = "test_tool" }
    end
    
    local decorated = CCCompat.decorate_tool(original_tool, 20)
    
    return {
      is_same_function = decorated == original_tool,
    }
  ]])

  h.eq(true, result.is_same_function)
end

T["CCCompat.decorate_tool"]["adapts output.success signature for v18"] = function()
  local result = child.lua([[
    local CCCompat = require("codecompanion._extensions.agentskills.cc_compat")
    
    local v19_success_args = nil
    local original_tool = function()
      return {
        name = "test_tool",
        output = {
          success = function(self, output, meta)
            v19_success_args = {
              has_self = self ~= nil,
              output = output,
              meta = meta,
            }
            return "success_result"
          end,
        },
      }
    end
    
    local decorated = CCCompat.decorate_tool(original_tool, 18)
    local tool = decorated()
    
    -- Call v18 signature: success(self, tools, cmd, output)
    local ret = tool.output.success("self_val", "tools_val", "cmd_val", "output_val")
    
    return {
      return_value = ret,
      captured_args = v19_success_args,
    }
  ]])

  h.eq("success_result", result.return_value)
  h.eq(true, result.captured_args.has_self)
  h.eq("output_val", result.captured_args.output)
  h.eq("tools_val", result.captured_args.meta.tools)
end

T["CCCompat.decorate_tool"]["adapts output.error signature for v18"] = function()
  local result = child.lua([[
    local CCCompat = require("codecompanion._extensions.agentskills.cc_compat")
    
    local v19_error_args = nil
    local original_tool = function()
      return {
        name = "test_tool",
        output = {
          error = function(self, output, meta)
            v19_error_args = {
              has_self = self ~= nil,
              output = output,
              meta = meta,
            }
            return "error_result"
          end,
        },
      }
    end
    
    local decorated = CCCompat.decorate_tool(original_tool, 18)
    local tool = decorated()
    
    -- Call v18 signature: error(self, tools, cmd, output)
    local ret = tool.output.error("self_val", "tools_val", "cmd_val", "error_output")
    
    return {
      return_value = ret,
      captured_args = v19_error_args,
    }
  ]])

  h.eq("error_result", result.return_value)
  h.eq(true, result.captured_args.has_self)
  h.eq("error_output", result.captured_args.output)
  h.eq("tools_val", result.captured_args.meta.tools)
end

T["CCCompat.decorate_tool"]["adapts output.prompt signature for v18"] = function()
  local result = child.lua([[
    local CCCompat = require("codecompanion._extensions.agentskills.cc_compat")
    
    local v19_prompt_self = nil
    local original_tool = function()
      return {
        name = "test_tool",
        output = {
          prompt = function(self)
            v19_prompt_self = self
            return "prompt_result"
          end,
        },
      }
    end
    
    local decorated = CCCompat.decorate_tool(original_tool, 18)
    local tool = decorated()
    
    -- Call v18 signature: prompt(self, tools)
    local ret = tool.output.prompt("self_val", "tools_val")
    
    return {
      return_value = ret,
      captured_self = v19_prompt_self,
    }
  ]])

  h.eq("prompt_result", result.return_value)
  h.eq("self_val", result.captured_self)
end

T["CCCompat.decorate_tool"]["adapts cmds output_cb for v18"] = function()
  local result = child.lua([[
    local CCCompat = require("codecompanion._extensions.agentskills.cc_compat")
    
    local captured_opts = nil
    local original_tool = function()
      return {
        name = "test_tool",
        cmds = {
          function(self, args, opts)
            captured_opts = opts
            -- Simulate calling the output callback
            if opts.output_cb then
              opts.output_cb({ code = 0, stdout = "test output" })
            end
            return "cmd_result"
          end,
        },
      }
    end
    
    local decorated = CCCompat.decorate_tool(original_tool, 18)
    local tool = decorated()
    
    -- Track what output_handler receives
    local handler_result = nil
    local output_handler = function(result)
      handler_result = result
    end
    
    -- Call v18 signature: cmd(self, args, input, output_handler)
    local ret = tool.cmds[1]("self_val", "args_val", "input_val", output_handler)
    
    return {
      return_value = ret,
      has_output_cb = captured_opts ~= nil and captured_opts.output_cb ~= nil,
      handler_result = handler_result,
    }
  ]])

  h.eq("cmd_result", result.return_value)
  h.eq(true, result.has_output_cb)
  h.eq(0, result.handler_result.code)
  h.eq("test output", result.handler_result.stdout)
end

T["CCCompat.decorate_tool"]["handles tool without output for v18"] = function()
  local result = child.lua([[
    local CCCompat = require("codecompanion._extensions.agentskills.cc_compat")
    
    local original_tool = function()
      return {
        name = "test_tool",
        -- No output field
      }
    end
    
    local decorated = CCCompat.decorate_tool(original_tool, 18)
    local tool = decorated()
    
    return {
      name = tool.name,
      has_output = tool.output ~= nil,
    }
  ]])

  h.eq("test_tool", result.name)
  h.eq(false, result.has_output)
end

T["CCCompat.decorate_tool"]["handles tool without cmds for v18"] = function()
  local result = child.lua([[
    local CCCompat = require("codecompanion._extensions.agentskills.cc_compat")
    
    local original_tool = function()
      return {
        name = "test_tool",
        output = {
          success = function() return "ok" end,
        },
        -- No cmds field
      }
    end
    
    local decorated = CCCompat.decorate_tool(original_tool, 18)
    local tool = decorated()
    
    return {
      name = tool.name,
      has_cmds = tool.cmds ~= nil,
    }
  ]])

  h.eq("test_tool", result.name)
  h.eq(false, result.has_cmds)
end

T["CCCompat.decorate_tool"]["handles tool with empty cmds array for v18"] = function()
  local result = child.lua([[
    local CCCompat = require("codecompanion._extensions.agentskills.cc_compat")
    
    local original_tool = function()
      return {
        name = "test_tool",
        cmds = {}, -- Empty array
      }
    end
    
    local decorated = CCCompat.decorate_tool(original_tool, 18)
    local tool = decorated()
    
    return {
      name = tool.name,
      cmds_count = #tool.cmds,
    }
  ]])

  h.eq("test_tool", result.name)
  h.eq(0, result.cmds_count)
end

return T
