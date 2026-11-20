local _, ns = ...
local UI = ns.UI

-- The settings window (/xivparty): FrogLib's controls; every change calls ns.Refresh().

local STYLES = UI.Options("pale", "Party list (thin pale rim)", "framed", "Framed (gold rim)", "line", "Line (thin glow)")
local COLOR_MODES = UI.Options("pale", "One colour (below)", "xiv", "FFXIV colour for each power", "wow",
    "WoW power colours")
local STATUS_MODES = UI.Options("mine", "Debuffs, then my buffs on them", "all", "Debuffs, then all buffs",
    "debuffs", "Debuffs only")

local function BuildLayout(page)
    local db = ns.db
    local place = UI.Placer(page)
    place(UI.Checkbox(page, "Unlock to move (drag the first row; shows a preview)",
        function() return not db.locked end, function(value) db.locked = not value end), 28)
    place(UI.Checkbox(page, "Show me on my own too (FFXIV always shows you)", db, "showSolo"), 28)
    place(UI.Checkbox(page, "\"LIGHT PARTY\" / \"FULL PARTY\" over the list", db, "title"), 28)
    place(UI.Checkbox(page, "Click to target, right-click for the member's menu", db, "clicks"), 28)
    place(UI.Checkbox(page, "Hide Blizzard's party frames", db, "hideBlizzard"), 34)
    place(UI.Stepper(page, "Scale", 0.5, 2, 0.05, db, "scale", "%.2f"), 26)
    place(UI.Stepper(page, "Row height", 24, 70, 1, db, "rowHeight"), 26)
    place(UI.Stepper(page, "Space between rows", 0, 30, 1, db, "spacing"), 26)
    place(UI.Stepper(page, "HP gauge width", 60, 300, 5, db, "hpWidth"), 26)
    place(UI.Stepper(page, "MP gauge width", 30, 200, 5, db, "mpWidth"), 26)
    place(UI.Stepper(page, "Gap between HP and MP", 0, 40, 1, db, "gap"), 26)
    place(UI.Stepper(page, "Gauge height", 2, 12, 1, db, "gaugeHeight"), 32)
    place(UI.Dropdown(page, "Gauge style", STYLES, db, "style"), 30)
    place(UI.Dropdown(page, "Bar texture", function() return ns.Media:List("statusbar") end, db, "texture"), 30)
    place(UI.ColorSwatch(page, "HP colour", db, "hpColor"), 30)
    place(UI.Checkbox(page, "Show MP (each member's power)", db, "showMP"), 26)
    place(UI.Dropdown(page, "MP colour", COLOR_MODES, db, "colorMode"), 30)
    place(UI.ColorSwatch(page, "MP colour (one colour)", db, "mpColor"), 30)
    place(UI.Checkbox(page, "Show incoming heals on HP", db, "heals"), 26)
    place(UI.Checkbox(page, "Show shields on HP", db, "absorb"), 26)
    place(UI.Checkbox(page, "Show casts on the name line", db, "cast"), 26)
    place(UI.Checkbox(page, "Enmity order on your target by the icon (A, 1, 2...)", db, "enmity"), 26)
    place(UI.Checkbox(page, "Red glow on the icon of a member something attacks", db, "aggro"), 26)
    place(UI.Checkbox(page, "Job (class) icons", db, "classIcon"), 26)
    place(UI.Checkbox(page, "Place numbers in a box before the name", db, "number"), 30)
    place(UI.Stepper(page, "Out of range opacity", 0.1, 1, 0.05, db, "rangeAlpha", "%.2f"), 26)
end

local function BuildText(page)
    local db = ns.db
    local place = UI.Placer(page)
    place(UI.TextBox(page, "Name", db, "nameText"), 28)
    place(UI.TextBox(page, "HP number", db, "hpText"), 28)
    place(UI.TextBox(page, "MP number", db, "mpText"), 30)
    place(UI.Help(page, "Name words: |cffffd100name|r, |cffffd100level|r, |cffffd100class|r. Number words: "
        .. "|cffffd100value|r, |cffffd100max|r, |cffffd100percent|r (|cffffd100percent.1|r for a decimal). "
        .. "For example: Lv level name, or percent%", 400), 44, 4)
    place(UI.Checkbox(page, "Names in their class colour", db, "classColorNames"), 30)
    place(UI.Dropdown(page, "Name font", function() return ns.Media:List("font") end, db, "font"), 30)
    place(UI.Dropdown(page, "Number font", function() return ns.Media:List("font") end, db, "numberFont"), 30)
    place(UI.Dropdown(page, "Font outline", UI.OUTLINES, db, "outline"), 30)
    place(UI.Stepper(page, "Name size", 8, 24, 1, db, "nameSize"), 26)
    place(UI.Stepper(page, "HP number size", 8, 30, 1, db, "hpSize"), 26)
    place(UI.Stepper(page, "MP number size", 7, 24, 1, db, "mpSize"), 26)
end

local function BuildStatuses(page)
    local cfg = ns.db.statuses
    local place = UI.Placer(page)
    place(UI.Checkbox(page, "Show status effects beside each member", cfg, "enabled"), 28)
    place(UI.Dropdown(page, "Which", STATUS_MODES, cfg, "mode"), 30)
    place(UI.Stepper(page, "Icon size", 12, 40, 1, cfg, "size"), 26)
    place(UI.Stepper(page, "Most of each kind", 1, 16, 1, cfg, "max"), 26)
    place(UI.Stepper(page, "Space between icons", 0, 10, 1, cfg, "spacing"), 26)
    place(UI.Checkbox(page, "Time left under each icon", cfg, "showTimer"), 30)
    place(UI.Help(page, "The game picks and draws them, so they keep working in combat and dungeons, where "
        .. "addons can't read auras. Debuffs have their dispel type's colour. Changes made in combat apply once "
        .. "it ends.", 400), 44)
end

local function BuildAlliance(page)
    local cfg = ns.db.alliance
    local place = UI.Placer(page)
    place(UI.Checkbox(page, "Show the rest of the raid as alliance lists", cfg, "enabled"), 28)
    place(UI.Checkbox(page, "Hide Blizzard's raid frames", cfg, "hideBlizzard"), 34)
    place(UI.Stepper(page, "Scale", 0.5, 2, 0.05, cfg, "scale", "%.2f"), 26)
    place(UI.Stepper(page, "Groups side by side", 1, 8, 1, cfg, "columns"), 26)
    place(UI.Stepper(page, "Width", 70, 250, 5, cfg, "width"), 26)
    place(UI.Stepper(page, "Row height", 14, 40, 1, cfg, "rowHeight"), 26)
    place(UI.Stepper(page, "Gauge height", 1, 8, 1, cfg, "gaugeHeight"), 26)
    place(UI.Stepper(page, "Name size", 7, 18, 1, cfg, "nameSize"), 26)
    place(UI.Stepper(page, "Space between groups", 0, 40, 1, cfg, "spacing"), 32)
    place(UI.Help(page, "In a raid the party list is the full party (your group and the next, up to ten), and "
        .. "these show the other groups, a box each. "
        .. "Unlock (Layout) to drag them; every box shows while unlocked. A group that was empty when a fight "
        .. "started gets its box once it ends.", 400), 44)
end

function ns.ToggleConfig()
    if not ns.window then
        ns.window = UI.Window("XIVPartyConfig", "XIVParty", 460, 660, {
            { "layout", "Layout", BuildLayout },
            { "text", "Text", BuildText },
            { "statuses", "Status effects", BuildStatuses },
            { "alliance", "Alliance lists", BuildAlliance },
        }, { scroll = true, fitTabs = true })
        return
    end
    ns.window:SetShown(not ns.window:IsShown())
end
