
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
```

# The "Space" Leader setup
"space" = { "f" = "file_picker", "w" = ":w", "q" = ":q" }

# Navigation between Helix tabs (matches Zellij movement)
"A-h" = ":bp"\\
"A-l" = ":bn"


# 🖥️ Zellij Configuration (Totem Optimized)

This configuration is designed for the **GEIGEIGEIST Totem** 38-key split keyboard. It prioritizes screen real estate and uses `Alt`-based navigation to harmonize with Home Row Mods.

## 📍 Configuration Location
The source of truth for this config is:
`~/dev-env/zellij/config.kdl`

It is managed via **Home Manager** using `mkOutOfStoreSymlink`, meaning edits here are applied instantly to `~/.config/zellij/config.kdl`.

---

## ⌨️ Totem Keymap Logic
Since the Totem has limited physical keys, we use **Home Row Mods**. 
* **Modifier:** Hold `S` (Left Hand Home Row) to trigger `Alt`.
* **Action:** Combine with `HJKL` (Right Hand Home Row) for navigation.

### Global Navigation
These bindings are available in `shared` mode, meaning they work even while you are focused inside **Helix**.

| Keybind | Action | Description |
| :--- | :--- | :--- |
| `Alt + h` | **Focus Left** | Move focus to the pane or tab on the left. |
| `Alt + l` | **Focus Right** | Move focus to the pane or tab on the right. |
| `Alt + k` | **Focus Up** | Move focus to the pane above. |
| `Alt + j` | **Focus Down** | Move focus to the pane below. |

### Pane Management
| Keybind | Action | Description |
| :--- | :--- | :--- |
| `Alt + n` | **New Pane** | Opens a new terminal pane. |
| `Alt + x` | **Close Pane** | Closes the current active pane. |
| `Alt + f` | **Toggle Float** | Pops the current pane into a floating window. |

---

## 🎨 UI & Minimalism
To maximize vertical and horizontal space for the **Helix** editor, the following UI adjustments are applied:

* **Pane Frames:** `false` 
  * Removes the thick borders and titles around every pane.
* **Compact Layout:** * Uses the `compact-bar` to keep the status line to a single row.

```kdl
// Extraction from config.kdl
pane_frames false

keybinds {
    shared {
        bind "Alt h" { MoveFocusOrTab "Left"; }
        bind "Alt l" { MoveFocusOrTab "Right"; }
        bind "Alt j" { MoveFocus "Down"; }
        bind "Alt k" { MoveFocus "Up"; }
        bind "Alt n" { NewPane; }
        bind "Alt x" { CloseFocus; }
        bind "Alt f" { ToggleFloatingPanes; }
    }
}


🧬 Helix Keymap Documentation: 38-Key Totem Edition

This document details the ergonomic remapping of Helix for a sub-40% split keyboard (GEIGEIGEIST Totem). The layout focuses on maintaining high-speed editing and navigation without ever leaving the home row.
📐 Ergonomic Philosophy

On a 38-key layout, finger travel is the enemy. This keymap reassigns core Helix functionality based on three rules:

    Verticality via Layers: Up/Down navigation is handled by a dedicated hardware thumb layer.

    Left Hand = Editing: The left home row handles "destructive" and "constructive" actions.

    Right Hand = Horizontal Navigation: The right home row handles X-axis jumps and character seeking.

🎹 Home Row Reference

Left Hand: The "Editor"
Key	Finger	Command	Helix Default	Purpose
A	Pinky	insert_mode	i	Enter Insert mode
S	Ring	change_selection	c	Delete + enter Insert mode
D	Middle	delete_selection	d	Delete current selection
F	Index	extend_line_below	x	Select entire line
C	Inner	append_mode	a	Append after selection

Right Hand: The "Navigator"
Key	Finger	Command	Helix Default	Purpose
H	Inner	move_prev_word_start	b	Jump word back
J	Index	find_next_char	f	Find character forward (Seek)
K	Middle	select_mode	m	Match/Surround menu
L	Ring	move_next_word_start	w	Jump word forward
;	Pinky	move_next_word_end	e	Jump to word end
🚀 High-Frequency Combos

Optimizing the home row enables natural "finger rolls" for the most common editing tasks:

    Wipe Current Line: f → d (Index to Middle roll).

    Select inside Brackets: k → m (Middle to Bottom Index).

    Change Word: l (jump to word) → s (instantly change it).

    Symbol Teleport: j → [char] (Seek to symbol on current line).
