# Development tool care verification · 2.2.1

Core: 168 tests in 31 suites passed, including individual storage eligibility/revalidation, shared VS Code ownership, symlink/project/credential protections, cancellation, pressure review and tool-identity resource filtering. One independent whole-change review found a GUI display-name filtering mismatch; the fix passed three resource-filter tests and the full suite.

Design: release app build and strict ad-hoc signature verification passed. The standalone design skill passed schema validation and was installed globally. The portable installer was verified for first install, replacement and preservation of the prior skill. Four policy fixtures verify valid controls, rejection of new text dropdowns/native resource pickers and reference drift; CI runs them.

Native app: replaced the installed bundle while preserving app data, then checked tool row/reset selection, disabled files owned by a running tool, retention sheet open/close, tool-filtered memory navigation, task chips and empty state. Shared select/clear actions selected eligible app rows and excluded protected DonyHome/Finder rows; no termination action was executed. Development and resource layouts were visually checked at 960pt width and the standard 1130pt width. Fonts/icons are bundled and the main app uses a fixed light color scheme. Another physical Mac/OS version was not available for this check.

Boundaries: tests use temporary fixtures for moves and process control. Personal files were not cleaned and real developer processes were not suspended/stopped. Unknown cache roots/private conversation schemas remain unconfirmed and protected. Remaining text menus in legacy clipboard/maintenance settings are bounded in the checker and cannot be copied into new screens.
