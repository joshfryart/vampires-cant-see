# Troubleshooting

## The screen is black or blank
Click the page once. Browsers wait for a click before the game starts. If it
is still blank, reload the page with `?safe=1` added to the address (for
example `index.html?safe=1`). That skips saved settings. If it still does
not work, press F3 (or add `?debug=1`) and look at the debug text, then use
the error report steps below.

## The mouse won't turn
Click the game to lock the mouse. Press Esc to release it. If the mouse is
not locked, drag with the left button to look (**Drag to look** is on by
default; check Settings). If your browser refuses mouse lock (common in some
browsers and inside embedded previews), use the Left and Right arrow keys to
turn. Up and Down walk you forward and back.

## Open in another tab
If you see **Game is open in another tab — saving is paused here.**, the game
is already running in another tab or window. Saving is paused in this one so
the two cannot overwrite each other. Close the other tab, or keep playing
there. This tab resumes saving on its own shortly after the other tab closes.

## "Not saved" dot
A small coral dot with the words **not saved** in the bottom-right corner
means the last save failed, or saving is paused by another tab. If it stays
on, check the save error codes below, close other tabs, and export your save
from the menu.


## My save is gone
Browsers can clear saved data (for example, when you clear history or use a
private window). Saves live in your browser only. Click **Export save** in the
main menu now and then to keep a copy, and use **Import save** to load it
again.

## Meta save was damaged, restored backup
Your upgrades, essence or stats copy was damaged, so the game loaded the
backup copy. Your progress may be a little behind. Nothing else to do. Export
your save from the menu to keep a clean copy.

## Meta save was damaged (CODE). Started fresh.
The upgrades, essence and stats save could not be read, and no backup was
usable. You start with zero essence, no upgrades and empty stats.
1. If you have an exported save file, use **Import save** and pick it.
2. Otherwise, the game continues with a fresh save. Export often to avoid this.

The code in brackets is listed in the table below.

## Run save could not be loaded (CODE)
The saved run could not be read, so it was removed and **Continue** is off.
Click **New run** to start again. Your upgrades and essence are not affected.

## Import failed (CODE)
The file you chose was not loaded and your saves were not changed. Check the
file and see the table below.

## Save error codes

| Code | What it means | What to do |
|---|---|---|
| E_SAVE_PARSE | The file is not valid JSON. It was cut off or edited by hand. | Export a new save and use that file. Do not edit save files. |
| E_SAVE_BAD_KEY | The file has a forbidden field name (`__proto__`, `constructor` or `prototype`). | Use an unedited export from this game. |
| E_SAVE_CHECKSUM | The data does not match its checksum. It was changed after it was saved. | Use an unedited export. Do not edit save files. |
| E_SAVE_SCHEMA | The save has the wrong shape or is missing parts. | Use an unedited export made by this game. |
| E_SAVE_TOO_BIG | The file is over 128 KB (import), or a save is too large to store. | Import only an exported save file. Normal play should not hit this. |
| E_SAVE_QUOTA | Browser storage is full or blocked. This happens in private windows or when site data is blocked. | Close other tabs, clear old site data for other sites, or leave private mode. Export your save. |
| E_SAVE_VERIFY | The browser did not store the save correctly. | Close other tabs and try again. Check that storage is not full. |
| E_SAVE_VERSION | The save was made by a newer version of the game. | Use the newer build of the game. |
| E_SAVE_NONE | No save was found. | On a first visit this is normal. For a run, start a new one. For an import, pick a different file. |

## Full reset
This deletes all saves and settings for this game in this browser. Export
your save first if you want to keep your upgrades.

1. Open DevTools (F12, or right-click and choose Inspect).
2. Open the **Application** tab (Chrome, Edge) or **Storage** tab (Firefox).
3. Under **Local Storage**, select the address of the game.
4. Delete every key that starts with `vcs.` (for example `vcs.run`,
   `vcs.meta`, `vcs.settings`, and their `.bak` copies).
5. Reload the page.

Or clear the site data for the game address from your browser's settings.

## The game is slow or the frame rate is low
Lower the render scale in settings, or close other browser tabs. Press F3 to
see the frame rate.

## There is no sound
Click the page once. Browsers block sound until you interact with the page.
Also check the Volume setting in Settings.

## The night ended without warning
Dawn at 06:00 ends the run if you are outdoors. Stepping outside while it is
day ends it too, even indoors. Get back to your crypt or a safe spot before
dawn, and sleep there to end the night.

## An error screen appeared
The game shows this screen after a crash, or after three frame errors in a
row (code `E_LOOP`).

1. Click **Copy error report**. If copying fails, the report appears in a box
   on the screen. Select all the text in it and copy it.
2. Or click **Download log** to save a text file. The same two buttons are in
   the Paused menu (Esc).
3. Send that report or file to the person who gave you the game.
4. Click **Reload** to try again.

## Safe mode
Add `?safe=1` to the address (for example `index.html?safe=1`). This ignores
your saved settings and starts with the defaults. Try it if the game fails
after a settings change, or if the screen stays blank.

## Debug mode
Add `?debug=1` to the address. This records more detail in the log and turns
on the F3 overlay right away. It also enables the map view (M) and the test
hooks listed in the README.

## Drinking stops at once
Another person saw you (torchlight or within 1 cell), you let go of the right
button (or R), or the mouse lost capture. Drink from behind, in the dark.

## Power does nothing
A power works only when all three of these are true:
- **It is unlocked.** Shriek opens on night 1, Mist on night 2 and Still on
  night 3. Locked powers are not shown.
- **You have enough blood.** Shriek costs 15; Mist and Still cost 10 each. A
  dim icon with no sweep means you lack the blood. The game shows a "Not
  enough blood" card, at most once every 3 seconds.
- **It is not cooling down.** A dim icon with a sweeping arc is recharging.
  Wait until it shows its key letter.

## Overflow bar not filling
- **Gifts are closed for tonight.** After 2 gifts the overflow bar stops
  filling, and drinking at full blood works as before. The count resets when
  you sleep.
- **You are not at full blood.** The bar only fills while you drink with your
  blood at its maximum.
