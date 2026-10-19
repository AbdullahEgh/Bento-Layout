# Windows OTA continuity — 0.3.10

The staging branch is development only. The released app remains `Bento.exe` / assembly `Bento`, mutex `Local\Bento.Windows.SingleInstance`, settings `%LOCALAPPDATA%/Bento/settings.json`, default repository `AbdullahEgh/Bento-Layout`, manifest AppId `Bento.Windows`, Platform `win-x64`, archive `Bento-win-x64.zip` and internal manifest `bento-release.json`. The existing trusted updater helper still handles replacement/rollback. No installed application was operated.

The shipped 0.3.9 updater at eae0eda queries `/releases/latest`, accepts a numeric v-prefixed tag newer than its assembly version, and selects the exact Windows archive with a GitHub SHA-256 digest. Therefore the bootstrap release is `v0.3.10`, explicitly marked latest only after all assets are uploaded and verified. A frozen verbatim copy of that selector tests the actual built ZIP manifest/version and candidate selection, including a preceding Mac asset. Existing package extraction validates every file hash.

The new updater lists releases, chooses the highest explicit Windows version, and supports both legacy Windows tags and checksum-bound Windows metadata on shared platform releases. Mac version numbers are never compared as Windows versions. The Mac publish script already uses `--latest=false`, preserving old-client discovery after subsequent Mac releases.

Windows CI must pass build, native/core fixtures, package/legacy-selector compatibility and settings stacking before artifact upload or release. The tag-triggered release job independently rechecks tag/version/identity, archive and file hashes; downloads the existing Mac 0.2.40 archive and compares its published SHA-256; creates a draft; verifies uploaded GitHub digests; publishes it as latest; and checks the latest API response. Original Mac release/feed assets remain untouched.

Physical input, real virtual desktop/Task View behavior, mixed-DPI hardware and an on-device OTA replacement/restart remain unperformed. CI fixtures are not on-device QA.
