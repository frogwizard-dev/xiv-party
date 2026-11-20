local ADDON, ns = ...

-- XIVParty: FFXIV's party list (Party.lua, each member a row drawn by Row.lua): the light party, you and your party,
-- for dungeons; in a raid the full party, your raid group and the next, up to ten; and the rest of a bigger raid as
-- FFXIV's alliance lists (Alliance.lua), a small box per raid group with a name and a thin HP gauge per member.

local FONTS = "Interface\\AddOns\\" .. ADDON .. "\\Fonts\\"
ns.FONTS = FONTS

-- The bar textures and fonts the settings offer, this addon's own fonts first (FrogLib's Media).
ns.Media = FrogLib.Media.New({
    fonts = {
        { "Michroma (wide)", FONTS .. "Michroma.ttf" }, -- wide, like FFXIV's gauge numbers
        { "Source Sans 3 (Myriad-like)", FONTS .. "SourceSans3.ttf" },
    },
    fallbackFont = FONTS .. "SourceSans3.ttf",
})
-- The settings controls (FrogLib's UI.lua); every change calls ns.Refresh().
ns.UI = FrogLib.UI.Kit({ refresh = function() ns.Refresh() end })
ns.Print = FrogLib.Util.Printer("XIVParty", "8fd0f5")

local PALE = { r = 0.96, g = 0.97, b = 0.98 } -- the party list's gauges: white

ns.defaults = {
    locked = true,
    point = { "TOPLEFT", "UIParent", "TOPLEFT", 40, -230 },
    scale = 1,
    showSolo = true,    -- you on your own too, as FFXIV's list always shows you
    title = true,       -- "LIGHT PARTY" or "FULL PARTY" over the list
    rowHeight = 34,
    spacing = 2,        -- between one member and the next
    hpWidth = 110,
    mpWidth = 70,
    gap = 8,            -- between the HP and MP gauges
    gaugeHeight = 4,
    style = "pale",     -- "pale": the party list's flat bar in a thin light border; "framed": gold-rimmed; "line": a glow
    texture = "Interface\\Buttons\\WHITE8X8",
    hpColor = { r = PALE.r, g = PALE.g, b = PALE.b },
    mpColor = { r = PALE.r, g = PALE.g, b = PALE.b },
    colorMode = "pale", -- MP: "pale" mpColor, "xiv" FFXIV's colour for the power, "wow" the game's
    showMP = true,
    classIcon = true,   -- the job icon: each member's class
    number = true,      -- their place in the list, in a small box before the name
    enmity = true,      -- the enmity order on your target by the icon: "A" for the one it's attacking, then 1, 2...
    font = FONTS .. "SourceSans3.ttf",
    numberFont = FONTS .. "Michroma.ttf", -- the HP and MP numbers
    outline = "OUTLINE",
    nameSize = 12,
    hpSize = 12,
    mpSize = 12,
    -- Templates: name, level, class; value, max, percent (percent.1 for a decimal).
    nameText = "Lv level name",
    hpText = "value",
    mpText = "value",
    classColorNames = false,
    heals = true,       -- incoming heals on the HP gauge
    absorb = true,      -- shields on the HP gauge
    rangeAlpha = 0.45,  -- members out of range fade to this
    aggro = true,       -- a red glow on the icon of a member something is attacking
    cast = true,        -- a member's cast on the name line
    clicks = true,      -- left-click targets, right-click opens the member's menu
    hideBlizzard = true, -- Blizzard's party frames
    -- Status effects to the right of each row: "all" (debuffs, then buffs), "mine" (debuffs, then your buffs on
    -- them), or "debuffs".
    statuses = { enabled = true, mode = "all", size = 22, max = 8, spacing = 2, showTimer = true },
    -- The groups a raid has beyond the full party's two.
    alliance = {
        enabled = true,
        point = { "TOPRIGHT", "UIParent", "TOPRIGHT", -230, -240 },
        scale = 1,
        columns = 2,     -- boxes side by side; the rest go below
        width = 120,
        rowHeight = 22,
        gaugeHeight = 2,
        nameSize = 11,
        spacing = 12,    -- between boxes
        hideBlizzard = false, -- Blizzard's raid frames
    },
}

-- Fills a font string from a template (FrogLib.Unit: values may be secret, so only SetFormattedText formats them).
-- fake: a sample's words; values: words read a moment ago.
local textOptions = {}
function ns.SetUnitText(fontString, template, unit, fake, values, power)
    textOptions.fake, textOptions.values, textOptions.power = fake, values, power
    textOptions.classColor = false
    FrogLib.Unit.SetText(fontString, template, unit, textOptions)
    textOptions.fake, textOptions.values = nil, nil
end

-- A band of colour across a row, fading out to the right (your target, the mouse over it).
function ns.Band(content, r, g, b, a, sublevel)
    local band = content:CreateTexture(nil, "BACKGROUND", nil, sublevel)
    band:SetAllPoints()
    band:SetTexture("Interface\\Buttons\\WHITE8X8")
    band:SetGradient("HORIZONTAL", CreateColor(r, g, b, a), CreateColor(r, g, b, 0))
    band:Hide()
    return band
end

-- FFXIV's light blue, or the class's colour with "Names in their class colour" on (class: its token, maybe secret).
function ns.NameColor(fontString, class)
    local r, g, b = 0.68, 0.82, 0.98
    if ns.db.classColorNames then
        local cr, cg, cb = FrogLib.Color.Class(class)
        if cr then r, g, b = cr, cg, cb end
    end
    fontString:SetTextColor(r, g, b)
end

-- A member's drawing faded while they're out of range; by the game itself where whether they're near is secret.
function ns.FadeRange(region, unit)
    local near, alpha = FrogLib.Unit.InRange(unit, true), ns.db.rangeAlpha
    if FrogLib.issecret(near) then
        if not pcall(region.SetAlphaFromBoolean, region, near, 1, alpha) then region:SetAlpha(1) end
    else
        region:SetAlpha(near and 1 or alpha)
    end
end

-- The secure parts of a member's button, out of combat: left-click targets, right-click opens their menu (FrogLib's
-- Secure), click-casting addons pick it up, pings land on the member (EllesmereUI's way: the mixin's methods read the
-- unit attribute; nothing writes .unit). Returns the menu button's name.
function ns.SecureParts(button)
    button:RegisterForClicks("AnyUp")
    local menuName = button:GetName() .. "Menu"
    FrogLib.Secure.MenuButton(button, menuName)
    if PingableType_UnitFrameMixin then
        Mixin(button, PingableType_UnitFrameMixin)
        button:SetAttribute("ping-receiver", true)
    end
    ClickCastFrames = ClickCastFrames or {}
    ClickCastFrames[button] = true
    return menuName
end

-- The full party's raid groups: yours, and the lowest-numbered other one with someone in it (nil outside a raid).
local filled = {}
function ns.FullGroups()
    local index = UnitInRaid("player")
    if not index then return nil end
    local _, _, own = GetRaidRosterInfo(index)
    own = FrogLib.Safe(own)
    wipe(filled)
    for member = 1, GetNumGroupMembers() do
        local _, _, subgroup = GetRaidRosterInfo(member)
        subgroup = FrogLib.Safe(subgroup)
        if subgroup then filled[subgroup] = true end
    end
    for group = 1, 8 do
        if group ~= own and filled[group] then return own, group end
    end
    return own, nil
end

-- Hidden while the game shows them in their place.
function ns.HideBlizzard()
    local db = ns.db
    FrogLib.Hider.Set(ADDON, "PartyFrame", db.hideBlizzard)
    FrogLib.Hider.Set(ADDON, "CompactPartyFrame", db.hideBlizzard)
    FrogLib.Hider.Set(ADDON, "CompactRaidFrameContainer", db.alliance.enabled and db.alliance.hideBlizzard)
end

function ns.Refresh()
    if not ns.started then return end
    ns.Party:Apply()
    ns.Alliance:Apply()
    ns.HideBlizzard()
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(_, event, addonName)
    if event == "ADDON_LOADED" and addonName == ADDON then
        XIVPartyDB = XIVPartyDB or {}
        local db = XIVPartyDB
        -- The first test build's look (gold rims, roomy rows) saved on first load: settings left as they were then take
        -- the party list's look.
        if not db.version then
            local first = { rowHeight = 44, spacing = 6, hpWidth = 120, gap = 10, style = "framed", colorMode = "xiv",
                nameSize = 13, hpSize = 14, mpSize = 10, nameText = "name" }
            for key, value in pairs(first) do
                if db[key] == value then db[key] = nil end
            end
            if type(db.hpColor) == "table" and db.hpColor.r == 0.45 and db.hpColor.g == 0.80 then db.hpColor = nil end
            if type(db.statuses) == "table" then
                if db.statuses.mode == "mine" then db.statuses.mode = nil end
                if db.statuses.size == 20 then db.statuses.size = nil end
            end
            if type(db.alliance) == "table" then db.alliance.ownGroup = nil end
            db.version = 2
        end
        FrogLib.Util.CopyDefaults(ns.defaults, XIVPartyDB)
        ns.db = XIVPartyDB
    elseif event == "PLAYER_LOGIN" or (event == "PLAYER_REGEN_ENABLED" and not ns.started) then
        -- Secure frames can't be made in combat (a reload mid-fight): then once it ends.
        if InCombatLockdown() then
            loader:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
        loader:UnregisterEvent("PLAYER_REGEN_ENABLED")
        ns.started = true
        ns.Party:Init()
        ns.Alliance:Init()
        ns.HideBlizzard()
    end
end)

SLASH_XIVPARTY1 = "/xivparty"
SLASH_XIVPARTY2 = "/xivpt"
SlashCmdList.XIVPARTY = function() ns.ToggleConfig() end
function XIVParty_OnCompartmentClick() ns.ToggleConfig() end

-- Its entry in the game's Options > AddOns list (FrogLib's Options.lua).
FrogLib.Options.Add("XIVParty", ns, {
    open = function()
        if not (ns.window and ns.window:IsShown()) then ns.ToggleConfig() end
    end,
    commands = { { "/xivparty", "open or close the settings (also /xivpt)" } },
})
