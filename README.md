# Flow

A live network monitor for the macOS menu bar. Flow shows real-time download and upload speed, per-interface activity, and daily/monthly data usage — without the Dock, without accounts, and without sending anything off your Mac.

## Features

- Live download and upload speed in the menu bar
- Separate, independently scaled 60-second charts for download and upload
- Per-interface rates for VPN, Wi-Fi, Ethernet, and other active links
- Today, this month, and session usage totals, persisted locally
- Notification Center widget (small and medium) with current rates and usage
- Optional launch at login
- Light and dark appearance with a translucent glass panel

## Install

Requires macOS 13 or later (Apple silicon or Intel).

```sh
./test.sh
./build.sh
```

`build.sh` produces a universal binary, builds the icon, and installs `Flow.app` into `/Applications`.

## Notes

- Usage totals are based on the primary network interface, so traffic through a VPN is counted once.
- Usage history starts from the first time you run the app; macOS does not retain per-interface counters across reboots.
- The widget is fed by Flow.app and shows the last published sample. WidgetKit refreshes widgets at most about once a minute, so the widget is a summary — not a per-second meter.
- Flow reads interface counters through `sysctl` and makes no network requests of its own.

## License

MIT
