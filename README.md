# codecompanion-agentskills.nvim

An extension for [CodeCompanion.nvim](https://github.com/olimorris/codecompanion.nvim) that adds support for [Agent Skills](https://agentskills.io).

**Note: this project is currently in early prototype stage. There may be significant breaking changes without notice.**

## What is Agent Skills?

Agent Skills is a progressive disclosure system that enables AI agents to dynamically load specialized domain knowledge on demand. Instead of loading all knowledge at once, agents can activate specific skills only when needed.

For more information about Agent Skills, visit the [official website](https://agentskills.io).

## Features

- **Progressive Disclosure**: Activate specialized skills on demand to avoid context overload
- **Virtual Filesystem**: Skill resources are isolated from your workspace for security and clarity
- **Tools**:
  - `activate_skill`: Load a skill and inject its instructions into the AI context
  - `load_skill_file`: Read documentation, templates, or other text files provided by a skill
  - `run_skill_script`: Execute scripts provided by a skill
  - **The above tools are invisible to users and you should use the `@{agent_skills}` tool group in your Chat**
- **Flexible Discovery**: Scan single directories or recursively search for skills

## Requirements

- Neovim 0.11.0 or greater
- [CodeCompanion.nvim](https://github.com/olimorris/codecompanion.nvim)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "olimorris/codecompanion.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "cairijun/codecompanion-agentskills.nvim",
  },
  config = function()
    require("codecompanion").setup({
      -- Your CodeCompanion configuration...
      --
      -- Configure the AgentSkills extension
      extensions = {
        agentskills = {
          opts = {
            paths = {
              "~/my-agent-skills",  -- Single directory (non-recursive)
              { "~/.config/nvim/skills", recursive = true },  -- Recursive search
            }
          }
        }
      }
    })
  end
}
```

## Usage

* Put skills directories in one of the configured paths.
* Use `@{agent_skills}` tool group in your Chat. The LLM should activate skills when your task matches the skill's description. You can also explicitly ask the LLM to use a specific skill by name.
