# Automated update workflow (hooke007 + shinchiro + personal config)

## Current branch model
- `upstream`: hooke007 package rebuilt cleanly, then `mpv.exe` and `mpv.com` replaced from shinchiro
- `main`: your personal config layered on top of `upstream`

This model is good and can be automated.

## One-time requirements
- `git`
- `rsync`
- `7z` or `7zz`

## Step A: Rebuild `upstream` from new release archives
1. Download both assets locally:
- `mpv-lazy-*.exe` (hooke007)
- `mpv-x86_64-*.7z` (shinchiro)
2. Run:

```bash
tools/rebuild-upstream-from-archives.sh /path/to/mpv-lazy-XXXX.exe /path/to/mpv-x86_64-YYYY.7z
```

This will:
- extract both archives
- rebuild from hooke as the full base
- replace only `mpv.exe` and `mpv.com` from shinchiro
- sync into repository
- commit on `upstream`

## Step B: Merge upstream into main manually
Run:

```bash
tools/merge-upstream-into-main.sh
```

Behavior:
- merge `upstream` into `main`
- stop on any conflict so you can resolve it manually

## Conflict expectation
- Conflicts are usually manageable, not "too many to automate".
- Most likely conflict area is `portable_config/*`.
- Binary/runtime conflicts are reduced because shinchiro only supplies `mpv.exe` and `mpv.com`.

## Suggested routine per update cycle
1. `git checkout upstream`
2. Rebuild with new archives (`rebuild-upstream-from-archives.sh`)
3. `tools/merge-upstream-into-main.sh`
4. Quick runtime test on `main` (`mpv.exe --version`, open a sample video)
