# mStorage — Claude Instructions

## Release Workflow

This is the **standard process for every release**. Follow it in full, in order.

### 1. Read QUERY.md first
When a new release is mentioned or triggered, read `QUERY.md` at the root. It contains the target version and the change expectations for that release. This file is updated by the user on the fly.

### 2. Create a feature branch
Never commit release work directly to `main`. Create a branch named exactly:
```
feat/vX.Y.Z
```
where X.Y.Z matches the version in QUERY.md.

### 3. Plan before implementing
Before touching any code, produce a written plan of the changes described in QUERY.md and wait for the user to review it. Only proceed to implementation after the user approves.

### 4. Implement and iterate
Apply the changes. The user will review and give feedback. Go back and forth until the user explicitly says they are satisfied and ready to release.

### 5. Raise a PR
When the user confirms readiness, open a GitHub PR from `feat/vX.Y.Z` → `main`.

### 6. Merge

### 7. Build the Inno Setup installer
After merge, build the Windows installer using the Inno Setup script in the repo.

### 8. Tag and release on GitHub
Create a GitHub release using the tag `vX.Y.Z`. Write release notes following the rules in `.github/RELEASE_TEMPLATE.md`:
- Open with `## What's New`
- Use only `### Features`, `### Fixes`, `### Improvements` sections (omit empty ones)
- Each bullet: `- **Label** — Description` (em dash, no trailing period)
- No version number in body, no installation instructions

---

## Navigation
- `QUERY.md` — per-release version + change expectations (updated by user before each release)
- `.github/RELEASE_TEMPLATE.md` — release note format rules
