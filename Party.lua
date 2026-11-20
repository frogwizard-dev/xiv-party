local _, ns = ...

-- The party list, under a "LIGHT PARTY" or "FULL PARTY" title. Outside a raid: you first, then party1 to party4,
-- each a secure button of ours (left-click targets, right-click opens their menu, click-casting addons and pings work
-- on it) that the game shows while they exist; party tokens fill from 1 up, so nothing has to move in combat. In a
-- raid: the full party, up to ten, your raid group then the next one (the lowest-numbered other group with someone
-- in it), from one of Blizzard's secure group headers, which places members itself as the raid changes; its ten
-- buttons are made at login (EllesmereUI's startingIndex trick) and only filled in here, their unit handed to each
-- row as the header changes it. The rest of a bigger raid is the alliance lists (Alliance.lua). Everything hangs
-- from the first row, dragged while unlocked; secure frames only change out of combat, so a settings change or a
-- new pair of groups in combat waits for the end of it.

local Secure = FrogLib.Secure
local issecret, Safe = FrogLib.issecret, FrogLib.Safe

local Party = {}
ns.Party = Party

local UNITS = { "player", "party1", "party2", "party3", "party4" }
local FULL = 10 -- the full party's rows: two raid groups
local ENMITY_EVERY = 0.2 -- seconds between enmity order redraws while threat on your target changes

-- The unlocked preview's members.
local SAMPLES = {
    { name = "You", level = 60, class = "Paladin", classFile = "PALADIN", value = 4200, max = 5000,
        power = 2400, powermax = 3800, token = "MANA", enmity = "3", share = 0.55 },
    { name = "Thornwall", level = 60, class = "Warrior", classFile = "WARRIOR", value = 6100, max = 6800,
        power = 45, powermax = 100, token = "RAGE", enmity = "A", share = 1 },
    { name = "Mirelle", level = 60, class = "Priest", classFile = "PRIEST", value = 3500, max = 3900,
        power = 3100, powermax = 5200, token = "MANA", casting = true, enmity = "5", share = 0.2 },
    { name = "Sable", level = 59, class = "Rogue", classFile = "ROGUE", value = 1600, max = 4300,
        power = 80, powermax = 100, token = "ENERGY", enmity = "2", share = 0.8 },
    { name = "Quillon", level = 60, class = "Mage", classFile = "MAGE", value = 3000, max = 3600,
        power = 900, powermax = 5800, token = "MANA", enmity = "4", share = 0.35 },
}

-- Global events and what they redraw on every member shown.
local EVENTS = {
    GROUP_ROSTER_UPDATE = "Roster", PLAYER_ENTERING_WORLD = "UpdateAll", PLAYER_TARGET_CHANGED = "UpdateTarget",
    RAID_TARGET_UPDATE = "UpdateIcons", PARTY_LEADER_CHANGED = "UpdateIcons",
}
local STATUS_WAIT = 0.4 -- seconds a settings change waits before the status rows are built again (steppers repeat)

-- The order for groupBy "GROUP": Blizzard's header reads each group's place as the group-th entry, and compares the
-- entries, which are text for groups 1 to n and numbers past them when the list is short ("3,1" puts a number by a
-- text: a Lua error on every roster change). So all eight are given, each the place its group should take: yours
-- "1", the next "2", the rest (filtered out anyway) "9".
local order = {}
local function GroupingOrder(own, next)
    for group = 1, 8 do order[group] = (group == own and "1") or (group == next and "2") or "9" end
    return table.concat(order, ",")
end

local function SizeSnippet(db)
    return ("self:SetWidth(%d)\nself:SetHeight(%d)"):format(ns.Row.Width(db), db.rowHeight)
end

-- A row's hooks on its button: drawn while shown, the mouse over it.
local function Hook(button, row)
    button:HookScript("OnShow", function() row:Activate() end)
    button:HookScript("OnHide", function() row:Deactivate() end)
    button:HookScript("OnEnter", function(frame) row:Enter(frame) end)
    button:HookScript("OnLeave", function(frame) row:Leave(frame) end)
end

function Party:Init()
    local db = ns.db
    self.roots, self.rows, self.raidRows, self.all = {}, {}, {}, {}
    for i, unit in ipairs(UNITS) do
        local name = "XIVPartyMember" .. i
        local root = CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate")
        root:SetFrameStrata("LOW")
        root:SetAttribute("unit", unit)
        ns.SecureParts(root)
        local row = ns.Row.New(root, unit, i)
        Hook(root, row)
        root:Hide()
        self.roots[i], self.rows[i] = root, row
        self.all[#self.all + 1] = row
    end
    -- The first is the handle; its tint is stretched over the whole list in Apply.
    local first = self.roots[1]
    first:SetClampedToScreen(true)
    first:SetMovable(true)
    FrogLib.Mover.Make(first, { save = function(point) ns.db.point = point end, tint = 6, secure = true })

    -- The title over the list (a plain frame, only placed by the first row).
    local title = CreateFrame("Frame", nil, UIParent)
    title:SetSize(1, 1)
    title.text = FrogLib.Text.Shadowed(title)
    title.text:SetPoint("BOTTOMLEFT")
    title.text:SetTextColor(0.95, 0.92, 0.82)
    self.title = title

    -- The full party's header: buttons made now, out of combat, while it can show (it shows only in a raid).
    local header = CreateFrame("Frame", "XIVPartyFull", UIParent, "SecureGroupHeaderTemplate")
    header:SetFrameStrata("LOW")
    header:SetAttribute("template", "SecureUnitButtonTemplate")
    header:SetAttribute("templateType", "Button")
    header:SetAttribute("initialConfigFunction", SizeSnippet(db))
    header:SetAttribute("point", "TOP")
    header:SetAttribute("yOffset", -db.spacing)
    header:SetAttribute("showRaid", true)
    header:SetAttribute("groupBy", "GROUP")
    header:SetAttribute("groupingOrder", GroupingOrder(nil, nil))
    header:SetAttribute("sortMethod", "INDEX")
    header:SetAttribute("maxColumns", 1)
    header:SetAttribute("unitsPerColumn", FULL)
    self:SetGroups(header)
    header:SetAttribute("startingIndex", 1 - FULL)
    header:Show()
    header:SetAttribute("startingIndex", 1)
    self.header = header
    for i = 1, FULL do
        local button = header[i]
        if button then
            local row = ns.Row.New(button, button:GetAttribute("unit"), i)
            row.menu = ns.SecureParts(button)
            Hook(button, row)
            -- The header hands each button its unit, and hands them round again as the raid changes.
            button:HookScript("OnAttributeChanged", function(_, name, value)
                if name == "unit" then row:SetUnit(value) end
            end)
            self.raidRows[#self.raidRows + 1] = row
            self.all[#self.all + 1] = row
            if button:IsShown() then row:Activate() end -- made in a raid: no OnShow is coming for it
        end
    end

    local events = CreateFrame("Frame")
    for event in pairs(EVENTS) do events:RegisterEvent(event) end
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.events = events
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if self.pending then self:Apply() end
            return
        elseif event == "UNIT_THREAT_LIST_UPDATE" then
            self:EnmitySoon()
            return
        end
        local method = EVENTS[event]
        if method == "Roster" then
            -- Roster changes come in bursts: looked at once, a frame later.
            if self.redrawSoon then return end
            self.redrawSoon = true
            C_Timer.After(0, function()
                self.redrawSoon = false
                self:RosterChanged()
            end)
            return
        end
        self:Redraw(method)
        if event == "PLAYER_TARGET_CHANGED" then self:EnmitySoon() end
    end)
    self:Apply()
end

-- Every member shown (not the unlocked samples) redrawn by `method`.
function Party:Redraw(method)
    for _, row in ipairs(self.all) do
        if row.shown and not row.sample then row[method](row, true) end
    end
end

-- Someone joined, left or moved: each row whose token now means someone else is drawn afresh (a raid member's token
-- can, and the header doesn't always hand it out again; party1 can too); the same person again is left as it is.
function Party:RosterChanged()
    for _, row in ipairs(self.all) do
        if row.shown and not row.sample then row:SetUnit(row.root:GetAttribute("unit")) end
    end
    self:UpdateTitle()
    self:EnmitySoon()
    if not self:SetGroups(self.header) then self.pending = true end
end

-- The full party's two groups on the header (out of combat only: false while it has to wait).
function Party:SetGroups(header)
    local own, next = ns.FullGroups()
    local filter = own and (next and (own .. "," .. next) or tostring(own)) or "1"
    if header:GetAttribute("groupFilter") == filter then return true end
    if InCombatLockdown() then return false end
    header:SetAttribute("groupingOrder", GroupingOrder(own, next))
    header:SetAttribute("groupFilter", filter)
    return true
end

function Party:UpdateTitle()
    local text = self.title.text
    if not ns.db.title then
        text:Hide()
        return
    end
    -- Over nothing (alone, not shown alone) it stays off, unless unlocked.
    text:SetShown(not ns.db.locked or ns.db.showSolo or IsInGroup())
    text:SetText(IsInRaid() and "FULL PARTY" or "LIGHT PARTY")
end

------------------------------------------------------------------------------
-- Enmity order: who your target hates most, as FFXIV numbers the party list ("A" for the one it's attacking, then
-- 2, 3...). Threat reads plainly through "target"; where the game hides the numbers only "A" can show.
------------------------------------------------------------------------------

local ranked = {}
local function ByEnmity(first, second) return first.enmityValue > second.enmityValue end

function Party:EnmitySoon()
    if self.enmitySoon or not ns.db.enmity then return end
    self.enmitySoon = true
    self.enmityLater = self.enmityLater or function()
        self.enmitySoon = false
        self:UpdateEnmity()
    end
    C_Timer.After(ENMITY_EVERY, self.enmityLater)
end

function Party:UpdateEnmity()
    local wanted = ns.db.enmity and UnitExists("target") and Safe(UnitCanAttack("player", "target"))
    wipe(ranked)
    for _, row in ipairs(self.all) do
        if row.shown and not row.sample then
            if not (wanted and row.unit) then
                row:SetEnmity(nil)
            else
                local tanking, _, _, _, value = UnitDetailedThreatSituation(row.unit, "target")
                if issecret(tanking) then
                    row:SetEnmity(nil, tanking)
                elseif issecret(value) or value == nil or value <= 0 then
                    row:SetEnmity(tanking and "A" or nil)
                else
                    row.enmityValue, row.enmityTanking = value, tanking
                    ranked[#ranked + 1] = row
                end
            end
        end
    end
    table.sort(ranked, ByEnmity)
    -- FFXIV counts the one it's attacking as first ("A"), the rest from 2; the bar is each one's share of the top.
    local top, place = ranked[1] and ranked[1].enmityValue, 1
    for _, row in ipairs(ranked) do
        local share = row.enmityValue / top
        if row.enmityTanking then
            row:SetEnmity("A", nil, share)
        else
            place = place + 1
            row:SetEnmity(tostring(place), nil, share)
        end
    end
end

------------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------------

-- The status rows are built again only once the settings stop changing: each build is a new container (the old one
-- can't be freed), and a stepper held down changes them several times a second.
function Party:StatusesSoon()
    self.statusesAt = GetTime()
    if self.statusesWaiting then return end
    self.statusesWaiting = true
    local function Build()
        if GetTime() - self.statusesAt < STATUS_WAIT or InCombatLockdown() then
            C_Timer.After(STATUS_WAIT, Build)
            return
        end
        self.statusesWaiting = false
        for _, row in ipairs(self.all) do row:BuildStatuses(ns.db) end
    end
    C_Timer.After(STATUS_WAIT, Build)
end

-- Each fixed button shown by the game: you (always, or only in a group), the others while they exist; none in a
-- raid, where the full party's header shows everyone.
local function Watch(root, index, db)
    local rule
    if index == 1 then
        rule = db.showSolo and "[@raid1,exists] hide; show" or "[@raid1,exists] hide; [@party1,exists] show; hide"
    else
        rule = ("[@raid1,exists] hide; [@party%d,exists] show; hide"):format(index - 1)
    end
    RegisterStateDriver(root, "visibility", rule)
end

-- A row's settings: its size, clicks (off while unlocked, so the first row can be dragged), look and statuses, and
-- its events again (the cast's come and go with the setting), drawn afresh.
local function ApplyRow(row, button, db, mouse)
    Secure.SetClicks(button, db.clicks and db.locked and button:GetName() .. "Menu" or nil)
    button:EnableMouse(mouse)
    row:Layout(db)
    if button:IsShown() then
        row:Deactivate()
        row:Activate()
    end
end

function Party:Apply()
    if InCombatLockdown() then
        self.pending = true
        return
    end
    self.pending = nil
    local db = ns.db
    local width, height, step = ns.Row.Width(db), db.rowHeight, db.rowHeight + db.spacing
    local first = self.roots[1]
    first.unlockTint:ClearAllPoints()
    first.unlockTint:SetPoint("TOPLEFT", first, "TOPLEFT", -6, 6)
    first.unlockTint:SetPoint("BOTTOMRIGHT", first, "TOPRIGHT", 6, -(step * #UNITS - db.spacing) - 6)
    first.unlockTint:SetShown(not db.locked)
    -- Dragged only while unlocked (locked, its left button targets).
    if db.locked then first:RegisterForDrag() else first:RegisterForDrag("LeftButton") end
    for i, root in ipairs(self.roots) do
        local row = self.rows[i]
        root:SetScale(db.scale)
        root:SetSize(width, height)
        root:ClearAllPoints()
        if i == 1 then
            root:SetPoint(db.point[1], UIParent, db.point[3], db.point[4], db.point[5])
        else
            root:SetPoint("TOPLEFT", self.roots[i - 1], "BOTTOMLEFT", 0, -db.spacing)
        end
        row:Layout(db) -- before the watch below can show it and draw it
        if db.locked then
            row.sample = nil
            Watch(root, i, db)
        else
            UnregisterStateDriver(root, "visibility")
            row.sample = SAMPLES[i]
            root:Show()
        end
        ApplyRow(row, root, db, db.locked or i == 1)
    end

    -- The full party where the first row is; its buttons sized before the header lays them out again from them.
    local header = self.header
    header:SetScale(db.scale)
    header:ClearAllPoints()
    header:SetPoint("TOPLEFT", first, "TOPLEFT")
    for _, row in ipairs(self.raidRows) do
        row.root:SetSize(width, height)
        ApplyRow(row, row.root, db, db.locked)
    end
    header:SetAttribute("yOffset", -db.spacing)
    header:SetAttribute("initialConfigFunction", SizeSnippet(db))
    self:SetGroups(header)
    -- Unlocked, the preview rows take its place.
    header:SetShown(db.locked)
    if db.enmity then
        self.events:RegisterUnitEvent("UNIT_THREAT_LIST_UPDATE", "target")
    else
        self.events:UnregisterEvent("UNIT_THREAT_LIST_UPDATE")
    end
    self:StatusesSoon()

    local title = self.title
    title:SetScale(db.scale)
    title:ClearAllPoints()
    title:SetPoint("BOTTOMLEFT", first, "TOPLEFT", 2, 3)
    ns.Media:SetFont(title.text, db.font, math.max(8, db.nameSize - 1), db.outline)
    self:UpdateTitle()
    self:UpdateEnmity()
end
