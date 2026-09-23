# WebShader shared-memory WASM experiment

An isolated **build-time WASM backend for CUDA-WebShader**. It consumes the same
production `.cu` files, uses WebShader's compiler frontend and parsed kernel ABI,
and generates C++ execution wrappers that Emscripten/LLVM compiles into WASM.
All **17 WaterCuda kernels** compile, including the FFT, terrain cache, foliage
atlas, underwater reef, reflections and final shading. No procedural world or
kernel is reimplemented in JavaScript. The main app and vendored WebShader package
are separate from the experiment. The compiler and generic runtime now come from
upstream CUDA-WebShader commit `9011955806cee30636ba24ae34b22d218e84196f`, vendored
with provenance in `vendor/cuda-webshader/UPSTREAM.json`. Local compiler files are
compatibility re-exports, not a second implementation. WaterCuda only owns its
scene dispatch sequence and demonstration UI.

## Build and test

Install and activate the official [Emscripten SDK](https://emscripten.org/docs/getting_started/downloads.html).
The experiment was tested with Emscripten 6.0.10 and Node 24. From the repo root:

```powershell
# Optional explicit driver path; otherwise the driver is em++ from your SDK.
$env:EMXX = 'D:/WaterCuda/.native/emsdk/upstream/emscripten/em++.bat'
node experiments/webshader-wasm/build-threaded.mjs
node experiments/webshader-wasm/test-barriers.mjs
node experiments/webshader-wasm/test-threaded.mjs 4
node experiments/webshader-wasm/server.mjs 8091
```

Open **http://localhost:8091/experiments/webshader-wasm/**. This separate server
supplies COOP `same-origin`, COEP `require-corp`, and the WASM MIME type. Shared
WASM threads require cross-origin isolation; port 8090's original server does not
supply these headers. The experiment binds only to localhost. Production hosting
headers have not been changed.

Options: `?threads=1`, `?threads=4` (default), or `?threads=8`; `&auto=0` keeps WASM
active until you press the GPU button; `&seed=42` changes the initial seed.
WASD flies, Q/E moves vertically, drag looks around, and the wheel changes speed.
Tests also accept thread counts 1 through 8.

## How it works

The full renderer runs inside a dedicated browser worker. Emscripten pthreads
share one WASM memory; an atomic work queue assigns workgroups to CPU threads.
Every kernel's typed entry wrapper is generated from the WebShader frontend's
parsed parameters. Buffers remain in shared WASM memory between dispatches;
only controls and the completed image cross the browser worker boundary.

For cooperating kernels, the backend hoists fixed-size `__shared__` arrays into
per-workgroup storage and lowers each lane into a C++ coroutine. `__syncthreads()`
suspends each lane until the other lanes reach the same barrier site. Local state
survives suspension; workgroups never share their local arrays. Divergent exits
or different barrier sites are reported as an error. A per-thread frame arena
avoids allocator contention. CPU threads execute multiple workgroups concurrently;
logical CUDA lanes within each group are cooperatively scheduled, not separate
OS threads. The original FFT butterflies and loops are unchanged.

`threaded-runtime.js` owns persistent buffers and mirrors the production dispatch
sequence/cache invalidation. The default WASM image is **128×72**, using the full
pipeline at reduced pixel count. It retains the production 256×256 FFT cascades,
terrain bounds, atlas and reef cache dimensions. The GPU takes over at 640×360.
This is a startup experiment, not a claim that CPUs match GPU throughput.

After the first WASM image, WebGPU initializes in parallel. Before handover, the
page renders a matching saved camera/seed/time snapshot on the GPU and reports
per-channel image error. After a current-state GPU frame finishes, it fades over
and terminates the WASM worker and its pthreads. Controls/time do not reset.
If GPU initialization fails, WASM remains active. Background pages pause new
frame requests. For honest cold-start timing, distinguish shader/driver cache
state; the displayed timings alone cannot prove a cold driver cache.

The module reserves **256 MiB initial shared linear memory**, with a 512 MiB
maximum. Emscripten preloads a pool of seven helper workers; the selected thread
count controls how many actually participate (the dedicated host worker is one).
No JSPI/Asyncify is needed: the UI communicates asynchronously with the worker,
and CPU parallelism comes from shared-memory pthreads.

## Validation and current limits

- Generic reduction test: two shared arrays, repeated barriers, preserved local
  variables, isolated workgroups and observed execution on multiple pthreads.
- Divergent barrier test fails explicitly rather than silently computing output.
- Two-axis FFT impulse test and independent native terrain/ocean fixture.
- Full-frame repeatability, animated waves, underwater reef and coral specimen.
- Tests run with one, four and eight participating threads.
- Browser reports full-pipeline WASM/GPU pixel differences at matching resolution.

The current backend supports this entire WaterCuda pipeline, **not every CUDA or
WebShader language feature**. Atomics/warp intrinsics, dynamic shared memory,
barriers inside helper functions, and arbitrary pointer/record ABIs need further
lowering and conformance tests. Shared arrays currently require literal sizes.
Kernel dispatch is serialized by one host worker; concurrent host dispatch into
the same module is unsupported. This prototype accepts trusted project sources
and does not infer/validate all buffer access bounds.

The first full-pipeline browser run (four threads) displayed a WASM image in
742 ms at 128×72 and handed over successfully after 275.6 seconds. Comparing the
same saved state on both backends gave mean channel error 0.004/255, maximum 2,
and no channels differing by more than 10. This is one local observation, not a
device-independent promise or controlled measurement of compiler contention.
The initial cooperative allocator cost was then removed: the four-thread Node
FFT timing fell from approximately 60–68 ms to 7.6 ms while reference tests still
passed. A subsequent browser run displayed its first image in 689 ms and animated
the shoreline in approximately 34 ms per CPU frame (128×72, four threads).
Paused/cached frame timings omit FFT updates and must not be presented as
animated frame rate. WASM submits at most one frame at a time, with a 33 ms minimum
interval in threaded mode. `&width=256` tests a higher pixel count; supported
widths are multiples of 64 from 64 to 384, with a 16:9 image.

## Earlier lightweight comparison

`build.mjs`, `compiler/wasm.mjs`, `preview.cu`, and `test.mjs` retain the first
independent-invocation experiment. Build it separately and visit
`?cpu=preview&target=preview` to compare WASM and WGSL from the exact same smaller
kernel. In that test the first image appeared in 235 ms, GPU compilation took
29.7 s, and maximum channel error was 2/255. That simplified preview is **not** the
default and is not the full renderer.

All generated C++, JS, WASM and manifests are ignored and reproducible. The local
SDK lives under ignored `.native/emsdk`; no SDK binaries are included in changes.
To update the vendored backend, use `node tools/sync-webshader.mjs PATH_TO_CLEAN_UPSTREAM_CHECKOUT`.
The sync records the upstream commit and normalized source hashes.

## Recording a demo

Add `&record=1` to the automatic handover URL. The page records the actual CPU and
GPU canvases with explanatory captions, then stops 18 seconds after handover.
The dedicated local server saves the WebM and measured event times under
`artifacts/video/`. It accepts this upload only from its own localhost origin.
Any final edit that removes the long compilation wait should label that cut.
