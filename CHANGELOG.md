# XIVParty

## 0.1.0

First release: FFXIV's party list.

- **Light party**: you first, then your party, a row each as FFXIV draws them: the job (class) icon on the left, then their place in a small box and "Lv60 Name", the HP and MP gauges under it with each number under its gauge's end, and status effects to the right. Pale gauges in thin pale rims like the party list's (or framed in gold, or a thin glowing line), and a hit's loss drains away in red past the HP fill.
- **Full party** in a raid: one list of up to ten, your raid group then the next one, so a 10-player raid fits whole. In bigger raids the other groups show as **alliance lists**: a small box per group, each member a name over a thin HP gauge. The title over the list says "LIGHT PARTY" or "FULL PARTY".
- **Enmity order** by each icon: who your target hates most, "A" for the one it's attacking, then 1, 2, 3. Where the game hides the threat numbers only the "A" can show.
- **Casts** on the name line: the spell's icon, its name on the right and a thin line filling under it; red when interrupted.
- **Status effects**: debuffs first (in their dispel type's colour), then buffs (all of them, only yours, or none), with the time left under each. The game picks and draws them, so they keep working in combat and dungeons where addons can't read auras.
- On each row: incoming heals and shields on HP; "Dead", "Ghost" or "Offline" in place of the HP number, the gauge greyed; out of range faded; your target in a blue band; a red glow on the icon of anyone something is attacking; the leader's crown and raid marks by the name.
- **Clicks**: left-click targets (with shift, ctrl or alt too), right-click opens the member's menu; click-casting addons such as Clique pick the rows up, and pings land on the member.
- Shows you on your own too (FFXIV always shows you), or only in a group.
- Hides Blizzard's party frames (an option); Blizzard's raid frames can be hidden too (off to start with).
- `/xivparty` (or `/xivpt`) opens the settings: layout, text templates (name, HP and MP numbers), status effects, alliance lists. Unlock to drag the list and the alliance boxes, with a preview party to place it by.
