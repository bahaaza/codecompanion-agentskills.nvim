---
name: demo-skill
description: Use when user asks to run an AgentSkills demo, demonstrate AgentSkills capabilities, test skill file loading and script execution features, or verify the Agent Skills system is working correctly.
---

# Demo Skill

This skill demonstrates the full capabilities of the **codecompanion-agentskills.nvim** plugin, including file loading, multi-language script execution, Python relative imports, and dependency management.

## Instructions

Follow these steps **in order**. Do not skip any step.

---

### Step 1: Output Execution Plan

Before doing anything else, output an execution plan to the user in Markdown:

```
📋 Demo Skill Execution Plan
─────────────────────────────────────────────
1. YOUR FIRST ACTION
2. ...
─────────────────────────────────────────────
```

---

### Step 2: Load Welcome File

Load the skill file `references/welcome.md` and display its contents to the user.

---

### Step 3: Run Python Demo

**If `python3` is available**, run script `scripts/run.py` with dependency `faker`.

**If `python3` is NOT available**, note this in your summary and skip to the next step.

---

### Step 4: Run Bash Argument Demo

**If `bash` is available**, run script `scripts/check_bash.sh` with arguments.

Pass example arguments including:
- a plain argument containing a whitespace like `first argument`
- an argument containing `${SKILL_DIR}` such as `${SKILL_DIR}/references/welcome.md`

Then verify that the script output contains:
- the Bash version line
- the first argument value
- the resolved absolute path for the `${SKILL_DIR}`-based argument

If the output does not match, report the mismatch in the final summary.

---

### Step 5: Run Node.js Version Check

**If `node` is available**, run script `scripts/check_node.js` to check the installed Node.js version.

**If `node` is NOT available**, note this and skip.

---

### Step 6: Summarize Results

After completing all steps, output a summary table to the user:

| Step | Description | Status |
|------|-------------|--------|
| 1 | Output execution plan | ✅ Done |
| 2 | Load `references/welcome.md` | ✅ / ❌ |
| 3 | Python demo (faker + relative imports) | ✅ / ❌ / ⏭️ Skipped |
| 4 | Bash argument demo (args + `${SKILL_DIR}` placeholder validation) | ✅ / ❌ / ⏭️ Skipped |
| 5 | Node.js version check | ✅ / ❌ / ⏭️ Skipped |

Fill in the actual status for each step. Include any error messages for failed steps. End with a brief conclusion about whether the AgentSkills system is working correctly.

---

### Step 7: Output Available Agent Skills List

Output the complete list of currently available Agent Skills in the following format:

**Currently Available Agent Skills:**

| # | Skill Name | Description |
|---|------------|-------------|
| 1 | skill-name-1 | Description 1 |
| 2 | skill-name-2 | Description 2 |
| ... | ... | ... |

**Note:** 
- If the total number of available Agent Skills exceeds 10, display only up to 10 skills that the user might be interested in, and add a note at the end indicating "And X more available skills not shown."
- You can make reasonable assumptions about which skills might interest the user based on the context of this conversation.
