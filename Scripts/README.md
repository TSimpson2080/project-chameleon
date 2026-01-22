# Sampling tools (macOS `sample`)

These scripts help extract useful information from macOS `sample` output without opening Xcode.

## Capture

```bash
sudo sample <pid> 10 -file chameleon-sample.txt
```

If you’re sampling a Simulator app and don’t know the PID, you can also use:

```bash
Scripts/capture_sim_hang.sh
```

## Extract main thread (Thread 0 equivalent)

Supports both common `sample` formats:

- Per-thread sections (`Thread 0:` / `Dispatch Queue: com.apple.main-thread`)
- Call graph aggregation (`Thread_#### … com.apple.main-thread`)

```bash
Scripts/extract_sample_main_thread.sh chameleon-sample.txt
Scripts/extract_sample_main_thread.sh chameleon-sample.txt --lines 300
```

## Extract hotspots

Prefers `Sort by top of stack` when present; otherwise prints the `Call graph:` block.

```bash
Scripts/extract_sample_hotspots.sh chameleon-sample.txt
Scripts/extract_sample_hotspots.sh chameleon-sample.txt --lines 200
```

## Run script “tests”

```bash
Scripts/Tests/run.sh
```

