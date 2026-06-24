-- Test helpers for mini.test
local Helpers = {}

-- Extend with expectations
Helpers = vim.tbl_extend("error", Helpers, require("tests.expectations"))

---Start a child Neovim process for testing
---@param child table MiniTest child neovim instance
function Helpers.child_start(child)
  child.restart({ "-u", "tests/minimal_init.lua" })
  child.o.statusline = ""
  child.o.laststatus = 0
  child.o.cmdheight = 0
end

---Setup codecompanion in child process
---@param child table
---@param config? table Optional config overrides to merge with base test config
function Helpers.setup_codecompanion(child, config)
  config = config or {}
  child.lua(
    [[
    local overrides = ...
    local config = require("tests.config")
    if overrides and next(overrides) ~= nil then
      config = vim.tbl_deep_extend("force", config, overrides)
    end
    require("codecompanion").setup(config)
  ]],
    { config }
  )
end

---Create a temporary directory
---@return string path
function Helpers.temp_dir()
  local path = vim.fn.tempname()
  vim.fn.mkdir(path, "p")
  return path
end

---Clean up a directory
---@param path string
function Helpers.cleanup_dir(path)
  if path and vim.uv.fs_stat(path) then
    vim.fn.delete(path, "rf")
  end
end

---Create a test skill directory with SKILL.md
---@param base_dir string Base directory to create skill in
---@param name string Skill name
---@param skill_md_content string Content for SKILL.md
---@param extra_files? table<string, string> Additional files to create {relative_path: content}
---@return string skill_dir Path to created skill directory
function Helpers.create_test_skill(base_dir, name, skill_md_content, extra_files)
  local skill_dir = vim.fs.joinpath(base_dir, name)
  vim.fn.mkdir(skill_dir, "p")

  -- Create SKILL.md
  local skill_md = vim.fs.joinpath(skill_dir, "SKILL.md")
  vim.fn.writefile(vim.split(skill_md_content, "\n"), skill_md)

  -- Create extra files if provided
  if extra_files then
    for rel_path, content in pairs(extra_files) do
      local file_path = vim.fs.joinpath(skill_dir, rel_path)
      local parent = vim.fs.dirname(file_path)
      vim.fn.mkdir(parent, "p")
      vim.fn.writefile(vim.split(content, "\n"), file_path)
    end
  end

  return skill_dir
end

---Create a minimal valid SKILL.md content
---@param name string Skill name
---@param description string Skill description
---@param body? string Optional body content
---@return string content
function Helpers.make_skill_md(name, description, body)
  local content = string.format(
    [[---
name: %s
description: %s
---
%s]],
    name,
    description,
    body or ""
  )
  return content
end

---Assert tool schema structure
---@param tool table Tool definition
---@param expected table Expected values: { name, params?, required? }
function Helpers.assert_tool_schema(tool, expected)
  Helpers.eq(expected.name, tool.name)
  Helpers.eq(true, tool.schema ~= nil)
  Helpers.eq("function", tool.schema.type)
  Helpers.eq(expected.name, tool.schema["function"].name)

  if expected.params then
    for _, param in ipairs(expected.params) do
      Helpers.eq(true, tool.schema["function"].parameters.properties[param] ~= nil,
        "Expected parameter: " .. param)
    end
  end

  if expected.required then
    for _, param in ipairs(expected.required) do
      Helpers.eq(true, vim.list_contains(tool.schema["function"].parameters.required, param),
        "Expected required parameter: " .. param)
    end
  end
end

---Setup mock HTTP client in child process
---@param child table MiniTest child neovim instance
---@param adapter? string Adapter variable name in child process (default: "_G.mock_adapter")
---@return nil
function Helpers.mock_http(child, adapter)
  adapter = adapter or "_G.mock_adapter"
  -- Get the project root directory to construct absolute path
  -- require("tests.mocks.http") replaces ? with "tests/mocks/http"
  -- So the pattern needs to be: deps/codecompanion.nvim/?.lua
  local project_root = vim.fn.getcwd()
  local cc_path_lua = project_root .. "/deps/codecompanion.nvim/?.lua"
  local cc_path_init = project_root .. "/deps/codecompanion.nvim/?/init.lua"

  child.lua(string.format(
    [[
    -- Add CodeCompanion root to package.path so tests.mocks.http can be found
    package.path = package.path .. ";" .. %q .. ";" .. %q

    local mock_client = require("tests.mocks.http").new({ adapter = %s })
    _G.mock_client = mock_client
    package.loaded["codecompanion.http"] = {
      new = function()
        return _G.mock_client
      end,
    }
  ]],
    cc_path_lua,
    cc_path_init,
    adapter
  ))
end

---Queue a mock HTTP response
---@param child table MiniTest child neovim instance
---@param response table The response to queue
---@return nil
function Helpers.queue_mock_http_response(child, response)
  child.lua([[_G.mock_client:queue_response(...)]], { response })
end

---Setup a chat buffer with agentskills tools for integration testing
---@param child table MiniTest child neovim instance
---@param opts? table Optional config: { skills?: table, temp_dir?: string, ... }
---  skills: table of skill name -> skill definition
---    Each skill can have: description, content (SKILL.md body), opts (skill opts like scripts_require_approval),
---    files (table mapping relative_path -> content)
---  temp_dir: optional temp directory path (will be created if not provided)
---@return string chat_var The variable name where chat is stored ("_G._test_chat")
function Helpers.setup_chat_with_agentskills(child, opts)
  opts = opts or {}
  local skills_input = opts.skills or {}

  -- Create temp directory for skills
  local temp_dir = opts.temp_dir or Helpers.temp_dir()

  -- Collect skill_opts from skill definitions
  local skill_opts = {}

  -- Create real skill files in temp directory
  for skill_name, skill_def in pairs(skills_input) do
    local skill_md_content = Helpers.make_skill_md(
      skill_name,
      skill_def.description or ("Test skill: " .. skill_name),
      skill_def.content or ""
    )
    Helpers.create_test_skill(temp_dir, skill_name, skill_md_content, skill_def.files)

    -- Collect opts for this skill
    if skill_def.opts then
      skill_opts[skill_name] = skill_def.opts
    end
  end

  -- Define adapter inline in child process (functions can't be serialized across process boundary)
  child.lua([[
    local temp_dir, skill_opts = ...

    -- Define custom adapter with parse_chat handler for tool_calls
    local adapter = {
      name = "test_adapter_for_agentskills",
      formatted_name = "Test Adapter for AgentSkills",
      type = "http",
      url = "http://test.local",
      roles = { llm = "assistant", user = "user" },
      features = { tools = true },
      opts = { stream = false },
      schema = { model = { default = "test-model" } },
      handlers = {
        response = {
          parse_chat = function(self, data, tools)
            for _, tool in ipairs(data.tools or {}) do
              table.insert(tools, tool)
            end
            return {
              status = "success",
              output = { role = "assistant", content = data.content or "" },
            }
          end,
        },
        tools = {
          format_calls = function(self, tools)
            return tools
          end,
          format_response = function(self, tool_call, output)
            return {
              role = "tool",
              tools = { call_id = tool_call.id },
              content = output,
              _meta = { tag = tool_call.id },
              opts = { visible = false },
            }
          end,
        },
      },
    }

    -- Setup CodeCompanion with agentskills extension
    local config = require("tests.config")
    config.adapters.http[adapter.name] = adapter
    -- Configure agentskills to use temp directory
    config.extensions = config.extensions or {}
    config.extensions.agentskills = {
      opts = {
        paths = { { temp_dir, recursive = true } },  -- recursive to scan skill subdirectories
        disable_demo_skill = true,  -- Disable demo skill for isolated testing
        skill_opts = skill_opts,  -- Per-skill options (e.g. scripts_require_approval)
      },
    }
    require("codecompanion").setup(config)

    -- Create chat buffer
    local Chat = require("codecompanion.interactions.chat")
    local adapters = require("codecompanion.adapters")
    local resolved_adapter = adapters.resolve(adapter.name)

    local chat = Chat.new({
      adapter = resolved_adapter,
      buffer_context = { bufnr = 1, filetype = "lua" },
    })

    -- Register agentskills tools to tool_registry
    local tools_config = require("codecompanion.config").interactions.chat.tools
    for _, tool_name in ipairs({"activate_skill", "load_skill_file", "run_skill_script"}) do
      local tool_cfg = tools_config[tool_name]
      if tool_cfg then
        chat.tool_registry:add_single_tool(tool_name, { config = tool_cfg, visible = false })
      end
    end

    _G._test_chat = chat
  ]], { temp_dir, skill_opts })

  -- Mock HTTP client
  Helpers.mock_http(child, "_G._test_chat.adapter")

  return "_G._test_chat"
end

---Queue a mock HTTP response containing tool_calls
---@param child table MiniTest child neovim instance
---@param tool_calls table[] Array of tool call objects: { ["function"] = { name, arguments }, id?, type? }
---@param content? string Optional content string (default: "I'll use the tool")
---@return nil
function Helpers.queue_tool_call_response(child, tool_calls, content)
  local response = {
    content = content or "I'll use the tool",
    tools = tool_calls,
  }
  Helpers.queue_mock_http_response(child, response)
end

---Wait for tool execution to complete
---@param child table MiniTest child neovim instance
---@param chat_var? string Chat variable name (default: "_G._test_chat")
---@param timeout? number Timeout in milliseconds (default: 2000)
---@return boolean success Whether the wait completed successfully
function Helpers.wait_for_tool_completion(child, chat_var, timeout)
  chat_var = chat_var or "_G._test_chat"
  timeout = timeout or 2000

  return child.lua(string.format([[
    local chat = %s
    return vim.wait(%d, function()
      return vim.bo[chat.bufnr].modifiable
    end)
  ]], chat_var, timeout))
end

---Get tool output messages from chat
---@param child table MiniTest child neovim instance
---@param chat_var? string Chat variable name (default: "_G._test_chat")
---@return table[] messages List of messages with { content } format
function Helpers.get_tool_output_messages(child, chat_var)
  chat_var = chat_var or "_G._test_chat"

  return child.lua(string.format([[
    local chat = %s
    if not chat or not chat.messages then
      return {}
    end

    local result = {}
    for _, msg in ipairs(chat.messages) do
      if msg.role == "tool" then
        table.insert(result, { content = msg.content or "" })
      end
    end
    return result
  ]], chat_var)) or {}
end

return Helpers
