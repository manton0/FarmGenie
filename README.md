# FarmGenie

A farming session tracker for the **Ascension** private server (WoW 3.3.5). FarmGenie tracks items looted during farming sessions, displays their auction house value, and shows you how much gold you're earning per hour. It also provides a powerful bag cleanup system that can auto-delete, auto-sell, and auto-bank items using a flexible condition-based rule builder.

## Features

- **Loot Log Window** — Real-time scrollable list of looted items with color-coded quality, AH prices, and hover tooltips
- **Session Stats** — Zone, duration, total value, gold/hr, items looted, and raw gold at a glance
- **Auction House Prices** — Integrates with Auctionator for accurate AH pricing, falls back to vendor prices
- **Item Counter Bar** — Vertical bar of draggable item slots to track specific item counts in your bags in real-time
- **Loot Filters** — Filter by minimum item quality and minimum AH price to keep the log clean
- **Condition-Based Rule Builder** — Create rules with multiple conditions (item quality, type, name, AH price, vendor price, soulbound, quest item) to control what happens to your loot. Each rule has an action (Keep, Delete, Sell, or Bank) and conditions that must all match (AND logic). Keep rules always take priority.
- **Auto Delete** — Automatically delete items matching Delete rules as you loot them
- **Auto Vendor** — Automatically sell items matching Sell rules when you open a merchant, with an optional confirmation popup
- **Auto Bank** — Automatically deposit items matching Bank rules when you open a bank, with an optional confirmation popup
- **Clean Bags** — Manually scan and delete items matching Delete rules with a confirmation popup
- **Global Exclusions** — Protect soulbound and quest items from all cleanup actions regardless of rules
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
- `/fg vendor` — Run auto-vendor scan (sells items matching Sell rules if at a merchant)
- `/fg clean` — Clean bags now (delete items matching Delete rules)
- `/fg bank` — Deposit items matching Bank rules (requires bank to be open)
- `/fg help` — Show all available commands
- **Item Counter Bar** — Drag items from your bags into slots to track their count. Right-click a slot to remove it. Items auto-rearrange when slots are removed.
- **Bag Cleanup Rules** — Configure rules in Settings > Bag Cleanup > Rules. Each rule has an action and one or more conditions. Use Keep rules to protect valuable items, Delete rules for junk, Sell rules for vendor trash, and Bank rules for items to store. Enable automation toggles in the Bag Cleanup panel to trigger rules automatically.

## Optional Dependencies

- **Auctionator** — For auction house price lookups. Without it, FarmGenie uses vendor sell prices.

## Author

**mazer** (Discord: the_mazer)
