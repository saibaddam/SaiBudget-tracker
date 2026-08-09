# SaiBudget-tracker

Two single-file, dependency-free trackers. Both are plain HTML — open the file in
a browser and use it. No build step, no server, no account, no network calls.

| File | What it tracks | Where data lives |
|---|---|---|
| [`budget-tracker.html`](budget-tracker.html) | Personal budget — income, expenses, categories, monthly limits | This browser's `localStorage` |
| [`trading-tracker.html`](trading-tracker.html) | Daily trading P&L against a weekly target | A `.json` file you pick on disk |

## Budget tracker

Open `budget-tracker.html` in any modern browser.

- **Transactions** — add income or expenses with a date, category, amount, and
  note. Rows can be edited (✎) or deleted (✕).
- **Month view** — everything (stats, charts, budgets, table) is scoped to the
  month in the header. Use `‹` / `›` to move between months.
- **Stats** — income, expenses, net, savings rate, and share of total budget used.
- **Charts** — spending by category for the month, and income vs expenses across
  the last six months, with a table view of the same numbers.
- **Budgets** — set a monthly limit per expense category. Bars turn yellow at 80%
  and red with an "⚠ Over by …" badge past the limit.
- **Categories** — sensible defaults, plus "+ New category…" in the picker.
- **Import / export** — JSON round-trips everything (transactions, budgets,
  categories); CSV exports all transactions for a spreadsheet.

Empty on first run: **Load sample data** fills three months of realistic
transactions and budgets so the charts have something to show. Delete the rows
when you're done with them.

### Where your data is

Everything is written to `localStorage` under the key `saibudget.tracker.v1`, in
the browser, on your machine. Nothing is uploaded. Two consequences worth
knowing:

- Data is **per-browser and per-profile** — it does not follow you to another
  browser, device, or a private window.
- Clearing site data (or "clear cookies and site data" for `file://`) erases it.

Use **Export JSON** for backups and to move data between machines; **Import**
replaces the current data with the file's contents after confirming.

### Data format

```jsonc
{
  "version": 1,
  "transactions": [
    { "id": "…", "date": "2026-08-05", "type": "expense",
      "category": "Groceries", "amount": 186.32, "note": "" }
  ],
  "budgets":    { "Groceries": 400 },          // monthly limit per expense category
  "categories": { "income": [], "expense": [] }
}
```

Imports are validated field by field: bad rows are dropped, `amount` is coerced
to a positive number, unknown categories are added to the picker, and anything
unparseable leaves your existing data untouched.

### Notes on the charts

The income/expense series are **blue and orange, not green and red**. Green
`#3fb950` against red `#f85149` differ by ΔE 2.2 under deuteranopia — one color to
roughly 5% of men — so they are unusable as a two-series encoding. Green and red
survive only on signed text, where the `+` / `−` carries the meaning
independently of hue. Both series also carry a legend, and the trend chart has a
table view, so identity is never color-alone.

## Trading tracker

`trading-tracker.html` logs daily money made/lost and tracks each week against a
$2,500 target. It stores data in a `.json` file you choose via the File System
Access API (**New File** / **Open File** / **Save**, or Ctrl/Cmd+S), which means
it needs Chrome or Edge; other browsers can use it, but nothing persists.

## TradingView MCP connector

`.mcp.json` registers a local TradingView bridge, unrelated to the trackers
above. It only works on a machine running TradingView Desktop — see
[`docs/tradingview-mcp-setup.md`](docs/tradingview-mcp-setup.md) and run
[`scripts/tv-health-check.sh`](scripts/tv-health-check.sh) to diagnose it.
