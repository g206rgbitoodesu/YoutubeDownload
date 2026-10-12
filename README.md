# YoutubeDownload — Technical Demo

 This project is a "Technical Demo."
This is a proof-of-concept and learning repository designed to build an automated pipeline by integrating multiple open-source tools (yt-dlp / ffmpeg / MusicBrainz Picard / Navidrome) using PowerShell and Python.
Please be sure to read the Disclaimer at the bottom for details.
Demo Highlights:
•  Tool Integration: Unifies yt-dlp, ffmpeg, Picard, and Navidrome via PowerShell.

•  Automated Pipeline: Executes a 9-step workflow with a single command.

•  Web UI: Features a Flask-powered request form accessible from mobile devices.

•  Error Handling: Implements client rotation, retries, and data integrity checks.

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B-blue.svg)](https://docs.microsoft.com/powershell/)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-lightgrey.svg)]()
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

---

##  Table of Contents

1. [Overview](#1-overview)
2. [Requirements](#2-requirements)
3. [Quick Start](#3-quick-start)
4. [Manual Setup](#4-manual-setup)
5. [Usage](#5-usage)
6. [Directory Layout](#6-directory-layout)
7. [Script Reference](#7-script-reference)
8. [Script Details](#8-script-details)
9. [Workflow Examples](#9-workflow-examples)
10. [Troubleshooting](#10-troubleshooting)
11. [Known Limitations](#11-known-limitations)
12. [License](#12-license)

v2 New Features: Batch input (simultaneous support for multiple songs and playlist URLs) and real-time progress display are now supported.
A Web UI to request songs and playlists in bulk from a smartphone browser, which automatically executes downloading → tagging → Navidrome deployment on a PC.

---

## 1. Overview

### High-Level Flow

```
songlist.csv / playlist.txt
    │
    ▼
[1] download_pc.ps1 / download_playlist.ps1   ← yt-dlp download
    │
    ▼
music_download/                                ← staging directory
    │
    ▼
[2] verify_downloads.ps1                       ← ffprobe integrity check
    │  if NG
    ▼
[3] redownload_failed.ps1                      ← re-download failed items
    │
    ▼
[4] run_picard.ps1                             ← Picard tagging & moving
    │
    ▼
[5] clean_music_download.ps1                   ← clean up remaining filenames
    │
    ▼
[6] run_picard.ps1 (again)                     ← re-match cleaned filenames
    │
    ▼
[7] move_leftovers.ps1                         ← move leftovers to Navidrome
    │
    ▼
Navidrome music folder → Quick scan
```

---

## 2. Requirements

### Required Tools

| Tool | Purpose | Source |
|---|---|---|
| **yt-dlp** | YouTube download | https://github.com/yt-dlp/yt-dlp |
| **ffmpeg / ffprobe** | Audio conversion & integrity check | https://ffmpeg.org/ |
| **MusicBrainz Picard** | Tagging | https://picard.musicbrainz.org/ |
| **Chromaprint (fpcalc)** | Audio fingerprinting | https://acoustid.org/chromaprint |
| **AcoustID API Key** | Picard fingerprint authentication | https://acoustid.org/new-application |

### Recommended Environment

- Windows 10 / 11
- PowerShell 5.1 or later (bundled with Windows)
- Navidrome server (assumed already running)

---

## 3. Quick Start

### 3-1. Place the Repository

Clone or extract the repository into any folder. Example:

```
C:\Users\<username>\Documents\YoutubeDownload
```

### 3-2. Double-Click `setup.bat`

**This is all you need.** The script will automatically:

1. Detect `yt-dlp` / `ffmpeg` / `ffprobe` / `fpcalc` / Picard.
2. Search common locations for tools that are not on PATH.
3. Persistently add found directories to your **user PATH** (no admin required).
4. Suggest `winget install` commands for any missing tools.
5. Run `diagnose.ps1` for a final environment check.

### 3-3. Restart PowerShell

Close and reopen PowerShell so the new PATH takes effect.

### 3-4. Run the Pipeline

```powershell
cd C:\Users\<username>\Documents\YoutubeDownload
.\run_all.ps1
```

When finished, open the Navidrome admin UI and run **Quick scan**.

---

## 4. Manual Setup

For environments where `setup.bat` cannot be used. Intended for advanced users.

### 4-1. Create the Working Directory

```powershell
mkdir C:\Users\<username>\Documents\YoutubeDownload
cd C:\Users\<username>\Documents\YoutubeDownload
```

### 4-2. Place the Scripts

Copy all files from this repository into the folder above.

### 4-3. Diagnose the Environment

```powershell
.\diagnose.ps1
```

Ensure every line shows `[OK]`. If any show `[NG]`, install the corresponding tool.

### 4-4. Fix `fpcalc` PATH (If Needed)

```powershell
.\fix_fpcalc.ps1 -DryRun    # preview
.\fix_fpcalc.ps1            # apply (persistent PATH update)
```

Restart PowerShell for the change to take effect.

### 4-5. Picard GUI Configuration (Manual)

Launch Picard and configure the following:

1. **Options → File Naming**
   - Enable "Move files to a folder structure based on tags".
   - Set the destination to your Navidrome music folder.
2. **Options → Fingerprinting**
   - Set `fpcalc location` to the full path of `fpcalc.exe`.
   - Enter your AcoustID API key.
3. Save the settings and close Picard.

---

## 5. Usage

### 5-1. Prepare Input Files

**songlist.csv** (CSV mode)

```csv
Artist,Title,URL
Queen,Bohemian Rhapsody,https://youtu.be/fJ9rUzIMcZQ
Sakanaction,Shin Takarajima,
```

- Leave the URL empty to let `ytsearch1:Artist Title` auto-search.
- Titles containing commas must be wrapped in `"..."`.

**playlist.txt** (Playlist mode)

```
https://www.youtube.com/playlist?list=XXXXXXXX
```

- One URL per line.
- Lines starting with `#` are treated as comments.

### 5-2. Run the Full Pipeline (Recommended)

```powershell
.\run_all.ps1
```

### 5-3. Common Options

```powershell
# Dry run (show plan only, no writes)
.\run_all.ps1 -DryRun

# Resume from step 6 (e.g., already downloaded)
.\run_all.ps1 -StartFrom 6

# Skip specific steps
.\run_all.ps1 -SkipSteps 3,4

# Run without confirmation prompts
.\run_all.ps1 -NoPause

# Playlist mode
.\run_all.ps1 -Source playlist
```

---

## 6. Directory Layout

```
YoutubeDownload/
├── setup.bat                    # ★ Initial setup (double-click)
├── setup_env.ps1                #   Environment discovery & PATH update
├── check_syntax.ps1             #   Syntax check for all .ps1 files
├── sanitize_for_release.ps1     #   Strip personal info for release
│
├── run_all.ps1                  # ★ Main pipeline (recommended entry point)
├── pipeline.ps1                 #   Legacy orchestrator
│
├── download_pc.ps1              #   Bulk download from CSV
├── download_playlist.ps1        #   Bulk download from playlist URLs
├── verify_downloads.ps1         #   Integrity check
├── redownload_failed.ps1        #   Re-download NG items
├── run_picard.ps1               #   Launch Picard
├── clean_music_download.ps1     #   Filename cleanup
├── move_leftovers.ps1           #   Move leftovers to Navidrome
├── dedup_music.ps1              #   Duplicate consolidation
├── enrich_tags.ps1              #   Fill NA tags from CSV
├── clean_songlist.ps1           #   CSV normalization
├── make_todo.ps1                #   Extract not-yet-downloaded items
├── diagnose.ps1                 #   Environment diagnostics
├── fix_fpcalc.ps1               #   fpcalc-specific PATH setup
│
├── picard_commands.txt          #   Picard command script
├── songlist.csv                 #   Input data
├── playlist.txt                 #   Input data (playlists)
│
├── music_download/              #   Staging directory (auto-created)
├── downloaded.txt               #   Download archive (auto-created)
├── downloaded_playlist.txt      #   Playlist download archive
├── success.log / failed.log     #   CSV logs
├── success_playlist.log / failed_playlist.log
├── verify_ok.txt / verify_ng.txt
├── duplicates_backup/           #   Duplicate quarantine
│
├── _sanitize_backup/            #   Auto-backup from sanitize script
├── backup/                      #   clean_songlist backup
│
├── README.md                    #   This file (English)
├── README.ja.md                 #   Japanese version
├── LICENSE
└── .gitignore
```

---

## 7. Script Reference

### Setup Scripts

| File | Purpose |
|---|---|
| `setup.bat` | **Initial setup (double-click)** |
| `setup_env.ps1` | Auto-discover tools and update PATH |
| `diagnose.ps1` | Environment diagnostics |
| `fix_fpcalc.ps1` | fpcalc-specific PATH setup |
| `check_syntax.ps1` | Syntax check for all .ps1 files |
| `sanitize_for_release.ps1` | Strip personal info for public release |

### Pipeline Scripts

| File | Purpose |
|---|---|
| `run_all.ps1` | **Main pipeline (recommended)** |
| `pipeline.ps1` | Legacy orchestrator (deprecated) |
| `clean_songlist.ps1` | CSV normalization (dedupe, quote) |
| `make_todo.ps1` | Extract not-yet-downloaded items |
| `download_pc.ps1` | Bulk download from CSV |
| `download_playlist.ps1` | Bulk download from playlist URLs |
| `verify_downloads.ps1` | Integrity check (ffprobe) |
| `redownload_failed.ps1` | Re-download NG items |
| `run_picard.ps1` | Launch Picard |
| `clean_music_download.ps1` | Filename cleanup |
| `move_leftovers.ps1` | Move leftovers to Navidrome |
| `dedup_music.ps1` | Duplicate consolidation |
| `enrich_tags.ps1` | Fill NA tags from CSV |

### Input Files

| File | Description |
|---|---|
| `songlist.csv` | CSV with `Artist,Title,URL` |
| `playlist.txt` | Playlist URLs (one per line, `#` for comments) |

---

## 8. Script Details

### 8-1. `setup.bat` / `setup_env.ps1`

Initial environment setup. Just double-click `setup.bat`.

- Discovers 5 tools in three stages (PATH → fixed path → recursive search across 14 roots)
- Persistently adds found directories to the **user PATH** (no admin required)
- For missing tools, prints download URLs and `winget install` commands
- Runs `diagnose.ps1` at the end for a final check

Options for `setup_env.ps1`:

| Parameter | Description |
|---|---|
| `-DryRun` | Preview only; do not modify PATH |
| `-AutoInstall` | Skip the confirmation and run `winget install` automatically |
| `-SkipDiagnose` | Do not invoke `diagnose.ps1` at the end |

### 8-2. `run_all.ps1` (Main Pipeline, Recommended)

Runs all 9 steps in sequence.

```powershell
.\run_all.ps1                   # CSV mode
.\run_all.ps1 -Source playlist  # Playlist mode
.\run_all.ps1 -DryRun           # Plan only
.\run_all.ps1 -StartFrom 6      # Start from step 6
.\run_all.ps1 -SkipSteps 3,4    # Skip steps 3 and 4
.\run_all.ps1 -NoPause          # Non-interactive
```

**Step list:**

| # | Script | Purpose |
|---|---|---|
| 1 | clean_songlist | Normalize CSV |
| 2 | make_todo | Extract not-yet-downloaded |
| 3 | download_pc | Download |
| 4 | verify_downloads | Integrity check |
| 5 | redownload_failed | Re-download NG items (only if any) |
| 6 | run_picard | Picard tagging |
| 7 | clean_music_download | Filename cleanup |
| 8 | run_picard (again) | Re-match cleaned filenames |
| 9 | move_leftovers | Move leftovers to Navidrome |

### 8-3. `clean_songlist.ps1`

Removes duplicates and normalizes quoting in the CSV.

```powershell
.\clean_songlist.ps1            # preview
.\clean_songlist.ps1 -InPlace   # overwrite (auto-backup)
```

| Parameter | Default | Description |
|---|---|---|
| `-CsvFile` | songlist.csv | Input |
| `-OutFile` | songlist_clean.csv | Output |
| `-BackupDir` | backup | Backup destination |
| `-InPlace` | off | Overwrite the original |

### 8-4. `make_todo.ps1`

Extracts only the items that have not been downloaded yet.

```powershell
.\make_todo.ps1
.\make_todo.ps1 -ShowDone   # show already-downloaded items too
```

| Parameter | Default |
|---|---|
| `-CsvFile` | songlist.csv |
| `-DoneLogs` | @("success.log") |
| `-ScanFolders` | music_download, Navidrome |
| `-OutFile` | songlist_todo.csv |
| `-TitleOnly` | off |
| `-ShowDone` | off |

### 8-5. `download_pc.ps1`

Bulk download from CSV.

```powershell
.\download_pc.ps1                  # normal
.\download_pc.ps1 -StartIndex 88   # resume from row 88
.\download_pc.ps1 -Force           # force re-download
.\download_pc.ps1 -SkipPicard      # skip Picard integration
```

| Parameter | Default | Description |
|---|---|---|
| `-CsvFile` | songlist.csv | Input |
| `-OutputDir` | music_download | Output |
| `-ArchiveFile` | downloaded.txt | Archive |
| `-SleepTime` | 5 | Sleep between tracks (sec) |
| `-MaxRetries` | 2 | Retries per client |
| `-StartIndex` | 1 | Start row |
| `-Force` | off | Ignore archive |
| `-SkipPicard` | off | Skip Picard integration |

### 8-6. `download_playlist.ps1`

Bulk download of playlists.

```powershell
.\download_playlist.ps1
.\download_playlist.ps1 -StartIndex 2
```

| Parameter | Default |
|---|---|
| `-PlaylistFile` | playlist.txt |
| `-OutputDir` | music_download |
| `-ArchiveFile` | downloaded_playlist.txt |
| `-SleepTime` | 5 |
| `-MaxRetries` | 2 |

### 8-7. `verify_downloads.ps1`

Integrity check via ffprobe.

```powershell
.\verify_downloads.ps1
.\verify_downloads.ps1 -MinDuration 60 -MinBitrate 128   # stricter
```

| Parameter | Default |
|---|---|
| `-TargetDir` | music_download |
| `-MinDuration` | 30 seconds |
| `-MinBitrate` | 64 kbps |
| `-MinSizeKB` | 100 KB |

**Exit codes**: `0` = all OK / `10` = NG found / `1` = error

### 8-8. `redownload_failed.ps1`

Re-downloads NG items (thin wrapper around `download_pc.ps1 -Force`).

```powershell
.\redownload_failed.ps1
```

| Parameter | Default |
|---|---|
| `-NgFile` | verify_ng.txt |
| `-NgCsv` | songlist_ng.csv |

### 8-9. `run_picard.ps1`

Launches Picard and runs `picard_commands.txt`.

```powershell
.\run_picard.ps1
```

- Detects Picard already running (exits with code 2).

### 8-10. `clean_music_download.ps1`

Removes decorations from filenames.

```powershell
.\clean_music_download.ps1 -DryRun   # preview
.\clean_music_download.ps1           # apply
```

Example:

```
Queen - Queen - A Kind of Magic (Official Video Remastered).mp3
   -> Queen - A Kind of Magic.mp3
```

### 8-11. `move_leftovers.ps1`

Moves files that Picard could not match into the Navidrome library, using their tags.

```powershell
.\move_leftovers.ps1 -DryRun   # preview
.\move_leftovers.ps1           # apply
```

| Parameter | Default |
|---|---|
| `-SourceDir` | music_download |
| `-DestDir` | Navidrome music folder |
| `-DryRun` | off |
| `-Force` | off |

### 8-12. `dedup_music.ps1`

Consolidates duplicate files (with `(1)`, `(2)` suffixes) in the Navidrome folder.

```powershell
.\dedup_music.ps1 -DryRun   # preview
.\dedup_music.ps1           # apply (type y to confirm)
.\dedup_music.ps1 -Force    # no prompt
```

Quarantine folder: `duplicates_backup/`

### 8-13. `enrich_tags.ps1`

Fills in `NA` values for `artist` / `title` using `songlist.csv`.

```powershell
.\enrich_tags.ps1 -DryRun   # preview
.\enrich_tags.ps1           # apply
```

### 8-14. `diagnose.ps1`

Environment diagnostics across 7 sections.

```powershell
.\diagnose.ps1
```

Checks:

- Required tools (yt-dlp, ffmpeg, ffprobe, fpcalc, python)
- fpcalc execution test
- Picard presence and running process
- Picard configuration (`fpcalc_path`, `acoustid_api_key`)
- Broken file detection via ffprobe
- Disk free space
- Overall result

### 8-15. `fix_fpcalc.ps1`

Locates `fpcalc` and persistently adds it to PATH.

```powershell
.\fix_fpcalc.ps1 -DryRun   # preview
.\fix_fpcalc.ps1           # apply
```

### 8-16. `check_syntax.ps1`

Runs a syntax check on all `.ps1` files. Backup directories are automatically excluded.

```powershell
.\check_syntax.ps1
```

### 8-17. `sanitize_for_release.ps1`

Removes personal information (username, versioned paths) before publishing.

```powershell
.\sanitize_for_release.ps1 -DryRun   # preview
.\sanitize_for_release.ps1           # apply (auto-backup)
```

---

## 9. Workflow Examples

### Example 1: Add 10 New Tracks

```powershell
# 1. Append entries to songlist.csv

# 2. Run the pipeline
cd C:\Users\<username>\Documents\YoutubeDownload
.\run_all.ps1

# 3. Trigger a Quick scan in Navidrome (browser)
```

### Example 2: Network Dropped Midway → Resume

```powershell
# Resume from row 88
.\download_pc.ps1 -StartIndex 88

# Then continue manually
.\verify_downloads.ps1
.\run_picard.ps1
.\clean_music_download.ps1
.\run_picard.ps1
.\move_leftovers.ps1
```

### Example 3: Download Now, Organize Later

```powershell
.\download_pc.ps1 -SkipPicard
# Later:
.\run_picard.ps1
```

### Example 4: When Duplicates Appear

```powershell
# 1. Preview
.\dedup_music.ps1 -DryRun

# 2. Apply
.\dedup_music.ps1

# 3. Remove the quarantine folder when satisfied
Remove-Item .\duplicates_backup -Recurse -Force
```

---

## 10. Troubleshooting

### ❌ Tools not found / PATH missing

```powershell
.\setup_env.ps1 -DryRun    # explore only
.\setup_env.ps1            # update PATH
# Restart PowerShell
.\diagnose.ps1             # re-check
```

### ❌ `fpcalc` not found

```powershell
.\diagnose.ps1
.\fix_fpcalc.ps1
# Restart PowerShell
.\diagnose.ps1
```

### ❌ Picard says `Unknown command: LOOKUP_CLUSTERED`

Change `LOOKUP_CLUSTERED` to `LOOKUP` in `picard_commands.txt`.

### ❌ Picard will not launch (already running)

```powershell
Get-Process picard | Stop-Process -Force
.\run_picard.ps1
```

### ❌ Tags become `artist=NA`

Check the `--parse-metadata` argument in `download_pc.ps1`.

```powershell
# ❌ Wrong
--parse-metadata "Queen:%(meta_artist)s"

# ✅ Correct
--parse-metadata "%(artist,uploader,channel,creator)s:%(meta_artist)s"
```

### ❌ The header row is being processed

Verify that `$RawLines = @(...)` is used when reading the CSV.

### ❌ Navidrome does not show new tracks

In the Navidrome admin UI, run **Quick scan**.

### ❌ Files duplicated as `(1)`, `(2)`

```powershell
.\dedup_music.ps1 -DryRun
.\dedup_music.ps1
```

### ❌ Syntax errors

```powershell
.\check_syntax.ps1
```

Backup folders are automatically excluded.

---


---

## 10.5. Web Form (Local Server)

Since v2, you can submit songs from your phone via a local web form — no more typing commands on the PC.

### Quick Start

```powershell
cd C:\Users\<username>\Documents\YoutubeDownload\webapp
python -m pip install -r requirements.txt
.\start.bat
```

Then open `http://<PC-IP>:5000` on your phone (same Wi-Fi network).

### Features

- **Bulk input**: Paste multiple songs or playlist URLs at once
- **Two modes**: Song list (CSV) / Playlist URL
- **Real-time progress**: See download/tagging progress live on your phone
- **Fully automatic**: From submission to Navidrome placement, all handled by `run_all.ps1`

### Architecture

```
[Phone] ──Wi-Fi──→ Flask (port 5000)
                       │
                       ├─ Append to songlist.csv / playlist.txt
                       └─ Launch run_all.ps1 in background
                             │
                             ├─ make_todo.ps1 (skip already-downloaded)
                             ├─ yt-dlp download
                             ├─ Picard tagging
                             └─ Move to Navidrome
```

### Security

- **LAN-only**: Never expose port 5000 to the internet
- **Firewall**: Allow "Private network" only on first launch
- See `webapp/README.md` for details



## 11. Known Limitations

| Item | Notes |
|---|---|
| **Picard destination** | Controlled via GUI settings (not scriptable) |
| **Separate archives** | CSV and playlist archives are managed independently |
| **AcoustID** | Without an API key, FINGERPRINT/SCAN silently fails |
| **Artists containing `:` or `%`** | Requires care with `--parse-metadata` |
| **Music videos in playlists** | Official MVs are hard for Picard to match |
| **`(N)` duplicates** | Happens on repeated downloads → resolve with `dedup_music.ps1` |

---

## 12. License

MIT License. See [LICENSE](LICENSE) for details.

This tool is intended for personal use.
The copyright of downloaded content belongs to its respective owners.
Use at your own risk.

---

---

## ⚠️ Disclaimer

### This project is a **technical demonstration**

This repository is a **technical demonstration** of a PowerShell + Python automation pipeline that combines multiple open-source tools (yt-dlp, ffmpeg, MusicBrainz Picard, Navidrome). It is **NOT** intended to promote, encourage, or facilitate copyright infringement.

### Intended use

The primary intended use is:

- **Downloading your own YouTube videos** (content you have uploaded)
- **Downloading content you have explicit permission to download**
- **Downloading content that is explicitly licensed for free download** (e.g. Creative Commons, public domain)
- **Educational study of the automation techniques** demonstrated here

### Prohibited use

**Do NOT** use this tool to:

- Download copyrighted music or videos without the rights holder's permission
- Circumvent DRM, paywalls, or access restrictions
- Redistribute copyrighted content
- Violate YouTube's Terms of Service or any applicable laws

### Default configuration: self-videos only

To enforce responsible use, the default configuration **only allows downloading videos from your own channel** (see `config.ps1` → `$OwnChannelUrls`). To download from other sources, you must **explicitly opt in** by editing this configuration and confirming that you have the legal right to do so.

### No warranty

This software is provided "as is", without warranty of any kind. The authors are **not responsible** for:

- Any legal consequences arising from misuse
- Any damage to your system, data, or network
- Any content downloaded using this tool
- Any violation of third-party terms of service

### Copyright notice

All content downloaded using this tool remains the property of its respective copyright holders. Users are **solely responsible** for ensuring their use complies with:

- Copyright laws in their jurisdiction
- YouTube's Terms of Service
- MusicBrainz / AcoustID usage policies
- Any other applicable regulations

### Legal basis

Downloading content from YouTube may be restricted in your country. In some jurisdictions, downloading for **personal use** may be permitted, while in others it is **strictly prohibited**. It is the user's responsibility to know and follow the laws of their own country.

### Reporting

If you believe this repository contains anything that promotes illegal activity, please open an issue and it will be addressed promptly.

### Recommended alternative

For **legal music library building**, consider:

- **Bandcamp** — direct artist support, DRM-free
- **Jamendo** — Creative Commons licensed music
- **Free Music Archive** — curated public domain / CC music
- **Internet Archive** — public domain recordings
- **Purchasing** digital music or physical media

---

## 📜 License

MIT License. See [LICENSE](LICENSE) for details.

**Last updated**: 2026-10-13


