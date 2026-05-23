# grndctrl-delta

> Ground support packages, tools, and modules for [GroundControl](https://github.com/your-org/groundcontrol) agents.

Like the ramp crews that make every flight possible, `grndctrl-delta` is the supply side of GroundControl — the packages your agents load before they can do their work.

---

## Structure

```
grndctrl-delta/
  catalog.json              ← browsable index, fetched by GroundControl on demand
  packages/
    <package_id>/
      package.json          ← manifest: actions, config schema, dependencies
      <script>.ps1 / .py    ← one script, N dispatchable actions
  modules/
    gc_logging.ps1          ← shared module dot-sourced by packages, never a direct tool
    gc_auth.ps1             ← (planned) shared Azure auth helpers
```

---

## Concepts

### Package
The unit of installation. One folder, one manifest, one or more scripts. A package exposes one or more **actions** — each action becomes a callable tool in GroundControl.

### Action
The unit the LLM reasons about. Maps 1:1 to a GroundControl tool entry. Multiple actions share the same script via an `-Action` dispatch parameter.

### Module
Shared plumbing (auth, logging, config helpers). Dot-sourced inside scripts. Never exposed as a callable tool. Installed alongside any package that lists it as a dependency.

### Config
Each package declares the environment variables it needs (`config` in `package.json`). GroundControl surfaces these in the install flow and injects them as `$env:` vars at runtime. Profiles allow multiple named credential sets (e.g. two Azure tenants) per package.

---

## catalog.json

The root index. GroundControl fetches this to power the Catalog browser. Each entry contains enough metadata to display without downloading scripts.

```json
{
  "catalog_version": "1.0",
  "packages": [ ... ],
  "modules": [ ... ]
}
```

---

## package.json

```json
{
  "id": "my_package",
  "name": "My Package",
  "description": "What it does.",
  "version": "1.0.0",
  "type": "powershell",
  "tags": ["category"],
  "scripts": ["my_package.ps1"],
  "dependencies": ["modules/gc_logging.ps1"],
  "config": {
    "MY_API_KEY": { "description": "API key for the service", "secret": true }
  },
  "actions": [
    {
      "name": "do_thing",
      "function": "Invoke-DoThing",
      "description": "Does the thing.",
      "parameters": [
        {
          "name": "input_value",
          "ps_name": "InputValue",
          "type": "string",
          "description": "The value to process.",
          "required": true
        }
      ]
    }
  ]
}
```

---

## Writing a package

1. Create `packages/<id>/` folder
2. Write your script with a `-Action` dispatcher and one function per action
3. Dot-source any needed modules via `"$PSScriptRoot\..\..\modules\<module>.ps1"`
4. Write `package.json` — one entry in `actions[]` per callable function
5. Add your entry to `catalog.json`
6. Submit a PR

GroundControl will auto-scaffold the registry entries from `package.json` on install — no manual JSON required.

---

## Script conventions

- Output **JSON on stdout** — `@{ ok=$true; ... } | ConvertTo-Json -Compress`
- Use `Write-GcLog` from `gc_logging.ps1` for all log output
- Accept `-Action` as the first parameter, dispatch with `switch`
- Exit 0 on success, non-zero on failure

---

## Planned modules

| Module | Purpose |
|---|---|
| `gc_logging.ps1` | Structured JSON logging ✅ |
| `gc_auth.ps1` | Azure AD / MSGraph authentication |
| `gc_config.ps1` | Read package config from GroundControl config store |
| `gc_output.ps1` | Standardised result formatting helpers |
