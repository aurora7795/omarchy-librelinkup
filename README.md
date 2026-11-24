# omarchy-librelinkup

A bar widget for the [Omarchy](https://omarchy.org/) shell that shows your
blood glucose from **LibreLinkUp**: the current value and trend arrow in the
bar, and a 12-hour graph in a popup.

> **Not a medical device.** This is a convenience display. Do not use it for
> treatment or dosing decisions. It is not affiliated with or endorsed by
> Abbott. It uses the unofficial LibreView follower API, which can change or
> break without notice, and use may be subject to Abbott's terms.

## Features

- Value and trend arrow (`5.8 →`) in the bar; turns the bar's urgent colour
  when low or high; `?` appended when the reading is over 15 minutes old.
- Popup with large reading, age, 12-hour graph with your target range shaded,
  and range / average.
- Click the unit label in the popup to switch between mg/dL and mmol/L; the
  graph axis follows. The choice is remembered.
- Sign in from the popup itself, no config file editing.
- Left-click opens the popup, middle-click refreshes, `r` refreshes in the popup.

## Install

```bash
omarchy plugin add https://github.com/aurora7795/omarchy-librelinkup --enable
```

Or clone into `~/.config/omarchy/plugins/aurora7795.librelinkup/` and run
`omarchy plugin enable aurora7795.librelinkup --section right`.

Requires `python3` (standard library only). Then click the widget and sign in.

## Sign in

Use the **LibreLinkUp follower** account that your Libre app shares with, not
the sensor owner's login. If LibreLinkUp asks you to accept new terms, do that
in the phone app first.

## Where things are stored

| File | Contents |
|---|---|
| `~/.config/librelinkup/config.json` | email, password (**plain text**, permissions 600), unit |
| `~/.cache/librelinkup/session.json` | cached session token (permissions 600) |

The password is passed to the helper through an environment variable, never on
the command line. Nothing is sent anywhere except LibreView
(`api*.libreview.io`).

## Settings

In the widget's entry in `~/.config/omarchy/shell.json`:

| Key | Default | |
|---|---|---|
| `intervalSec` | `60` | refresh interval, 60 to 600 |
| `unit` | `"mgdl"` | default unit; the popup's choice overrides it |

## Files

- `manifest.json`: plugin manifest
- `BarWidget.qml`: the bar pill
- `Panel.qml`: data polling, popup, sign-in form, graph
- `llu.py`: LibreLinkUp client (login, region redirect, token cache, fetch)

## License

MIT
