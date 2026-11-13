# Stargate Command dialing computer

A dialing program for **Just Stargate Mod** gates, run on a **CC: Tweaked** computer. It's laid out like the Stargate
Command dialing computer on the show: the gate with its chevrons locking one by one, the address in boxes, the event
horizon and the iris in the ring, and a big status word (IDLE, ENGAGED, LOCKED, INCOMING, IRIS CLOSED, SHUTDOWN).

Made by Darkmoon Hollow. It's also built into the Eclipse Gate mod, which sets it all up in its Stargate Command base.

## What it does

- **The gate comes alive:** the ring carries a mark for every glyph and turns to each symbol as it's encoded, the top chevron lifts as the symbol comes under it, chevrons flash as they lock, the wormhole bursts out in a kawoosh and settles into a rippling event horizon, and the iris's vanes close in and open out.
- **Dial** from the address book, glyph by glyph on the manual dial page, or with **REDIAL**. It works out whether the gate needs 6, 7 or 8 symbols (the boxes and chevron lamps grow to match, up to 9), checks the address and the power first, stops at once on ABORT or an incoming wormhole, tries a busy gate again, and has one more go if a chevron fails to lock. **Fast dial** hands the gate the whole address at once, as a DHD does.
- **Address book:** every entry's full gate address in chevron boxes, the power to dial it and hold it open, and how often you've dialed it. Show one world at a time or just your **favourites** (always listed first), sort by name, distance or most dialed, jump to a letter.
- **Sounds** through any speaker on the computer: DHD clicks for each chevron, the last one clunking home, the kawoosh, the iris, travellers, IDC codes accepted or refused, and a klaxon while something's coming in.
- **Iris:** a button on the main screen. With the automatic iris on, it closes when a wormhole comes in, opens for a known IDC code (and tells the traveller), and opens again when the wormhole closes.
- **IDC codes:** allow or deny each code, add the last code someone sent, and set your own GDO code (sent to the far gate when you dial out).
- **Gate status:** the gate's own address, power, capacitors, iris strength, how long the wormhole has been open, and the most dialed addresses.
- **Event log:** everything the gate does, with the day and time (the last 200 events, kept through restarts), including everyone who goes through the gate.
- **Base alert:** every side of the computer gives a flashing redstone signal while a wormhole is coming in. Put redstone lamps next to it.
- **Self-destruct:** arm and confirm it, then a minute's countdown with sirens and lights (abort any time). At zero the gate shuts down, the iris closes, and every side of the computer gives a steady redstone signal for five seconds, for whatever you've wired to it.
- **Pocket remote:** set a code with K, then run `sgc remote` on a pocket computer with a wireless or ender modem: see the gate, dial, work the iris, shut down or abort from anywhere the modem reaches.

## What you need

- Just Stargate Mod and CC: Tweaked (Minecraft 1.20.1, Forge).
- An **advanced computer**, connected to the gate's **base block**: either right next to it, or through **wired modems** (right-click each modem so it turns red, connected).
- An **advanced monitor**, **5 wide by 3 tall**, next to the computer.
- For the iris controls: the gate's iris set to **computer mode** in the gate's settings.
- Optional: a **speaker** next to the computer for sounds, and a **wireless or ender modem** on it for the pocket remote.

## Install

On the computer:

```
wget https://raw.githubusercontent.com/Darkmoon-Hollow-Development/SGC-Dialing-Program/main/sgc.lua sgc
```

Then run `sgc`. To update to the newest version later, delete the old one and get it again (your address book, IDC codes and log are kept):

```
delete sgc
wget https://raw.githubusercontent.com/Darkmoon-Hollow-Development/SGC-Dialing-Program/main/sgc.lua sgc
```

To have it start whenever the computer boots:

```
label set "Stargate Command"
edit startup
```

and put this one line in `startup`:

```
shell.run("sgc")
```

If `wget` says the domain isn't allowed, the server has turned off CC: Tweaked's internet access (`http` in `computercraft-server.toml`); `raw.githubusercontent.com` is allowed by default.

## Using it

On the monitor, tap **KEYBOARD** for the pages (address book, manual dial, IDC codes, gate status, event log), **LOG** for the event log, the **IRIS** button to open or close the iris, **CLOSE GATE** to shut the wormhole down (it reads **STOP DIAL** while dialing), and **REDIAL** to dial the last address again. Fast dial, sounds, the remote and the self-destruct are on the gate status page.

On the computer's own keyboard:

| Key | Does |
|---|---|
| 1-9 | dial that address |
| A / X | add / remove an address |
| C / R | add / remove an IDC code |
| P | set your GDO code |
| T | automatic iris on or off |
| I | open or close the iris |
| F | fast dial on or off |
| S | sounds on or off |
| K | set the pocket remote's code (empty turns it off) |
| G | close the gate |
| B | abort dialing |
| Q | quit |

The address book, IDC codes and settings are kept in `/sgc/data` on the computer, the event log in `/sgc/log`.
