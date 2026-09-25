# comfylogin: development notes

The facts here were measured on 2026-09-25 in two 1.12 clients: an OctoWoW build and a Turtle build. The code is `ComfyLogin.xml` and `ComfyLogin.lua`. The build is `node build.js`, which writes `patch-W.mpq` at the repo root.

## How the files load

A patch cannot add a glue file on its own. The client loads only the files that `Interface\GlueXML\GlueXML.toc` names. Replacing the toc is not safe: the two clients have different tocs, and paokkerkir's autologin replaces the toc and drops OctoWoW's six locale files with it.

So ComfyCraft's `patch-V` has this line at the end of its `CharacterCreate.xml`:

```xml
<Include file="ComfyLogin.xml"/>
```

`ComfyLogin.xml` loads `ComfyLogin.lua` with a `<Script>` line. When the file is not there, the client writes one line to `Logs\GlueXML.log` and loads the rest of the screen:

```
Couldn't open Interface\GlueXML\ComfyLogin.xml
```

`CharacterCreate.xml` loads after `AccountLogin.xml` and `CharacterSelect.xml`. So every function that comfylogin wraps exists when `ComfyAccounts_OnLoad` runs.

Letter W is not used by any pack that the ComfyCraft launcher lists, or by either test client.

## Where the list is kept

The list is in `Imports\logins.txt`, through Nampower's `ImportFile` and `ExportFile`. The format is paokkerkir's: a Lua table, read back with `loadstring` in an empty environment. comfylogin keeps any key it does not know. A file that does not parse is never written over.

The login screen has no other place to keep data. It has no `GetCVar`, `SetCVar` or `RegisterCVar`. The only saved string is the saved account name, in `Config.wtf`. The client reads each `Config.wtf` line into a 127-byte buffer, so the value can be about 109 characters. A 187-character value came back as 110 characters, with no closing quote. That is room for about four accounts and no character order.

Without Nampower the list stays hidden, and the login screen is the stock screen.

## Traps

**The client clears the password string after a login.** It clears every copy of the string in memory (paokkerkir found this). comfylogin stores each password with a `:` in front, which makes a different string, and removes the `:` when it uses it.

**The login boxes take the focus back.** Turtle's two edit boxes do not have `autoFocus="false"`. After `ClearFocus`, the account box took the focus again with all its text selected, so one key replaced the name. That matters on a gamepad, where one button can send a click and a number. comfylogin gives the focus to `ComfyAccountsSink`, an edit box that drops every key. Enter logs in and Tab goes to the password box. Esc does nothing, because the stock Esc on the login screen quits the game.

**The sink must be off the screen, not transparent.** At alpha 0 its cursor still blinked. It is 10000 units off the screen. A hidden edit box cannot hold the focus.

**The character select highlight is too bright for a 40-unit row.** At full strength it fills the row with solid gold. The row glow uses the same texture at alpha 0.35. It is a texture that the code shows and hides, not a `HighlightTexture`, so that one row glows at a time.

## Character order

The engine numbers the characters from 1 and uses that number for every call: `SelectCharacter`, `EnterWorld` and delete. comfylogin does not move characters in the engine. It draws the buttons in the saved order, and a click on button k means the character that button k shows.

The order is kept by character name. paokkerkir's matched by number, which goes wrong after a delete, because the characters after it move up one.

## Other autologin patches

comfylogin does nothing when `LoginManager` (paokkerkir's) or `Autologin_Table` (the older Haaxor-style patch) is defined. Their files load after `CharacterCreate.xml`, so each wrap tests this at every call and not once at load.
