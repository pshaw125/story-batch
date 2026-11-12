# TypeScript desktop host decision

Decision: Electron, with a plain TypeScript/DOM renderer for the Phase 1 spike. Recorded 2026-11-11 before scaffolding. A richer UI framework is deferred until Phase 3 demonstrates a need.

Electron supplies the same Chromium/Node host on Windows and macOS, with filesystem, process and loopback HTTP/WebSocket APIs in the main process. It avoids an additional Rust toolchain and differing system webviews during the first renderer integration. Its larger distribution and memory footprint are accepted tradeoffs; measure sustained use on the Air before replacing Swift.

The renderer is sandboxed with context isolation and no Node integration. A preload exposes individual typed operations, not generic IPC, shell commands or paths. Only bundled content loads; external navigation/windows/requests and permissions are denied. Local renderer API access belongs to the main process, with dedicated-loopback service configuration in Phase 2. No updater, telemetry or remote resources are included.

Shared modules own parsing, planning and the renderer contract. Node modules own storage and process/API adapters. The DOM layer handles presentation only. This spike uses synthetic jobs, never the installed image renderer.

Packaging strategy: pin Electron and build tooling in package-lock.json; use @electron/packager for OS/architecture-specific unpacked applications. Build on the destination OS (Mac app bundle; Windows application directory), with CI for Windows and macOS core tests and packaging. Native installers and signing are deferred to the workhorse release. Runtime dependencies are bundled; no system Node or npm is needed by a packaged app. Dependencies/Electron binaries are explicitly procured during setup; offline use does not run npm or download assets. Builds may need cached Electron distributions after procurement.

Phase 1 requires a real Mac host probe and portable Windows probe scripts. Windows execution cannot be inferred from a Mac build. Record missing evidence in the phase report rather than calling the host cross-platform verified. Existing Swift app/data remain untouched.

References: [Electron isolation](https://www.electronjs.org/docs/latest/tutorial/context-isolation), [security](https://www.electronjs.org/docs/latest/tutorial/security), [distribution](https://www.electronjs.org/docs/latest/tutorial/application-distribution).
