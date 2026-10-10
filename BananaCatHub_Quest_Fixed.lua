--[[
Banana Cat Hub - Delta compatibility loader with QUEST-ONLY additional fixes
Based on the user's original BananaCatHub_Delta_Fix.lua loader.

The original Banana Cat Hub script is downloaded unchanged at run time.
All menus, features and the original compatibility patches are retained.
Only quest lookup, quest GUI detection, and quest acceptance are additionally fixed.
This has not been tested in a live Blox Fruits/Delta session.
Inspect remote scripts before using them.
]]

local SOURCE_URL = "https://raw.githubusercontent.com/ptlhub2026/ptlhub/refs/heads/main/3nn_main.lua.txt"
local SAVE_FOLDER = "Banana Cat Hub"
local SAVE_FILE = SAVE_FOLDER .. "/BananaCatHub_Quest_Fixed_Full.lua"
local LOG_FILE = SAVE_FOLDER .. "/Delta_Fix_Errors.txt"
local PREFIX = "[BananaCat Delta Fix] "

local function info(message)
    print(PREFIX .. tostring(message))
end
local function problem(message)
    warn(PREFIX .. tostring(message))
end

if type(getgenv) ~= "function" then
    problem("Delta/getgenv() is unavailable; cannot start.")
    return
end

local env = getgenv()
if env.__BC_DELTA_PATCH_RUNNING then
    problem("The Delta patch loader is already running. Do not execute it twice.")
    return
end
if env.__BF_LOADED or env.LoadScript then
    problem("A Banana Cat Hub session is already loaded. Leave and rejoin Blox Fruits, then use ONLY this file once.")
    return
end

env.__BC_DELTA_PATCH_RUNNING = true
local function stop(message)
    env.__BC_DELTA_PATCH_RUNNING = false
    problem(message)
end

if type(loadstring) ~= "function" then
    stop("Delta does not expose loadstring().")
    return
end
if not game:IsLoaded() then
    game.Loaded:Wait()
end

local players = game:GetService("Players")
local deadline = os.clock() + 25
while not players.LocalPlayer and os.clock() < deadline do
    task.wait(0.1)
end
if not players.LocalPlayer then
    stop("LocalPlayer is not ready.")
    return
end

-- Download the original hub as text. Patch before compiling/executing it.
local downloaded, original = pcall(function()
    return game:HttpGet(SOURCE_URL, true)
end)
if not downloaded or type(original) ~= "string" then
    stop("Failed to download original source: " .. tostring(original))
    return
end
if #original < 100000
    or not original:find("function toTarget(", 1, true)
    or not original:find("function AttackAOE(", 1, true)
    or not original:find("Settings = ReadSetting()", 1, true)
then
    stop("The original source does not match the inspected Banana Cat Hub version; refusing to patch unrelated code.")
    return
end

local source = original
local counts = {}
local function escapePattern(value)
    return (value:gsub("([^%w])", "%%%1"))
end
local function replaceLiteral(name, oldText, newText)
    local amount
    source, amount = source:gsub(escapePattern(oldText), function()
        return newText
    end)
    counts[name] = amount
    info(name .. " -> " .. tostring(amount) .. " replacement(s)")
    return amount
end

-- ORIGINAL COMPATIBILITY FIXES (unchanged)
replaceLiteral("Protection directive", "LPH_ATTRIBUTES(VM(NONE))", "do end -- BC_DELTA: ignored source protection directive")
replaceLiteral("Player hit target lookup", "S:GetPlayerFromCharacter(", 'game:GetService("Players"):GetPlayerFromCharacter(')
replaceLiteral("LocalPlayer capitalization", "game.Players.localPlayer", "game.Players.LocalPlayer")
replaceLiteral("HTTP request nil guard", "or http.request", "or (http and http.request)")
replaceLiteral(
    "Missing farm defaults",
    "Settings = ReadSetting()",
    [[Settings = ReadSetting()
if Settings["Select Method Farm"] == nil then
    SaveSettings("Select Method Farm", "Level Farm")
end
if Settings["Select Weapon"] == nil then
    SaveSettings("Select Weapon", "Melee")
end]]
)

-- QUEST FIX 1: QuestData may exist before its Task field has loaded.
replaceLiteral(
    "Quest task readiness",
    "return Z.Data and Z.Data.QuestData ~= nil",
    [[return type(Z.Data) == "table"
        and type(Z.Data.QuestData) == "table"
        and type(Z.Data.QuestData.Task) == "table"]]
)

-- QUEST FIX 2: NPC and quest data may not be loaded or may contain stale entries.
replaceLiteral(
    "Quest lookup initialization",
    [[local function B(C)
	local J = Z.Data.QuestData
	local F, q, c = J and (next(J.Task)), 0, {}
	for D, r in pairs(Z.Data.NPCList) do]],
    [[local function B(C)
	local data = Z and Z.Data
	local currentQuest = data and data.QuestData
	local tasks = currentQuest and currentQuest.Task
	local F, q, c = type(tasks) == "table" and next(tasks) or nil, 0, {}
	local npcList = data and data.NPCList
	if type(npcList) ~= "table" then
		return nil
	end
	for D, r in pairs(npcList) do]]
)
replaceLiteral(
    "Quest NPC entry guard",
    "if not table.find(V, r.InternalQuestName) then\n\t\t\tfor V, n in pairs(r.Levels) do",
    [[if type(r) == "table" and type(r.InternalQuestName) == "string"
			and type(r.Levels) == "table" and not table.find(V, r.InternalQuestName) then
			for V, n in pairs(r.Levels) do]]
)
replaceLiteral(
    "Quest ID nil guard",
    "D = H[r.InternalQuestName][V]",
    "D = H[r.InternalQuestName] and H[r.InternalQuestName][V]"
)
replaceLiteral(
    "Quest task selection",
    [[if D then
					local u, W = next(D.Task)
					if W and W > 1 and n <= C and n >= q then]],
    [[if D and type(D.Task) == "table" then
					local u, W
					for mobName, amount in pairs(D.Task) do
						if type(amount) == "number" and amount > 1 then
							u, W = mobName, amount
							break
						end
					end
					if W and type(n) == "number" and n <= C and n >= q
						and (typeof(r.Position) == "Vector3" or typeof(r.Position) == "CFrame") then]]
)
replaceLiteral(
    "Quest ID numeric guard",
    "if F == u and V > 1 then",
    "if F == u and tonumber(V) and tonumber(V) > 1 then"
)
replaceLiteral(
    "Quest previous ID guard",
    "J = H[r.InternalQuestName][V - 1]",
    "J = H[r.InternalQuestName][tonumber(V) - 1]"
)

-- QUEST FIX 3: NPCList can be absent when special quest points are built.
replaceLiteral(
    "Quest point NPC list guard",
    "for C, J in next, Z.Data.NPCList, nil do",
    [[for C, J in pairs(type(Z.Data) == "table" and type(Z.Data.NPCList) == "table" and Z.Data.NPCList or {}) do]]
)
replaceLiteral(
    "Quest point levels guard",
    "for F, q in next, J.Levels, nil do",
    "for F, q in pairs(type(J) == \"table\" and type(J.Levels) == \"table\" and J.Levels or {}) do"
)
replaceLiteral(
    "Quest point parent guard",
    'if C.Parent.Name ~= "Marine Leader" and F and not getgenv().questpoint[F] then',
    'if C and C.Parent and C.Parent.Name ~= "Marine Leader" and F and J.Position and not getgenv().questpoint[F] then'
)
replaceLiteral(
    "Quest point CFrame guard",
    "getgenv().questpoint[F] = CFrame.new(J.Position)",
    'getgenv().questpoint[F] = typeof(J.Position) == "CFrame" and J.Position or CFrame.new(J.Position)'
)

-- QUEST FIX 4: Accept the quest only when close enough, alive, and no quest
-- is active. Throttle requests, verify the quest UI and log failures.
replaceLiteral(
    "TakeQuestLevel",
    [[TakeQuestLevel = function()
	local V = B(t.Data.Level.Value)
	if not V or not V.Pos then
		return
	end
	local H, B, C =
		typeof(V.Pos) == "CFrame" and V.Pos.Position or V.Pos,
		t.Character and (t.Character:FindFirstChild("HumanoidRootPart")),
		t.Character and (t.Character:FindFirstChild("Humanoid"))
	if not B or not C then
		return
	end
	if (H - B.Position).Magnitude <= 8 and C.Health > 0 then
		wait(2)
		CommF:InvokeServer("StartQuest", tostring(V.QuestName), V.Id)
	else
		toTarget(CFrame.new(H) * CFrame.new(0, 4, 2), true)
	end
end]],
    [[TakeQuestLevel = function()
	local data = t:FindFirstChild("Data")
	local level = data and data:FindFirstChild("Level")
	if not level then return end
	local quest = B(level.Value)
	if type(quest) ~= "table" or not quest.Pos or not quest.QuestName or quest.Id == nil then
		local now = os.clock()
		if not getgenv().__BC_QUEST_NO_DATA or now - getgenv().__BC_QUEST_NO_DATA > 15 then
			getgenv().__BC_QUEST_NO_DATA = now
			warn("[BananaCat Quest] No matching NPC/quest data for level " .. tostring(level.Value))
		end
		return
	end
	local pos = typeof(quest.Pos) == "CFrame" and quest.Pos.Position or quest.Pos
	if typeof(pos) ~= "Vector3" then return end
	local character = t.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return end
	local main = t.PlayerGui:FindFirstChild("Main") or t.PlayerGui:FindFirstChild("Main (minimal)")
	local questFrame = main and main:FindFirstChild("Quest")
	if questFrame and questFrame.Visible then return end
	if (pos - root.Position).Magnitude > 8 then
		toTarget(CFrame.new(pos) * CFrame.new(0, 4, 2), true)
		return
	end
	local now = os.clock()
	if getgenv().__BC_QUEST_LAST_TRY and now - getgenv().__BC_QUEST_LAST_TRY < 2 then
		return
	end
	getgenv().__BC_QUEST_LAST_TRY = now
	local ok, result = pcall(function()
		return CommF:InvokeServer("StartQuest", tostring(quest.QuestName), quest.Id)
	end)
	if not ok then
		warn("[BananaCat Quest] StartQuest failed: " .. tostring(result))
		return
	end
	task.wait(0.8)
	main = t.PlayerGui:FindFirstChild("Main") or t.PlayerGui:FindFirstChild("Main (minimal)")
	questFrame = main and main:FindFirstChild("Quest")
	if not (questFrame and questFrame.Visible) then
		local state = Z and Z.Data and Z.Data.QuestData
		if not (type(state) == "table" and type(state.Task) == "table") then
			local tickNow = os.clock()
			if not getgenv().__BC_QUEST_REJECT_WARN or tickNow - getgenv().__BC_QUEST_REJECT_WARN > 10 then
				getgenv().__BC_QUEST_REJECT_WARN = tickNow
				warn("[BananaCat Quest] Quest not confirmed: " .. tostring(quest.QuestName)
					.. " #" .. tostring(quest.Id) .. "; remote result=" .. tostring(result))
			end
		end
	end
end]]
)

-- QUEST FIX 5: Blox Fruits can expose Main or Main (minimal) on Delta.
replaceLiteral(
    "Farm quest GUI detection",
    [[f = V or (GetNameDoubleQuest()) or ""
	if not t.PlayerGui.Main:FindFirstChild("Quest").Visible and typeof(f) == "string" then]],
    [[f = V or (GetNameDoubleQuest()) or ""
	local main = t.PlayerGui:FindFirstChild("Main") or t.PlayerGui:FindFirstChild("Main (minimal)")
	local questFrame = main and main:FindFirstChild("Quest")
	local questVisible = questFrame and questFrame.Visible or false
	if not questVisible and typeof(f) == "string" then]]
)
replaceLiteral(
    "Special farm quest GUI detection",
    [[and not t.PlayerGui.Main:FindFirstChild("Quest").Visible
		then
			QuestBoneAndkatakuri(H, J)]],
    [[and not questVisible
		then
			QuestBoneAndkatakuri(H, J)]]
)

-- Keep the original diagnostics wrapper (it reports swallowed pcall errors).
local instrument = [==[
-- BEGIN Banana Cat Hub Delta diagnostics
local Workspace = game:GetService("Workspace")
local __BC_NATIVE_PCALL = pcall
local __BC_SEEN_ERRORS = {}
local __BC_ERROR_COUNT = 0
local function pcall(...)
    local results = table.pack(__BC_NATIVE_PCALL(...))
    if results[1] == false then
        local message = tostring(results[2])
        local now = os.clock()
        local previous = __BC_SEEN_ERRORS[message]
        if __BC_ERROR_COUNT < 30 and (not previous or now - previous > 20) then
            __BC_SEEN_ERRORS[message] = now
            __BC_ERROR_COUNT = __BC_ERROR_COUNT + 1
            warn("[BananaCat Delta Fix][caught error] " .. message)
            local shared = getgenv()
            shared.__BC_DELTA_ERRORS = shared.__BC_DELTA_ERRORS or {}
            table.insert(shared.__BC_DELTA_ERRORS, message)
            if type(appendfile) == "function" then
                __BC_NATIVE_PCALL(function()
                    appendfile("Banana Cat Hub/Delta_Fix_Errors.txt", message .. "\n")
                end)
            end
        end
    end
    return table.unpack(results, 1, results.n)
end
-- END Banana Cat Hub Delta diagnostics
]==]
source = instrument .. "\n" .. source

-- Do not silently launch if a critical quest patch did not apply.
local required = {
    "Missing farm defaults",
    "Quest task readiness",
    "Quest lookup initialization",
    "Quest NPC entry guard",
    "Quest ID nil guard",
    "Quest task selection",
    "Quest ID numeric guard",
    "Quest previous ID guard",
    "Quest point NPC list guard",
    "Quest point levels guard",
    "Quest point parent guard",
    "Quest point CFrame guard",
    "TakeQuestLevel",
    "Farm quest GUI detection",
    "Special farm quest GUI detection",
}
for _, name in ipairs({"Protection directive", "Player hit target lookup"}) do
    if (counts[name] or 0) < 1 then
        stop("Original compatibility patch missing: " .. name)
        return
    end
end
for _, name in ipairs(required) do
    if (counts[name] or 0) ~= 1 then
        stop("Required patch marker '" .. name .. "' expected once, got " .. tostring(counts[name] or 0) .. ". Original source may have changed.")
        return
    end
end

local folderAvailable = false
if type(isfolder) == "function" and type(makefolder) == "function" then
    local ok, message = pcall(function()
        if not isfolder(SAVE_FOLDER) then
            makefolder(SAVE_FOLDER)
        end
    end)
    folderAvailable = ok
    if not ok then
        problem("Couldn't create output directory: " .. tostring(message))
    end
end
if folderAvailable and type(writefile) == "function" then
    local saved, why = pcall(function()
        writefile(SAVE_FILE, source)
        writefile(LOG_FILE, "Banana Cat Hub Quest Fix log (2026-10-10)\n")
    end)
    if saved then
        info("Complete patched original (~19k lines) saved to: " .. SAVE_FILE)
    else
        problem("The patched script is in memory; could not write it: " .. tostring(why))
    end
else
    problem("File APIs are unavailable. Running patched source from memory.")
end
if type(debug) ~= "table"
    or type(debug.getupvalues) ~= "function"
    or type(debug.getupvalue) ~= "function"
then
    problem("Some debug.getupvalue(s) APIs are missing in this Delta build. Some features may still fail.")
end
if not (workspace:FindFirstChild("Enemies") and game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")) then
    problem("Enemies/Remotes not found at startup; game may still be loading or may have changed.")
end
local compiler, compileError = loadstring(source)
if not compiler then
    stop("Luau compile failed: " .. tostring(compileError))
    return
end

info("Launching original Banana Cat Hub with the quest fixes and original compatibility patches.")
local success, executionError = pcall(compiler)
env.__BC_DELTA_PATCH_RUNNING = false
if not success then
    problem("Main script stopped: " .. tostring(executionError))
    problem("If the menu already appeared, rejoin before another attempt.")
    return
end
info("Loader returned. Check Delta Console for [BananaCat Quest] messages if quests fail.")
info("Full source on device: " .. SAVE_FILE)
