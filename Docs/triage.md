# Blank screen triage (Simulator)

## Fixture demo (no sudo required)

```bash
cd ~/dev/project-chameleon/Chameleon
Scripts/extract_sample_main_thread.sh Scripts/fixtures/sample_callgraph.txt --lines 40
Scripts/extract_sample_hotspots.sh Scripts/fixtures/sample_callgraph.txt --lines 20
```

## Run script tests

```bash
cd ~/dev/project-chameleon/Chameleon
Scripts/Tests/run.sh
```

## Capture during a blank screen

```bash
cd ~/dev/project-chameleon/Chameleon
Scripts/capture_samples.sh
```

Customize sample count/duration:

```bash
cd ~/dev/project-chameleon/Chameleon
SAMPLES=5 DURATION=3 Scripts/capture_samples.sh
```

This writes a timestamped folder under `Scripts/output/` containing:
- `chameleon-sample-<i>.txt` (raw `sample` output)
- `main-thread-<i>.txt` (Thread 0 equivalent / `com.apple.main-thread` call-graph block)
- `hotspots-<i>.txt` (“Sort by top of stack…” section)

## Quick interpretation tips

- If the “main thread” stack ends in `mach_msg2_trap` / runloop frames, it often means the main runloop is idle at that instant.
- The “hotspots” section shows where CPU time is accumulating (top-of-stack collapsed samples). Look for app/SwiftUI frames, PDF generation, hashing, or filesystem work.

## Manual fallback

1) Find the PID:

```bash
ps aux | awk '/\\/Chameleon\\.app\\/Chameleon/ && !/awk/ {print $2; exit}'
```

2) Capture a single sample and extract:

```bash
sudo sample "$PID" 10 -file chameleon-sample.txt
Scripts/extract_sample_main_thread.sh chameleon-sample.txt
Scripts/extract_sample_hotspots.sh chameleon-sample.txt
```

## Bonus (device logs)

If you need stdout/stderr logs from a device without Xcode UI, you can launch with console output:

```bash
xcrun devicectl device launch app --terminate-existing --device <udid> --console com.tsimpson.chameleon
```

Some environments don’t support a separate `devicectl device log stream` flow; `--console` on launch is often the most reliable.
