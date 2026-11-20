local _, ns = ...

-- One member of the party list, drawn inside their secure button (Party.lua), laid out as FFXIV's: the job (class)
-- icon top left with the enmity order on your target under it ("A" for the one it's attacking, then 2, 3...) and a
-- small bar of how much; a line with their place in a gold box, "Lv60 Name" and the leader's crown; the HP and MP
-- gauges under it (flat, in a thin light border) with each number under its gauge's end; status effects to the right.
-- All the text is FFXIV's light blue. A cast fills a bar over the name line, the spell's name in the name's place. A
-- hit's loss drains away in red past the HP fill. Anything the game may keep secret (health, power, names, range,
-- auras, casts) only goes into widgets that take it.

local issecret, Safe = FrogLib.issecret, FrogLib.Safe
local Color, Unit, Cast, Icons, AuraKit = FrogLib.Color, FrogLib.Unit, FrogLib.Cast, FrogLib.Icons, FrogLib.Auras
local UI = ns.UI

local DISC = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- a soft-edged white circle
local GREY = { 0.45, 0.45, 0.45 }
local MARK_SIZE = 12
local SORT = AuraContainerSortMethod and AuraContainerSortMethod.Default
local SORT_DIR = AuraContainerSortDirection and AuraContainerSortDirection.Normal
local DEBUFF_BORDER = { 0.75, 0.12, 0.08 }
-- The rim and dark track of the framed styles reach this far past the gauge's own edges.
local RIM = { framed = 4, pale = 1, line = 1 }
local TEXT = { 0.68, 0.82, 0.98 }       -- FFXIV's party list text: light blue
local CAST_TEXT = { 0.95, 0.88, 0.90 }  -- a cast's name: a warm white
local SHADOW = { 0, 0.07, 0.2, 1 }      -- under it all: a dark blue
local SAMPLE_CAST = { label = "Greater Heal", value = 0.6, time = "" }
-- The enmity bar: the one it's attacking, the next, everyone else.
local ENMITY_COLORS = { A = { 0.90, 0.25, 0.20 }, ["2"] = { 0.95, 0.55, 0.20 }, other = { 0.40, 0.45, 0.55 } }

local Row = {}
Row.__index = Row
ns.Row = Row

-- What each of the row's own unit events redraws, and the setting it needs on (NEEDS; others always listened to).
local HANDLERS = {
    UNIT_HEALTH = "UpdateHealth", UNIT_MAXHEALTH = "UpdateHealth", UNIT_FLAGS = "UpdateHealth",
    UNIT_CONNECTION = "UpdateAll", UNIT_HEAL_PREDICTION = "UpdateShields", UNIT_ABSORB_AMOUNT_CHANGED = "UpdateShields",
    UNIT_POWER_FREQUENT = "UpdatePower", UNIT_MAXPOWER = "UpdatePower", UNIT_DISPLAYPOWER = "UpdatePower",
    UNIT_NAME_UPDATE = "UpdateName", UNIT_LEVEL = "UpdateName", UNIT_IN_RANGE_UPDATE = "UpdateRange",
    UNIT_THREAT_SITUATION_UPDATE = "UpdateAggro",
}
local NEEDS = {
    UNIT_HEAL_PREDICTION = "heals", UNIT_ABSORB_AMOUNT_CHANGED = "absorb", UNIT_POWER_FREQUENT = "showMP",
    UNIT_MAXPOWER = "showMP", UNIT_DISPLAYPOWER = "showMP", UNIT_THREAT_SITUATION_UPDATE = "aggro",
}
local CAST_EVENT = {}
for _, event in ipairs(Cast.EVENTS) do CAST_EVENT[event] = true end

function Row.IconSize(db)
    return math.max(10, math.min(db.nameSize + 6, db.rowHeight - 12))
end

-- The column before the name and gauges: the icon over the enmity order and its bar.
local function IconColumn(db)
    return math.max(Row.IconSize(db), 26) + 4
end

-- Light blue over a dark blue shadow, as FFXIV's party list.
local function Tint(fontString, color)
    color = color or TEXT
    fontString:SetTextColor(color[1], color[2], color[3])
    fontString:SetShadowColor(SHADOW[1], SHADOW[2], SHADOW[3], SHADOW[4])
end

-- How far the gauges reach from the row's left edge.
function Row.Width(db)
    return IconColumn(db) + db.hpWidth + (db.showMP and (db.gap + db.mpWidth) or 0)
end

-- root: the member's secure button; unit: its token ("player", "party1"; a raid member's comes from the header
-- through SetUnit); index: its place in the list.
function Row.New(root, unit, index)
    local row = setmetatable({ root = root, index = index }, Row)
    local content = CreateFrame("Frame", nil, root)
    content:SetAllPoints()
    row.content = content

    row.targeted = ns.Band(content, 0.35, 0.6, 1, 0.4, 1)
    row.hover = ns.Band(content, 1, 1, 1, 0.12, 2)

    row.glow = content:CreateTexture(nil, "ARTWORK", nil, -1)
    row.glow:SetTexture(DISC)
    row.glow:SetBlendMode("ADD")
    row.glow:SetVertexColor(1, 0.15, 0.1, 0.9)
    row.glow:Hide()
    row.icon = content:CreateTexture(nil, "ARTWORK")
    row.enmity = FrogLib.Text.Shadowed(content)
    row.enmity:SetJustifyH("LEFT")
    Tint(row.enmity)
    local enmityBar = CreateFrame("StatusBar", nil, content)
    enmityBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    enmityBar:SetMinMaxValues(0, 1)
    enmityBar.track = enmityBar:CreateTexture(nil, "BACKGROUND")
    enmityBar.track:SetAllPoints()
    enmityBar.track:SetColorTexture(0, 0, 0, 0.6)
    enmityBar:Hide()
    row.enmityBar = enmityBar

    -- The place number in its small gold box.
    local box = CreateFrame("Frame", nil, content)
    box.edge = box:CreateTexture(nil, "BACKGROUND")
    box.edge:SetAllPoints()
    box.edge:SetColorTexture(0.93, 0.82, 0.55, 1)
    box.fill = box:CreateTexture(nil, "BORDER")
    box.fill:SetPoint("TOPLEFT", 1, -1)
    box.fill:SetPoint("BOTTOMRIGHT", -1, 1)
    box.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    box.fill:SetGradient("VERTICAL", CreateColor(0.55, 0.40, 0.18, 1), CreateColor(0.80, 0.64, 0.36, 1))
    box.text = FrogLib.Text.Shadowed(box) -- a font up front: the number can be written before the layout's
    box.text:SetPoint("CENTER", 0, 0)
    box.text:SetTextColor(1, 1, 1)
    row.box = box

    row.name = FrogLib.Text.Shadowed(content)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    Tint(row.name)
    row.leader = content:CreateTexture(nil, "OVERLAY")
    row.mark = content:CreateFontString(nil, "OVERLAY")
    row.mark:SetFont(STANDARD_TEXT_FONT, 12, "")
    row.mark:SetSize(MARK_SIZE, MARK_SIZE)

    row.hp = FrogLib.Gauge.New(content)
    row.hp:EnableLag()
    row.hp:EnableHeal()
    row.hp:EnableAbsorb()
    row.mp = FrogLib.Gauge.New(content)
    row.hpText = FrogLib.Text.Shadowed(content)
    row.hpText:SetJustifyH("RIGHT")
    Tint(row.hpText)
    row.mpText = FrogLib.Text.Shadowed(content)
    row.mpText:SetJustifyH("RIGHT")
    Tint(row.mpText)

    -- The cast: a bar over the name line, the name giving way to the spell's name on the right.
    local holder = CreateFrame("Frame", nil, content)
    holder:Hide()
    holder:SetScript("OnShow", function() row.name:SetAlpha(0) end)
    holder:SetScript("OnHide", function() row.name:SetAlpha(1) end)
    local castGauge = FrogLib.Gauge.New(holder)
    castGauge:SetStyle("pale")
    castGauge:SetHeight(3)
    row.castGauge = castGauge
    row.castLabel = FrogLib.Text.Shadowed(holder)
    row.castLabel:SetJustifyH("RIGHT")
    row.castLabel:SetWordWrap(false)
    Tint(row.castLabel, CAST_TEXT)
    row.castTime = FrogLib.Text.Shadowed(holder)
    row.castTime:Hide()
    row.castHolder = holder
    row.cast = Cast.NewLine({
        bar = castGauge.bar, gauge = castGauge, label = row.castLabel, time = row.castTime, holder = holder, showTime = function() return false end, sample = SAMPLE_CAST,
    })

    content:SetScript("OnEvent", function(_, event, ...) row:OnEvent(event, ...) end)
    row:SetUnit(unit)
    return row
end

------------------------------------------------------------------------------
-- Layout (out of combat: Party.lua sizes the secure button)
------------------------------------------------------------------------------

local function StyleGauge(gauge, db, width)
    gauge:SetStyle(db.style)
    gauge:SetHeight(db.gaugeHeight)
    gauge:SetTexture(db.texture)
    gauge.bar:SetWidth(width)
end

function Row:Layout(db)
    local media, content = ns.Media, self.content
    local x = IconColumn(db)
    -- The name line, gauges and numbers stacked and centred in the row's height.
    local rim = RIM[db.style] or 1
    local block = db.nameSize + 1 + rim + db.gaugeHeight + rim + math.max(db.hpSize, db.mpSize)
    local top = math.floor((db.rowHeight - block) / 2 + 0.5)
    local span = db.hpWidth + (db.showMP and (db.gap + db.mpWidth) or 0)

    -- The icon at the top of its column, the enmity order and bar under it.
    local iconSize = Row.IconSize(db)
    self.icon:ClearAllPoints()
    self.icon:SetSize(iconSize, iconSize)
    self.icon:SetPoint("TOP", content, "TOPLEFT", (x - 4) / 2, -top + 2)
    self.glow:ClearAllPoints()
    self.glow:SetSize(iconSize * 1.8, iconSize * 1.8)
    self.glow:SetPoint("CENTER", self.icon, "CENTER")
    media:SetFont(self.enmity, db.numberFont, math.max(7, db.mpSize - 2), db.outline)
    self.enmity:ClearAllPoints()
    self.enmity:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, math.max(0, top - 2))
    self.enmityBar:ClearAllPoints()
    self.enmityBar:SetPoint("BOTTOMLEFT", self.enmity, "BOTTOMRIGHT", 2, 2)
    self.enmityBar:SetSize(math.max(10, x - 18), 3)

    local box, boxSize = self.box, db.nameSize
    box:ClearAllPoints()
    box:SetSize(boxSize, boxSize)
    box:SetPoint("TOPLEFT", content, "TOPLEFT", x, -top)
    box:SetShown(db.number)
    media:SetFont(box.text, db.numberFont, math.max(7, db.nameSize - 3), db.outline)
    local nameLeft = x + (db.number and (boxSize + 3) or 0)

    self.name:ClearAllPoints()
    self.name:SetPoint("TOPLEFT", content, "TOPLEFT", nameLeft, -top)
    self.name:SetWidth(x + span - nameLeft - MARK_SIZE * 2 - 4)
    media:SetNameFont(self.name, db.font, db.nameSize, db.outline)
    self.leader:ClearAllPoints()
    self.leader:SetSize(db.nameSize, db.nameSize)
    self.leader:SetPoint("TOPRIGHT", content, "TOPLEFT", x + span, -top)
    self.mark:ClearAllPoints()
    self.mark:SetPoint("RIGHT", self.leader, "LEFT", -1, 0)

    local gaugeTop = top + db.nameSize + 1 + rim
    StyleGauge(self.hp, db, db.hpWidth)
    self.hp.bar:ClearAllPoints()
    self.hp.bar:SetPoint("TOPLEFT", content, "TOPLEFT", x, -gaugeTop)
    StyleGauge(self.mp, db, db.mpWidth)
    self.mp.bar:ClearAllPoints()
    self.mp.bar:SetPoint("LEFT", self.hp.bar, "RIGHT", db.gap, 0)
    self.mp.bar:SetShown(db.showMP)

    media:SetFont(self.hpText, db.numberFont, db.hpSize, db.outline)
    media:SetFont(self.mpText, db.numberFont, db.mpSize, db.outline)
    self.hpText:ClearAllPoints()
    self.hpText:SetPoint("TOPRIGHT", self.hp.bar, "BOTTOMRIGHT", 0, -rim)
    self.mpText:ClearAllPoints()
    self.mpText:SetPoint("TOPRIGHT", self.mp.bar, "BOTTOMRIGHT", 0, -rim)
    self.mpText:SetShown(db.showMP)

    local holder = self.castHolder
    holder:ClearAllPoints()
    holder:SetPoint("TOPLEFT", content, "TOPLEFT", nameLeft, -top)
    holder:SetSize(x + span - nameLeft, db.nameSize + 1)
    media:SetFont(self.castLabel, db.font, db.nameSize, db.outline)
    self.castLabel:ClearAllPoints()
    self.castLabel:SetPoint("TOPLEFT")
    self.castLabel:SetPoint("TOPRIGHT")
    -- The bar over the name line, from the place box to the end of the gauges.
    self.castGauge:SetTexture(db.texture)
    self.castGauge.bar:ClearAllPoints()
    self.castGauge.bar:SetPoint("BOTTOMLEFT", content, "TOPLEFT", x, -top + 2)
    self.castGauge.bar:SetPoint("RIGHT", holder, "RIGHT", 0, 0)
end

------------------------------------------------------------------------------
-- Status effects: one of 12.1's AuraContainers, the engine picking and drawing them where addons can't read
-- them (FrogLib's Auras). Built out of combat only; where it sits is part of what it's built with.
------------------------------------------------------------------------------

local function StyleStatus(slot)
    local cfg, db = ns.db.statuses, ns.db
    if slot.size ~= cfg.size and pcall(slot.button.SetSize, slot.button, cfg.size, cfg.size) then
        slot.size = cfg.size
    end
    local size = math.max(8, math.floor(cfg.size * 0.45))
    ns.Media:SetFont(slot.stack, db.font, size, db.outline)
    ns.Media:SetFont(slot.duration, db.font, size, db.outline)
    slot.duration:SetShown(cfg.showTimer)
end

local GROUPS = {
    debuffs = { { "harm", "HARMFUL", true } },
    mine = { { "harm", "HARMFUL", true }, { "mine", "HELPFUL|PLAYER" } },
    all = { { "harm", "HARMFUL", true }, { "help", "HELPFUL" } },
}

local function StatusSignature(db)
    local cfg = db.statuses
    return table.concat({ tostring(cfg.enabled), cfg.mode, cfg.max, cfg.size, cfg.spacing, tostring(cfg.showTimer),
        Row.Width(db), db.rowHeight }, "|")
end

-- false when it has to wait for the end of combat.
function Row:BuildStatuses(db)
    local signature = StatusSignature(db)
    if self.statusSignature == signature then
        for _, slot in ipairs(self.statusSlots or {}) do pcall(StyleStatus, slot) end
        return true
    end
    if InCombatLockdown() then return false end
    AuraKit.Release(self.statuses)
    self.statuses, self.statusUnit, self.statusSlots, self.statusSignature = nil, nil, {}, signature
    local cfg = db.statuses
    if not cfg.enabled then return true end
    local container = AuraKit.NewContainer(self.content)
    if not container then return true end
    -- Centred in the row with the timers under the icons.
    local tall = cfg.size + (cfg.showTimer and 10 or 0)
    container:SetPoint("TOPLEFT", self.content, "TOPLEFT", Row.Width(db) + 8,
        -math.max(0, math.floor((db.rowHeight - tall) / 2 + 0.5)))
    AuraKit.Flow(container, "TOPLEFT", "RIGHT", "DOWN")
    local layout = { elementWidth = cfg.size, elementHeight = cfg.size, elementSpacing = cfg.spacing,
        lineSpacing = cfg.spacing + (cfg.showTimer and 12 or 0) }
    local slots = self.statusSlots
    for _, group in ipairs(GROUPS[cfg.mode] or GROUPS.mine) do
        local harmful = group[3]
        pcall(container.AddAuraGroup, container, group[1], group[2], {
            maxFrameCount = cfg.max, sortMethod = SORT, sortDirection = SORT_DIR, layout = layout,
            initializeFrame = function(button)
                slots[#slots + 1] = AuraKit.InitButton(button, { border = harmful and DEBUFF_BORDER or nil,
                    style = StyleStatus })
            end,
        })
    end
    -- One line, as long as both groups at their fullest.
    AuraKit.SetLineSize(container, (cfg.size + cfg.spacing) * cfg.max * 2 + 1)
    self.statuses = container
    self:BindStatuses()
    return true
end

-- The container follows the row's unit (a raid member's can change); the game may refuse in combat, and it's asked
-- again at the next redraw.
function Row:BindStatuses()
    local container = self.statuses
    if not container or not self.unit or self.statusUnit == self.unit then return end
    if pcall(container.SetUnit, container, self.unit) then self.statusUnit = self.unit end
end

------------------------------------------------------------------------------
-- The unit, shown and hidden (the game shows the button while its member exists)
------------------------------------------------------------------------------

-- A new unit, or the same token for someone else (a raid member leaving moves everyone after them down one): drawn
-- afresh, its events following. The header hands units round again on every roster change; the same person again
-- changes nothing.
function Row:SetUnit(unit)
    local guid = unit and UnitGUID(unit)
    if issecret(guid) then guid = nil end
    if unit == self.unit and guid ~= nil and guid == self.guid then return end
    local wasMe = self.isMe
    local newToken = unit ~= self.unit
    self.unit, self.guid = unit, guid
    self.isMe = unit ~= nil and Unit.IsPlayer(unit) == true
    if self.shown and not self.sample then
        -- You take no range event: registered afresh when the token, or whether it's you, changed.
        if newToken or wasMe ~= self.isMe then self:Register() end
        self:UpdateAll(true)
    end
end

function Row:Register()
    local content, unit, db = self.content, self.unit, ns.db
    content:UnregisterAllEvents()
    if not unit then return end
    for event in pairs(HANDLERS) do
        local need = NEEDS[event]
        if (not need or db[need]) and not (self.isMe and event == "UNIT_IN_RANGE_UPDATE") then
            pcall(content.RegisterUnitEvent, content, event, unit)
        end
    end
    if db.cast then
        for event in pairs(CAST_EVENT) do pcall(content.RegisterUnitEvent, content, event, unit) end
    end
end

function Row:Activate()
    self.shown = true
    if self.sample then
        self:ShowSample()
        return
    end
    self:Register()
    self:UpdateAll(true)
end

function Row:Deactivate()
    self.shown = false
    self.content:UnregisterAllEvents()
    self.cast:Hide()
end

function Row:OnEvent(event, ...)
    if CAST_EVENT[event] then
        self.cast:Update(self.unit, event, false, (select(4, ...)))
        return
    end
    local handler = HANDLERS[event]
    if handler then self[handler](self) end
end

------------------------------------------------------------------------------
-- Drawing
------------------------------------------------------------------------------

function Row:UpdateAll(instant)
    if self.sample then
        self:ShowSample()
        return
    end
    if not self.unit then return end
    self.box.text:SetText(self.index)
    self:UpdateName()
    self:UpdateIcons()
    self:UpdateHealth(instant)
    self:UpdatePower(instant)
    self:UpdateRange()
    self:UpdateTarget()
    self:UpdateAggro()
    if ns.db.cast then self.cast:Update(self.unit, nil, false) else self.cast:Hide() end
    self:BindStatuses()
    if self.statuses then pcall(self.statuses.UpdateAllAuras, self.statuses) end
end

-- FFXIV's light blue, or the class's colour with that setting on.
local function PaintName(fontString, class)
    if ns.db.classColorNames then
        ns.NameColor(fontString, class)
    else
        fontString:SetTextColor(TEXT[1], TEXT[2], TEXT[3])
    end
end

function Row:UpdateName()
    ns.SetUnitText(self.name, ns.db.nameText, self.unit)
    local _, class = UnitClass(self.unit)
    PaintName(self.name, class)
end

function Row:UpdateIcons()
    local db, unit = ns.db, self.unit
    local _, class = UnitClass(unit)
    self.icon:SetShown(db.classIcon and Icons.SetClass(self.icon, Safe(class)) or false)
    self.leader:SetShown(Icons.SHOW.leader(self.leader, unit))
    -- The mark may be secret: written, never tested (nothing shows for "no mark").
    self.mark:SetShown(Icons.SHOW.raid(self.mark, unit, MARK_SIZE))
end

local healthValues = {}

-- Dead, a ghost or offline: the gauge grey and the word in place of the number.
function Row:UpdateHealth(instant)
    local db, unit, gauge = ns.db, self.unit, self.hp
    local status, offline = Unit.Status(unit)
    self.status = status
    if status then
        gauge:SetValues(offline and 1 or 0, 1, true)
        gauge:SetColor(GREY[1], GREY[2], GREY[3])
        gauge:ShowHeal(false)
        gauge:ShowAbsorb(false)
        self.hpText:Show()
        self.hpText:SetText(status)
        self.hpText:SetTextColor(0.7, 0.7, 0.7)
        return
    end
    local value, max = UnitHealth(unit), UnitHealthMax(unit)
    gauge:SetValues(value, max, instant)
    local color = db.hpColor
    gauge:SetColor(color.r, color.g, color.b)
    self:UpdateShields(instant, max)
    self.hpText:SetTextColor(TEXT[1], TEXT[2], TEXT[3])
    healthValues.value, healthValues.max, healthValues.percent = value, max, Unit.HealthPercent(unit)
    UI.SetTemplateText(self.hpText, db.hpText, healthValues)
    healthValues.value, healthValues.max, healthValues.percent = nil, nil, nil
end

-- Incoming heals and shields on the HP gauge (none while dead or offline). max: the health maximum, just read.
function Row:UpdateShields(instant, max)
    if self.status or not self.unit then return end
    local db, unit, gauge = ns.db, self.unit, self.hp
    gauge:ShowHeal(db.heals)
    if db.heals then gauge:UpdateHeal(unit, instant) end
    gauge:ShowAbsorb(db.absorb)
    -- The shield can be secret: it only goes into the gauge's bars.
    if db.absorb then
        gauge:SetAbsorb((UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit)) or 0, max or UnitHealthMax(unit))
    end
end

-- The MP gauge's colour: the party list's pale one, FFXIV's for the power, or the game's.
local function PowerColor(token, db)
    if db.colorMode == "pale" then
        local color = db.mpColor
        return color.r, color.g, color.b
    end
    local _, r, g, b = Color.XIVPower(token, db.colorMode == "wow")
    return r, g, b
end

local powerValues = {}

function Row:UpdatePower(instant)
    local db, unit = ns.db, self.unit
    if not db.showMP or not unit then return end
    local powerType, token = UnitPowerType(unit)
    powerType = Safe(powerType)
    local value, max = UnitPower(unit, powerType), UnitPowerMax(unit, powerType)
    self.mp:SetValues(value, max, instant)
    self.mp:SetColor(PowerColor(Safe(token), db))
    powerValues.value, powerValues.max, powerValues.percent = value, max, Unit.PowerPercent(unit, powerType)
    UI.SetTemplateText(self.mpText, db.mpText, powerValues)
    powerValues.value, powerValues.max, powerValues.percent = nil, nil, nil
end

-- Out of range: faded by the game itself where whether they're near is secret.
function Row:UpdateRange()
    local content = self.content
    if self.isMe or self.sample or not self.unit then
        content:SetAlpha(1)
        return
    end
    ns.FadeRange(content, self.unit)
end

-- Your target among them: a blue band (a secret answer counts as no).
function Row:UpdateTarget()
    self.targeted:SetShown(not self.sample and self.unit ~= nil and Safe(UnitIsUnit(self.unit, "target")) == true)
end

-- Something attacking them: situation 2 (tanking without the most threat) or 3 (tanking securely).
function Row:UpdateAggro()
    local situation = not self.sample and ns.db.aggro and self.unit and Safe(UnitThreatSituation(self.unit))
    self.glow:SetShown(type(situation) == "number" and situation >= 2)
end

-- The enmity order on your target (Party.lua works it out): "A", "2", "3"... or nothing, and how much of the top
-- enmity they have (0 to 1) for the bar. tanking: a secret yes/no where the game hides the numbers, so only "A" can
-- show, drawn by the game from it.
function Row:SetEnmity(text, tanking, share)
    local enmity, bar = self.enmity, self.enmityBar
    if tanking ~= nil then
        enmity:SetText("A")
        if not pcall(enmity.SetAlphaFromBoolean, enmity, tanking, 1, 0) then enmity:SetAlpha(0) end
        bar:Hide()
        return
    end
    enmity:SetAlpha(1)
    enmity:SetText(text or "")
    if text and share then
        local color = ENMITY_COLORS[text] or ENMITY_COLORS.other
        bar:SetStatusBarColor(color[1], color[2], color[3])
        bar:SetValue(share)
        bar:Show()
    else
        bar:Hide()
    end
end

function Row:Enter(frame)
    self.hover:Show()
    if self.sample or not self.unit or InCombatLockdown() then return end
    GameTooltip_SetDefaultAnchor(GameTooltip, frame)
    GameTooltip:SetUnit(self.unit)
    GameTooltip:Show()
end

function Row:Leave(frame)
    self.hover:Hide()
    if GameTooltip:IsOwned(frame) then GameTooltip:Hide() end
end

------------------------------------------------------------------------------
-- Samples while unlocked
------------------------------------------------------------------------------

function Row:ShowSample()
    local db, fake = ns.db, self.sample
    self.content:SetAlpha(1)
    self.box.text:SetText(self.index)
    ns.SetUnitText(self.name, db.nameText, nil, fake)
    PaintName(self.name, fake.classFile)
    self.icon:SetShown(db.classIcon and Icons.SetClass(self.icon, fake.classFile) or false)
    self.leader:SetShown(self.index == 1 and Icons.PREVIEW.leader(self.leader) or false)
    self.mark:Hide()
    self.targeted:SetShown(self.index == 3)
    self.glow:SetShown(db.aggro and self.index == 2)
    self:SetEnmity(fake.enmity, nil, fake.share)
    local color = db.hpColor
    self.hp:SetValues(fake.value, fake.max, true)
    self.hp:SetColor(color.r, color.g, color.b)
    self.hp:ShowHeal(false)
    self.hp:ShowAbsorb(false)
    self.hpText:SetTextColor(TEXT[1], TEXT[2], TEXT[3])
    UI.SetTemplateText(self.hpText, db.hpText, { value = fake.value, max = fake.max, percent = fake.value / fake.max * 100 })
    self.mp:SetValues(fake.power, fake.powermax, true)
    self.mp:SetColor(PowerColor(fake.token, db))
    UI.SetTemplateText(self.mpText, db.mpText,
        { value = fake.power, max = fake.powermax, percent = fake.power / fake.powermax * 100 })
    if db.cast and fake.casting then self.cast:Sample() else self.cast:Hide() end
end
