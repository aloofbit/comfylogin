-- comfylogin: saved accounts on the login screen, and the order of the
-- characters on character select, with an auto login character. The frames
-- are ComfyLogin.xml, which loads this file. Written after
-- paokkerkir/vanilla-autologin (itself after Haaxor1689/vanilla-autologin and
-- Otari98/Reorder-Patch), whose file it reads and writes, so accounts saved
-- with it carry over.
--
-- THE LIST NEEDS NAMPOWER. It lives in Imports\logins.txt, through Nampower's
-- ImportFile and ExportFile. The only glue storage without a DLL is the saved
-- account name in Config.wtf, and the client reads each Config.wtf line into
-- 127 bytes, which leaves about 109 characters (measured 2026-09-25). Without
-- Nampower the panel stays hidden and the login screen is stock.
--
-- IT STANDS DOWN FOR ANOTHER AUTOLOGIN. paokkerkir's defines LoginManager and
-- the older one defines Autologin_Table. Both wrap the same functions, and
-- theirs load after this file, so the test runs at every call, not once.

local ComfyAcc = { page = 0 };
local COMFY_ACC_PAGE = 4;
local COMFY_ACC_ROW = 40;
local COMFY_ACC_GAP = 12;
local ComfyAccData;

local function ComfyAccOff()
	return not ( ImportFile and ExportFile ) or LoginManager ~= nil or Autologin_Table ~= nil;
end

-- The same shape paokkerkir's writes: a Lua table, read back with loadstring.
local function ComfyAccSerialize(value, indent)
	local kind = type(value);
	if ( kind == "string" ) then
		return string.format("%q", value);
	elseif ( kind == "number" or kind == "boolean" ) then
		return tostring(value);
	elseif ( kind ~= "table" ) then
		return "nil";
	end
	local inner = indent .. "  ";
	local out = "{\n";
	for k, v in pairs(value) do
		local key;
		if ( type(k) == "string" and string.find(k, "^[_%a][_%w]*$") ) then
			key = k;
		else
			key = "[" .. ComfyAccSerialize(k, inner) .. "]";
		end
		out = out .. inner .. key .. " = " .. ComfyAccSerialize(v, inner) .. ",\n";
	end
	return out .. indent .. "}";
end

-- A file that does not parse is never written over: the list stays empty for
-- this session and the file stays as it was.
local function ComfyAccLoad()
	ComfyAccData = { accounts = {} };
	ComfyAcc.broken = nil;
	local ok, text = pcall(ImportFile, "logins");
	if ( not ok or type(text) ~= "string" or text == "" ) then
		return;
	end
	local chunk = loadstring("return " .. text);
	if ( chunk and setfenv ) then
		setfenv(chunk, {});
	end
	local good, data;
	if ( chunk ) then
		good, data = pcall(chunk);
	end
	if ( not good or type(data) ~= "table" ) then
		ComfyAcc.broken = true;
		return;
	end
	if ( type(data.accounts) ~= "table" ) then
		data.accounts = {};
	end
	ComfyAccData = data;
end

local function ComfyAccSave()
	if ( ComfyAcc.broken or not ComfyAccData ) then
		return;
	end
	pcall(ExportFile, "logins", ComfyAccSerialize(ComfyAccData, ""));
end

local function ComfyAccFind(name)
	if ( not name ) then
		return nil;
	end
	name = string.upper(name);
	for i, acct in ipairs(ComfyAccData.accounts) do
		if ( acct.account and string.upper(acct.account) == name ) then
			return i;
		end
	end
end

-- The account in use: the one logged in with, or after a return from the
-- world, the last one saved.
local function ComfyAccCurrent()
	if ( not ComfyAccData ) then
		return nil;
	end
	local i = ComfyAccFind(ComfyAcc.current) or ComfyAccData.last;
	return i and ComfyAccData.accounts[i];
end

-- The auto login character of an account on a realm, from the box on
-- character select: characters[realm].auto and .autoClass.
local function ComfyAccAuto(acct, realm)
	local saved = acct.characters and acct.characters[realm or ""];
	if ( saved and saved.auto and saved.auto ~= "" ) then
		return saved.auto, saved.autoClass;
	end
end

-- The character line under an account, in its class colour: the auto login
-- character on this realm, or else the last one played.
local function ComfyAccCharText(acct)
	local name, class = ComfyAccAuto(acct, GetServerName());
	if ( not name ) then
		name, class = acct.character, acct.class;
	end
	-- An empty line under the name looked wrong (the owner's call,
	-- 2026-09-25), so an account never played on says so, in grey.
	if ( not name or name == "" ) then
		return "|cff808080No character|r";
	end
	local token = TW_CLASS_TOKEN and class and TW_CLASS_TOKEN[class];
	local color = token and CLASS_COLORS and CLASS_COLORS[token];
	if ( type(color) == "string" ) then
		return color .. name .. "|r";
	end
	return name;
end

-- The character select highlight at full strength fills a 40 unit row with
-- solid gold (the owner's call, 2026-09-25: too bright).
local COMFY_ACC_GLOW = 0.35;

-- One row glows: the hovered one, or with nothing hovered, the selected one.
-- The owner's call, 2026-09-25.
local function ComfyAccGlow(row)
	local glow = _G[row:GetName() .. "Glow"];
	local lit;
	if ( ComfyAcc.hover ) then
		lit = ComfyAcc.hover == row;
	else
		lit = row.index and row.index == ComfyAcc.selected;
	end
	if ( lit ) then
		glow:SetAlpha(COMFY_ACC_GLOW);
		glow:Show();
	else
		glow:Hide();
	end
	-- The x shows on the hovered row only (the owner's call, 2026-09-25).
	local remove = _G[row:GetName() .. "Remove"];
	if ( ComfyAcc.hover == row ) then
		remove:Show();
	else
		remove:Hide();
	end
end

local function ComfyAccGlowAll()
	for i = 1, COMFY_ACC_PAGE do
		ComfyAccGlow(_G["ComfyAccountsRow" .. i]);
	end
end

-- The x on a row reports for its row, so the glow stays while over it.
function ComfyAccounts_Hover(row, on)
	if ( on ) then
		ComfyAcc.hover = row;
	elseif ( ComfyAcc.hover == row ) then
		ComfyAcc.hover = nil;
	end
	ComfyAccGlowAll();
end

function ComfyAccounts_Update()
	local list = ComfyAccData and ComfyAccData.accounts;
	local total = list and table.getn(list) or 0;
	if ( ComfyAccOff() or total == 0 ) then
		ComfyAccounts:Hide();
		if ( AccountLoginSaveAccountName and not ComfyAccOff() ) then
			AccountLoginSaveAccountName:Show();
		end
		return;
	end
	-- Every login is saved, and the x on a row forgets it, so the stock
	-- "remember account name" box has nothing left to do.
	if ( AccountLoginSaveAccountName ) then
		AccountLoginSaveAccountName:Hide();
	end

	local pages = math.ceil(total / COMFY_ACC_PAGE);
	if ( ComfyAcc.page >= pages ) then
		ComfyAcc.page = pages - 1;
	end
	local first = ComfyAcc.page * COMFY_ACC_PAGE;
	local shown = 0;
	for i = 1, COMFY_ACC_PAGE do
		local row = _G["ComfyAccountsRow" .. i];
		local acct = list[first + i];
		if ( acct ) then
			row.index = first + i;
			_G[row:GetName() .. "Name"]:SetText(acct.account);
			_G[row:GetName() .. "Char"]:SetText(ComfyAccCharText(acct));
			ComfyAccGlow(row);
			row:Show();
			shown = shown + 1;
		else
			row.index = nil;
			row:Hide();
		end
	end

	-- The pager sits under the panel, on the right (the owner's call, 2026-09-25).
	if ( pages > 1 ) then
		ComfyAccountsPage:SetText((ComfyAcc.page + 1) .. " / " .. pages);
		ComfyAccountsPage:Show();
		ComfyAccountsPrev:Show();
		ComfyAccountsNext:Show();
	else
		ComfyAccountsPage:Hide();
		ComfyAccountsPrev:Hide();
		ComfyAccountsNext:Hide();
	end
	ComfyAccounts:SetHeight(20 + shown * COMFY_ACC_ROW + ( shown - 1 ) * COMFY_ACC_GAP + 20);
	ComfyAccounts:Show();
end

function ComfyAccounts_Page(step)
	ComfyAcc.page = ComfyAcc.page + step;
	if ( ComfyAcc.page < 0 ) then
		ComfyAcc.page = 0;
	end
	PlaySound("gsTitleOptionOK");
	ComfyAccounts_Update();
end

-- One click fills both boxes, so the name or the password can be changed
-- before Login; a double click logs in (the owner's call, 2026-09-25). The
-- boxes lose focus, so a stray key lands in neither, unless there is no
-- password to send, when the password box takes it.
-- A password Nampower encrypted is not shown: the box stays empty, and the
-- Login wrap sends the stored one for an empty box.
function ComfyAccounts_Select(index)
	local acct = index and ComfyAccData.accounts[index];
	if ( not acct ) then
		return;
	end
	ComfyAcc.selected = index;
	local stored = acct.password or "";
	AccountLoginAccountEdit:SetText(acct.account);
	local usable;
	if ( string.find(stored, "^:encrypted:") ) then
		AccountLoginPasswordEdit:SetText("");
		usable = EncryptedServerLogin ~= nil;
	else
		AccountLoginPasswordEdit:SetText(string.sub(stored, 2));
		usable = string.len(stored) > 1;
	end
	-- With no password to send, typing one is the next step. Otherwise the
	-- focus goes to ComfyAccountsSink (ComfyLogin.xml has why).
	if ( usable ) then
		ComfyAccountsSink:SetFocus();
	else
		AccountLogin_FocusPassword();
	end
	ComfyAccGlowAll();
end

function ComfyAccounts_Login(index)
	ComfyAccounts_Select(index);
	if ( ComfyAcc.selected == index ) then
		AccountLogin_Login();
	end
end

-- An index into the list, moved down one when a row above it goes.
local function ComfyAccShift(value, removed)
	if ( value == removed ) then
		return nil;
	elseif ( value and value > removed ) then
		return value - 1;
	end
	return value;
end

function ComfyAccounts_Remove(index)
	if ( not index or not ComfyAccData.accounts[index] ) then
		return;
	end
	table.remove(ComfyAccData.accounts, index);
	ComfyAccData.last = ComfyAccShift(ComfyAccData.last, index);
	ComfyAcc.selected = ComfyAccShift(ComfyAcc.selected, index);
	ComfyAccSave();
	PlaySound("gsTitleOptionOK");
	ComfyAccounts_Update();
end

-- A login is written to the file only once the character list arrives, so a
-- wrong password is never saved.
--
-- The client wipes the password string it logged in with from memory, every
-- copy of it (paokkerkir found this). The stored form carries a ":" in front,
-- which makes it a different string, and the ":" is cut off at use.
local function ComfyAccCommit()
	local pending = ComfyAcc.pending;
	ComfyAcc.pending = nil;
	if ( pending ) then
		local i = ComfyAccFind(pending.account);
		local stored = pending.password;
		if ( ComfyAccData.encrypt_passwords and EncryptPassword ) then
			local ok, encrypted = pcall(EncryptPassword, string.sub(stored, 2));
			if ( ok and encrypted ) then
				stored = encrypted;
			end
		end
		if ( i ) then
			ComfyAccData.accounts[i].password = stored;
		else
			table.insert(ComfyAccData.accounts, { account = pending.account, password = stored });
		end
	end
	local i = ComfyAccFind(ComfyAcc.current);
	if ( i ) then
		ComfyAccData.last = i;
	end
	if ( pending or i ) then
		ComfyAccSave();
	end
	ComfyAcc.current = nil;
	if ( i ) then
		ComfyAcc.current = ComfyAccData.accounts[i].account;
	end
end

---------------------------------------------------------------------------
-- Character order. The engine keeps its own numbering, 1 to n, and every
-- call (SelectCharacter, EnterWorld, delete) takes that number. So nothing
-- is moved: the buttons show the characters in the saved order, and a click
-- on button k means the character shown there, ComfyChar.map[k].
---------------------------------------------------------------------------

local ComfyChar = {};

local function ComfyCharRealm()
	return GetServerName() or "";
end

local function ComfyCharSaved()
	local acct = ComfyAccCurrent();
	local saved = acct and acct.characters and acct.characters[ComfyCharRealm()];
	return acct, saved;
end

-- The order is kept by name. paokkerkir's matched by number, which goes
-- wrong after a delete, since every character after it moves up one.
local function ComfyCharDraw()
	local map = ComfyChar.map;
	if ( not map ) then
		return;
	end
	for slot, id in ipairs(map) do
		local text = ComfyChar.text[id];
		local base = "CharSelectCharacterButton" .. slot .. "ButtonText";
		_G[base .. "Name"]:SetText(text[1]);
		_G[base .. "Info"]:SetText(text[2]);
		_G[base .. "Location"]:SetText(text[3]);
	end
	UpdateCharacterSelection();
end

local function ComfyCharStore()
	local acct = ComfyCharSaved();
	if ( not acct or not ComfyChar.map ) then
		return;
	end
	acct.characters = acct.characters or {};
	local realm = acct.characters[ComfyCharRealm()] or {};
	acct.characters[ComfyCharRealm()] = realm;
	realm.order = {};
	for _, id in ipairs(ComfyChar.map) do
		table.insert(realm.order, { id = id, name = ComfyChar.names[id] });
	end
	local selected = CharacterSelect.selectedIndex;
	if ( selected and selected > 0 ) then
		realm.last = selected;
		realm.lastName = ComfyChar.names[selected];
	end
	ComfyAccSave();
end

local function ComfyCharApply(autoEnter)
	ComfyChar.map = nil;
	local count = math.min(GetNumCharacters(), MAX_CHARACTERS_DISPLAYED);
	local acct, saved = ComfyCharSaved();
	if ( ComfyAccOff() or not acct or count == 0 ) then
		return;
	end

	-- The stock list has just drawn every button in engine order.
	ComfyChar.text = {};
	ComfyChar.names = {};
	local byName = {};
	for id = 1, count do
		local base = "CharSelectCharacterButton" .. id .. "ButtonText";
		ComfyChar.text[id] = { _G[base .. "Name"]:GetText(), _G[base .. "Info"]:GetText(), _G[base .. "Location"]:GetText() };
		ComfyChar.names[id] = GetCharacterInfo(id);
		if ( ComfyChar.names[id] ) then
			byName[ComfyChar.names[id]] = id;
		end
	end

	local map, used = {}, {};
	for _, entry in ipairs(saved and saved.order or {}) do
		local id = entry.name and byName[entry.name];
		if ( id and not used[id] ) then
			table.insert(map, id);
			used[id] = true;
		end
	end
	for id = 1, count do
		if ( not used[id] ) then
			table.insert(map, id);
		end
	end
	ComfyChar.map = map;
	ComfyChar.slot = {};
	for slot, id in ipairs(map) do
		ComfyChar.slot[id] = slot;
	end

	-- The last character played, once per realm per session. After a
	-- create, the stock list selects the new one and that wins.
	local realm = ComfyCharRealm();
	if ( ComfyChar.picked ~= realm and CharacterSelect.selectLast ~= 1 and saved ) then
		ComfyChar.picked = realm;
		local id = ( saved.lastName and byName[saved.lastName] ) or saved.last;
		if ( id and id >= 1 and id <= count ) then
			CharacterSelect.selectedIndex = id;
			CharacterSelect_SelectCharacter(id, 1);
		end
	end
	ComfyCharDraw();

	-- Every login from the login screen goes straight into the world with
	-- the auto login character (the owner's call, 2026-09-25). A logout to
	-- character select does not, so that is the way to pick another.
	local auto = autoEnter and ComfyAccAuto(acct, realm);
	local id = auto and byName[auto];
	if ( id ) then
		CharacterSelect.selectedIndex = id;
		CharacterSelect_SelectCharacter(id, 1);
		CharacterSelect_EnterWorld();
	end
end

-- Moves the character shown in a slot one place up or down.
local function ComfyCharMove(slot, step)
	local map = ComfyChar.map;
	local other = map and slot + step;
	if ( not other or other < 1 or other > table.getn(map) ) then
		return;
	end
	map[slot], map[other] = map[other], map[slot];
	ComfyChar.slot[map[slot]] = slot;
	ComfyChar.slot[map[other]] = other;
	PlaySound("gsTitleOptionOK");
	ComfyCharDraw();
	ComfyCharStore();
end

-- The arrows show on the hovered character only (the owner's call,
-- 2026-09-25), and move that character.
local function ComfyCharArrows()
	local count = ComfyChar.map and table.getn(ComfyChar.map) or 0;
	for slot = 1, MAX_CHARACTERS_DISPLAYED do
		local button = _G["CharSelectCharacterButton" .. slot];
		if ( button and button.comfyUp ) then
			local here = slot == ComfyChar.hover and count > 1 and not ComfyAccOff();
			if ( here and slot > 1 ) then button.comfyUp:Show(); else button.comfyUp:Hide(); end
			if ( here and slot < count ) then button.comfyDown:Show(); else button.comfyDown:Hide(); end
		end
	end
end

-- The arrows report for their row, so they stay while the pointer is on
-- them.
local function ComfyCharHover(slot, on)
	if ( on ) then
		ComfyChar.hover = slot;
	elseif ( ComfyChar.hover == slot ) then
		ComfyChar.hover = nil;
	end
	ComfyCharArrows();
end

local function ComfyCharMakeArrow(button, step)
	local arrow = CreateFrame("Button", nil, button);
	arrow:SetWidth(26);
	arrow:SetHeight(26);
	local dir = "Up";
	if ( step > 0 ) then
		dir = "Down";
		arrow:SetPoint("TOP", button.comfyUp, "BOTTOM", 0, 8);
	else
		-- Centred on the 55 a character row shows (70, less the 15 its hit
		-- rect leaves off the bottom): the pair is 26 + 26 - 8 = 44 tall.
		arrow:SetPoint("TOPRIGHT", button, "TOPRIGHT", -38, -5);
	end
	arrow:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-Scroll" .. dir .. "-Up");
	arrow:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-Scroll" .. dir .. "-Down");
	arrow:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD");
	arrow:SetScript("OnClick", function()
		ComfyCharMove(this:GetParent():GetID(), step);
	end);
	arrow:SetScript("OnEnter", function()
		ComfyCharHover(this:GetParent():GetID(), true);
	end);
	arrow:SetScript("OnLeave", function()
		ComfyCharHover(this:GetParent():GetID(), false);
	end);
	arrow:Hide();
	return arrow;
end

-- The engine number behind a button.
local function ComfyCharId(slot)
	return ( ComfyChar.map and ComfyChar.map[slot] ) or slot;
end

-- The Auto login box under the list, for the selected character. One per
-- account and realm: ticking it on another character moves it there.
local function ComfyAutoUpdate()
	local acct = ComfyCharSaved();
	local id = CharacterSelect.selectedIndex;
	if ( ComfyAccOff() or not ComfyChar.map or not acct or not id or id < 1 ) then
		ComfyAutoLogin:Hide();
		return;
	end
	local auto = ComfyAccAuto(acct, ComfyCharRealm());
	if ( auto and auto == ComfyChar.names[id] ) then
		ComfyAutoLogin:SetChecked(1);
	else
		ComfyAutoLogin:SetChecked(0);
	end
	ComfyAutoLogin:Show();
end

function ComfyAutoLogin_OnClick()
	local acct = ComfyCharSaved();
	local id = CharacterSelect.selectedIndex;
	if ( not acct or not id or id < 1 ) then
		return;
	end
	acct.characters = acct.characters or {};
	local realm = ComfyCharRealm();
	local saved = acct.characters[realm] or {};
	acct.characters[realm] = saved;
	if ( this:GetChecked() ) then
		local name, race, class = GetCharacterInfo(id);
		saved.auto = name;
		saved.autoClass = class;
		PlaySound("igMainMenuOptionCheckBoxOn");
	else
		saved.auto = nil;
		saved.autoClass = nil;
		PlaySound("igMainMenuOptionCheckBoxOff");
	end
	ComfyAccSave();
end

---------------------------------------------------------------------------
-- The wraps. Each passes straight through while ComfyAccOff().
---------------------------------------------------------------------------

function ComfyAccounts_OnLoad()
	if ( ImportFile and ExportFile ) then
		ComfyAccLoad();
	end

	-- Whatever is in the boxes is what logs in, so a password changed after
	-- a click is the one saved. An empty password box on an account whose
	-- password Nampower encrypted sends the stored one.
	local login = AccountLogin_Login;
	AccountLogin_Login = function()
		if ( not ComfyAccOff() ) then
			local name = AccountLoginAccountEdit:GetText();
			local password = AccountLoginPasswordEdit:GetText();
			ComfyAcc.current = name;
			ComfyAcc.pending = nil;
			ComfyAcc.autoEnter = true;
			local i = ComfyAccFind(name);
			local stored = i and ComfyAccData.accounts[i].password or "";
			if ( password == "" and EncryptedServerLogin and string.find(stored, "^:encrypted:") ) then
				PlaySound("gsLogin");
				EncryptedServerLogin(name, stored);
				return;
			end
			if ( name ~= "" and password ~= "" ) then
				ComfyAcc.pending = { account = name, password = ":" .. password };
			end
		end
		login();
	end

	-- The stock screen fills the account box with the saved account name. An
	-- older autologin kept its whole list there, passwords and all, so with
	-- the panel up the last account used is selected instead, on its page.
	local show = AccountLogin_OnShow;
	AccountLogin_OnShow = function()
		show();
		-- A row clicked to log in never saw the pointer leave.
		ComfyAcc.hover = nil;
		ComfyAcc.selected = nil;
		local last = ComfyAccData and ComfyAccData.last;
		if ( last and ComfyAccData.accounts[last] ) then
			ComfyAcc.page = math.floor(( last - 1 ) / COMFY_ACC_PAGE);
		else
			last = nil;
		end
		ComfyAccounts_Update();
		if ( not ComfyAccounts:IsShown() ) then
			return;
		end
		if ( last ) then
			ComfyAccounts_Select(last);
		else
			AccountLoginAccountEdit:SetText("");
			AccountLoginPasswordEdit:SetText("");
			AccountLogin_FocusAccountName();
		end
	end

	-- A name typed that is in the list selects its row.
	local typed = AccountLoginAccountEdit:GetScript("OnTextChanged");
	AccountLoginAccountEdit:SetScript("OnTextChanged", function()
		if ( typed ) then
			typed();
		end
		if ( ComfyAccData and not ComfyAccOff() ) then
			ComfyAcc.selected = ComfyAccFind(this:GetText());
			ComfyAccGlowAll();
		end
	end);

	local list = UpdateCharacterList;
	UpdateCharacterList = function()
		list();
		if ( ComfyAccOff() ) then
			ComfyChar.map = nil;
			return;
		end
		ComfyAccCommit();
		-- Once per login: the next list update is a logout or a create.
		local autoEnter = ComfyAcc.autoEnter;
		ComfyAcc.autoEnter = nil;
		ComfyCharApply(autoEnter);
	end

	local selection = UpdateCharacterSelection;
	UpdateCharacterSelection = function()
		if ( not ComfyChar.map or ComfyAccOff() ) then
			selection();
			ComfyCharArrows();
			ComfyAutoUpdate();
			return;
		end
		for i = 1, MAX_CHARACTERS_DISPLAYED do
			_G["CharSelectCharacterButton" .. i]:UnlockHighlight();
		end
		local slot = ComfyChar.slot[CharacterSelect.selectedIndex];
		if ( slot ) then
			_G["CharSelectCharacterButton" .. slot]:LockHighlight();
		end
		ComfyCharArrows();
		ComfyAutoUpdate();
	end

	CharacterSelectButton_OnClick = function()
		local id = ComfyCharId(this:GetID());
		if ( id ~= CharacterSelect.selectedIndex ) then
			CharacterSelect_SelectCharacter(id);
		end
	end

	CharacterSelectButton_OnDoubleClick = function()
		local id = ComfyCharId(this:GetID());
		if ( id ~= CharacterSelect.selectedIndex ) then
			CharacterSelect_SelectCharacter(id);
		end
		CharacterSelect_EnterWorld();
	end

	-- Up and down walk the order on screen.
	local keys = CharacterSelect_OnKeyDown;
	CharacterSelect_OnKeyDown = function()
		local map = ComfyChar.map;
		local count = map and table.getn(map) or 0;
		local step = 0;
		if ( arg1 == "UP" or arg1 == "LEFT" ) then
			step = -1;
		elseif ( arg1 == "DOWN" or arg1 == "RIGHT" ) then
			step = 1;
		end
		if ( step == 0 or count < 2 or ComfyAccOff() ) then
			keys();
			return;
		end
		local slot = ComfyChar.slot[CharacterSelect.selectedIndex] or 1;
		slot = slot + step;
		if ( slot < 1 ) then
			slot = count;
		elseif ( slot > count ) then
			slot = 1;
		end
		CharacterSelect_SelectCharacter(map[slot]);
	end

	local enter = CharacterSelect_EnterWorld;
	CharacterSelect_EnterWorld = function()
		if ( not ComfyAccOff() ) then
			ComfyCharStore();
			local acct = ComfyCharSaved();
			local id = CharacterSelect.selectedIndex;
			if ( acct and id and id > 0 ) then
				local name, race, class, level, zone = GetCharacterInfo(id);
				acct.character = name;
				acct.race = race;
				acct.class = class;
				acct.zone = zone;
				ComfyAccSave();
			end
		end
		enter();
	end

	for slot = 1, MAX_CHARACTERS_DISPLAYED do
		local button = _G["CharSelectCharacterButton" .. slot];
		if ( button ) then
			button.comfyUp = ComfyCharMakeArrow(button, -1);
			button.comfyDown = ComfyCharMakeArrow(button, 1);
			local enter = button:GetScript("OnEnter");
			local leave = button:GetScript("OnLeave");
			button:SetScript("OnEnter", function()
				if ( enter ) then
					enter();
				end
				ComfyCharHover(this:GetID(), true);
			end);
			button:SetScript("OnLeave", function()
				if ( leave ) then
					leave();
				end
				ComfyCharHover(this:GetID(), false);
			end);
		end
	end

	if ( CURRENT_GLUE_SCREEN == "login" ) then
		ComfyAccounts_Update();
	end
end
