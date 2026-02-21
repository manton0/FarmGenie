# FarmGenie

A farming session tracker for the **Ascension** private server (WoW 3.3.5). FarmGenie tracks items looted during farming sessions, displays their auction house value, and shows you how much gold you're earning per hour.

## Features

- **Loot Log Window** — Real-time scrollable list of looted items with color-coded quality, AH prices, and hover tooltips
- **Session Stats** — Zone, duration, total value, gold/hr, items looted, and raw gold at a glance
- **Auction House Prices** — Integrates with Auctionator for accurate AH pricing, falls back to vendor prices
- **Item Counter Bar** — Vertical bar of draggable item slots to track specific item counts in your bags in real-time
- **Loot Filters** — Filter by minimum item quality and minimum AH price to keep the log clean
- **Session Management** — Start, pause, and resume sessions; auto-start option available
- **Minimap Button** — Quick-access dropdown for Loot Log, Item Bar, Settings, and New Session
- **Persistent Settings** — Window positions, tracked items, and preferences saved between sessions

## Installation

1. Download the latest release from the [Releases page](https://github.com/manton0/FarmGenie/releases/latest)
2. Extract the ZIP into your `Interface/AddOns` folder
3. Make sure the folder is called `FarmGenie`
4. Start your client and enjoy

## Usage

- **Minimap Button** — Click the Genie minimap button to access Loot Log, Item Bar, Settings, and New Session from a dropdown menu. Drag the button around the minimap to reposition it.
- `/fg` — Open the config window
- `/fg loot` — Toggle the loot log window
- `/fg bar` — Toggle the item counter bar
- `/fg new` — Start a new farming session
- `/fg pause` — Pause logging
- `/fg resume` — Resume logging
- `/fg help` — Show all available commands
- **Item Counter Bar** — Drag items from your bags into slots to track their count. Right-click a slot to remove it. Items auto-rearrange when slots are removed.

## Optional Dependencies

- **Auctionator** — For auction house price lookups. Without it, FarmGenie uses vendor sell prices.

## Author

**mazer** (Discord: the_mazer)
