# Blank screen triage (Simulator)

Copy/paste:

```bash
cd ~/dev/project-chameleon/Chameleon
Scripts/capture_samples.sh
```

This captures 3 short `sample` traces from the running Simulator app, then prints:
- the `com.apple.main-thread` call-graph block (Thread 0 equivalent)
- the `Sort by top of stack...` hotspots section

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

