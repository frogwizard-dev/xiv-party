local _, ns = ...

-- FFXIV's alliance lists, for a raid: a small box for each raid group beyond the full party's two (Party.lua),
-- each member a name over a thin HP gauge, faded out of range, a light band on your target; clicks target and open
-- the menu as on the party list. Raid members come and go in combat, so each box is one of Blizzard's secure group
-- headers (groupFilter = its group), which places members itself; its five buttons are made at login (EllesmereUI's
-- startingIndex trick) and only filled in by this file. The game-made buttons carry no keys of ours: what's drawn on
-- each is kept in a weak table by button. Boxes are laid out out of combat only, so a group's box that was empty
-- when combat began shows once it ends.

local issecret, Safe = FrogLib.issecret, FrogLib.Safe
local Secure, Unit = FrogLib.Secure, FrogLib.Unit

local Alliance = {}
ns.Alliance = Alliance

local GROUPS = 8
local PER_GROUP = 5
local LABEL = 14 -- the group's label above its members
local GREY = { 0.45, 0.45, 0.45 }

------------------------------------------------------------------------------
-- A member
------------------------------------------------------------------------------

local Member = {}
Member.__index = Member
local members = setmetatable({}, { __mode = "k" }) -- [game-made button] = its Member

local HANDLERS = {
    UNIT_HEALTH = "UpdateHealth", UNIT_MAXHEALTH = "UpdateHealth", UNIT_FLAGS = "UpdateHealth",
    UNIT_CONNECTION = "UpdateAll", UNIT_NAME_UPDATE = "UpdateName", UNIT_IN_RANGE_UPDATE = "UpdateRange",
}

function Member.New(button)
    local member = setmetatable({ button = button }, Member)
    local content = CreateFrame("Frame", nil, button)
    content:SetAllPoints()
    member.content = content
    member.targeted = ns.Band(content, 1, 0.95, 0.7, 0.3, 1)
    member.hover = ns.Band(content, 1, 1, 1, 0.12, 2)
    member.name = FrogLib.Text.Shadowed(content)
    member.name:SetJustifyH("LEFT")
    member.name:SetWordWrap(false)
    member.status = FrogLib.Text.Shadowed(content)
    member.status:SetJustifyH("RIGHT")
    member.status:SetTextColor(0.7, 0.7, 0.7)
    member.status:SetShadowColor(0, 0.07, 0.2, 1)
    member.hp = FrogLib.Gauge.New(content)
    content:SetScript("OnEvent", function(_, event)
        local handler = HANDLERS[event]
        if handler then member[handler](member) end
    end)
    -- The header hands each button its unit (and hands them round again as the raid changes).
    button:HookScript("OnAttributeChanged", function(_, name, value)
        if name == "unit" then member:SetUnit(value) end
    end)
    button:HookScript("OnShow", function() member:Activate() end)
    button:HookScript("OnHide", function() member:Deactivate() end)
    button:HookScript("OnEnter", function(frame)
        member.hover:Show()
        if member.unit and not InCombatLockdown() then
            GameTooltip_SetDefaultAnchor(GameTooltip, frame)
            GameTooltip:SetUnit(member.unit)
            GameTooltip:Show()
        end
    end)
    button:HookScript("OnLeave", function(frame)
        member.hover:Hide()
        if GameTooltip:IsOwned(frame) then GameTooltip:Hide() end
    end)
    members[button] = member
    member:SetUnit(button:GetAttribute("unit"))
    -- Already shown by the header (made in a raid, after a reload): no OnShow is coming for it.
    if button:IsShown() then member:Activate() end
    return member
end

function Member:Layout(cfg, db)
    local media = ns.Media
    media:SetNameFont(self.name, db.font, cfg.nameSize, db.outline)
    media:SetFont(self.status, db.font, math.max(8, cfg.nameSize - 2), db.outline)
    self.hp:SetStyle(db.style)
    self.hp:SetHeight(cfg.gaugeHeight)
    self.hp:SetTexture(db.texture)
    local rim = db.style == "framed" and 4 or 1
    self.name:SetShadowColor(0, 0.07, 0.2, 1)
    self.hp.bar:ClearAllPoints()
    self.hp.bar:SetPoint("BOTTOMLEFT", self.content, "BOTTOMLEFT", 2, rim + 1)
    self.hp.bar:SetPoint("RIGHT", self.content, "RIGHT", -2, 0)
    self.name:ClearAllPoints()
    self.name:SetPoint("BOTTOMLEFT", self.hp.bar, "TOPLEFT", 0, rim + 1)
    self.name:SetPoint("RIGHT", self.content, "RIGHT", -34, 0)
    self.status:ClearAllPoints()
    self.status:SetPoint("BOTTOMRIGHT", self.hp.bar, "TOPRIGHT", 0, rim + 1)
end

-- A new unit, or the same token for someone else (raid7 leaves and raid8 becomes raid7): its events follow and it's
-- drawn afresh. The header hands units round again on every roster change; the same person again changes nothing.
function Member:SetUnit(unit)
    local guid = unit and UnitGUID(unit)
    if issecret(guid) then guid = nil end
    if unit == self.unit and guid ~= nil and guid == self.guid then return end
    local newToken = unit ~= self.unit
    self.unit, self.guid = unit, guid
    if self.shown then
        if newToken then self:Register() end
        self:UpdateAll(true)
    end
end

function Member:Register()
    local content, unit = self.content, self.unit
    content:UnregisterAllEvents()
    if not unit then return end
    for event in pairs(HANDLERS) do pcall(content.RegisterUnitEvent, content, event, unit) end
end

function Member:Activate()
    self.shown = true
    self:Register()
    self:UpdateAll(true)
end

function Member:Deactivate()
    self.shown = false
    self.content:UnregisterAllEvents()
end

function Member:UpdateAll(instant)
    if not self.unit then return end
    self:UpdateName()
    self:UpdateHealth(instant)
    self:UpdateRange()
    self:UpdateTarget()
end

function Member:UpdateName()
    self.name:SetText(Unit.Name(self.unit))
    local _, class = UnitClass(self.unit)
    ns.NameColor(self.name, class)
end

function Member:UpdateHealth(instant)
    local unit, gauge = self.unit, self.hp
    if not unit then return end
    local status, offline = Unit.Status(unit)
    if status then
        gauge:SetValues(offline and 1 or 0, 1, true)
        gauge:SetColor(GREY[1], GREY[2], GREY[3])
        self.status:SetText(status)
        self.status:Show()
        return
    end
    if self.status:IsShown() then self.status:Hide() end
    gauge:SetValues(UnitHealth(unit), UnitHealthMax(unit), instant)
    local color = ns.db.hpColor
    gauge:SetColor(color.r, color.g, color.b)
end

function Member:UpdateRange()
    if self.unit then ns.FadeRange(self.content, self.unit) end
end

function Member:UpdateTarget()
    self.targeted:SetShown(self.unit ~= nil and Safe(UnitIsUnit(self.unit, "target")) == true)
end

------------------------------------------------------------------------------
-- The boxes
------------------------------------------------------------------------------

local function SizeSnippet(cfg)
    return ("self:SetWidth(%d)\nself:SetHeight(%d)"):format(cfg.width, cfg.rowHeight)
end

-- The secure parts of a game-made button (Core.lua) and what's drawn on it.
local function SetUpButton(button)
    local menuName = ns.SecureParts(button)
    Member.New(button)
    return menuName
end

function Alliance:Init()
    local db, cfg = ns.db, ns.db.alliance
    local container = CreateFrame("Frame", "XIVPartyAlliance", UIParent)
    container:SetClampedToScreen(true)
    container:SetMovable(true)
    container:SetSize(1, 1)
    FrogLib.Mover.Make(container, { save = function(point) ns.db.alliance.point = point end, tint = 6,
        secure = true })
    self.container = container
    self.boxes, self.buttons = {}, {}

    -- A header makes buttons only while it's visible (EllesmereUI: IsVisible walks the parent chain), so the
    -- container shows for the making.
    container:Show()
    for group = 1, GROUPS do
        local box = CreateFrame("Frame", nil, container)
        box:SetSize(cfg.width, LABEL + PER_GROUP * cfg.rowHeight)
        box.label = FrogLib.Text.Shadowed(box)
        box.label:SetPoint("TOPLEFT", 2, 0)
        box.label:SetText((GROUP or "Group") .. " " .. group)
        box.label:SetTextColor(0.95, 0.85, 0.55)
        box.sample = box:CreateTexture(nil, "BACKGROUND")
        box.sample:SetPoint("TOPLEFT", 0, -LABEL)
        box.sample:SetPoint("BOTTOMRIGHT")
        box.sample:SetColorTexture(1, 1, 1, 0.08)
        box.sample:Hide()
        local header = CreateFrame("Frame", "XIVPartyGroup" .. group, box, "SecureGroupHeaderTemplate")
        header:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -LABEL)
        header:SetAttribute("template", "SecureUnitButtonTemplate")
        header:SetAttribute("templateType", "Button")
        header:SetAttribute("initialConfigFunction", SizeSnippet(cfg))
        header:SetAttribute("point", "TOP")
        header:SetAttribute("groupFilter", tostring(group))
        header:SetAttribute("showRaid", true)
        header:SetAttribute("maxColumns", 1)
        header:SetAttribute("unitsPerColumn", PER_GROUP)
        header:SetAttribute("sortMethod", "INDEX")
        box:Show()
        header:SetAttribute("startingIndex", 1 - PER_GROUP)
        header:Show()
        header:SetAttribute("startingIndex", 1)
        box.header = header
        for i = 1, PER_GROUP do
            local button = header[i]
            if button then
                self.buttons[#self.buttons + 1] = { button = button, menu = SetUpButton(button) }
            end
        end
        self.boxes[group] = box
    end

    local events = CreateFrame("Frame")
    self.events = events
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_TARGET_CHANGED" then
            for _, member in pairs(members) do
                if member.shown then member:UpdateTarget() end
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            if self.pending then self:Apply() end
        elseif not self.rosterSoon then
            -- Roster changes come in bursts: looked at once, a frame later.
            self.rosterSoon = true
            C_Timer.After(0, function()
                self.rosterSoon = false
                self:RosterChanged()
            end)
        end
    end)
    self:Apply()
end

local counts = {}

-- Someone joined, left or moved: anyone whose token now means someone else is drawn afresh (the header doesn't always
-- hand the same token out again), and the boxes are laid out again if which groups have people changed.
function Alliance:RosterChanged()
    for button, member in pairs(members) do
        if member.shown then member:SetUnit(button:GetAttribute("unit")) end
    end
    self:Layout()
end

-- Which groups have someone in them beyond the full party's two (as bits): the same as last time, and the boxes stay
-- where they are.
local function Signature()
    local own, next = ns.FullGroups()
    for group = 1, GROUPS do counts[group] = 0 end
    if IsInRaid() then
        for index = 1, GetNumGroupMembers() do
            local _, _, subgroup = GetRaidRosterInfo(index)
            subgroup = Safe(subgroup)
            if counts[subgroup] then counts[subgroup] = counts[subgroup] + 1 end
        end
    end
    local filled = 0
    for group = GROUPS, 1, -1 do
        filled = filled * 2 + ((counts[group] > 0 and group ~= own and group ~= next) and 1 or 0)
    end
    return filled
end

-- The boxes wanted, in rows of `columns`: every group with someone in it beyond the full party's (all eight while
-- unlocked).
-- force: the settings changed, so even the same groups are laid out again.
function Alliance:Layout(force)
    if not self.container or not ns.db.alliance.enabled then return end
    if InCombatLockdown() then
        self.pending = true
        return
    end
    local db, cfg = ns.db, ns.db.alliance
    local filled = Signature()
    if not force and filled == self.filled then return end
    self.filled = filled
    local boxHeight = LABEL + PER_GROUP * cfg.rowHeight
    local columns = math.max(1, cfg.columns)
    local placed = 0
    for group, box in ipairs(self.boxes) do
        local wanted = not db.locked or filled % (2 ^ group) >= 2 ^ (group - 1)
        if wanted then
            local column, line = placed % columns, math.floor(placed / columns)
            box:ClearAllPoints()
            box:SetPoint("TOPLEFT", self.container, "TOPLEFT", column * (cfg.width + cfg.spacing),
                -line * (boxHeight + cfg.spacing))
            box:SetSize(cfg.width, boxHeight)
            box:Show()
            placed = placed + 1
        else
            box:Hide()
        end
    end
    local lines = math.max(1, math.ceil(placed / columns))
    local across = math.min(math.max(placed, 1), columns)
    self.container:SetSize(across * (cfg.width + cfg.spacing) - cfg.spacing,
        lines * (boxHeight + cfg.spacing) - cfg.spacing)
end

function Alliance:Apply()
    if not self.container then return end
    if InCombatLockdown() then
        self.pending = true
        return
    end
    self.pending = nil
    local db, cfg = ns.db, ns.db.alliance
    local container = self.container
    container:SetScale(cfg.scale)
    container:ClearAllPoints()
    container:SetPoint(cfg.point[1], UIParent, cfg.point[3], cfg.point[4], cfg.point[5])
    container:EnableMouse(not db.locked)
    container.unlockTint:SetShown(not db.locked)
    -- The buttons sized first: the header lays them out again from their size when its attribute changes below.
    for _, entry in ipairs(self.buttons) do
        local button = entry.button
        button:SetSize(cfg.width, cfg.rowHeight)
        Secure.SetClicks(button, db.clicks and db.locked and entry.menu or nil)
        button:EnableMouse(db.locked)
        local member = members[button]
        if member then
            member:Layout(cfg, db)
            if member.shown then member:UpdateAll(true) end
        end
    end
    for _, box in ipairs(self.boxes) do
        box.sample:SetShown(not db.locked)
        ns.Media:SetFont(box.label, db.font, math.max(8, cfg.nameSize - 1), db.outline)
        box.header:SetAttribute("initialConfigFunction", SizeSnippet(cfg))
    end
    self:Layout(true)
    -- Its events only while it's on.
    local events = { "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_REGEN_ENABLED" }
    for _, event in ipairs(events) do
        if cfg.enabled then self.events:RegisterEvent(event) else self.events:UnregisterEvent(event) end
    end
    -- Shown in a raid (while unlocked always, to be placed).
    if not cfg.enabled then
        UnregisterStateDriver(container, "visibility")
        container:Hide()
    elseif db.locked then
        RegisterStateDriver(container, "visibility", "[group:raid] show; hide")
    else
        UnregisterStateDriver(container, "visibility")
        container:Show()
    end
end
