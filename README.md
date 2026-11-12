# Stargate Command dialing computer

A dialing program for **Just Stargate Mod** gates, run on a **CC: Tweaked** computer. It's laid out like the Stargate
Command dialing computer on the show: the gate with its chevrons locking one by one, the address in boxes, the event
horizon and the iris in the ring, and a big status word (IDLE, ENGAGED, LOCKED, INCOMING, IRIS CLOSED, SHUTDOWN).

Made by Darkmoon Hollow. It's also built into the Eclipse Gate mod, which sets it all up in its Stargate Command base.

## What it does

- **Dial** from an address book, or glyph by glyph on the manual dial page. It works out whether the gate needs 6, 7 or 8 symbols, and the destination boxes and chevron lamps grow to match (up to 9 chevrons).
- **Address book:** the full gate address of every entry in chevron boxes, how much power it takes to dial and to hold open, and how often you've dialed it. Add and remove entries.
- **Iris:** open or close it with one button. With the automatic iris on, it closes when a wormhole comes in, opens for a known IDC code (and tells the traveller), and opens again when the wormhole closes.
- **IDC codes:** allow or deny each code, add the last code someone sent, and set your own GDO code (sent to the far gate when you dial out).
- **Gate status:** the gate's own address, power, capacitors, iris strength, how long the wormhole has been open, and the most dialed addresses.
- **Event log:** everything the gate does, with the day and time (the last 200 events, kept through restarts).
- **Base alert:** every side of the computer gives a flashing redstone signal while a wormhole is coming in. Put redstone lamps next to it.
- **Redial** the last address that opened.

## What you need

- Just Stargate Mod and CC: Tweaked (Minecraft 1.20.1, Forge).
- An **advanced computer**, connected to the gate's **base block**: either right next to it, or through **wired modems** (right-click each modem so it turns red, connected).
- An **advanced monitor**, **5 wide by 3 tall**, next to the computer.
- For the iris controls: the gate's iris set to **computer mode** in the gate's settings.

## Install

On the computer:

```
pastebin get <code> sgc
```

or, from a direct link to `sgc.lua`:

```
wget <link to sgc.lua> sgc
```

Then run `sgc`. To have it start whenever the computer boots:

```
label set "Stargate Command"
edit startup
```

and put this one line in `startup`:

```
shell.run("sgc")
```

## Using it

On the monitor, tap **KEYBOARD** for the pages (address book, manual dial, IDC codes, gate status, event log), **LOG** for the event log, the **IRIS** button to open or close the iris, and **REDIAL** to dial the last address again.

On the computer's own keyboard:

| Key | Does |
|---|---|
| 1-9 | dial that address |
| A / X | add / remove an address |
| C / R | add / remove an IDC code |
| P | set your GDO code |
| T | automatic iris on or off |
| I | open or close the iris |
| G | close the gate |
| B | abort dialing |
| Q | quit |

The address book, IDC codes and settings are kept in `/sgc/data` on the computer, the event log in `/sgc/log`.
