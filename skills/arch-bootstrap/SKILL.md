---
name: arch-bootstrap
description: "Bootstrap or verify a repository's AI architecture and workflow files (ai_architecture_map.yaml, interactive MAP.html, CHANGELOG.md, AI_WORKFLOW.md, CLAUDE.md, AGENTS.md) for any tech stack. Runs a 4-stage interactive state machine with token-saving gates. Use when the user invokes /arch-bootstrap or asks to make a repo AI-ready, set up an architecture map, or bootstrap the AI workflow docs."
version: 1.0.0
---

# arch-bootstrap

A stack-agnostic, 4-stage state machine that bootstraps or verifies a repository's AI architecture and workflow files. Run the stages in order. Two stages end at a **WAIT** gate: end the turn there and do nothing more until the user answers.

All paths are relative to the repo root (`git rev-parse --show-toplevel`, else the cwd).

## Target files

| File | Created in | Role |
|---|---|---|
| `docs/architecture/ai_architecture_map.yaml` | Stage 1 | LLM index: the source of truth for agents |
| `docs/architecture/MAP.html` | Stage 1 | Full-screen interactive Mermaid viewer for humans |
| `docs/architecture/CHANGELOG.md` | Stage 2 | Append-only, 3-line micro-doc log |
| `docs/AI_WORKFLOW.md` | Stage 2 (amended in Stage 4) | Human guide to the workflow |
| `CLAUDE.md`, `AGENTS.md` | Stage 4 | Agent rules (Claude Code, OpenCode, Cursor, Codex) |

## Global rules (every stage)

- **Token economy.** Never read the whole codebase. Start from `git ls-files` (or a depth-limited tree), the manifests, and `rg` hits. Read only the files that turn out to be entry points or hold invariants, and read the relevant ranges, not whole files, when a file is large. Skip vendored, generated and lock files (`node_modules`, `vendor`, `dist`, `build`, `*.lock`, minified assets, migrations dumps, bundled third-party libraries).
- **Never destroy history.** If a target file exists, read it and merge into it. Never truncate `CHANGELOG.md`; only append. In an existing `CLAUDE.md` or `AGENTS.md`, keep the user's content and add or replace only a clearly delimited section (see Stage 4).
- **Cite evidence.** Every entry point, invariant and hidden hook in the YAML carries a `path:line` reference that you verified. Mark anything inferred but not read as `confidence: inferred`.
- **Report faithfully.** End with a short list of files created or updated, and any gaps you could not trace.

---

## Stage 1: Architecture map verification (token-saving gate)

Check for both files:

```bash
test -f docs/architecture/ai_architecture_map.yaml && echo YAML_OK
test -f docs/architecture/MAP.html && echo HTML_OK
```

### 1A. Both exist: gate, no scanning

Do not scan the codebase. Ask exactly this, then **WAIT**:

> The architectural map files (`ai_architecture_map.yaml` and `MAP.html`) already exist. Are you confident they cover the current codebase (skip scan to save tokens), or would you like me to run a delta scan to verify accuracy and fill any gaps?

- **Skip:** go straight to Stage 2.
- **Delta scan:**
  1. Read the YAML. Note its `commit:` field, if any, and the files it cites.
  2. Find what changed since then: `git diff --stat <commit>..HEAD` if the commit is known, otherwise `git log --since=<generated date> --name-only`. If neither is available, compare `git ls-files` against the files the YAML cites.
  3. Re-verify only the changed or unmapped areas, using the scan recipe in 1B, scoped to them.
  4. Patch the YAML in place: fix stale `path:line` references, add new domains, and record removals under `known_gaps` or delete them. Update `commit:` and `generated:`.
  5. Patch the Mermaid source in `MAP.html` to match. Keep the viewer shell unchanged.
  6. Go to Stage 2.

### 1B. One or both missing: detect, scan, generate

If only one file exists, keep it and regenerate the other from it plus whatever scanning is needed to fill the gaps. A legacy `docs/architecture/MAP.md` with Mermaid blocks can seed `MAP.html`.

**Step 1: detect the stack.** Check the manifests at the root and one level down:

| Signal | Stack | Where the roots usually live |
|---|---|---|
| `hooks.py` + `modules.txt` | Frappe/ERPNext | `hooks.py` (doc_events, scheduler_events, override_*), `@frappe.whitelist`, `frappe.enqueue` |
| `package.json` with `next` | Next.js | `app/**/page.*`, `app/**/route.*`, `pages/api/**`, `middleware.*`, server actions (`"use server"`) |
| `package.json` (other) | Node | `main`/`bin`/`scripts`, express/fastify/nest routers, event emitters |
| `pyproject.toml` / `setup.py` / `requirements.txt` | Python | `__main__`, CLI entry points, Django `urls.py`/signals, FastAPI/Flask routes, Celery tasks |
| `go.mod` | Go | `cmd/*/main.go`, `http.HandleFunc`/router setup, goroutines, `sync.Mutex` |
| `Cargo.toml` | Rust | `src/main.rs`, `src/bin/*`, `#[tokio::main]`, axum/actix routes |
| `CMakeLists.txt` / `Makefile` / `meson.build` | C/C++ | `main(`, signal handlers, `fork`/`pthread`, explicit source lists |
| `pom.xml` / `build.gradle*` | JVM | `@SpringBootApplication`, `@RestController`, `@Scheduled`, `@Transactional` |
| `Gemfile` + `config/routes.rb` | Rails | routes, controllers, callbacks, jobs |
| `composer.json` | PHP | routes, controllers, event listeners, middleware |

A repo can have several stacks (a monorepo, say). Map each one as its own group of domains.

**Step 2: run the structural scan.** Use `rg -n` with `-g '!<vendored dirs>'`. Run independent searches in parallel. Adapt the patterns to the stack you detected:

1. **Entry points:** process `main`s, CLI commands, HTTP routes and handlers, RPC/whitelisted endpoints, page and route files, cron and scheduler definitions, queue consumers.
2. **Hidden hooks and events:** framework hook registries (`hooks.py`, signals, middleware, interceptors, lifecycle callbacks, ORM `before_*`/`after_*`), event emitters and listeners, pub/sub, webhooks, OS signal handlers, `init()`/static initializers, DI registrations, global mutable state.
3. **Core controllers and services:** the modules the entry points call into. Follow one or two hops, not the whole graph.
4. **Concurrency and locks:** `FOR UPDATE`, `with_for_update`, `select_for_update`, advisory locks, mutexes, `synchronized`, transactions, idempotency keys, unique constraints, job deduplication, retries, `fork`/threads/goroutines.
5. **Permission guards:** auth decorators and middleware, `has_permission`, role checks, `ignore_permissions`, guest or public endpoints, CSRF exemptions.
6. **Fail-closed and fail-open patterns:** paths that abort on error (`throw`, `raise`, `return err`, early `exit`) as opposed to broad `try/except` or `catch` blocks that swallow errors, especially around money, stock, auth or data writes.
7. **Build and registration lists:** anything that must be edited when a file is added (explicit source lists, route registries, `__init__` exports, plugin manifests).
8. **Docs drift:** claims in the README that the code contradicts.

**Step 3: write `docs/architecture/ai_architecture_map.yaml`.** It must be strict, valid YAML (quote strings containing `:`, `#`, `{` or `|`). Use this schema and add stack-specific keys if useful:

```yaml
schema_version: 1
generated: "YYYY-MM-DD"
commit: <short sha>
project: {name, stacks: [...], build, tests, registration_rules: [...]}
entry_points:
  - {id, symbol, location: "path:line", kind, does}
global_state:            # shared mutable state, singletons, globals, caches
  - {name, location, writers: [...], readers: [...], blast_radius}
domains:
  - id: <kebab-id>
    trace_depth: deep | entry_only     # deep only if the functions were actually read
    entry_points: ["symbol path:line"]
    core_logic_files: [...]
    hidden_hooks_or_events: ["what -> where (path:line)"]
    critical_invariants: ["fail-closed / lock / idempotency / permission / ordering rule"]
    blast_radius: low | medium | high | critical
    blast_notes: "what else breaks if this changes"
hidden_dependencies:     # cross-cutting couplings not visible from the call graph
  - {id, what, why_it_matters}
critical_invariants:     # consolidated, grouped: fail_closed, locks_concurrency, permissions, idempotency, ordering
known_gaps: [...]        # bugs, dead code, doc drift found during the scan
change_playbook:         # "to add X, touch A, B, C" with blast radius
  - {change, touch: [...], blast_radius}
```

Validate it: `python3 -I -c "import yaml,sys; yaml.safe_load(open(sys.argv[1]))" docs/architecture/ai_architecture_map.yaml`. If PyYAML is missing, try `ruby -ryaml -e 'YAML.load_file(ARGV[0])'`, or check by eye.

**Step 4: write `docs/architecture/MAP.html`** from the template below. Replace `{{PROJECT}}` and `{{MERMAID}}`.

Diagram rules:
- One `flowchart TD`, grouped into one `subgraph` per module or domain. Show the data and control flow between them, mark shared state as cylinders `[("...")]`, and draw hidden hooks as dotted edges `-.->`.
- Add `classDef` styles for fail-closed paths (red), hazards and known gaps (amber), shared state (blue) and dead code (grey dashed).
- Quote every label: `A["label"]`. Inside labels, write `<`, `>`, `&` and `|` as `#lt;`, `#gt;`, `#amp;` and `#124;`. Then HTML-escape the whole Mermaid source (`&` → `&amp;`, `<` → `&lt;`, `>` → `&gt;`) before you put it into `<pre>`, because the browser decodes it back.
- Keep the diagram under about 150 nodes. If it would be larger, keep module-level boxes in the main graph and drop function-level detail (that belongs in the YAML).

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{{PROJECT}} Architecture</title>
<style>
  :root { --bg:#ffffff; --fg:#1f2328; --panel:#f6f8fa; --border:#d0d7de; }
  @media (prefers-color-scheme: dark) { :root { --bg:#0d1117; --fg:#e6edf3; --panel:#161b22; --border:#30363d; } }
  html, body { margin:0; padding:0; width:100vw; height:100vh; overflow:hidden; background:var(--bg); color:var(--fg);
               font:14px/1.4 system-ui, -apple-system, "Segoe UI", sans-serif; }
  #stage { position:fixed; inset:0; width:100vw; height:100vh; }
  #stage pre.mermaid { margin:0; width:100%; height:100%; display:flex; align-items:center; justify-content:center; }
  #stage svg { width:100% !important; height:100% !important; max-width:none !important; }
  #title { position:fixed; top:12px; left:16px; z-index:10; padding:6px 10px; border-radius:6px;
           background:var(--panel); border:1px solid var(--border); font-weight:600; }
  #controls { position:fixed; right:16px; bottom:16px; z-index:10; display:flex; gap:6px; }
  #controls button { min-width:40px; height:36px; padding:0 12px; border-radius:6px; cursor:pointer;
                     background:var(--panel); color:var(--fg); border:1px solid var(--border); font-size:16px; }
  #controls button:hover { border-color:var(--fg); }
  #err { position:fixed; inset:auto 16px 64px 16px; z-index:10; color:#c0392b; white-space:pre-wrap; }
</style>
</head>
<body>
<div id="title">{{PROJECT}} · Architecture</div>
<div id="stage">
<pre class="mermaid">
%%{init: {'flowchart': {'useMaxWidth': false}}}%%
{{MERMAID}}
</pre>
</div>
<div id="controls">
  <button id="zin" title="Zoom in" aria-label="Zoom in">+</button>
  <button id="zout" title="Zoom out" aria-label="Zoom out">−</button>
  <button id="zreset" title="Reset view">Reset</button>
</div>
<div id="err"></div>
<script src="https://cdn.jsdelivr.net/npm/svg-pan-zoom@3.6.1/dist/svg-pan-zoom.min.js"></script>
<script type="module">
  import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11.4.1/dist/mermaid.esm.min.mjs";
  const dark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  mermaid.initialize({ startOnLoad: false, theme: dark ? "dark" : "default",
                       maxTextSize: 500000, maxEdges: 2000, flowchart: { useMaxWidth: false } });
  try {
    await mermaid.run({ querySelector: "pre.mermaid" });
    const svg = document.querySelector("#stage svg");
    svg.removeAttribute("style");
    const pz = svgPanZoom(svg, { zoomEnabled: true, panEnabled: true, controlIconsEnabled: false,
                                 mouseWheelZoomEnabled: true, dblClickZoomEnabled: true,
                                 fit: true, center: true, minZoom: 0.05, maxZoom: 40, zoomScaleSensitivity: 0.3 });
    document.getElementById("zin").onclick = () => pz.zoomIn();
    document.getElementById("zout").onclick = () => pz.zoomOut();
    document.getElementById("zreset").onclick = () => { pz.resetZoom(); pz.fit(); pz.center(); };
    window.addEventListener("resize", () => { pz.resize(); pz.fit(); pz.center(); });
  } catch (e) {
    document.getElementById("err").textContent = "Mermaid render failed: " + e.message;
  }
</script>
</body>
</html>
```

Validate the Mermaid if a renderer is available, for example `npx -y @mermaid-js/mermaid-cli@11.4.2 -i <extracted.mmd> -o /tmp/out.svg`. Run it in a scratch directory, not the repo. If you can't validate, say so in the final report.

Go straight to Stage 2. There is no gate here.

---

## Stage 2: Bootstrap documentation and changelog

Create these files, or verify them if they exist. Never overwrite history.

**`docs/architecture/CHANGELOG.md`**
- If the file is missing, write a short header saying the AI workflow maintains it, the fixed entry format below, and a seed entry under today's date (`## YYYY-MM-DD`) recording the architecture bootstrap.
- If it exists, keep everything and append the seed entry at the bottom. Add it only if the map was created or changed in this run, and only if an equivalent entry for today isn't already there.

```
- **Feature/File modified:** [File path]
- **What changed:** [Brief technical description of logic added/altered]
- **Hooks/Dependencies updated:** [Hooks, events, locks, registrations, or shared state touched]
```

**`docs/AI_WORKFLOW.md`**: a concise guide for developers. Keep it under about 80 lines. Cover:
- what each file is for: the YAML is the agents' source of truth, `MAP.html` is the visual map for humans (open it in a browser, scroll to zoom, drag to pan), and `CHANGELOG.md` is the record of AI changes
- the agent's loop: read the YAML entry → check blast radius and invariants → change the code → append to the changelog → update the YAML and `MAP.html` when new roots or domains appear
- what developers should do: keep the YAML current when they change architecture by hand, and give agents evidence for bugs
- the project's top invariants, pulled from the YAML (three to six bullets, in plain language)

If it exists, update it in place and keep any human-written sections.

---

## Stage 3: Triage router decision (interactive gate)

Ask exactly this, then **WAIT**:

> Would you like to enable the strict Triage Router (`@feature`, `@bug`, `@qa`, `@audit`) for this project, or do you prefer Direct Mode (relying only on the architecture map and automatic `CHANGELOG.md` updates without tags)?

Do not run Stage 4 until the user answers.

---

## Stage 4: Generate `CLAUDE.md` and `AGENTS.md`

Write the same rules into both files. If either file already exists, keep its other content and put the generated rules between these markers. On a re-run, replace the text between existing markers instead of adding a second copy.

```
<!-- arch-bootstrap:start -->
...generated rules...
<!-- arch-bootstrap:end -->
```

Fill in project-specific invariants from the YAML's `critical_invariants`, as concrete rules for this stack. Don't use generic placeholders. Keep the generated section under about 60 lines.

### If the user chose Direct Mode

Include only these:

1. **Context loading (mandatory):** before editing code, read `docs/architecture/ai_architecture_map.yaml`, find the domain being touched, and check its `blast_radius`, `hidden_hooks_or_events` and `critical_invariants`. Trust the map over memory, but confirm a named file or function exists before editing it. If the area is unmapped or marked `trace_depth: entry_only`, trace it with `rg` and update the YAML first.
2. **Project invariants:** the concrete rules from the YAML (fail-closed paths, locks, idempotency, permission guards, ordering, registration lists). Never weaken a fail-closed path, remove a lock, bypass a permission check, or break idempotency.
3. **Micro-doc rule (mandatory):** after any verified code change, append the 3-line entry to `docs/architecture/CHANGELOG.md` under today's date heading.

### If the user chose the Triage Router

Include everything in Direct Mode, plus these:

4. **Map upkeep:** when a change adds a new root (entry point, route, hook, cron, consumer) or a new domain or data flow, update the YAML and the Mermaid in `docs/architecture/MAP.html`.
5. **The four pipelines.** Each tag runs only its own state. A fix found in one state is handed to the state that owns it.
   - **@feature:** (1) Read the YAML. (2) If the domain is unmapped or `entry_only`, trace it with `rg` and update the YAML. (3) State the blast radius in one or two sentences, then write code that respects the invariants. Run tests if there are any. (4) Append the 3-line `CHANGELOG.md` entry, and update `MAP.html` if a new root was added.
   - **@bug:** (1) On the first turn, write no code. Ask for the logs, traceback or reproduction steps that are missing, then wait. (2) Check the YAML for blast radius, hidden hooks and known gaps. (3) Apply the narrowest fix that keeps the invariants, and run tests. (4) Append to `CHANGELOG.md`. If the bug showed the YAML was wrong, correct it.
   - **@qa:** Read-only. (1) Write an edge-case checklist for the diff, weighted towards the YAML's invariants and hidden hooks, with test snippets in the repo's existing test style where practical. (2) Wait for human validation. No edits and no changelog entry.
   - **@audit:** Read-only and report-only. (1) Scan for technical debt, hooks or handlers nothing references, missing locks or idempotency, fail-open wrappers, permission gaps, and drift between the YAML and the code. (2) Output a prioritised markdown report with severity, `path:line`, why each item matters, and the owning tag (`@bug` or `@feature`). Mark items already in `known_gaps` as known. Fix nothing, and write no changelog entry.
   - A prompt without a tag gets normal judgment. If it clearly fits one state, say in one line which state you are assuming, then follow it.

Then update `docs/AI_WORKFLOW.md`: add a short section for each tag with one example prompt, and this quick-reference table:

| Tag | Edits code | Waits for you | Writes CHANGELOG |
|---|---|---|---|
| `@feature` | yes | no | yes |
| `@bug` | yes, after evidence | yes, first turn | yes |
| `@qa` | no | yes, at end | no |
| `@audit` | no | no | no |

### Finish

Report the files created and the files updated, the mode chosen, any validation you could not run, and the top three or four `known_gaps` found. Do not commit unless the user asks.
