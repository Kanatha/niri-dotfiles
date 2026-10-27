# Dotfiles sync: PC agent instructions

Goal: push this PC's niri/waybar/etc. setup to a `pc` branch of
https://github.com/Kanatha/niri-dotfiles.git, then merge it with the `laptop` branch.

## Repo layout

- Bare repo at `~/.dotfiles`, work tree is `$HOME`, tracked paths look like `.config/niri/config.kdl`, `.local/bin/osd`.
- Helper: `g(){ git --git-dir=$HOME/.dotfiles --work-tree=$HOME "$@"; }`
- The remote's old `master` is an unrelated, outdated history (`~/.config` contents at the repo root). Do not push to it or force-push anything.
- The `laptop` branch uses the `$HOME`-rooted layout (same as this file's location).

## Steps

1. If `~/.dotfiles` doesn't exist: `git clone --bare https://github.com/Kanatha/niri-dotfiles.git ~/.dotfiles`, then `g config status.showUntrackedFiles no`. Then `g fetch origin` and look at `g ls-tree -r origin/laptop --name-only`.
   If it already exists, add the remote (`g remote add origin ...`) and fetch.
2. Create `pc` as a **fresh** branch from the PC's own current files (not from `laptop`):
   `g checkout --orphan pc` (or init the bare repo empty), then add the PC's version of every file in the same
   set the laptop tracks: `.config/{niri,waybar,wofi,mako,colors,control-center,systemd/user,swaylock,swappy,tmux,alacritty,presets}`
   and the scripts in `.local/bin` (battery-watch, caffeine, focus-mode, lock, media-active, nightlight, osd, preset, scratch-term),
   plus anything else on the PC that niri/waybar/wofi/mako/keybinds call (grep the niri config and waybar config for script paths
   and make sure each referenced script is tracked).
3. Do NOT commit: `*.bak*`, `__pycache__/`, symlinks to installed binaries in `.local/bin` (claude, nvim, clickhouse, yazi, ...),
   systemd `*.wants/` symlinks (absolute paths; enable with `systemctl --user enable` instead), aerc config / `mail-password`
   (the user will set mail up later), and anything containing passwords, tokens, OAuth client secrets, or keys.
   Grep staged files for `password|token|secret|api.?key` before committing and show hits to the user.
4. Commit and `g push -u origin pc`.
5. Merge: `g checkout -b merged laptop`, then `g merge --allow-unrelated-histories pc`. For conflicts:
   - Hardware-specific differences (outputs/monitors, brightness/battery bits, laptop-only keys, touchpad) are usually
     both legitimate. Prefer keeping both via per-host sections or separate included files rather than picking one side.
   - Everything else: ask the user when unsure, don't guess.
   Push `merged` with `g push -u origin merged`.
6. Do not touch `master` or force-push anything; tell the user the result and let them decide whether `merged` replaces `master`.
