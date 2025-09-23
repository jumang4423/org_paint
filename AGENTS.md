# Repository Guidelines

## Project Structure & Module Organization
- `org_paint.pde` drives the GLSL-based canvas, MIDI control, undo/redo, and orchestrates helper classes.
- `AnimatedPen.pde` manages particle-style overlays, while `LineCanvas.pde` stores and animates line segments.
- `paint_final_frag.glsl` holds the fragment shader; keep shader constants in sync with `CANVAS_WIDTH` and brush logic.
- Art assets and animation frames live in `data/` (`kit_frames/`, `smile.png`, etc.); keep new assets optimized for 576px width.
- `munbyn_printer.py` wraps ESC/POS printing for the thermal printer workflow and expects Python 3 plus `python-escpos`.

## Build, Test, and Development Commands
- `./Paint.command` — runs environment checks, installs The MidiBus and Python deps if missing, then launches the sketch with `processing-java`.
- `processing-java --sketch="$(pwd)" --run` — direct launch from the repo root; useful when you need verbose console logs or headless runs.
- `python3 -c "from munbyn_printer import MUNBYNPrinter"` — quick import smoke test confirming printer dependencies load without runtime errors.

## Coding Style & Naming Conventions
- Use two-space indentation, same-line braces, and concise comments explaining intent (follow the existing Processing style).
- Keep class names PascalCase (`AnimatedPen`), methods and fields lowerCamelCase, and constants SCREAMING_SNAKE_CASE (`CANVAS_WIDTH`).
- Favor typed collections (`ArrayList<LineSegment>`) and reuse existing naming patterns like `penModeNames` for parallel arrays.

## Testing Guidelines
- Run the sketch (`./Paint.command`) after changes and exercise drawing, erasing, zoom, animation playback, and save/print triggers.
- Watch the console for shader compile errors or MIDI connection warnings; address them before submitting changes.
- Validate printing flows by exporting an image, then instantiating `MUNBYNPrinter` in a Python REPL and sending a small test ticket.
- When introducing new assets, verify they appear under the correct `data/` subdirectory and render at 576px width without stretching.

## Commit & Pull Request Guidelines
- Recent history uses placeholder commits; please switch to imperative, descriptive messages under 72 characters (e.g., `git commit -m "Refine zoomed eraser overlay"`).
- Reference related issues or TODOs in the body and describe manual verification steps (e.g., hardware used, commands run).
- PRs should include before/after visuals or exported samples when UI or printer output changes, and call out any new dependencies.

## Peripheral & Asset Notes
- Maintain directory naming patterns (`kit_frames/frameNNN.png`) so animation loaders keep working without code changes.
- Re-run `./Paint.command` after updating Processing libraries to ensure The MidiBus reinstall logic completes successfully.
- Document shader-level expectations (precision, uniforms) in PRs when touching `paint_final_frag.glsl` to help reviewers trace rendering differences.
