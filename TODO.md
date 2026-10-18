# TODO: Fixes and Improvements for omarchy-mihomo-plugin

This document tracks known architectural and functional issues introduced by the managed profiles system (`omarchy-mihomo-manager`) and proposed fixes.

---

## 1. SSRF Check vs Fake-IP Conflict (Subscription Fetching Broken)

### Problem
In `manager/internal/fetcher/fetcher.go`:
- Line 139: `isBlockedIPv4` treats `198.18.0.0/15` as a blocked address (`"subscription URL host resolves to a private address"`).
- Mihomo defaults to Fake-IP in `198.18.0.1/16` for DNS queries.
- When Mihomo TUN mode or DNS capture is active, the host resolver returns a fake IP in `198.18.x.x` for any domain name.
- The fetcher executes `validateResolvedHost()` locally before dialing or passing to the proxy.
- Even when updating via proxy (`--via-proxy`), `fetchViaProxy()` pins the resolved IP locally first (`pinPublicURL`), which immediately trips the `198.18` blocked check.

### Result
When Mihomo is running, **no subscription URL can ever be fetched or updated**. Every attempt fails with `"subscription URL host resolves to a private address"`.

### Proposed Fix
- In `isBlockedIPv4`, do not treat `198.18.0.0/15` as a private block for DNS-resolved hostnames (only block literal IP hosts if necessary, or use a direct upstream DNS like `1.1.1.1:53` / `8.8.8.8:53` inside the fetcher to bypass local Fake-IP poisoning).
- In `fetchViaProxy`, delegate name resolution directly to the HTTP proxy (`http://127.0.0.1:mixedPort`) instead of pre-resolving and IP-pinning on the host.

---

## 2. Catch-22: `no current runtime to backup` When Core is Inactive

### Problem
In `manager/cmd/omarchy-mihomo-manager/main.go`:
- Lines 1345–1363: `backupRuntime()` is called whenever a profile is activated or added with `--activate-if-empty`.
- If `current.yaml` does not exist yet (initial onboarding), it queries `core.CoreInfo()` via the Mihomo REST API to locate `info.ConfigPath`.
- If Mihomo is stopped or running without a file-based configuration, `core.CoreInfo()` fails and returns `"no current runtime to back up"`.

### Result
A Catch-22 situation:
- If Mihomo is active -> Fake-IP causes `"subscription URL host resolves to a private address"`.
- If Mihomo is stopped -> Profile addition/activation aborts with `"no current runtime to back up"`.

### Proposed Fix
- If `current.yaml` does not exist and `core.CoreInfo()` fails or returns an empty path, `backupRuntime()` should treat this as a no-op initial state rather than aborting the transaction.

---

## 3. Manager Hijacks Network Configuration (Disables TUN, Forces System Proxy)

### Problem
- In `manager/internal/profile/profile.go`: `DefaultSettings()` sets `TUNManagement: "managed"` and `TUN.Enable: false`.
- On initial startup, `Service.qml` triggers `maybeInitialReconcile()`, which runs `manager reconcile`.
- The compiler compiles settings with `tun.enable = false` and applies it to Mihomo, turning off the user's running TUN mode and switching traffic capture to the desktop system proxy.

### Result
The plugin silently modifies the user's running core configuration on startup, disabling TUN without user consent.

### Proposed Fix
- Provide an explicit **Standalone / Unmanaged Mode**:
  If the user chooses not to use managed profiles (or runs Mihomo with their own hand-written `config.yaml`), the plugin should act purely as a controller/viewer (status, proxy selection, rule providers, traffic stats) and never invoke `manager reconcile` or overwrite `tun` / `dns` settings.
- If managed mode is active, default `TUN.Enable` to `inherit` rather than forcing `false`.

---

## 4. UI Actions in Rules & Profiles Not Triggering

### Problem
- The "Edit proxy group" buttons in `ProfilesPage.qml` and `RulesPage.qml` call `svc.openProxyBindingEditor()`, which queries `policy binding candidates <activeProfile>`. If no managed profile is active, it quietly fails without visual feedback.
- `AddRuleDialog` and `allRulesPopup` are embedded inside `RulesPage.qml` rather than being hosted in the top-level `KeyboardPanel` overlay, leading to clipping or focus issues depending on the panel host hierarchy.

### Proposed Fix
- Add explicit disabled state and tooltips explaining that proxy bindings require an active managed profile.
- Unify popup/dialog hosting under `MihomoPanel.qml`'s `KeyboardPanel` window overlay.
