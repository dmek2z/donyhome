# DonyHome battery integration

Pinned battery engine: https://github.com/actuallymentor/battery at
`f4e342f013e5e35d6c55f89a4f06917a118f993a` (v1.3.4). `battery.upstream.sh`
is the unmodified MIT-licensed source; `battery` is our offline adaptation.
The copyright and complete MIT terms are in `LICENSE.battery`.

The adapted engine retains percentage/range/voltage maintenance, force discharge,
charging and adapter switching, one-time charge/discharge targets, calibration,
status/logs, and maintenance persistence through a user LaunchAgent. The changes:

- version suffix `-donyhome.1`;
- dedicated root-owned `/Library/PrivilegedHelperTools/donyhome-battery`;
- dedicated `~/.donyhome-battery` and `kr.donyhome.battery` LaunchAgent;
- remove upstream network updater, installer, uninstaller and broad sudoers writer;
- refuse these administrative commands instead of fetching/executing remote code;
- noninteractive SMC sudo calls, with failed key writes exiting visibly;
- PID identity checks and tracked charge/discharge jobs;
- cancellation traps stop helper children, cancellable waits propagate failures;
- quote all home-derived filesystem arguments and redirections, and XML-escape
  LaunchAgent log paths, supporting home directories containing spaces;
- explicitly redirect detached maintenance stdout/stderr/stdin, and use a
  file-backed Swift command runner so inherited child descriptors cannot hang
  foreground command completion. Status probes have a 15-second limit.

We do not expose network update/reinstall. The app installs only fixed bundled
resources after an explicit click and macOS administrator authentication. The
installer refuses existing foreign or incomplete installs, checks root-owned
parent directories, hashes root-owned staged bytes, validates sudoers with
visudo, then commits. The current user can sudo only 17 exact SMC write commands;
there is no passwordless shell, arbitrary arguments, or updater privilege.

An explicit removal action stops maintenance and verifies charging and adapter
allowance are restored before administrator authentication. The offline removal
script verifies root ownership, safe parents, exact hashes and exact sudoers
contents. It deletes only this integration's three helper files and sudoers rule;
non-recursive rmdir preserves unexpected extra files. The matching user LaunchAgent
and runtime PID markers are removed; logs and target preferences are preserved.

SMC executable: rebuilt from https://github.com/hholtmann/smcFanControl commit
`e1bd672bcd2d72eddff9b6da7b9cae38e35c4206`, `smc-command` sources. All source,
original Makefile, README and GPL v2 license are bundled in `smc-source`.
`LICENSE.smc` contains the distribution's GPL v2 license. The original battery
repository provided an older unversioned SMC binary, so it is deliberately not
distributed. `SMC-PROVENANCE.md` records the original upstream note for context.
The distributed executable was built, never executed, using:

```
/usr/bin/clang -arch arm64 -DCMD_TOOL_BUILD -framework IOKit \
  -o smc smc-source/smc.c
```

The source emits deprecation and format-security warnings inherited from
smcFanControl. This integration only invokes fixed reviewed four-character SMC
keys. It supports Apple Silicon machines with an internal battery and matching
SMC keys; other hardware controls are disabled.

GPL redistribution: retain the GPL text and corresponding complete machine-readable
SMC source/build instructions with every app distribution. The MIT engine notice
must also accompany every distribution. These are separate command-line programs
invoked by SwiftUI, not linked into the app. Source/license folders are accessible
from the Battery Management page. Never remove them during resource copying.
