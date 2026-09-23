# WaterCuda native C++ / NVIDIA CUDA

This is a native executable, not a browser wrapper. NVIDIA `nvcc` compiles the **same, unchanged** scene source used by the WebGPU version:

- `../kernels/common.cu`
- `../kernels/terrain.cu`
- `../kernels/shrubs.cu`
- `../kernels/ocean.cu`
- `../kernels/render.cu`

`src/renderer.cu` includes those files directly and launches their kernels with CUDA `<<<grid, block>>>` calls. It does not copy, translate, or fork their rendering algorithms. Edits to the shared files are picked up by the next native build and browser shader build. `src/cuda_vectors.cuh` supplies only the small vector-operator adapter that native CUDA needs.

## Windows: build and run

Requirements: an NVIDIA CUDA-capable GPU, a compatible NVIDIA driver, CUDA Toolkit, CMake 3.24+, Ninja, and Visual Studio's **Desktop development with C++** workload. The PowerShell helper finds Visual Studio and loads its x64 compiler environment. Visual Studio's development environment normally supplies Ninja; otherwise put it on PATH.

From the repository root:

```powershell
.\native\build.ps1 -Test -Run
```

If PowerShell blocks local scripts, use a process-scoped invocation:

```powershell
powershell -ExecutionPolicy Bypass -File .\native\build.ps1 -Test -Run
```

After building, launch directly; no Node server, browser, WebGPU, or downloaded scene assets are required:

```powershell
.\native\build\watercuda.exe
.\native\build\watercuda.exe --seed 884 --view bars
```

The default build targets the installed GPU. To build for another supported architecture, configure CMake explicitly from an x64 developer prompt, for example using your target's numeric CUDA architecture instead of `native`:

```powershell
cmake -S native -B native/build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_CUDA_ARCHITECTURES=native
cmake --build native/build
ctest --test-dir native/build --output-on-failure
```

The interactive window is currently Windows-only. The CUDA renderer and headless entry point are also written for Linux; configure with CMake and the installed CUDA host compiler. Linux has not been tested in this workspace.

## Controls

| Control | Action |
| --- | --- |
| WASD / arrow keys | Fly along the camera direction |
| Q / E / Space | Descend / ascend |
| Shift / Z | Boost / slow movement |
| Mouse drag | Look around |
| F | Toggle captured raw mouse look |
| Esc | Release captured mouse, or close the viewer |
| Mouse wheel | Change flight speed; no application-defined upper cap |
| 1–6 | Coast, aerial, waterline, shore, scrub, sandbars |
| P | Pause or resume waves and weather |
| R / C | Toggle island reflections / caustics |
| L | Cycle clear coast, golden hour, open sea swell |
| T | Cycle automatic / clear / overcast / rain / thunderstorm |
| G | Generate the next world seed |
| + / − | Increase / decrease render resolution |
| N | Cycle natural, pixel footprint, surface normals |
| H | Toggle control overlay |
| F12 | Save `watercuda-native.bmp` in the current working directory |

The window title shows actual frame rate, CUDA GPU time, flight speed and world seed. Render width starts at 1280 and fits the window; the rendered image scales to the client area. There is no imposed FPS limit. Floating-origin rebasing and the world-coordinate safety limit are preserved.

## Headless rendering and GPU checks

```powershell
.\native\build\watercuda.exe --self-test
.\native\build\watercuda.exe --headless --seed 884 --view bars --width 1280 --height 720 --frames 30 --output native\build\sandbanks.bmp
.\native\build\watercuda.exe --headless --view scrub --output native\build\shrubs.bmp
```

Headless frames start at ocean time 3 seconds and advance by 1/60 second per frame, making runs reproducible. `--frames` also supports a bounded interactive run. `--hidden --frames 3` is the Windows window/presentation smoke test and cannot run indefinitely.

CTest checks actual GPU execution: repeated sample determinism, the existing CPU terrain/ocean reference fixture, floating-origin rebasing, generated foliage mip coverage, opaque nonuniform images, and the hidden Windows presentation path. `--self-test` needs the source checkout for `tests/ocean-reference.json`; ordinary rendering does not.

## Implementation and current limits

The native host uses the same spectrum cache, four CUDA FFT cascades, ocean mip chain, foliage atlas and habitat cache, visibility passes, reflections, and shading order as the browser host. Spectrum coefficients are regenerated only when the seed changes; paused ocean frames reuse their wave textures; habitat is regenerated only when its cell, seed or origin changes. Native compilation disables floating-point contraction for closer agreement with the existing reference tests; small cross-backend floating-point differences can still occur.

The Windows viewer uses the Win32 API and GDI for presentation, avoiding extra windowing dependencies. Rendering happens on the NVIDIA GPU, then the final RGBA image is copied to CPU memory, converted to the Windows pixel layout and presented. It is **not zero-copy CUDA/graphics interop**. The displayed CUDA time excludes image readback and window presentation; the title's FPS includes them. Direct graphics interop could improve presentation overhead later without changing the shared `.cu` files.

`build/` and rendered images are ignored by Git. The native executable is built locally, not added to the GitHub Pages payload.

Underwater preview: `--view reef` or key **7** (seed 884). Q descends below the surface. The native and browser viewers share the same seeded seabed, depth habitat and reef cache kernels. See [underwater notes](../docs/underwater.md) for the current height-field limitations.

Dynamic weather uses the same `kernels/weather.cu` as WebGPU. Press **T** to cycle Auto, Clear, Overcast, Rain and Thunderstorm, or launch with `--weather storm`. **P** freezes weather and waves together. See [weather details](../docs/weather.md).

The default sky follows a 24-minute day/night cycle. Use `--hour 18` for sunset, **J/K** to step the world hour, **L** for manual light, and **P** to pause. Changing the hour preserves weather history.
