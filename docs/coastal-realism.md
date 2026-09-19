# Coastal light / 002

Based on `c16326f5ca495cfb27d8caa2b6a0d3b403c64752`. This is an incremental
rendering upgrade, not a replacement engine. The visible scene still comes from
CUDA-authored compute kernels through CUDA-WebShader. There are no Three.js
scene objects, imported meshes, environment photographs or image textures.

## What changed

* Water, wet sand and terrain share elevation-dependent incident sunlight.
  The reflection environment excludes the finite sun disk: a Smith/GGX lobe
  accounts for direct solar reflection once. Unresolved FFT slope variance
  broadens the highlight and filters cloud detail rather than creating glitter
  from subpixel cloud frequencies. Back-facing light contributes no sun lobe.
* The sky has a directional warm horizon, procedural cloud thickness/lighting
  and a finite solar disk. It is an analytic/layered approximation, not a
  physically integrated atmosphere or volumetric weather simulation.
* Reflected islands use the same wet-sand response and terrain shadows as the
  primary view. Nearshore direct sunlight is occluded by terrain too.
* Shallow water has separate seabed sand/reef materials and filtered sand ripples.
  The clarity uniform scales Beer–Lambert absorption distance on both solar and
  viewing paths; it does not recolour the ocean with a flat cyan overlay.
* Optional caustics use a local refracted-ray Jacobian computed from the actual
  FFT wave slopes. A flat wave field produces no focusing. Contrast, depth and
  footprint budgets bound the effect. This is a local flat-receiver lens
  approximation, not photon transport and not guaranteed global flux conservation.
* Incoming shoreline fronts, trailing wash and broken-up whitecaps use continuous
  world-stable noise. Foam is analytical coverage, **not** a fluid simulation.
* Scene-linear colour is tone-mapped and converted with the piecewise sRGB curve.
  The old natural-colour screenshot equality is intentionally obsolete; the
  replacement checks physical helper invariants, deterministic output and explicit
  debug colour contracts. The original terrain and FFT regression oracles remain.

## Runtime work avoided

`cacheOceanSpectrum` evaluates the seed-dependent Gaussian Fourier coefficients
once per world seed, in CUDA. `advanceOceanSpectrum` only applies dispersion,
phase rotation and wind scale each frame. The original eager kernel remains an
independent regression path, loaded only when GPU validation is requested.
The cache costs 4 MiB. Camera movement/rebasing never rebuilds it. If wave time,
wind and seed are unchanged (paused ocean), the FFT and mip passes are reused.
New seeds and wind/time edits invalidate the correct stages independently.

Kernel source loading/translation is concurrent; the underlying runtime still
serializes driver pipeline creation to keep its stack-based error scopes safe.
No hardware FPS or cold-compile speedup is claimed without target-GPU measurements.

## Controls

The Sea & light selector provides Clear coast, Golden hour and Open sea swell.
These change uniforms, not shaders. Water clarity, sun direction, wind and sun
height remain editable. FFT-driven caustics can be disabled in Under the surface.
Existing mouse-look/WASD flight is unchanged. View 4 / Shallows is a closer
shoreline composition, most useful with seed 884. Views remain procedural and
other seeds can have a different coastline at that position.

Examples: `?seed=884&view=shore&look=coastal` and
`?seed=884&view=coast&look=golden`.

## Reproduce checks

```sh
npm test
npm run test:native
# Optional browser-only development tooling, not application dependencies:
npm install --no-save --package-lock=false playwright@1.63.0
npx playwright install --with-deps chromium
npm run test:browser
```

The browser runner uses an explicitly requested SwiftShader software adapter by
 default. Set `CW_SOFTWARE_GPU=0` to use your machine's normal adapter. It reads
actual CUDA-produced pixels, compares cached/eager GPU Fourier output against the
independent CPU fixture, checks seed/time invalidation, clarity and caustics,
and records backend/test details in `reports/coastal-browser.json`. It does not
substitute a WebGL scene or make external data/asset requests. Failed WebGPU
presentation must fail the browser check, not silently select another renderer.

Optional offline reference previews execute the same CUDA functions on the CPU:

```sh
g++ -O3 -std=c++17 -fopenmp tests/visual.cpp -o water-preview
./water-preview coast.ppm coast 960 884
./water-preview sunset.ppm sunset 960 884
./water-preview shallows.ppm water 960 884 1850 25 1250 .15 -.30
```

These CPU previews are for visual iteration and are not GPU performance evidence.

## Technical background

The renderer's optical conventions follow the standard dielectric reflection and
transmission model. Useful primary references:

- NVIDIA GPU Gems, chapter 1: https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-1-effective-water-simulation-physical-models
- NVIDIA GPU Gems, chapter 2 (distinguishes aesthetic caustic approximations from full transport): https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-2-rendering-water-caustics

## Remaining limits

The FFT ocean is still a vertical heightfield: no overturning breakers, coupled
shoreline shallow-water solver, volumetric foam, boats or underwater camera.
The island geometry is unchanged. There is no temporal anti-aliasing or bloom
in this pass; extreme grazing reflections may still shimmer at low resolution.

## Integration validation

The Windows source-parser test uses `fileURLToPath`, and the browser fixture server normalizes its native root directory before containment checks. An HTTP regression test exercises the real server using a trailing-separator directory URL. Chromium validation uses Playwright 1.63.0 and reports application startup failures without waiting out the readiness timeout. The unused encoded patch transport was removed.

The integrated scene passed all nine built-in GPU checks in the desktop browser. Daylight coast, shallow water, caustics on/off, golden hour and stronger waterline waves were inspected at 1280 × 720 with approximately 60 FPS during those spot checks. These are not controlled before/after performance measurements. Caustic contrast was reduced after the close shoreline comparison to avoid overwhelming the visible seabed.
