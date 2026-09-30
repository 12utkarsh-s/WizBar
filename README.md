# WizBar

A tiny macOS menu bar app for controlling [WiZ](https://www.wizconnected.com/) smart bulbs over your local network — no cloud, no account, no phone.

![alt text](image-1.png)

Click the 💡 in the menu bar to get a panel with, for each bulb:

- **Power** switch
- **Brightness** slider (10–100%)
- **White / Color** mode
  - White: color temperature slider (2200K warm → 6500K cool)
  - Color: hue and saturation sliders
- **Link both** — apply every change to all bulbs at once
- **Launch at login**

The menu bar icon is filled when any bulb is on. Bulbs that don't respond are shown as _Offline_.

## Requirements

- macOS 14 (Sonoma) or later
- Swift toolchain — either Xcode or just the Command Line Tools (`xcode-select --install`)
- WiZ bulbs already set up on your Wi‑Fi (via the WiZ phone app), on the same network as your Mac

## 1. Configure your bulbs

WizBar talks to bulbs by IP address, so you need to tell it where yours are.

### Find each bulb's IP address

Either:

- **Your router's admin page** — look in the list of connected / DHCP clients. WiZ bulbs usually show up with a name starting `wiz_`.
- **The WiZ app** — open the light's settings; the device info section shows its IP and MAC address.

Then check that your Mac can reach it (replace the IP):

```sh
echo -n '{"method":"getPilot","params":{}}' | nc -u -w 1 192.168.1.14 38899
```

A working bulb replies with something like:

```json
{
  "method": "getPilot",
  "env": "pro",
  "result": {
    "mac": "9877d52ea3f8",
    "state": true,
    "temp": 2700,
    "dimming": 100
  }
}
```

No reply means the IP is wrong, the bulb is unplugged, or it's on a different network.

### Pin the IPs (recommended)

Routers can hand out new IPs after a restart, which would make a bulb show as _Offline_. In your router settings, add a **DHCP reservation** (sometimes called "static lease" or "address reservation") for each bulb's MAC address so it always gets the same IP.

### Add them to WizBar

Open `Sources/WizBar/Models.swift` and edit the `bulbs` list in `AppModel`:

```swift
let bulbs = [
    Bulb(name: "Bedroom Lamp", host: "192.168.1.14"),
    Bulb(name: "Desk Light",   host: "192.168.1.17"),
]
```

`name` is whatever you want shown in the panel; `host` is the bulb's IP. Add as many lines as you have bulbs — the panel grows to fit, and **Link both** applies to all of them.

## 2. Build and install

```sh
git clone https://github.com/12utkarsh-s/WizBar.git
cd WizBar
# ...edit Sources/WizBar/Models.swift as above...
./build.sh --install
open /Applications/WizBar.app
```

`build.sh` compiles a release build, packages it as `build/WizBar.app`, and signs it locally. With `--install` it also quits any running copy and replaces `/Applications/WizBar.app`. Without the flag it only builds, so you can try `open build/WizBar.app` first.

### First launch

1. The 💡 icon appears in the menu bar. The app has no Dock icon or window. (On a crowded menu bar it may be hidden behind the notch.)
2. macOS asks to allow WizBar to **find devices on your local network** — click **Allow**. Without it every bulb shows as _Offline_. If you missed the prompt, enable it in **System Settings → Privacy & Security → Local Network**, then quit and reopen WizBar.
3. Tick **Launch at login** at the bottom of the panel to have it start automatically.

### Updating

After changing the code (or pulling new changes), run `./build.sh --install` and reopen the app. Your _Launch at login_ and _Link both_ settings carry over. Because the app is signed locally rather than with an Apple Developer ID, macOS may ask for Local Network permission again after a rebuild.

## How it works

WiZ bulbs run a small JSON-over-UDP server on **port 38899** on your local network. WizBar just speaks that protocol directly — the same thing you can do by hand with `nc`:

```sh
# Read the current state
echo -n '{"method":"getPilot","params":{}}' | nc -u -w 1 <bulb-ip> 38899

# Warm white at 75%
echo -n '{"id":1,"method":"setPilot","params":{"state":true,"temp":3000,"dimming":75}}' | nc -u -w 1 <bulb-ip> 38899

# Red
echo -n '{"id":1,"method":"setPilot","params":{"state":true,"r":255,"g":0,"b":0,"dimming":75}}' | nc -u -w 1 <bulb-ip> 38899
```

| `setPilot` param | Meaning                                  |
| ---------------- | ---------------------------------------- |
| `state`          | `true` = on, `false` = off               |
| `dimming`        | brightness, 10–100                       |
| `temp`           | color temperature in Kelvin (white mode) |
| `r`, `g`, `b`    | color, 0–255 each (color mode)           |

A bulb is either in white mode (`temp`) or color mode (`r`/`g`/`b`) — sending one switches it out of the other.

### Inside the app

| File                             | Role                                                                                                                                                                     |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `Sources/WizBar/WizClient.swift` | Sends one UDP datagram with Apple's Network framework and waits up to 1 s for the reply. `getPilot` parses the bulb's state; `setPilot` sends a change.                  |
| `Sources/WizBar/Models.swift`    | `Bulb` holds each bulb's state and turns control changes into `setPilot` params. `AppModel` holds the bulb list, _Link both_, background refresh, and _Launch at login_. |
| `Sources/WizBar/Views.swift`     | The SwiftUI UI: a `MenuBarExtra` (the menu bar icon + dropdown panel), one card per bulb, and a gradient slider control.                                                 |
| `Info.plist`                     | `LSUIElement` hides the Dock icon; `NSLocalNetworkUsageDescription` is the text in the Local Network permission prompt.                                                  |
| `build.sh`                       | Builds with Swift Package Manager and assembles the `.app` bundle.                                                                                                       |

A few details worth knowing:

- **Live state.** Each time you open the panel (and every 30 seconds in the background) WizBar sends `getPilot` to every bulb, so the sliders match reality even if you changed the lights from your phone.
- **Throttled dragging.** Dragging a slider produces far more updates than a bulb can handle. WizBar sends at most one `setPilot` per bulb every 100 ms, always with the latest values, and resends the final state when you release the slider in case a UDP packet was lost.
- **Offline detection.** If a bulb doesn't answer within 1 second, its card is greyed out until the next successful refresh.
- **Adjusting turns it on.** Moving any slider on a bulb that's off switches it on.

## Troubleshooting

| Symptom                                 | Fix                                                                                                                                                             |
| --------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| All bulbs _Offline_                     | Allow WizBar under **System Settings → Privacy & Security → Local Network**, then reopen it.                                                                    |
| One bulb _Offline_                      | Its IP probably changed — re-check with the `nc` command above and set up a DHCP reservation.                                                                   |
| No menu bar icon                        | The menu bar may be full (hidden behind the notch), or WizBar may be switched off in **System Settings → Menu Bar**. Check it's running with `pgrep -x WizBar`. |
| "WizBar can't be opened" on another Mac | The app is signed locally, not notarized. Build it on that Mac with `./build.sh`, or right-click the app → **Open**.                                            |
