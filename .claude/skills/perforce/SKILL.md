# Perforce Skill

Get help with Perforce (Helix Core) operations including branching, syncing, submitting, resolving conflicts, and shelving.

## Trigger
`/perforce`

## Overview

A concise, practical guide to day‑to‑day Perforce (Helix Core) work: branching, syncing, submitting, resolving conflicts, and shelving/unshelving. Covers both **Streams** and **Classic depots**, with CLI (**p4**) and P4V GUI notes.

---

## Table of Contents
- [Prereqs & Config](#prereqs--config)
- [Glossary](#glossary)
- [Branching Models](#branching-models)
  - [Streams (recommended)](#streams-recommended)
  - [Classic Depots](#classic-depots)
- [Daily Workflow](#daily-workflow)
  - [Get/Sync](#getsync)
  - [Edit & Pending Changelists](#edit--pending-changelists)
  - [Shelve / Unshelve](#shelve--unshelve)
  - [Submit](#submit)
- [Code Review (Swarm)](#code-review-swarm)
- [Merging / Integrating](#merging--integrating)
  - [Streams: Merge Down / Copy Up](#streams-merge-down--copy-up)
  - [Classic: p4 integrate](#classic-p4-integrate)
  - [Cherry‑pick a single change](#cherry-pick-a-single-change)
- [Conflict Resolution](#conflict-resolution)
- [Release Flow Example](#release-flow-example)
- [Troubleshooting & Tips](#troubleshooting--tips)
- [Useful Commands Cheat‑Sheet](#useful-commands-cheat-sheet)

---

## Prereqs & Config

**Environment / p4config**
```bash
# Create a .p4config in your workspace root (auto‑picked up if P4CONFIG set)
P4PORT=perforce:1666
P4USER=your_username
P4CLIENT=your_workspace
P4CHARSET=utf8
# optional single sign‑on or ticket:
# P4TICKETS=~/.p4tickets
```

```bash
# One‑time shell env (e.g., .bashrc / PowerShell profile)
export P4CONFIG=.p4config       # or setx P4CONFIG .p4config  (Windows)
export P4EDITOR=vim             # your editor for specs
```

**Login**
```bash
p4 login
# Enter password or leverage SSO if configured
```

**Create/Update a workspace**
- **Streams**: Use P4V > *New Workspace* > choose a stream. CLI:
  ```bash
  p4 client -S //Depot/Streams/dev -o | p4 client -i
  ```
- **Classic**: Map depot paths in `p4 client -o` View, then `p4 client -i`.

---

## Glossary
- **Depot**: Server‑side storage (e.g., `//Depot/...`).
- **Workspace/Client**: Your local view & mapping.
- **Stream**: A first‑class branch with parent/child relationships and policies.
- **Changelist (CL)**: A set of file revisions (pending or submitted).
- **Shelve**: Store CL files on the server without submitting.
- **Integrate**: Propagate changes across branches/streams.
- **Resolve**: Reconcile content after integrate or concurrent edits.

---

## Branching Models

### Streams (recommended)
Common topology:
```
main ──► release/*
  ▲
  └── dev ──► feature/*
```
- **Policy**: *Merge down* (from parent to child), *Copy up* (from child to parent) is the canonical flow.
- Stream types: `mainline`, `development`, `release`, `virtual`, `task`.

Create a stream (admin):
```bash
p4 stream -t development -P //Depot/Streams/main //Depot/Streams/dev
```

Switch workspace to a stream:
```bash
p4 client -S //Depot/Streams/dev -o | p4 client -i
p4 switch //Depot/Streams/dev       # if 'p4 switch' enabled
```

### Classic Depots
- Layout by convention, e.g.:
  - `//Depot/main/...`
  - `//Depot/rel/1.2/...`
  - `//Depot/users/you/feature/foo/...`
- Integrations managed by `p4 integrate` with explicit source/target paths.

---

## Daily Workflow

### Get/Sync
```bash
p4 sync                # get latest for current workspace view
p4 sync //...@=12345   # sync to changelist number (pin)
p4 sync //Depot/Proj/...@label     # to a label
```
P4V: **Get Latest Revision** or **Time‑lapse/Revision Graph** for specific revs.

### Edit & Pending Changelists
```bash
p4 edit file.cc
p4 add newfile.cc
p4 delete oldfile.cc

p4 opened                # what you have checked out
p4 change -o > cl.txt    # dump CL spec to edit
p4 change -i < cl.txt    # create/edit pending CL (description, jobs, etc.)
```
P4V: Right‑click files → *Check Out*, *Add*, *Delete*; edit CL description in *Pending* tab.

### Shelve / Unshelve
```bash
# Shelve everything in pending CL 123456
p4 shelve -c 123456

# Update shelved files (after more edits)
p4 shelve -r -c 123456

# Unshelve to current workspace/CL
p4 unshelve -s 123456
# Unshelve into a specific pending CL
p4 unshelve -s 123456 -c 888888
```
P4V: Drag‑and‑drop shelved files/CLs, or use *Shelves* tab.

### Submit
```bash
# Submit a pending changelist
p4 submit -c 123456
```
Best practices:
- Clear, actionable description (what/why; mention bug/issue IDs).
- Keep CLs small, logically cohesive.
- Run presubmit checks/tests locally if applicable.
- Ensure file types are correct (`p4 filetype`, `p4 typemap` on server).

---

## Code Review (Swarm)
If Helix **Swarm** is enabled:

```bash
# Create a review from a shelved CL
p4 shelve -c 123456
# Associate with a Swarm review (if configured, triggers auto‑create)
p4 change -o | edit Description:
#   Review: #new
# or use Swarm UI: "Create Review" from shelved changelist
```
Tips:
- Iterate by re‑shelving the same CL (`p4 shelve -r -c 123456`).
- Address comments; Swarm can auto‑update the review.
- When approved/verified, submit the CL linked to the review.

---

## Merging / Integrating

### Streams: Merge Down / Copy Up
- **Merge down** (parent → child), bring stability fixes to dev/feature:
  ```bash
  p4 merge -S //Depot/Streams/dev -r   # -r = reverse direction (from parent)
  p4 resolve -am                       # auto‑merge where possible
  p4 resolve                            # manually resolve remaining
  p4 submit -d "Merge down main → dev"
  ```
- **Copy up** (child → parent), deliver completed work upstream:
  ```bash
  p4 copy -S //Depot/Streams/dev
  p4 resolve -am
  p4 resolve
  p4 submit -d "Copy up dev → main"
  ```
Notes:
- `p4 switch` can move the workspace between streams quickly.
- Stream policies can restrict integrate/copy directions; follow stream rules.

### Classic: p4 integrate
Merge changes from `main` to `dev` (or vice versa):
```bash
# Preview integrations (no files touched)
p4 integrate -n //Depot/main/... //Depot/dev/...

# Integrate actual files
p4 integrate //Depot/main/... //Depot/dev/...

# Resolve merges
p4 resolve -am       # try auto, then manual for conflicts
p4 resolve           # interactive resolver

# Submit the merge CL
p4 submit -d "Merge main → dev"
```

### Cherry‑pick a single change
```bash
# Integrate only files affected by CL 123456 from source → target
p4 integrate //Depot/main/...@=123456 //Depot/rel/1.2/...
p4 resolve -am
p4 resolve
p4 submit -d "Cherry‑pick CL 123456 to rel/1.2"
```

---

## Conflict Resolution

1. **During `p4 resolve`**, you’ll see choices:
   - **`ay` / accept yours**: keep your edited file
   - **`at` / accept theirs**: take source version
   - **`am` / accept merge**: auto‑merge result
   - **`e` / edit**: open merge tool to hand‑edit
2. **Graphical tools**: Configure `P4MERGE` (Perforce Merge) or your preferred tool.
   ```bash
   export P4MERGE="/path/to/merge/tool"
   p4 resolve -t    # launch external merge tool for text files
   ```
3. **Typical patterns**:
   - **Keep local but re‑apply upstream fix**: choose *yours*, then manually bring in relevant hunks.
   - **Binary conflicts**: pick one side or version by version; consider `p4 filetype` (`+l` exclusive lock) for binaries.
4. **Re‑run tests** post‑merge before submit.

---

## Release Flow Example

1. **Cut release stream/branch** from `main`:
   - Streams: create `//Depot/Streams/release/1.2` with parent `main`.
   - Classic: `//Depot/rel/1.2/...` from `//Depot/main/...` (integrate/copy).
2. **Stabilize in release** (hotfixes here). Periodically **merge down** hotfixes to dev/feature.
3. **Only critical fixes** flow into release; new features continue in `dev/feature/*`.
4. **Tag/label** builds:
   ```bash
   p4 label -o REL_1.2.0 | p4 label -i
   p4 labelsync -l REL_1.2.0 //Depot/Streams/release/1.2/...
   ```
5. **After GA**, integrate critical fixes back to `main` (copy up) and optionally forward‑integrate to future releases.

---

## Troubleshooting & Tips

- **Ticket expired / auth errors**: `p4 login -a` (get a new ticket), check time skew.
- **Workspace mapping issues**: `p4 client -o` → verify `View` lines; `p4 where file.cc`.
- **File type wrong** (e.g., `+l` for large binaries / exclusive lock):
  ```bash
  p4 reopen -t binary+l big_asset.fbx
  # Server typemap can enforce types centrally (ask admin).
  ```
- **Clobber/readonly errors**: `p4 clean -n` to preview mismatches; `p4 clean` to fix.
- **Performance**: Limit workspace view; avoid syncing `//...` broadly; prefer labels for reproducible builds.
- **Safety**: Submit small CLs; shelve early/often; integrate frequently to reduce conflicts.
- **Streams gotcha**: Respect stream policies; if blocked, you may need an admin policy change or to use the correct flow (merge down vs copy up).

---

## Useful Commands Cheat‑Sheet

```bash
# Auth & setup
p4 set                         # Windows: view Perforce env
p4 info
p4 login
p4 client -o | p4 client -i
p4 switch //Depot/Streams/dev  # if enabled

# Sync
p4 sync
p4 sync //path/...@label
p4 sync //path/...@=123456

# Work
p4 edit/add/delete file
p4 opened
p4 revert file                 # discard local edit
p4 clean -n                    # preview untracked/modified
p4 clean

# Changelists
p4 change -o | p4 change -i
p4 describe 123456
p4 submit -c 123456

# Shelving
p4 shelve -c 123456
p4 shelve -r -c 123456
p4 unshelve -s 123456 [-c 888888]

# Integrate / Merge
p4 merge -S //Depot/Streams/dev -r   # streams merge down
p4 copy  -S //Depot/Streams/dev      # streams copy up
p4 integrate //main/... //dev/...
p4 integrate //main/...@=123456 //rel/1.2/...
p4 resolve [-am]                     # then interactive
p4 submit -d "message"

# Labels
p4 label -o | p4 label -i
p4 labelsync -l REL_1.2.0 //path/...

# Diagnostics
p4 where file.cc
p4 fstat file.cc
p4 dirs //Depot/*
```

---

**Appendix: P4V Quick Pointers**
- *Get Latest*, *Check Out*, *Resolve* are in context menus.
- *Pending* tab shows your CLs; *Shelves* tab for shelved CLs.
- *Stream Graph* visualizes merge/copy directions and policies.
- *Time‑lapse View* and *Revision Graph* help with history and blame.

> Keep CLs small, integrate early/often, and always test after merges.