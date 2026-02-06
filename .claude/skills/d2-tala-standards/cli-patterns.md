# CLI Patterns

## 1. Installation

### macOS (Homebrew)

```bash
# Install D2
brew install d2

# Install TALA plugin
brew install d2plugin-tala

# Verify
d2 --version
d2plugin-tala --version
```

### Linux / CI (curl install script)

```bash
# Install D2
curl -fsSL https://d2lang.com/install.sh | sh -s --

# Install TALA plugin
curl -fsSL https://d2lang.com/install.sh | sh -s -- --tala

# Or download binary releases from GitHub
# https://github.com/terrastruct/d2/releases
# https://github.com/terrastruct/TALA/releases
```

### Verify Installation

```bash
d2 --version
d2plugin-tala --version

# Check TALA auth
cat ~/.config/tstruct/auth.json 2>/dev/null || echo "No auth file found"
```

---

## 2. Basic CLI Usage

### Render to SVG (default)

```bash
# With TALA via vars block in the .d2 file
d2 diagram.d2 output.svg

# With TALA via CLI flag (overrides vars block)
d2 --layout tala diagram.d2 output.svg

# Short form
d2 -l tala diagram.d2 output.svg
```

### Render to PNG

PNG rendering requires a headless browser (Playwright). See section 5 for setup.

```bash
d2 --layout tala diagram.d2 output.png
```

### Environment Variable

```bash
# Set TALA as default layout engine for all d2 commands
export D2_LAYOUT=tala
d2 diagram.d2 output.svg  # Uses TALA automatically
```

---

## 3. Output Formats

| Format | Extension | Notes |
|--------|-----------|-------|
| SVG | `.svg` | Default. Vector, scalable, supports animations |
| PNG | `.png` | Requires Playwright browser. Good for embedding in docs |
| PDF | `.pdf` | Requires Playwright browser |

```bash
d2 --layout tala diagram.d2 output.svg
d2 --layout tala diagram.d2 output.png
d2 --layout tala diagram.d2 output.pdf
```

The output format is determined by the file extension.

---

## 4. Watch Mode

Watch mode re-renders the diagram automatically when the `.d2` file changes. Opens a browser preview.

```bash
d2 --watch --layout tala diagram.d2
# Opens browser at http://localhost:PORT with live preview
```

---

## 5. Playwright Setup (PNG/PDF)

PNG and PDF rendering requires Playwright's headless Chromium browser.

### Install Playwright browsers

```bash
# D2 manages its own Playwright installation
# On first PNG render, D2 will prompt to install browsers

# Manual install (if needed)
npx playwright install chromium
```

### macOS Playwright Cache

D2's Go-based Playwright cache is at:
```
~/Library/Caches/ms-playwright-go/<version>/
```

The version matches the Playwright Go driver version bundled with D2 (e.g., `1.47.2`).

### Corrupted Cache Fix

If PNG rendering fails with browser errors:

```bash
# Remove the corrupted Playwright cache
rm -rf ~/Library/Caches/ms-playwright-go/

# Re-render — D2 will re-download browsers
d2 --layout tala diagram.d2 output.png
```

---

## 6. Seed Tuning

TALA's randomized optimizer uses seeds to explore different layout possibilities. More seeds = more candidates = better chance of finding a clean layout.

```bash
# Default: tries seeds 1, 2, 3
d2 --layout tala diagram.d2 output.svg

# Try specific seeds
d2 --layout tala --tala-seeds 1,2,3,42,99 diagram.d2 output.svg

# Single seed for reproducible builds
d2 --layout tala --tala-seeds 42 diagram.d2 output.svg
```

### Seed Tuning Workflow

1. Render with default seeds: `d2 --layout tala diagram.d2 output.svg`
2. If layout has issues (overlapping, poor routing), try more seeds:
   `d2 --layout tala --tala-seeds 1,2,3,4,5,6,7,8,9,10 diagram.d2 output.svg`
3. If still not good, try high/random seeds:
   `d2 --layout tala --tala-seeds 42,99,137,256,999 diagram.d2 output.svg`
4. Once you find a good seed, use `--tala-seeds <N>` for reproducibility

---

## 7. D2 vars Config Block

The `vars.d2-config` block in the `.d2` file is equivalent to CLI flags:

```d2
vars: {
  d2-config: {
    layout-engine: tala      # --layout tala
    theme-id: 0              # --theme 0
    pad: 30                  # --pad 30
    sketch: false            # --sketch
    center: false            # --center
  }
}
```

CLI flags override `vars.d2-config` values.

---

## 8. Troubleshooting

### TALA Auth Errors

```
Error: TALA requires authentication
```

**Fix**: Set up TALA auth:
```bash
# Option 1: Persistent token file
d2plugin-tala --auth-token <TOKEN>

# Option 2: Environment variable
export TSTRUCT_TOKEN="your-token"
```

### Icon 403 Errors

```
Error: failed to fetch icon: 403 Forbidden
```

**Causes**:
- Icon URL uses `+` instead of `%20` for spaces
- Icon doesn't exist on Terrastruct's CDN
- Rate limiting on icon fetches

**Fix**: Verify the icon URL is correct with `%20` encoding. Check available icons at https://icons.terrastruct.com.

### Reserved Keyword Errors

```
Error: failed to compile: "top" is a reserved keyword
```

**Fix**: Rename any shape using a reserved keyword (`top`, `left`, `right`, `bottom`, `top-left`, etc.) to a descriptive name:
```d2
# WRONG
top: Header Section

# CORRECT
header: Header Section
```

### Corrupted Playwright Cache

```
Error: could not find browser at ...
```

**Fix**:
```bash
rm -rf ~/Library/Caches/ms-playwright-go/
d2 --layout tala diagram.d2 output.png  # Re-downloads automatically
```

### Layout Issues

If TALA produces suboptimal layouts:

1. **Try more seeds**: `--tala-seeds 1,2,3,4,5,6,7,8,9,10`
2. **Reduce nesting**: Flatten container hierarchy to 3 levels max
3. **Add direction**: Set `direction: right` on containers that should flow horizontally
4. **Use dimensions**: Set `width`/`height` on hub nodes with many connections
5. **Check for cycles**: Circular connection patterns can confuse layout
6. **Simplify connections**: Too many cross-container connections make any layout messy
