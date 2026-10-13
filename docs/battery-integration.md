# 배터리 관리 integration

Use `BatteryManagementView()` in the app's section switch. It owns its
`@StateObject BatteryController`; no AppModel property or injected environment
object is required. The controller uses DonyCore BatteryCommand, BatteryEngineReading,
and BatteryInstallation. It refreshes read-only state every 15 seconds while the
page is visible. Switching sections does not stop original maintenance jobs.

Copy `Resources/Battery` recursively into `Contents/Resources/Battery` before app
signing. Preserve `battery`, `battery.upstream.sh`, `smc`, `smc-source/**`, both
licenses, provenance and adaptation notes. Do not recompile or re-sign `smc`
without updating the hardcoded SHA256 in BatteryEngine.swift. The checks apply to
the exact staged binary. App bundle signing may be checked to ensure it does not
change this binary's bytes. The bundled smc is arm64, as the original battery
engine targets Apple Silicon MacBooks.

No privileged operation runs at app launch, in tests, or on unsupported hardware.
Mac mini: `pmset -g batt` contains no InternalBattery; every installation/control
action is disabled and the page states that this Mac has no internal battery.
On a supported MacBook an explicit install-review action explains the paths and
17 narrowly scoped SMC write permissions before requesting macOS authentication.
Existing battery/smc installation paths, legacy ~/.battery or LaunchAgents block
installation until independently reviewed/backed up/removed. The app never takes
ownership of those existing installations.

Operations: percentage limit; lower/upper range; voltage/hysteresis; optional
force discharge; stop and restore charging; charging on/off; adapter supply
on/off; charge/discharge to a target; original 15% → 100% → 1 hour → 80%
calibration; status and logs; original reboot-persistent maintenance LaunchAgent.
Maintenance stop cancels tracked operations and restores charging. No automatic
updater or remote installer exists. Offline removal is available through an
explicit review action: first restore and verify charging/adapter allowance,
then authenticate and verify exact ownership/hashes/sudoers contents before
deleting only the app-specific helper files/rule and matching user LaunchAgent.
Logs and target preferences remain. Unexpected extra helper files are preserved
for review; no recursive privileged deletion is used.
The installed CLI is reachable at
`/Library/PrivilegedHelperTools/donyhome-battery/battery` (no global PATH shim).

Meaningful command/config/parser tests are in BatteryTests.swift. Engine syntax
was parsed with bash -n and SMC was compiled without execution. Real SMC writes,
macOS authorization, sleep/reboot persistence, long-running calibration and
hardware behavior must be validated on an opted-in Apple Silicon MacBook. A CLI
exit is shown as command completion, never as verified hardware success; live
readings/logs show actual status. No battery/control fixtures claim real hardware
success. All home-derived filesystem arguments/redirections are quoted, and
LaunchAgent XML paths escaped, including homes containing spaces or XML characters.
Detached maintenance uses explicit stdio redirection. BatteryCommandRunner uses
file-backed bounded output; status/probe operations have a 15-second timeout while
long-running target operations/calibration may continue until completion or stop.
Tests reproduce a detached child inheriting stderr using only harmless shell/sleep
fixtures, and test timeout termination without executing any battery engine.
