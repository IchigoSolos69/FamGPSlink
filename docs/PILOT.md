# Physical-device acceptance checklist

Status: **not run**. Compilation and emulator security tests do not establish real battery usage or background reliability.

Use one Android phone and one iPhone on the same configured family. Record OS version, phone model, app build, battery health and power settings. Do not use this pilot as an emergency tracking system.

## Functional checks

- Fresh installation: name entry, private pairing code, no family access before approval, sharing off by default.
- Approve both phones; enable foreground/precise permissions, then background/Always permission; both see each other's latest pin, timestamp and accuracy.
- Approve an additional phone with **Private connection (only you)**. Verify only the owner sees its profile/pin and the private phone sees only the owner and its own pin. Check a normal family phone's map, list and count for absence of the private profile. Confirm the private phone's audience explanation and sharing toggle. Recover the private profile on a replacement phone and verify the audience remains restricted and the old phone loses access.
- Close and reopen repeatedly: same profile, no duplicate setup. Reinstall a member phone and recover the existing profile through the owner; old installation loses all reads and writes.
- Owner sign-in with the configured email/password; password recovery; a different email account cannot become owner.
- Choose an owner manual pin: family sees only that pin, no manual label or invented accuracy. Keep it through restart. Inspect database: no underlying owner GPS records. Pause sharing: shared pin disappears; resume: chosen pin returns.
- Restore GPS with usable signal: obtain a fresh fix, clear override and publish atomically. Deny permission/disable GPS/no signal: restoration fails and manual pin stays intact.
- Go offline while moving: only one latest encrypted fix is retained; reconnect and verify no replay of a route or older pin. Set a manual pin while a GPS upload is in flight and verify the GPS write cannot win.
- Deny/revoke location, approximate-only access, GPS disabled, low-power mode, Android battery restrictions, screen lock, reboot and force-stop. UI must report limitations and retain truthful timestamps; force-stop may require reopening.
- Open settings and background the app: stop family map listeners; own background tracking continues as permitted. Remove a member while their app is open: stop tracking and remove cached family access.
- Exhaust/disable test database access: show offline/unavailable or stale data, never imply an old point is fresh. Map tile failure: member list remains usable.

## 24-hour battery run

For each platform, compare a representative 24-hour baseline with a 24-hour sharing run, using a similar mix of screen-off stationary time and walking/driving. Record:

| Metric | Android | iPhone |
| --- | --- | --- |
| OS / device / build | | |
| Baseline battery drain | | |
| Sharing battery drain | | |
| Incremental battery drain | | |
| Moving median / worst update delay | | |
| Stationary update delay / pause periods | | |
| Typical / worst horizontal accuracy | | |
| Location data uploaded / downloaded | | |
| Reboot / power-saving behavior | | |

Pilot tuning target: moving updates normally within two minutes where permissions and network allow; no route replay; no unsupported precision claim. Investigate incremental battery drain above five percentage points/day on either test phone and tune location accuracy, movement threshold or stationary timing before rollout. This is a tuning target, not a device-independent guarantee.

Check Firebase usage daily in the pilot. Keep a margin below Spark's quotas. Do not enable billing to work around a quota failure without an explicit project decision.
