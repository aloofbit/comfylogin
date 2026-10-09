# comfylogin: development notes

The facts here were measured on 2026-09-25 in two 1.12 clients, an OctoWoW build and a Turtle build, and on 2026-10-07 in a stock 1.12.1 client (`WoW.exe` md5 `ccf83146dbb3d10ef826aa4de178a5be`). The patch is `ComfyLoginPanel.xml` and `ComfyLogin.lua`, built by `node build.js` into `patch-W.mpq`. The DLL is `dll/comfylogin.cpp`, built by CMake into `comfylogin.dll`:

```
cmake -B build -A Win32
cmake --build build --config Release
```

Both land at the repo root.

## How the files load

A patch cannot add a glue file on its own. The client loads only the files that `Interface\GlueXML\GlueXML.toc` names. Replacing the toc is not safe: the clients have different tocs. paokkerkir's autologin replaces the toc and drops OctoWoW's six locale files with it.

So comfylogin rides in a file the toc already names. `patch-W` ships its own copy of `MovieFrame.xml`, the intro cinematic frame, with one line added at the end:

```xml
<Include file="ComfyLoginPanel.xml"/>
```

`ComfyLoginPanel.xml` loads `ComfyLogin.lua` with a `<Script>` line.

**Why `MovieFrame.xml`.** A host file must meet three rules:

1. It loads after `AccountLogin.xml` and `CharacterSelect.xml`, so every function that comfylogin wraps exists when `ComfyAccounts_OnLoad` runs.
2. No other pack ships it. `W` sorts after every numbered and lettered patch below it, so our copy replaces theirs. A host that `patch-V` or Turtle edits would lose those edits.
3. It is the same bytes in every client, so one copy fits all of them.

In `octow`, `octow - Copy` and `clean-turtle`, three files meet all three: `PatchDownload.xml`, `MovieFrame.xml` and `CreditsFrame.xml`. Each comes from Blizzard's 1.12.1 `patch.MPQ`, and Turtle has not changed them. `MovieFrame.xml` is the smallest, 1,448 bytes, so our copy pins the least. `build.js` packs `src/MovieFrame.xml`, which is Blizzard's file plus the Include line. Checked: our copy without that line is byte for byte the stock file.

The cost: if a pack ever ships its own `MovieFrame.xml`, ours hides it.

**The old hook.** comfylogin first loaded through ComfyCraft's `patch-V`, which has `<Include file="ComfyLogin.xml"/>` at the end of its `CharacterCreate.xml`. That line is in clients now. With the panel still under that name, such a client would load it twice. So `patch-W` also ships a `ComfyLogin.xml` that is an empty `<Ui>`: the old line loads nothing, and it no longer writes `Couldn't open Interface\GlueXML\ComfyLogin.xml` to `Logs\GlueXML.log`.

Measured in `octow - Copy` on 2026-09-25: with `patch-V`, the panel shows once and `GlueXML.log` is not written. With `patch-V` moved out, the panel shows on Turtle's own login screen and `GlueXML.log` is not written. The log is written only when something fails.

Letter W is not used by any pack that the ComfyCraft launcher lists, or by either test client.

## Where the list is kept

The list is in `WTF\comfylogin.txt`, through the DLL's `ComfyLoginRead` and `ComfyLoginWrite`.

The format is paokkerkir's: a Lua table, read back with `loadstring` in an empty environment. comfylogin keeps any key it does not know. A file that does not parse is never written over. `ComfyLoginRead` returns `false` for a file that exists but cannot be read, and the Lua treats that the same way.

comfylogin does not read `Imports\logins.txt` (Nampower's `ImportFile`, and paokkerkir's list). Up to v0.2.0-alpha it did, and on 2026-10-08 an old file there left the login screen black. The owner dropped the import instead of finding the cause.

The login screen has no other place to keep data. It has no `GetCVar`, `SetCVar` or `RegisterCVar`. The only saved string is the saved account name, in `Config.wtf`. The client reads each `Config.wtf` line into a 127-byte buffer, so the value can be about 109 characters. A 187-character value came back as 110 characters, with no closing quote. That is room for about four accounts and no character order.

Without the DLL, the list stays hidden, and the login screen is the stock screen.

## Passwords

A password is stored in one of two forms:

| Form | Written by | Logged in with |
|---|---|---|
| `:` and the password | the Lua, when `ComfyLoginEncrypt` fails | the stock login, with the `:` removed |
| `:comfy:` and base64 DPAPI | `ComfyLoginEncrypt` | `ComfyLoginServerLogin` |

`ComfyLoginEncrypt` calls `CryptProtectData` with user scope and the fixed entropy `comfylogin`. The entropy is not a secret: it keeps these blobs apart from other programs' DPAPI blobs. `ComfyLoginServerLogin` decrypts in C and calls the client's login function, so a decrypted password never reaches Lua. A typed password is encrypted first and logs in the same way. `ComfyLoginCanDecrypt` tells the Lua whether a stored password decrypts here, without returning it.

A click on an account with an encrypted password puts `COMFY_ACC_SAVED` (`~comfy~saved~`) in the password box, which shows it as asterisks. The Login wrap never sends it: it sends the stored password instead. A change to the account name clears it, so it never logs in another account.

**Under Wine, DPAPI is not a secret.** Wine's `CryptProtectData` (`dlls/crypt32/protectdata.c`, read 2026-10-07) derives the key from the user name, a fixed string compiled into Wine and the salt stored in the blob. It ignores `dwFlags`. Anyone with the file and the user name can decrypt it.

## comfylogin.dll

The DLL makes three patches at `DLL_PROCESS_ATTACH`. Each is made only when the stock bytes are found. Otherwise the DLL logs to `Logs\comfylogin.log` and leaves that part alone. Before the patches, it writes and deletes `WTF\comfylogin.probe` and logs whether `WTF` can be written, and whether `WTF\comfylogin.txt` is read-only.

`ComfyLoginCheckWrite` makes the same test each time the login screen loads. When it finds a problem, or when a save fails, `ComfyAccountsError` shows the reason in red in the panel's corner. When the panel shows, the error box goes under it.

All addresses were read in the stock exe and compared with the `octow`, `octow - Copy` and `twow-hd` exes on 2026-10-07 (capstone disassembly). The bytes are the same in all four, except where a row says otherwise. Nampower's names come from `offsets.hpp` in github.com/Emyrk/nampower.

**1. The GlueXML signature check.** `0x6F10F0` checks one glue file against its signature. It returns 3 for a match, and 0, 1 or 2 for no signature, a bad signature or a mismatch. A stock client that loads a changed glue file writes `GlueXML is modified or corrupt` to `Logs\GlueXML.log` and closes. Four changes send every path to the `return 3`:

| Address | Stock | Patched | Path |
|---|---|---|---|
| `0x6F113A` | `5F 5E` | `EB 19` | no signature file |
| `0x6F1158` | `01` | `03` | bad signature |
| `0x6F11A7` | `01` | `03` | the signature does not verify |
| `0x6F11F0` | `5F 5E` | `EB B2` | the hash compare |

The Turtle and OctoWoW exes have the patched bytes. A PowerShell script on the forums makes the same change to the file. The DLL changes memory only, so `WoW.exe` stays the stock file.

**2. The pointer check.** The Lua VM calls a C function from two places. Before each call it loads the function into `ecx` and calls `0x42A320`. That function closes the client with `Invalid function pointer` for an address outside a range in WoW.exe, so a function in a DLL fails when Lua calls it, not when it is registered. The five bytes of each call become `90`. The calls have no stack arguments, and `eax` is not read after them. Nampower hooks `0x42A320` itself, and Turtle changed that function's body, so the call sites are the places that are the same in every exe. The DLL patches both sites or neither.

| Address | Stock | Patched |
|---|---|---|
| `0x6F5DE6` | `8B CE E8 33 45 D3 FF` (`mov ecx, esi; call 0x42A320`) | `8B CE 90 90 90 90 90` |
| `0x6F619F` | `8B CF E8 7A 41 D3 FF` (`mov ecx, edi; call 0x42A320`) | `8B CF 90 90 90 90 90` |

`0x42A320` has three more callers: `0x6F601B` (the Lua debug hook) and `0x63CE8F` and `0x63DF6B` (frame code). None of them calls a function that comfylogin registers.

**v0.2.0-alpha patched only `0x6F5DE6`.** It closed a client that had no Nampower. Nampower's hook on `0x42A320` passed every address, so the second site did not show in a test with Nampower loaded. The bytes at both sites are the same in the stock, `octow`, `octow - Copy`, `twow-hd` and `uninitialized-client` exes (checked 2026-10-08).

**3. The login screen's functions.** `0x46A7B0` builds a new Lua state each time the login screen opens, then at `0x46A880` calls `0x46ABB0`, which registers the client's glue functions (Nampower's `Glue_LoadScriptFunctions`). The DLL changes that call's target to its own function, which makes the same call and then registers six functions with `FrameScript_RegisterFunction` (`0x704120`, `__fastcall(name, fn)`). It patches the call site and not the head of `0x46ABB0`: Nampower hooks the head, and the Turtle exes have a `jmp` into their own code at `0x46ABC4`.

The Lua VM calls a C function as `__fastcall(L)`: `mov ecx, edi; call esi` at `0x6F5DF3`. It returns the number of results. The Lua API functions the DLL calls, all `__fastcall(L, ...)`:

| Function | Address |
|---|---|
| `lua_gettop` | `0x6F3070` |
| `lua_isstring` | `0x6F3510` |
| `lua_tostring` | `0x6F3690` |
| `lua_pushnil` | `0x6F37F0` |
| `lua_pushstring` | `0x6F3890` |
| `lua_pushboolean` | `0x6F39F0` |
| `CGlueMgr::DefaultServerLogin(user, password)` | `0x46AFB0` |

The DLL checks the first bytes of each before it registers anything.

**Checked on 2026-10-07 in clean-vanilla** (stock exe, Nampower 2.2 with no `ImportFile`, `comfylogin.dll` first in `dlls.txt`): the log shows all three patches, the panel shows, and every saved password was in the `:comfy:` form. `ProtectedData.Unprotect` in PowerShell, with the entropy `comfylogin`, decrypts each one.

## Traps

**The client clears the password string after a login.** `0x46AFB0` writes zeros over the string it gets, in place. Lua keeps one copy of each text, so every Lua value with the same text becomes zeros (paokkerkir found this). An account name or a character name that is the same as the password is cleared with it, and the next save writes the zeros to the file. comfylogin stores each password with a `:` in front, which makes a different string, and removes the `:` when it uses it. With the DLL, a typed password is encrypted and sent through `ComfyLoginServerLogin` too, so the client clears the DLL's copy and no Lua string. The stock login is used only when `ComfyLoginEncrypt` fails.

**The stock login screen has no `_G`.** Turtle's has. On a stock client, `_G[name]` stopped the file at load with `attempt to index global '_G' (a nil value)`. comfylogin uses `getglobal(name)`, which Blizzard's own glue code uses and every 1.12 client has.

**The stock login screen has no `CLASS_COLORS`.** comfylogin has its own table, 1.12.1's `RAID_CLASS_COLORS`, keyed by the English class name, for when `CLASS_COLORS` is missing.

**The login boxes take the focus back.** Turtle's two edit boxes do not have `autoFocus="false"`. After `ClearFocus`, the account box took the focus again with all its text selected, so one key replaced the name. That matters on a gamepad, where one button can send a click and a number. comfylogin gives the focus to `ComfyAccountsSink`, an edit box that drops every key. Enter logs in and Tab goes to the password box. Esc does nothing, because the stock Esc on the login screen quits the game.

**The sink must be off the screen, not transparent.** At alpha 0 its cursor still blinked. It is 10000 units off the screen. A hidden edit box cannot hold the focus.

**The character select highlight is too bright for a 40-unit row.** At full strength it fills the row with solid gold. The row glow uses the same texture at alpha 0.35. It is a texture that the code shows and hides, not a `HighlightTexture`, so that one row glows at a time.

## Character order

The engine numbers the characters from 1 and uses that number for every call: `SelectCharacter`, `EnterWorld` and delete. comfylogin does not move characters in the engine. It draws the buttons in the saved order, and a click on button k means the character that button k shows.

The order is kept by character name. paokkerkir's matched by number, which goes wrong after a delete, because the characters after it move up one.

## Other autologin patches

comfylogin does nothing when `LoginManager` (paokkerkir's) or `Autologin_Table` (the older Haaxor-style patch) is defined. The older patch replaces `AccountLogin.xml` and `CharacterSelect.xml`, and paokkerkir's adds a toc line after `MovieFrame.xml`. So each wrap tests this at every call and not once at load.
