# Tephra changelog

## v0.99.78
- Less desktop on the way in: on the first start Tephra turns KDE's own splash screen off and makes the desktop wallpaper plain black, so the moment between the boot picture and Tephra shows black instead of your wallpaper. `uninstall.sh` puts KDE's normal wallpaper and splash back.

## v0.99.77
- Tephra now creates all three of its KDE window rules for Steam by itself at start-up (the toast rule it already made, plus "Hide Steam behind Tephra" and "Hide Steam Startup Windows"). Before, the last two only came from a file that the installer never copied, so a new install let Steam windows show over Tephra. Rules already on a PC are kept and only fixed if they differ.

## v0.99.76
- A game's page now takes its colours from the game's cover on every theme. On Aero, Channels and Sleek the whole sky behind the page is a pale version of the cover's colour (it was the theme's own blue and green), and on Aero the chosen button and the section headings use it too.
- Fix: a game whose cover was fetched after its page opened kept a made-up colour (often green) instead of the cover's. The colours are now worked out again once the cover arrives.
- The colour is the cover's strongest hue, so a red-and-teal cover is red or teal and not a muddy average.

## v0.99.75
- The developer menu is gone. The Tephra logo in the top bar is just a logo now, so the cursor goes Wi-Fi, Bluetooth, controllers, battery, settings, profile.
- The control center no longer has a Mods card. Mods are still on a game's page (its options menu and its info page), and "Hide Mods" is gone with the menu.
- New: Settings > System > Help, with View Tephra's log, Run first-boot setup again, a switch for showing hidden folders in Files, and clearing the cover art and achievement caches. Restart Tephra, Close Tephra and Re-scan games were already in Settings.
- Test tools (pretend battery alerts, the fake loading screen, the controller and 3D tests as a menu) are no longer reachable from a menu. Settings > Controllers still has the button test.
- If you had turned on "Performance info on every screen" or "Keep Tephra under all apps" in the old menu, that setting stays as it was, with no switch to change it now.

## v0.99.74
- The PS2 theme is called **Retro**, not BIOS (BIOS already means the PS2 file in Settings).

## v0.99.73
- Two themes have new names: Frutiger is now **Aero** and PS2 is now **BIOS** (renamed again in v0.99.74). Nothing about how they look or sound changed, and your chosen theme stays chosen.

## v0.99.72
- Tephra is public at github.com/wintrsson/tephra-os, under the GPL-3.0 licence, with a one-command installer (`install.sh`), an uninstaller and a new README with theme screenshots.
- Personal details are gone from Tephra's files: no username in the configs, and the developer menu's "Add my Steam ID as family member" button is removed.
- Public installs update from the public repo (the new `UPDATE_BRANCH` file). This PC keeps updating as before.

## v0.99.71
- Library: a non-Steam game's page has "Remove from Library". It asks first, closes Steam if it's open (Steam rewrites its list when it closes), and takes the game out of Steam's list of non-Steam games. The game's own files stay on the drive. Not for PS2 games.

## v0.99.70
- Fix: on the Theme step of setup, going back to a theme you had already looked at made every button, the title and the hints disappear (only the background and the clock were left). The background of a theme you looked at again was put on top of the page instead of behind it. It stays behind now.
- The buttons on that step are clearer in every theme: each one has the theme's own button colour and a thin edge, so on the light themes (Sleek, Frutiger, Channels) they no longer fade into the background.
- The button pictures at the bottom (Select, Choose, Previous step) are drawn in the colours of the theme being previewed, so they stay readable on light and dark looks.

## v0.99.69
- First-boot setup, reworked from your notes:
  - It can't be skipped any more: the Welcome step only has Start, and R1 no longer skips a step (every step still has Continue, and Back goes to the step before). Redo from the Developer menu can still be left with Back on the first step.
  - A change you make in Display and sound now shows big on the right (what changed and its new value) while the row lights up green: refresh rate, frame rate limit and volume. A live "Tephra is running at N FPS right now" line shows the effect of the frame rate limit.
  - Menu sounds and Background music are gone from that step; Volume (and the sound output, when there are several) stay.
  - Wi-Fi is a page of its own, not a popup: Wi-Fi on/off, Look for networks, the networks (join, disconnect, saved ones, hidden network), and the password keyboard (with the Phone key) open from it.
  - On the Theme step, moving over a theme shows what it looks like (its background, colours and typeface fade in) without choosing it. Pressing A on a theme still restarts Tephra with it.

## v0.99.68
- Fix: `tephra start` / `tephra open` could do nothing at all. The launcher refuses to run twice by holding a lock file, and every program Tephra started (Steam, a game that was still running) inherited that lock and kept it after Tephra closed, so the next launcher said "already running" and quit without a word. Only the launcher holds the lock now.
- `tephra start` no longer hides problems: it checks that the launcher and Godot are there, waits to see Tephra come up, and if it doesn't, prints what the launcher said (also saved in `~/.config/tephra/launcher.log`). A launcher left running with no Tephra under it is cleared out instead of being waited on.

## v0.99.67
- The `tephra` terminal command now understands `tephra open` (opens Tephra, or says it is already open) and `tephra close` (closes Tephra and every game). Before, `tephra open` wasn't a command, so it only printed the list of commands; the list now also says "Unknown command: ..." first when you mistype one. `tephra start` still opens Tephra fresh (closing the open one first).

## v0.99.66
- Type with your phone. The on-screen keyboard has a new Phone key (next to Done). It shows a QR code; scan it with your phone's camera (same Wi-Fi as the PC) and a page opens where you type, and the text appears in the box on the TV. Done on the phone presses Done here, Cancel closes the keyboard. Works for every text box: Wi-Fi passwords, browser addresses, renaming, the weather city.
- Send captures to your phone. In the Album, R3 (P on a keyboard) shows a QR code; the phone's page lists your screenshots and recordings with small pictures and a Save button for each, and the one you picked is highlighted. Closing the QR code stops the sharing.
- The phone link only runs while one of these is on screen (it also stops 15 minutes after the last use), needs the random code from the QR code, and can only read the Album's two folders. Developer menu > "Phone link (screenshots)" opens it for testing. If the phone can't open the page, the PC's firewall may be blocking port 8765.

## v0.99.65
- Nothing changes on screen. First step of splitting home.gd into smaller files: everything about the Steam store (finding a game's pictures by its name, the picture downloads, adding a non-Steam game with Library > Add a game) moved into `store_lookup.gd`. home.gd is about 300 lines shorter.

## v0.99.64
- Steam sign-in from setup: on the Steam step, "Sign in to Steam" opens Steam's own sign-in window with Tephra moved underneath. Tephra comes back by itself once you are signed in (Steam is then closed again), or after 5 minutes. Untested on the PC: if the window doesn't show, wait the 5 minutes or run `tephra start`.
- Notifications that appear over a running game (KDE's banner) now carry Tephra's icon.

## v0.99.63
- Channels theme: the Home page now sits below the round Home and Settings buttons. Before, the page covered the lower half of both buttons and the clock bar looked cramped; now the bar shows in full above it. The status icons at the top (Wi-Fi, Bluetooth, controller) stay out of the way while the Home page is open, as before.

## v0.99.62
- First-boot setup. On a fresh install Tephra walks through ten short steps, each with a way past it: welcome, display and sound (refresh rate with a "keep this?" countdown, frame rate limit that follows the screen, volume, sound output, menu sounds, music), Wi-Fi, Steam (shows whether you're signed in), game drives (adds a drive that already holds Steam games), controllers (who is in charge, Bluetooth), weather (city or automatic, Celsius or Fahrenheit), theme (picking one restarts Tephra and setup carries on where it was), a tour of the controls, and done. Press Circle / B / Esc to go back a step and R1 to skip one.
- A PC that already has Tephra is not put through it.
- Developer menu > "Redo first-boot setup" walks through the steps again for testing; it keeps your settings, games and saves.
- Settings you change in the setup (frame rate limit, volume, theme...) are the same ones as in Settings.

## v0.99.61
- A new version that doesn't start is undone. After an update Tephra is watched: if it crashes or hangs before it has run fine for 10 seconds, the launcher puts the files of the version before the update back and starts that one. Tephra then says "Tephra X didn't start, so Tephra went back to Y", and doesn't offer X again (the next version after it is offered as usual). Works for both the in-app update and `tephra update`.

## v0.99.60
- Button pictures always follow the controller that was used last. Before, once you put a controller in charge (Settings > Controllers), only that one could change them; now with two controllers in use (say a DualSense and a Switch Pro controller) the hints flip to whichever one just sent input. The controller in charge still decides who can press Select.

## v0.99.59
- Fix: installing a Tephra download (`tephra update`) stopped right after closing the games, so Steam wasn't shut down and Tephra didn't restart into the new version. It now finishes and restarts.
- Fix: a link a game opened at the same moment Tephra picked up another one could be lost. Both arrive now.
- Fix: switching Settings > System > "Links from games" off and on quickly could leave the wrong browser in charge of links.

## v0.99.58
- Developer menu > Hide Mods now also hides the Mods button on a game's info page in the Library (it already hid the one in the game options menu and the control center card).

## v0.99.57
- Tephra no longer reopens by itself. The launcher only starts it again after an update or "Restart Tephra"; closing it any other way (its window, a crash, being killed) leaves it closed until you run `tephra start` or log in again.
- Cleanup: removed code nothing used any more (about 520 lines): retro_art.gd, the old fullscreen mpv video player and its key file, unused icons (shard, sun, chevron, file), two unused sounds, and a few leftover variables and helpers.
- (The entries for v0.99.26 to v0.99.56 below were written afterwards from the git log.)

## v0.99.56
- The browser's keyboard check tries up to three times after you click (search boxes that slide open take focus a moment late), looks inside frames and shadow DOM, and writes each try to `~/.config/tephra/overlay.log`, so a keyboard that doesn't come up shows why.

## v0.99.55
- Web links that games open on their own (Discord invites, "visit our website") stay out of the desktop browser. During a game they wait in the control center's Browser card ("From the game: ...") and open in Tephra's own browser; with nothing running they open there at once. Settings > System > "Links from games" switches this off.

## v0.99.54
- Leaving a menu over a running game unblurs inside Tephra into the sharp full-quality picture, then a short fade hands over to the live game.

## v0.99.53
- No blurry still between the menu and the game: Tephra's window stays see-through after the fade.

## v0.99.52
- Leaving the control center is one motion: waking the game and its sound no longer hold Tephra's frames before the fade.

## v0.99.51
- Smoother fade back into the game: one connection to the desktop, a step per frame, 2 % opacity steps.

## v0.99.50
- The fade back into the game is paced by Tephra (KWin 6 scripts have no timer, so it used to jump). The running game's page shows Resume and Options hints.

## v0.99.49
- Triangle on the game being played always opens Resume / Close game / Unpin / Mods.

## v0.99.48
- Leaving a menu fades back into the running game. Choosing the game that is being played on Home resumes it at once.

## v0.99.47
- Closing, restarting or updating Tephra closes every game (paused ones too), Proton, Wine, Steam and whatever Tephra started (`close-all.sh`).

## v0.99.46
- The control center never comes up before the game's picture is taken (a quick PS tap used to photograph Tephra's own black window).

## v0.99.45
- The picture behind the control center is a grab of the whole screen, not of the focused window (which was sometimes Tephra's own, giving black).

## v0.99.44
- Closing, restarting or updating Tephra closes every game Steam started, non-Steam shortcuts included (they are found by their SteamGameId).

## v0.99.43
- The control center never shows store artwork in place of the game's picture.

## v0.99.42
- A late picture behind the control center fades in slowly instead of snapping.

## v0.99.41
- The control center waits a moment for the game's picture so it opens with it already behind (no black flash). The blur is lighter.

## v0.99.40
- The control center shows the game's artwork when its picture is missing or black. Closing or updating Tephra closes Steam and every game.

## v0.99.39
- A game you start jumps to the first slot at once. Holding PS goes Home after 300 ms without opening the control center first.

## v0.99.38
- See when games update. Updates no longer block "Add a game".

## v0.99.37
- Games update by themselves while you are on Home, and queued updates no longer clutter Downloads.

## v0.99.36
- The control center in a game opens on the PS press and never waits for the picture.

## v0.99.35
- Recording has its own start and stop sounds, and holding the touchpad to record is faster.

## v0.99.34
- Games use "Tephra: Gamepad", Steam's Gamepad layout without the touchpad click.

## v0.99.33
- Library > Add a game (R1): add a .exe and Tephra finds its name and art automatically.

## v0.99.32
- Removed "Game resolution", and undid its launch wrapper on every Steam game.

## v0.99.31
- Fix: restoring Steam's controller layouts (`steam_pads.py`) no longer crawls the whole drive.

## v0.99.30
- The touchpad layout fix is switched off again and Steam's own layouts are put back.

## v0.99.29
- An already-open Steam is restarted once so the touchpad fix takes effect.

## v0.99.28
- The touchpad is only Tephra's screenshot button; Create and Options stay Select and Start in games.

## v0.99.27
- Spectacle is kept running so the in-game menu picture is near-instant.

## v0.99.26
- Faster control center in a game, and GPU memory is freed while a game runs.

## v0.99.25
- Fix for v0.99.24: Files couldn't load (a missing line), which could stop the control center or Tephra from starting.

## v0.99.24
- Developer menu: "Files: show hidden and system folders". On, Files lists hidden (dot) files and folders and adds a "System" entry that opens the whole disk from /. Protected things (system folders, Steam, Tephra itself) still can't be moved or deleted.

## v0.99.23
- Files: the first screen now has a "Steam games" entry (next to Home and your drives) that opens the folder your Steam games are installed in. Extra Steam libraries on other drives get their own entry ("Steam games 2"...).

## v0.99.22
- The blur behind menus is lighter (about half as strong).

## v0.99.21
- The control center over a running game now waits up to 1.1 s for the real picture of the game (the grab takes about 0.75 s) and blurs that, instead of opening on the game's cover art and swapping the picture in later.

## v0.99.20
- Undid v0.99.19: the game runs again behind the control center (with its sound), over a blurred still picture of the frame, which is how it was meant to work. "Game behind the control center" in Settings > Games is back to "Keeps running" by default.

## v0.99.19
- The game is now frozen (picture, sound and all) behind the control center by default, over the usual blurred picture, until you leave it. Settings > Games > "Game behind the control center" can still turn that back to "Keeps running". The old saved choice is reset so the new default applies.

## v0.99.18
- While a game runs and you open Home (hold PS), pressing A on another game now opens that game's page with Play. Play asks "Start X? Starting it will close Y", and on yes closes the running game and starts the new one. No more "Quit first" toast. Untested on the PC.

## v0.99.17
- Developer menu: new "Hide Mods" switch. On, it hides the Mods button on the game info page and the Mods card in the control center together. Switch it back any time (the control center shows the change the next time it opens).

## v0.99.16
- Files: pressing A on a picture (png, jpg, webp, bmp, svg, tga) opens a full-screen image viewer. Left/Right or L1/R1 go to the next or previous picture in the folder, A zooms (fit, 2x, 4x), the D-pad moves around while zoomed, B closes. GIF, AVIF and HEIC aren't supported yet.

## v0.99.15
- The Mods page "Get mods from Nexus Mods" now opens the game's own Nexus mods page (RE2/3/4/7, Zero, HD, Skyrim, Fallout, Cyberpunk and a few more). Unknown games still open a search.
- Browser: clicking a text box now opens Tephra's keyboard again (the check was never hooked up). Nexus runs without the web overlay, so there the keyboard doesn't open by itself: Square types.

## v0.99.14 (2026-10-16)
- **Fix: recording couldn't be started from inside a game.** While a game owned the screen, Tephra skipped the check for the held capture button, so only the tap (screenshot) worked. The hold is now checked in games too. Compile-checked only.

## v0.99.13 (2026-10-16)
- **The Album updates by itself.** While it is open, new recordings and photos appear (and deleted ones go) within about 2 seconds, with no need to leave and come back. The tile you were on stays selected. Compile-checked only.

## v0.99.12 (2026-10-16)
- **Music fades out while a recording plays** and fades back in when you leave it. Compile-checked only.

## v0.99.11 (2026-10-16)
- **Fix: recordings wouldn't play.** The player was started with an mpv option (`--input-file`) that this mpv doesn't have, so it quit at once. Tephra now talks to mpv over its IPC socket (`--input-ipc-server`) instead. Checked only against the video log; not run with a real clip.

## v0.99.10 (2026-10-16)
- **Album reworked.** L1 / R1 step through every photo and recording in order (photo, recording, photo...). A recording plays fullscreen in mpv and Tephra reads the pad itself: left stick scrubs (further = faster), D-pad skips 5 s back / forward, Cross pauses, Circle leaves the clip. It also works over a game paused behind the menu: the game stays frozen, and Tephra comes back when you leave the last clip. This replaces the player controls of v0.99.7 to v0.99.9. Compile-checked only, never run on a real pad or game.

## v0.99.9 (2026-10-16)
- **Recording player scrubs 1 second at a time.** D-pad left / right and both sticks move 1 s per step; D-pad up / down skip 5 s, bumpers 10 s, triggers 60 s. Not checked on a real pad.

## v0.99.8 (2026-10-16)
- **Watch a recording while a game is paused.** Open the Album from the menu over a paused game and play a clip: the game stays frozen (never closed), the player runs over it, and when it ends the menu opens again over the game with the Album in front. Choose Resume to carry on where you stopped. While the clip plays Tephra ignores the pad, so the player has it. Not tried on a real game yet: this is the riskiest change so far.

## v0.99.7 (2026-10-16)
- **Recording player controls.** Recordings play in mpv with a progress bar and set controls: D-pad left / right skip 5 s, up / down 30 s, bumpers 10 s, triggers 60 s, sticks scrub, A / Cross pauses, B / Circle leaves. Controls are written to `~/.config/tephra/mpv-input.conf` each time. The button names are from mpv's manual and not checked on a real pad. Playing a recording while a game is open is not done yet.

## v0.99.6 (2026-10-16)
- **DualSense touchpad click now takes screenshots and records.** Linux gives the touchpad its own input device, so Tephra never saw the click as a controller button. A small python watcher now reads it directly and feeds the same capture button (tap = screenshot, hold ~1.5 s = record). It needs read access to `/dev/input`; if that is missing, `~/.config/tephra/touchpad.log` says so. Compile-checked only, never run on a real DualSense.

## v0.99.5 (2026-10-16)
- **REFramework menu fix is stronger.** Missing `MenuOpen` / `RememberMenuState` lines are now added to a game's `*_fw_config.txt`, and games the Mods page knows (not only Steam library folders) are covered. Still only changes a config file that already exists. Tested on a made-up config.
- **Steam's "Battery low" toast.** Tephra's KDE script now also hides any small Steam window (not just ones named "notificationtoasts"), and logs what it hid in the KWin journal. Untested on the real toast.

## v0.99.4 (2026-10-16)
- **Mods: a clean copy of each game's .pak tables.** Opening a game's Mods page saves one small "known good" copy of its .pak table bytes, but only while the game is clean (no Fluffy mods, none of Tephra's switched on, no loose `natives` files). If mods are present it says so and takes nothing. One copy per game version, checksummed, dropped when the game updates. Nothing uses it yet; it prepares a "Remove Fluffy mod" button. Tested on a made-up .pak, not a real game.

## v0.99.3 (2026-10-16)
- **Mods: an overridden mod stays "On".** After holding Accept to put one mod over another, the first mod used to flip to Off (and be forgotten) because some of its files had been replaced. Files taken over by another switched-on mod no longer count against it. If the old mod already shows Off from before, switch the new one off and both back on. Compile-checked only.

## v0.99.2 (2026-10-16)
- **Mods: hold Accept (A / Cross) to override an overlap.** When two mods change the same file and the menu says only one can win, holding Accept on the blocked mod for a second switches it on anyway, so it goes over the other one. Switch the winner off first when taking them out. Compile-checked only.

## v0.99.1 (2026-10-16)
- **One capture button per pad.** Xbox Share, Switch Capture and the DualSense Create button take a screenshot on a tap and start or stop a recording on a hold. The DualSense touchpad click does the same. Not tried on real pads.

## v0.99.0 (2026-10-16)
- **REFramework menu stays closed automatically.** Before any Steam game starts, Tephra sets `MenuOpen=0` and `RememberMenuState=1` in the game's `*_fw_config.txt` (only lines that exist). Tested on a made-up config file, not a real REFramework one.

## v0.98.1 (2026-10-16)
- Two loading-screen jokes removed: "Deleting important all the evidence..." and "Watch out for the big one behind you!".

## v0.98.0 (2026-10-16)
- **Themes are sorted into two groups** in the Control Center and Settings: "Home row" (Tephra, Volcanic, Sleek, Frutiger, Mold) and "Own layout" (Channels, PS2, Wave, Miami, Planet, Circuit). Compile-checked only.

## v0.97.0 (2026-10-16)
- **Volcanic ember glow and hot-metal edges.** The selected Home tile glows orange like hot metal, and the selected Control Center card gets an orange edge and glow. Compile-checked only, not seen on a screen.

## v0.96.0 (2026-10-16)
- **Gun Metal, Nature, Castle and Temple themes removed.** Anyone using them falls back to Tephra.
- **Themes switch faster.** The new theme fades in right away and its sound starts immediately.
- **Volcanic:** glowing lava cracks along the bottom that pulse, plus popping sparks. Visual check only on a headless render, not on your screen.

## v0.95.0 (2026-10-16)
- **Closing the last browser tab no longer closes the browser.** In the Tabs list, closing a tab (Square) brings the list back; when no page is left the selection is on "New tab". In Page view, closing the last tab sends it back to the start page. Untested on a real Firefox.

## v0.94.1 (2026-10-16)
- The mod manager row now just says "Get mods from Nexus Mods".

## v0.94.0 (2026-10-16)
- **Developer menu > Fake loading screen.** Shows the loading screen on its own (bar, button hint and the changing messages like "Writing ... error codes...") with no game behind it, so the messages can be checked. The bar creeps up to 90% over about a minute; press Back (Circle) to stop it. Tested in a headless run: it shows and closes cleanly.

## v0.93.3 (2026-10-16)
- **Planet:** "Press Cross to play" no longer overlaps a game's logo (like Resident Evil 7's "biohazard" line); the text now always sits under the logo, whatever its height.

## v0.93.2 (2026-10-16)
- **Safety net for theme and colour changes.** If a rebuild after choosing a theme or a Wave colour ever stalls, the covering picture (the plain coloured screen) is now removed after 7 seconds instead of staying up for good, so you can see and use what is underneath. The Wave colour change itself works in a test run here (new colour, back on the Colours list), so if it still happens on your PC, tell me what you see after the 7 seconds.

## v0.93.1 (2026-10-16)
- **Simpler Browser card** while the browser is open: Page view (or Back to the page when the web overlay is off), Tabs, Go to an address or search, Web overlay on/off, Close browser. Removed: "Type into the page" (the keyboard opens on its own when you click a text box), "Reload the page" (the Create button reloads), and the long button note. Shorter wording.

## v0.93.0 (2026-10-16)
- **Temple theme reworked.** The "Help & Index" window (fake links and a fake prompt) is now **Controls**: the real buttons for your pad (D-pad, Cross/A, Triangle/Y, PS, hold PS) and what they do. The "Words" window (random words) is now **Tip**: a short real tip that changes every few seconds. Text is bigger. The games window starts higher, so the "Home" name no longer overlaps its title bar.
- **Better Temple icons.** Icons are drawn on a 24 by 24 pixel grid (were 14 by 14) with crisp edges, so the control center, top bar and menus read clearly (checked in a test render).
- **Chunkier 16-colour covers** in Temple: covers are 110 pixels wide with stronger dithering, so the 16-colour look is obvious.
- **Miami's down arrow** under the game title is less than half the size and sits lower, out of the way.
Not tested on your screen.

## v0.92.2 (2026-10-16)
- **Holding PS goes back to the Home icon** in the Circuit and Planet themes too (the other row themes already did).
- **Down arrow on the Home icon** in Circuit and Planet: a small bobbing arrow shows under its name, and pressing Down opens the Home page (your stats and trophies), like in the row themes. Untested on a real screen.

## v0.92.1 (2026-10-16)
- **Button names in sentences match your controller.** Texts like "Press A to play" (Circuit and Planet themes), "Press A again to stop..." (Downloads), the Files messages, the browser notes and the Wi-Fi hint now say Cross / Circle / Square / Triangle on a PlayStation pad, A / B / X / Y on Xbox, and Enter / Esc on a keyboard. The glyph icons in the hint bars already did this. Menu text that is not a button hint was checked and has no other hard-coded buttons.

## v0.92.0 (2026-10-16)
- **Circuit theme moves in a straight line.** Left and Right walk the chips in the order the traces join them (Home, then the games, then the Library), one chip per press, and wrap round at the ends. Up and Down no longer pick games (Up still goes to the top bar).
- **Circuit and Planet open on the Home icon** instead of the first game. The other themes with a Home icon already did; Channels is unchanged. Not tested on a real screen.

## v0.91.0 (2026-10-16)
- **Closing the browser closes all its tabs.** The browser always opens fresh (start page) instead of bringing back your last tabs. Sign-ins are still kept (they are cookies, not tabs); history is still cleared on close. This replaces the tab restore from v0.88.0.
- **Mod warnings** when switching a mod on (they never stop it, except the first case, which already did):
  - Two Tephra mods changing the same file: the message now says how many files and gives an example, and which mod to switch off.
  - A mod installed with Fluffy that changes the same files: warned (Tephra can't switch Fluffy's mods off; the one switched on last wins).
  - Version mismatch: a mod whose name says RT or non-RT gets a reminder to check it matches your game, and a mod none of whose game files match the game's own files says it may be for another version.
  Untested on a real game.

## v0.90.0 (2026-10-16)
- **Ad blocker in the browser.** Tephra's Firefox now gets uBlock Origin. The first time the browser opens, Tephra downloads it in the background from Mozilla's add-on site (needs curl and internet); it is active from the next time the browser opens, and stays in the browser's own profile. Works with the Tephra web overlay and in plain Firefox. Untested on a real PC.

## v0.89.1 (2026-10-16)
- **Smoother right-stick scrolling in the browser.** It starts at once instead of creeping (gentler stick curve, a smaller dead zone feel), reaches a higher top speed, and stops quickly instead of gliding on for about a second. Not tested on a real screen: if it is still too fast or slow, tell me which.

## v0.89.0 (2026-10-16)
- **Tephra keyboard opens when you click into a text box in the browser.** After Cross (click) on the page, Tephra checks whether a text box, search box, password box or text area now has focus and, if so, opens its keyboard over the frozen page; what you type goes into the box. Works while the Tephra web overlay is on (it needs that to ask the page). With the overlay off (plain Firefox) it can't see the page, so Square still opens the keyboard by hand.

## v0.88.0 (2026-10-16)
- The browser now opens your recent tabs again (with their sign-ins) instead of starting on a fresh page; the start page shows only the first time, or when nothing was open. History is still cleared when the browser closes (v0.86.0). Opening a site or a search from Tephra adds it as a new tab.

## v0.87.0 (2026-10-16)
- **Volume stays on steps of 5** (5, 10, 15 ... 100), whatever changes it: headphone buttons, a volume dial, media keys, another app. Tephra puts it on the next step quietly and quickly: a rise goes up to the next 5, a fall down to the previous 5, so every press still moves it. It listens for volume changes (pactl subscribe), so it costs nothing while the volume is left alone. Needs pactl and wpctl (already used by Tephra).

## v0.86.0 (2026-10-16)
- Browser history, form entries, download list and cache are cleared every time the browser closes, while sign-ins (cookies and site data) are kept. The history already there is cleared the next time the browser is closed properly.

## v0.85.1 (2026-10-16)
- Mod list: "On" and "On (Fluffy)" are green and "Off" is red (a filled dot for both), instead of the theme's accent colour and grey.

## v0.85.0 (2026-10-16)
- Browser keyboard: Square (type into the page) and Triangle (address / search) now open the on-screen keyboard straight over the page, which is frozen completely and shown sharp, as it was, instead of a blurred picture behind the control center. Cross sends the text to the page; Circle cancels and the page carries on.

## v0.84.1 (2026-10-16)
- Browser, no more dead ends: PS over Page view now opens the control center (it used to jump to the live Firefox page), holding PS for Home no longer leaves Home hidden behind Page view, and a control center opened from Page view is now the ordinary one, so closing it or coming back from Mods or the Album no longer ends on an empty screen. The Page view connection error now says what to press.

## v0.84.0 (2026-10-16)
- **Get mods from Nexus Mods** in a game's mod list: opens Tephra's browser on a Nexus search for the game, as plain Firefox (no Tephra overlay, so the site sees an ordinary browser). Sign in once, the login is kept; press Manual download on a mod and the zip lands in Downloads, where Add mods lists it first. Free accounts still go through Nexus's own slow-download page. The one-click "Mod Manager Download" button is not supported.

## v0.83.1 (2026-10-16)
- **Reload** with Triangle (or Y / F5 on the keyboard) in a game's mod list, shown as a hint at the bottom: Tephra rereads Fluffy's record for the game (its installed.ini) and looks at the game's files again, so every mod's status (On, Fluffy, off) is up to date after you changed something in Fluffy or in the game folder. Every row gives a small shrink-and-grow, one after another, to show that it reloaded. Fluffy itself never has to open.

## v0.83.0 (2026-10-16)
- First version of the reload (a "Reload Fluffy" row in the mod list); replaced by the Triangle shortcut in v0.83.1.

## v0.82.1 (2026-10-16)
- The Mods button no longer makes folders named after the game's title ("Resident Evil 7 biohazard", "Resident Evil 3"). It looks for your existing Fluffy folder first (RE7, RE3R, RE9...), matching on the program's name and on the title's initials ("Resident Evil 3" -> re3 -> RE3R, the remake first), then on Fluffy's own folder names, and only makes a new folder when none of those fit.

## v0.82.0 (2026-10-16)
- Steam is no longer closed while it still has an update to do for its own tools: Proton, the Steam Linux Runtimes and Steamworks Common. Before, Tephra only waited for downloads that had already started, so Steam could be shut down just as it was about to fetch one. It now waits for a pending tool update (up to 15 minutes if it gets stuck) and closes Steam afterwards as usual.

## v0.81.2 (2026-10-16)
- The **Mods** button now shows on games you added by hand (non-Steam, like RE3 and RE7), not only on Steam games. It opens the game's folder in ~/Games found by the program's name ("re7.exe" -> RE7) or the title, uses Fluffy's own folder name when the name is one it knows, and otherwise makes a folder from the program's folder name and links the program as the game's install. PS2 games still have no Mods button.

## v0.81.1 (2026-10-16)
- Storage bar on a game's page: the legend under it now follows the bar from left to right (Other games, Proton, Workshop, Other, This game, Free) instead of listing This game first. The Home page's storage bar already did.

## v0.81.0 (2026-10-16)
- **Size of non-Steam games:** Tephra measures the folder of each game added by hand (the folder its program is in; for a game under ~/Games/<Name>/..., the whole <Name> folder) and shows it wherever Steam games show their size (game page, library, storage totals). It is measured in the background and again after a day. Shared folders (home, Downloads, /usr...) and PS2 games are skipped.

## v0.80.6 (2026-10-16)
- Every missing cover now gets the same search: Steam games, hand-added games and PS2 games all try the shortened and spelled-out names (no .exe, Demo, Teaser, subtitles; "RE7" as Resident Evil 7), and each one writes a line to ~/.config/tephra/install.log when nothing is found.

## v0.80.5 (2026-10-16)
- A game added by its file name (like "re7.exe") is now searched without ".exe", so "RE7" is looked up as Resident Evil 7 for its cover and logo.

## v0.80.4 (2026-10-16)
- Covers for games added by hand (non-Steam, like a game added from Settings or the Mods page): the name search now tries the same shortened names as Steam games (without Demo, Teaser, subtitles), retries after 6 hours instead of 2 days, and writes a line to ~/.config/tephra/install.log when nothing is found, so a missing cover can be traced.

## v0.80.3 (2026-10-16)
- The **Tephra web overlay** (Firefox hidden, pages drawn by Tephra) is now a switch you can reach before opening the browser: Control center > Browser shows "Tephra web overlay: on / off" under the sites. Off gives plain Firefox. It was only offered while the browser was already open (as "Page mode").

## v0.80.2 (2026-10-16)
- Keyboard: **X** (or Delete) removes the selected Bluetooth device, and X, Y or Delete forgets the selected Wi-Fi network, the same as Square on the pad. It only worked with the controller before.

## v0.80.1 (2026-10-16)
- Screenshots are back on the DualSense **Create** button (Share on a DualShock 4): press for a screenshot, hold to start or stop recording. The touchpad click no longer does anything in Tephra. Settings > Buttons calls the row "Create button".

## v0.80.0 (2026-10-16)
- **Calibrate display** in Settings > Display (HDR section): three pages like a console's HDR set-up. Black level (two emblems, make the right one barely visible), white level (same on white), and the PlayStation-style sun symbol. The pictures use exact colour codes without smoothing, so "barely visible" means the same on every screen. With HDR on, Up/Down change KDE's "Brightness of non-HDR content" (80-600 nits); Back on the first page puts it back. With HDR off the pages are a guide for the monitor's own buttons. Tephra draws in SDR, so it cannot measure or set the HDR peak.

## v0.79.0 (2026-10-16)
- The Browser now opens straight into Tephra's own Page view: Firefox runs hidden behind it and its window is never shown. It starts on a Tephra start page (YouTube, Netflix, Twitch, Google, Wikipedia, Reddit); Triangle types an address or search. Circle on the first page opens the menu, "Back to the live page" is still there for video and DRM sites that Page view can't draw. Turn it off with Page mode in the Browser menu.
- Firefox no longer shows its own boxes: no "save password", no Firefox sign-in, no notification, location, camera or microphone requests, and cookie banners are rejected where Firefox can. Takes effect the next time the browser opens.

## v0.78.2 (2026-10-15)
- Loading screen: about 50 more silly lines. The "Writing N error codes..." line stays a second longer (4.8 s), and its number now climbs while it is on screen: it keeps ticking up on its own and is never lower than the loading bar's progress.

## v0.78.1 (2026-10-15)
- Control center pop-ups (Notifications, Downloads, Sound, Browser, Themes, Power, the info bar numbers) stay on the screen: they are kept inside its edges, and when their rows are taller than the room there scroll with the selection. Long lines wrap in a narrower pop-up, so it grows taller instead of wider. A notification shows its time above its text.

## v0.78.0 (2026-10-15)
- A **Mods** button on a game's page (next to Play, Rename and Uninstall) and in its menu opens the mod manager on that game's Mods folder. Back goes back to the game's page. Games Fluffy doesn't list get their folder made in ~/Games.
- Cover art by name: a game whose Steam cover is missing or only a blank placeholder (demos, test builds) now borrows the pictures of the store game with the same name (RESIDENT EVIL 7 biohazard Demo -> RESIDENT EVIL 7 biohazard). Before, a blank placeholder in Steam's own folder stopped the name search, and borrowed pictures were never shown even when found. The pictures are used by every theme, the Library, the game page and the menus. A failed lookup is tried again a few minutes later, and what was found is written to ~/.config/tephra/install.log.
- v0.77.0 / v0.76.x: Mods without Fluffy's window, Add a game by Fluffy's own game names, RE Engine .pak entries are hidden for loose-file mods (and restored when switched off).

## v0.3.0 — UI revamp (2026-10-11)

### Home
- New **Home tile** at the start of the row, with Tephra's animated background (drifting shards, rising ash). Tephra starts here, and holding the system button always comes back here.
- Top bar: **shard · clock · Wi-Fi** on the left, **Steam name + profile picture** on the right (from the Steam Web API, with an offline fallback).
- Game info card moved to the **bottom right**, just above the row. Button hints are bottom right too.
- Smooth scrolling along the row instead of snapping.
- Games with no tall cover show their store banner plus the name. The name only shows when there's no cover.
- After a game closes, it comes back first in the row and stays selected.

### Control center (v1.3)
- **Sound panel** opens above the Volume card: volume slider, output device list, mute, and mic mute. Up/Down on the Volume card still changes volume.
- Power options open in a panel above the Power card.
- **Controller cards**: numbered 1, 2, 3… in connection order, with an icon for the controller type and its battery.

### Controllers
- DualSense lightbar fades up to Tephra navy during the boot logo. Player lights show the player number. *(Needs the udev rule in configs/udev.)*
- **Low battery warning** at 15% and 5%: a notification at the top right and the lightbar flashing red.

### Library
- Smooth scrolling. Not-installed games are darker, not see-through. Banner fallback art. Same clock row as home.

### Other
- System button glyph is the Tephra shard in a circle (no console brand logos).
- New files: icons.gd, controllers.gd, toast.gd, tephra_bg.gd, steam_account.gd.
- Updater v2: git snapshot before each update, version tags, and GitHub push.

## v0.2.0 — Control center, library, info card
- Control center (quick press of the system button): volume, Wi-Fi, battery, power. Hold the button to go home.
- Library of every owned game (Steam Web API), Play for installed games.
- Game info card: Steam Deck rating, controller support, description, last played, playtime, size.
- Button glyphs match the controller in use (PlayStation / Xbox / Nintendo / keyboard).

## v0.1.0 — Boot to games
- Seamless boot: PC maker logo → Tephra logo → fade to home.
- Installed Steam games in a row, sorted by last played, launch with the controller, and fade back home when the game exits.
- Steam popups hidden with KWin rules; cursor hidden.
