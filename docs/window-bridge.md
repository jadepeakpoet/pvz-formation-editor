# Native editor/toolbox bridge

`WindowBridge` is a static, per-FlutterEngine endpoint on `pvz_formation_editor/windows`. The main editor owns the canonical document. Availability of this channel is separate from visual/native-window acceptance.

| Dart API / native event | Wire method / payload |
| --- | --- |
| Main `initialize` | `initialize`, no arguments, boolean result |
| Toolbox `initialize` | `ready`, no arguments, latest state map or null |
| Main `publish(state)` | `publishState`, state map |
| Toolbox `publish(state)` | `editState`, state map; returns native/main acceptance result unchanged |
| Main `setVisible(bool)` | `setToolboxVisible`, `{visible: bool}` |
| Toolbox `mainAction(name)` | `mainAction`, `{action: name}` |
| Main `deactivate()` | `deactivate`, no arguments; clears local active snapshot after success |
| Native state messages | `receiveState` / `applyToolboxState`, state map |
| Other native events | `toolboxVisibilityChanged` / `mainAction`, forwarded unchanged |

State snapshots are copied through the channel codec, including nested collections and typed bytes. Callback or getter mutation does not alter the stored snapshot. A `ready` response cannot replace a newer native event received while that request was pending. Generation guards prevent a disposed/older initialization or outgoing failure from detaching a newer editor.

`MissingPluginException` sets `supported=false`; later sends are no-ops until initialization succeeds again. Other platform and application errors propagate. `dispose()` removes the native event handler. `latestState` records local/received state and is not proof that another engine accepted it; callers must use `publish`'s acceptance result.

## Channel contract evidence

`tool/window_bridge_smoke.dart` runs in the real Flutter engine with an explicit in-memory native-channel substitute. The completed report `/tmp/pvz-window-bridge-report.json` contains **28 passing contract cases**: main/toolbox routing, event forwarding, deep snapshot copies, ready ordering, reinitialization/disposal races, unknown/malformed events, unsupported/error behavior, native acceptance true/false, and deactivation. It does not exercise native windows, actual cross-engine delivery, or OS toolbar actions.

Compile/run it with the same frontend-server/flutter_tester workflow as `tool/render_smoke.dart`, substituting `tool/window_bridge_smoke.dart` and its output dill. Focused analysis passed for the bridge and contract harness.

## Actual dual-window acceptance

`tool/parity_windows.dart` is a separate **native app build target**, not a headless mock test. Its root library exposes both `main` and the annotated `toolboxMain` entrypoint needed by the secondary FlutterEngine. Build with `FLUTTER_TARGET=tool/parity_windows.dart` and launch a fresh QA app process, leaving any user app process untouched.

Both QA sessions use `:memory:` repositories and `persistDraft:false`. The two Dart isolates coordinate only test commands/acknowledgements through `/tmp/pvz-window-qa`; the actual editor/toolbox state travels through the unmocked native bridge. The report contains the new process PID/run ID and paired screenshots. It deliberately leaves the app running for independent native screenshots and real AX close-button/operation-bar reopening checks.

The QA MaterialApp sets the production main/toolbox titles explicitly. The primary engine also installs the production `lifecycle.prepareExit` protocol and awaits the editor's exit guards, so subsequent native main-window close acceptance exercises normal shutdown rather than a missing lifecycle handler. The secondary engine does not own that handler.

Before pointer taps, the harness calls the real native `activateWindow` method to bring that engine's OS window forward. Frame settling waits for an actual scheduled frame or dirty repaint boundary, with a three-second timeout; it does not demand a redundant frame from an already painted, idle background engine. Failures retain the toolbox tab/state and current-frame screenshots when capture is possible.

The native harness checks:

- Main and toolbox actual content sizes, non-resizable native windows, absence of a native toolbar, and the separate engine.
- Main page has no scrolling container; real pointer wheel ±300 and a header drag keep the board origin fixed; original background remains 810×635 with the board below its 27-pixel title decoration.
- A toolbox card pointer click changes main selection, then a real main-board pointer click plants that card.
- Toolbox map selection waits for the real apply button, and a preset changes the canonical main document.
- Style 3 changes the actual main `window3.png` image, not merely its radio selection.
- Two real toolbox checkbox pointer actions occur while the first publish awaits native ACK; both document changes must survive in the main engine.
- Real pointer clicks on `toolbox-visibility-toggle` in the 32-pixel Flutter operation bar hide/reopen the actual NSWindow while retaining its engine, local tab and unsent input text. The toggle bounds must sit wholly above the PVZ background, which starts at y=32.
- The toolbox replica and QA main do not create competing persisted drafts.

If the native channel or diagnostics are unavailable, acceptance is failed/notRun and never converted to a native pass. Actual OS close-button and subsequent operation-bar reopen acceptance are separate from this harness report. Native toolbar AX evidence from earlier runs covers the superseded layout, not the current design. Consult the report's status before claiming that the native harness has run.

Current native evidence: run `1792439144231947-19030` completed **9/9 passing cases**, recorded in `/tmp/pvz-window-qa/report.json`. The coordinator separately pressed the actual toolbox close button through AX, observed only the main window in CG visibility after the hide settled, then used an actual OS mouse click on the main operation-bar button and observed the toolbox return. `/tmp/pvz-window-final-main.png` records that final native layout. These native results cover the two-engine/window contract; exhaustive original-control headless cases exercise the same production widgets in the legacy single-engine shell and are a separate acceptance scope.
