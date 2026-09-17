# Portable Onboarding

Barista onboarding is split into two layers:

1. **Portable defaults** checked on every machine
2. **Machine-local metadata** for personal or company-specific tools

This keeps a work laptop clone generic while still supporting custom launchers
on a personal Mac.

## First-run commands

Work Mac (generic):

```bash
./scripts/bootstrap_machine.sh \
  --profile work \
  --install-dependencies \
  --launch-agent \
  --reload
```

Personal Mac with workflow packs:

```bash
./scripts/bootstrap_machine.sh \
  --profile personal \
  --enable-pack personal \
  --install-dependencies \
  --launch-agent \
  --reload
```

Or enable packs later:

```bash
./scripts/enable_extension_pack.sh --pack personal
# optional company/safe examples:
./scripts/enable_extension_pack.sh --pack work
```

Verify:

```bash
./scripts/barista-doctor.sh --onboard --report
```

## Metadata surfaces

| File | Tracked? | Purpose |
| --- | --- | --- |
| `data/onboard.defaults.json` | yes | Portable first-run checks and pack catalog |
| `data/onboard.local.json` | no | Machine-only expected tools / workflow groups |
| `data/onboard.local.example.json` | yes | Example personal overlay |
| `data/machine.local.json` | no | Profile variant, menu packs, capabilities |
| `data/interface_extensions.local.json` | no | Actual menu/workflow rows for this Mac |

Rules:

- Shared behavior lives in git.
- Host-specific tools, paths, and packs write only to ignored `*.local.json` files.
- `--enable-pack personal` is blocked on `work` / `restricted-work` unless `--force` is explicit.

## Customizing a machine

Copy the example overlay only where those tools exist:

```bash
cp data/onboard.local.example.json data/onboard.local.json
```

Then edit `expected_tools` and `expected_workflow_groups`. Candidate paths may use:

- `%CONFIG%` / `${CONFIG_DIR}`
- `%CODE%` / `${CODE_DIR}`
- `%HOME%` / `${HOME}`

Work Macs should leave `onboard.local.json` absent so doctor stays portable.

## What `--onboard` checks

Portable:

- shared workflow runner (`scripts/open_local_workflow.sh`)
- `shortcut_mode` source presence
- generated shortcut health when available
- machine profile / menu packs
- enabled packs have a local extensions file

Local-only (from `onboard.local.json`):

- expected commands/paths
- expected Apple-menu workflow groups

Use `--offline` in CI or fixtures to skip live process and LaunchAgent checks.
