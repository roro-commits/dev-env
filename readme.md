
use stow to link to .config

stow -v -t ~ helix zellij home-manager


# 🛠️ Totem Dev Environment

This repository contains an optimized workflow for the **GEIGEIGEIST Totem** (38-key split keyboard), integrating **Helix** and **Zellij** via **Home Manager**.

## ⌨️ Keyboard Strategy: Home Row Mods
To navigate efficiently on 38 keys, this setup relies on **Home Row Mods** (configured in QMK/ZMK):
* **Hold `S`**: `Alt` (Zellij & Tab navigation)
* **Hold `D`**: `Ctrl` (Helix internals)
* **Tap `Space`**: Leader Key (Helix actions)

---

## 🧬 Helix Configuration
**Location:** `~/dev-env/helix/config.toml`  
Helix is configured with a **Space-Leader** workflow to minimize finger travel and avoid modifier gymnastics.

```toml
theme = "catppuccin_mocha"

[editor]
line-number = "relative"
cursorline = true
bufferline = "always"

[keys.normal]
# The "Space" Leader setup
"space" = { "f" = "file_picker", "w" = ":w", "q" = ":q" }

# Navigation between Helix tabs (matches Zellij movement)
"A-h" = ":bp"
"A-l" = ":bn"
