# Tephra notes for Claude

Console-style Linux shell in Godot 4.7 (GDScript). See `README.md` for what it is and `TODO.md` for what's next.

## How releases reach the PC
- Tephra updates itself from the branch named in `shell/tephra-shell/self_update.gd` (`const BRANCH`, currently
  `claude/project-thread-kou0vz`). It only takes `shell/tephra-shell/` and `tools/install-update.sh` from there, and only
  when that branch's `shell/tephra-shell/VERSION` is newer than the running one.
- `main` is what's installed on the PC: each in-app update pushes a "vX: updated from inside Tephra" commit there.
- A change isn't on the PC until it's on the update branch with a bumped VERSION.
- The owner has said yes to pushing finished releases straight to the update branch: `git push origin HEAD:<update branch>`,
  fast-forward only, never force. Push the session branch too.

## Public repo
`wintrsson/tephra-os` is the public copy. It gets snapshots only, never this repo's history (that has personal details):
after a release, run `tools/publish-public.sh` from the update branch. It refuses if it finds a personal detail, writes
`UPDATE_BRANCH` = `main` into the snapshot so public installs update from there, and commits as the owner's GitHub
noreply address. Never put the owner's name, username, email, Steam IDs or hardware into files or commit messages.
`install.sh` / `uninstall.sh` at the root are what new users run (Arch + KDE); keep their package list in step with
the programs Tephra calls.

## Every release
1. Bump `shell/tephra-shell/VERSION` (patch number: 0.99.57 -> 0.99.58).
2. Add a `## vX` entry at the top of `CHANGELOG.md` in plain words: what the player notices, not the code.
3. Commit subject: `vX: <what changed>`.
4. Run `tools/check.sh` (headless Godot compiles every script) and fix anything before pushing.
5. Run `tools/publish-public.sh` once the update branch has it.

## Code
- `home.gd` is the main shell; screens are separate scripts set up from it. It is being split one system at a time
  (`store_lookup.gd` is the first): the new file is a Node with `var home`, reaches Home through `home.x` (untyped, so write
  `var v = home.f()`, not `:=`), and home.gd keeps only a forwarding line where other files call in (`add_game`). After moving
  code run `tools/check.sh` and `tools/ui-test.sh`.
- No autoload for settings: a script that reads them needs `const Settings = preload("res://settings.gd")`.
  Same for other helpers (Themes, Haptics, Motion...). `tools/check.sh` catches a missing one.
- The developer menu lives in `top_menu.gd`.
- Nothing can be run here (no display or controller), so say "untested on the PC" for behaviour changes.

## Updates that don't start
`tephra-run.sh` watches a freshly installed version (note: `~/.config/tephra/update-pending`). Tephra deletes the note after 10 s
of running fine (`SelfUpdate.mark_healthy`); if it crashes or hangs first, the launcher puts the old files back, writes
`update-failed`, and Tephra won't offer that version again. Keep early startup free of long blocking work (the limit is 60 s).

## First-boot setup
`setup.gd`: ten steps (welcome, display and sound, Wi-Fi, Steam, game drives, controllers, weather, theme, controls tour, done), each
with a way past it. It opens by itself only on a fresh install (`note_fresh_install` looks for Tephra's saved files at the very start;
a PC that already has them just gets `setup_done`). Developer menu > "Redo first-boot setup" runs it again and keeps all data.
A theme choice restarts the scene, so `setup_active` / `setup_page` in settings bring it back at the same step.
It can't be skipped (Back on the first step only leaves a Developer-menu run). Changes to refresh rate / frame limit / volume call
`_notify_change` (big banner on the right plus a green row flash). The Wi-Fi step is its own page (nmcli through `_wifi_*`, workers via
`_wifi_run`). On the Theme step the cursor previews a theme: `_show_look` switches `Themes._id` for an instant to read colours, font and
to build that theme's background (cached), then puts it back, so nothing else ever sees the preview. The cached backgrounds are the
first children of `_root`, before the page content: keep that order when adding or re-showing one (`move_child` to a stale index once put a
background over every button).
New steps: add the id to `PAGES`, text in `_blurb_for`, rows in `_rows_for`. Rows are dictionaries; use bound methods
(`_fn.bind(x)`), not multi-line lambdas followed by more arguments.

## Phone link
`phone_link.gd` is a tiny hand-written web server (TCPServer) for typing from a phone and saving captures; `phone_screen.gd` shows its
QR code (`qr.gd` makes the code: byte mode, level M, versions 1 to 10; verified by decoding with OpenCV). It only runs while the QR screen
or the keyboard it was opened from is up, needs the random token, and serves only the Album's folders. Keyboard hooks are `phone_state`,
`phone_set`, `phone_submit`. Packed arrays stored in a dictionary are copied when read: put the changed array back (see `_service`).
To test it for real: `TEPHRA_PHONE_IP=127.0.0.1` makes it usable inside the sandbox, `HOMESEED` puts captures in the test home, and
`curl --noproxy '*'` (the sandbox proxy swallows localhost). Start Tephra and the client in the same shell command: background
processes don't survive between tool calls.

## Cloud sessions
`.claude/hooks/session-start.sh` installs Godot 4.7 for `tools/check.sh` and fast-forwards to the update branch.

`tools/ui-test.sh <plan.json> <outdir>` runs the real Tephra under Xvfb with software rendering on an empty data folder, presses keys
and saves screenshots (the plan format is in `tools/ui_shot.gd`; needs `xvfb-run` and ImageMagick to look at several shots at once).
Use it to actually look at a screen you built, not only to compile it. No controller, audio, Steam or kscreen-doctor there, so
those parts show their "not available" states.
