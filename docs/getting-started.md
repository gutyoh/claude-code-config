# Getting Started with Claude Code Config

This tutorial walks you through installing the Claude Code portable configuration on your machine. By the end, you will have 17 specialized agents, 19 skills, and 5 hooks available in every Claude Code session across all your projects.

**Time required:** 10 minutes

**What you will build:** A global Claude Code configuration with search integrations, domain-expert agents, and workflow automation hooks -- all synced from a single Git repository.

## Prerequisites

Before you begin, confirm that you have the following installed:

**1. Claude Code**

```bash
claude --version
```

You should see output like:

```
1.0.x (Claude Code)
```

If Claude Code is not installed, install it now:

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

**2. jq**

```bash
jq --version
```

You should see output like:

```
jq-1.7.1
```

If jq is not installed, install it now:

```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq
```

**3. Git**

```bash
git --version
```

You should see output like:

```
git version 2.47.0
```

## Step 1: Clone the Repository

Create a directory for the configuration and clone the repository:

```bash
mkdir -p ~/repos
cd ~/repos
git clone https://github.com/gutyoh/claude-code-config.git
cd claude-code-config
```

You should see:

```
Cloning into 'claude-code-config'...
remote: Enumerating objects: ...
Receiving objects: 100% ...
```

## Step 2: Run the Setup Script

Run the interactive setup script:

```bash
./setup.sh
```

The script begins by checking your prerequisites:

```
Claude Code Config Setup
========================
Repo location: /Users/you/repos/claude-code-config

Checking prerequisites...
  ✓ jq found
  ✓ python3 found
  ...
```

After the prerequisite check, the script displays the current installation options and presents a menu:

```
Current installation options:
  core (hooks, scripts, commands):  always
  agents & skills:                  yes
  MCP search servers:               brave-search, tavily
  agent teams (experimental):       yes
  proxy launcher PATH:              yes
  settings.json:                    merge (preserve existing, add new)
  statusline color theme:           dark
  ...

? What would you like to do?
> Proceed with installation
  Customize installation
  Cancel
```

Use the arrow keys to highlight **Proceed with installation** and press Enter.

The script creates symlinks and configures your environment in numbered steps:

```
Step 1: Creating symlinks...
  ✓ hooks -> /Users/you/repos/claude-code-config/.claude/hooks
  ✓ scripts -> /Users/you/repos/claude-code-config/.claude/scripts
  ✓ skills -> /Users/you/repos/claude-code-config/.claude/skills
  ✓ agents -> /Users/you/repos/claude-code-config/.claude/agents

Step 2: Configuring hooks (user scope)...
  ✓ IDE diagnostics hook configured

Step 3: Configuring file suggestion (user scope)...
  ...

Step 4: Configuring statusline (user scope)...
  ...

Step 5: Configuring statusline config...
  ...

Step 6: Configuring agent teams...
  ...

Step 7: Configuring proxy launcher PATH...
  ...

Step 8: Configuring MCP servers (user scope)...
  Adding brave-search MCP server...
  ✓ brave-search MCP added
  Adding tavily MCP server...
  ✓ tavily MCP added

Step 9: Environment variables
  ...

========================================
Setup complete!
========================================
```

> **Note:** If some optional tools are not installed (like `fd`, `fzf`, or `ccusage`), the script skips those features gracefully. The core installation still completes successfully.

## Step 3: Set Your API Keys

The configuration uses two MCP search servers that require API keys. Get free API keys from these services:

**Brave Search** (1,000 searches/month free):

1. Go to [https://api-dashboard.search.brave.com/](https://api-dashboard.search.brave.com/)
2. Sign up or log in
3. Click **Create API Key**
4. Copy the key

**Tavily** (1,000 credits/month free):

1. Go to [https://tavily.com](https://tavily.com)
2. Sign up or log in
3. Copy your API key from the dashboard

Add both keys to the MCP keys file that the setup script created:

```bash
echo 'BRAVE_API_KEY=your-brave-key-here' >> ~/.claude/mcp-keys.env
echo 'TAVILY_API_KEY=your-tavily-key-here' >> ~/.claude/mcp-keys.env
```

Replace `your-brave-key-here` and `your-tavily-key-here` with your actual keys.

Verify the file has both keys:

```bash
wc -l ~/.claude/mcp-keys.env
```

You should see:

```
2 /Users/you/.claude/mcp-keys.env
```

## Step 4: Verify the MCP Servers

Confirm the MCP servers are registered:

```bash
claude mcp list
```

You should see both servers listed:

```
  brave-search: npx ... (user)
  tavily: npx ... (user)
```

## Step 5: Verify the Agents

Open Claude Code in any project directory:

```bash
cd ~/repos/claude-code-config
claude
```

Inside the Claude Code session, type:

```
/agents
```

You should see all 17 agents listed:

```
  code-reviewer-expert
  d2-tala-expert
  data-scientist
  databricks-expert
  dbt-expert
  design-doc-expert
  diataxis-expert
  dotnet-expert
  internet-researcher
  kedro-expert
  langfuse-expert
  linus-torvalds
  pr-manager
  python-expert
  rust-expert
  sonarqube-fixer
  ui-designer
```

## Step 6: Verify the Skills

In the same Claude Code session, type:

```
/help
```

You should see available slash commands including:

```
  /brave-search    - Search using Brave Search MCP
  /tavily-search   - AI-native search using Tavily MCP
  /web-search      - Quick search using built-in WebSearch
  /pr              - Create PR/MR with Conventional Commits
  /pr-review       - Multi-agent PR review
  /mcp-key-rotate  - Rotate MCP API keys
```

## Step 7: Test a Search

In the same Claude Code session, run a Brave Search query:

```
/brave-search Claude Code MCP servers
```

You should see search results returned from the Brave Search API. This confirms the MCP server is running, authenticated, and returning data.

Exit the Claude Code session by typing `/exit` or pressing Ctrl+C.

## What You Have Now

You have successfully installed a portable Claude Code configuration. Here is what is available in every Claude Code session on this machine:

| Component | Count | What It Does |
|-----------|-------|--------------|
| **Agents** | 17 | Specialized subagents for Python, Rust, .NET, dbt, Kedro, Databricks, documentation, PR management, and more |
| **Skills** | 19 | Reusable capabilities including engineering standards, search integrations, PR workflows, and API key management |
| **Hooks** | 5 | Workflow automation: git rebase enforcement, IDE diagnostics, SQL safety, Brave Search rate limiting, usage cache refresh |
| **MCP Servers** | 2 | Brave Search and Tavily for internet search within Claude Code |

Because the configuration uses symlinks, pulling updates from Git automatically updates your global configuration:

```bash
cd ~/repos/claude-code-config
git pull origin main
```

No reinstallation required.

## Next steps

- [How to Add an Agent](how-to-add-agent.md): create a custom agent for your domain
- [How to Add a Skill](how-to-add-skill.md): create reusable standards for your team
- [How to Configure the Statusline](how-to-configure-statusline.md): customize billing and usage tracking
- [How to Add an MCP Server](how-to-add-mcp-server.md): integrate new external tools
- [Architecture](architecture.md): understand how the symlink system and agent+skill pattern work
- [Design Decisions](design-decisions.md): why things are designed this way
