# QA & Testing Report

This document outlines the testing methodology, known issues resolved during development, and performance optimizations implemented in **Hex Tunnel**. It serves as a historical record of technical challenges and solutions for future contributors.

## 1. Smart Routing & Memory Management

**Challenge:** 
When downloading large smart routing datasets (e.g., thousands of blocked domains/CIDRs) from remote endpoints, the `sing-box` engine occasionally attempted to read the `smart_routing_rules.json` file while it was still being written. This resulted in a critical `unexpected EOF` parsing error, crashing the VPN service.

**Resolution:**
Implemented atomic file writing in `TunnelProvider`. 
1. The remote dataset is downloaded to a temporary file (`.tmp`).
2. Only upon successful completion of the download and verification is the `.tmp` file atomically renamed to `smart_routing_rules.json`.
3. The `sing-box` engine is triggered only *after* the file is guaranteed to be complete.
*Status: Resolved and verified. No further EOF crashes observed.*

## 2. Dynamic Cloudflare WARP Balancer (Hybrid Legacy Mode)

**Challenge:**
Standard Cloudflare WARP IP addresses are frequently blocked by Deep Packet Inspection (DPI) heuristics in specific regions. Using a static endpoint resulted in connection timeouts.

**Resolution:**
Replaced the static WARP configuration with a dynamic `urltest` balancer in `sing-box`.
1. The config generator dynamically creates a pool of WireGuard endpoints using known clean Cloudflare IPs (`162.159.192.1`, `188.114.96.1`, etc.) and non-standard ports (`500`, `4500`, `2408`, `1701`).
2. The `urltest` outbound actively pings these endpoints (e.g., against `cp.cloudflare.com/generate_204`) and transparently routes traffic through the node with the lowest latency.
*Status: Resolved. Connection stability significantly improved.*

## 3. Sing-box Engine Syntax Compatibility

**Challenge:**
During the integration of the WARP `urltest` balancer, the configuration parser threw `unknown field "address"` and `unknown field "local_address"` errors. 

**Resolution:**
Identified that the bundled `libsingbox.so` engine (version 1.11+) enforces strict separation between `outbounds` and `endpoints` for WireGuard connections. 
1. The legacy `wireguard` outbound syntax (using `local_address` and `peers`) was migrating to the `endpoints` array.
2. Moved the generated WARP nodes into the root `endpoints` JSON array.
3. Configured the `urltest` outbound to directly reference the endpoint tags (`warp-0`, `warp-1`), taking advantage of `sing-box`'s implicit routing features.
*Status: Resolved. Configurations load without syntax errors.*

## 4. UI Rendering on Small Screens

**Challenge:**
The Settings screen displayed black-and-yellow hazard stripes (bottom overflow) when rendering the new Smart Routing toggles and Compatibility Actions cards on smaller displays.

**Resolution:**
Wrapped the `SettingsScreen` body in a `SingleChildScrollView` to allow flexible scrolling, ensuring the UI remains responsive and accessible regardless of screen dimensions.
*Status: Resolved.*

## Final Build Verification

The release APK is compiled using:
```bash
flutter build apk --release --target-platform android-arm64 --split-per-abi --obfuscate --split-debug-info=./debug_info
```
* **Obfuscation**: Enabled (Dart code is minified and obfuscated).
* **Debug Info**: Extracted out of the binary.
* **ABI Split**: Generated targeted `arm64-v8a` build to minimize final APK size.
* **Logging**: Release mode (`kReleaseMode`) automatically drops internal debug logs.
