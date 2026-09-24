# Desktop widget

`scripts/Ensure-Monitor.ps1` now starts the local service and a single native
Windows widget. `scripts/Start-Monitor.ps1` does the same; add `-Open` to also
open the full browser dashboard. Use `Ensure-Monitor.ps1 -NoWidget` for the
service alone.

The 320 x 300 widget starts at the bottom right of the primary display work
area, above the taskbar, and stays on top. Drag its background to move it.
The minus button folds it into a 210 x 44 cost-only bar; plus expands it again.
The bottom-right corner stays fixed and the selected mode survives restart.
The gauge uses a green arc without a needle: above 60% of the current maximum
it turns yellow, and above 80% it turns red. The tray menu can show it,
return it to the bottom right, open the dashboard, or exit the widget.

The gauge shows recorded API-equivalent USD over a trailing 30-second window,
displayed as USD/30s. It refreshes every second.
The gauge eases between samples over 600 ms using WPF animation;
the graph scrolls between samples. Numbers remain the actual recorded amounts.
The graph holds 300 one-second
points of the same rolling total; both use a fixed $0.60/30s maximum (equivalent
to $0.02/s). Above $0.60, the gauge stays full and red and the graph is capped;
the numeric amount still shows the actual total. Yellow starts above $0.36 and
red above $0.48. The API retains its per-second values, converted by the widget.
This is not
instantaneous billing: values arrive when Codex writes token usage events.
Auto-review is excluded; unknown prices are explicitly flagged. After five
seconds without valid data, the widget shows an offline state instead of zero.

`GET /api/widget` provides the series using event timestamps, so historical
rescans do not appear as new spending. An indexed query covers only 329 seconds.
No new external packages or services are required; WPF and Windows PowerShell
provide the window. HTTP reads are asynchronous and stay on localhost.

`scripts/Install-WidgetStartup.ps1` registers the service and widget at Windows
login for the current user. To disable login startup, remove the **Codex Usage
Monitor** shortcut from `shell:startup`. This does not remove the monitor.

Diagnostics: `%USERPROFILE%\.codex-usage-monitor\widget-status.json`,
`widget-error.log` (if an error occurs), and `widget-preview.png` (widget only).
Existing credit conversion and model pricing remain in `config/rate-card.json`.
