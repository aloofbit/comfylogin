# comfylogin

**Bugs, questions and screenshots: [join our Discord](https://discord.gg/YSWzYk8xP).**

[![Discord](https://img.shields.io/badge/Discord-ComfyCraft-5865F2?logo=discord&logoColor=white&style=for-the-badge)](https://discord.gg/YSWzYk8xP)

comfylogin is a patch for the World of Warcraft 1.12 client on ComfyCraft. It keeps a list of your accounts on the login screen. It also lets you put your characters in the order you want, and choose one character that each login goes to.

## What it does

On the login screen:

- A list of your accounts is in the top right corner. Each row shows the account name and a character from that account.
- Click an account to fill in the name and the password. Double click an account to log in.
- After you click an account, you can change the name or the password before you log in. A new password is saved only when the login succeeds.
- Each login that succeeds is added to the list. Hover over an account and click the x to remove it.
- The list shows four accounts on each page. The page arrows show under the list when you have more than four accounts.

On the character select screen:

- Hover over a character to show the arrows. Click an arrow to move that character up or down. The order is saved for each account and realm.
- Select a character and tick **Auto login**, to the right of **Enter World**. Each login with that account then goes to that character. There is one auto login character for each account and realm.
- To choose a different character, log out to the character select screen. That screen does not go into the world by itself.

## Before you install comfylogin

You must have these items:

- The ComfyCraft client patch, `patch-V.mpq`. The ComfyCraft launcher installs it.
- Nampower. comfylogin keeps the list in a file, and only Nampower lets the login screen read and write a file.

## How to install comfylogin

The ComfyCraft launcher installs comfylogin. Tick **Saved accounts** in the **ComfyCraft** section of the **Mods** tab.

To install it yourself:

1. Close the game.
2. Copy `patch-W.mpq` to the `Data` folder of your client.
3. Start the game.

## Your passwords

comfylogin keeps the list in the file `Imports\logins.txt` in the client folder. **THE FILE CONTAINS YOUR PASSWORDS. DO NOT GIVE THIS FILE TO OTHER PERSONS.**

The passwords are plain text. If you set the environment variable `WOW_ENCRYPTION_KEY` before a login, Nampower encrypts the password that is saved.

## Other autologin patches

comfylogin reads and writes the same file as [paokkerkir/vanilla-autologin](https://github.com/paokkerkir/vanilla-autologin). The accounts that you saved with it show in comfylogin.

Do not use two autologin patches together. If the client has a different one, comfylogin does not show its list, and the other patch operates as before.

## Thanks

comfylogin is a new patch. Its design comes from [paokkerkir/vanilla-autologin](https://github.com/paokkerkir/vanilla-autologin), [Haaxor1689/vanilla-autologin](https://github.com/Haaxor1689/vanilla-autologin) and [Otari98/Reorder-Patch](https://github.com/Otari98/Reorder-Patch).

## Licence

GNU General Public License v3.0. See `LICENSE`.
