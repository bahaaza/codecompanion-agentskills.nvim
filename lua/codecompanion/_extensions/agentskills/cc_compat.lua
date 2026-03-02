local CCCompat = {}

---Decorate a tool definition factory to adapt callback signatures for different CodeCompanion versions.
---@param tool_fn fun(): table The tool constructor function
---@param version number CodeCompanion version number
---@return fun(): table Returns a function that returns the adapted tool definition when called
function CCCompat.decorate_tool(tool_fn, version)
  -- v19 doesn't need adaptation, return the original function
  if version >= 19 then
    return tool_fn
  end

  -- v18: return decorated tool definition
  return function()
    local tool = tool_fn()

    -- Adapt output.success: v19(self, output, meta) -> v18(self, tools, cmd, output)
    if tool.output and tool.output.success then
      local v19_success = tool.output.success
      tool.output.success = function(self, tools, cmd, output)
        return v19_success(self, output, { tools = tools })
      end
    end

    -- Adapt output.error: v19(self, output, meta) -> v18(self, tools, cmd, output)
    if tool.output and tool.output.error then
      local v19_error = tool.output.error
      tool.output.error = function(self, tools, cmd, output)
        return v19_error(self, output, { tools = tools })
      end
    end

    -- Adapt output.prompt: v19(self) -> v18(self, tools)
    if tool.output and tool.output.prompt then
      local v19_prompt = tool.output.prompt
      tool.output.prompt = function(self, tools)
        return v19_prompt(self)
      end
    end

    -- Adapt cmds: opts.output_cb -> output_handler
    if tool.cmds and tool.cmds[1] then
      local v19_cmd = tool.cmds[1]
      tool.cmds[1] = function(self, args, input, output_handler)
        local opts = {
          output_cb = function(result)
            output_handler(result)
          end,
        }
        return v19_cmd(self, args, opts)
      end
    end

    return tool
  end
end

return CCCompat
