# Roadmap / ideas

Comment on (or open) an issue first so we don't duplicate work.

## Good first issues
- [ ] Add screenshots / a short screen recording to the README
- [ ] Rename the script to `Repair-Windows.ps1` (keep a shim for the old name) and update the launchers
- [ ] Add a `-WhatIf` switch that lists what would be changed without doing it
- [ ] Write the results to a timestamped log file the user can attach to a ticket

## Features
- [ ] Split into a module with one function per repair step
- [ ] Windows 11 specific fixes (Widgets, Copilot policies, Start menu)
- [ ] Export the before/after metrics as an HTML report
- [ ] Pester tests for the individual steps
- [ ] Publish to the PowerShell Gallery / winget
