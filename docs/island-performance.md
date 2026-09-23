# Island performance investigation

Native CUDA, RTX 5080, seed 884, 1280 × 720, 120 deterministic frames per view. The viewer was closed during measurement. These are native GPU timings, not browser frame times.

| View | Terrain/water tracing | Billboard tracing | Reflections | Shading | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Scrub, clear, before | 3.94 ms | 0.12 ms | 0.01 ms | 0.92 ms | 5.12 ms |
| Scrub, clear, after | 3.92 ms | 0.13 ms | 0.01 ms | 0.83 ms | 5.01 ms |
| Shore, auto, before | 3.79 ms | 0.12 ms | 4.32 ms | 2.12 ms | 10.48 ms |
| Shore, auto, after | 3.76 ms | 0.12 ms | 4.25 ms | 2.04 ms | 10.29 ms |

Totals include ocean/cache preparation. Small differences include measurement variation; the foliage change is not a major frame-time fix.

## Changes

- Reuse cached shrub habitat for terrain coverage inside the existing cache.
- Skip exact shrub habitat generation when the pixel footprint fully resolves to average foliage coverage. Previously this could evaluate terrain height five times for a plant that could not be seen individually.
- Keep exact seeded crowns outside the cache when still resolvable, and average coverage at long distance. Foliage does not simply vanish.
- Generate fuller, lower shrub silhouettes and use a muted olive palette for both cards and distant crowns. Additional leaf detail is generated only once into the atlas; runtime card count and texture dimensions remain unchanged.
- Native headless runs now report preparation, terrain/water, billboard, reflection and shading GPU times.

## Recommended next architectural work

The main cost is repeated procedural terrain evaluation in primary and reflected rays. A seeded GPU height-tile cache with a min/max hierarchy would let rays skip empty regions and sample already generated terrain. Near terrain needs sufficient resolution and a procedural detail fallback. Reflections can use a coarser terrain hierarchy while retaining each water pixel's own reflection direction, avoiding a return to visible square reflection cells.

The foliage cleanup did not implement this hierarchy; the subsequent terrain-cache implementation is described below. Current tests establish native correctness and continuity; browser shader translation passes, but the new foliage appearance was visually inspected in native CUDA only.

## Final review: quality-preserving changes

With the day/night system enabled, skip moonlight/weather sampling in full daylight and skip averaged foliage habitat calculations before that LOD becomes active. Empty foliage coverage returns the original material immediately. Render resolution, ray limits, vegetation density, reflection directions and texture detail are unchanged by these optimizations.

Controlled native measurements, RTX 5080, 1280 × 720, seed 884, 120 frames:

| Scene | Before | After |
| --- | ---: | ---: |
| Shore, automatic weather, noon | 10.522 ms | 10.308 ms |
| Scrub, rain, noon | 5.081 ms | 5.024 ms |
| Coast, clear, midnight | 4.557 ms | 4.499 ms |

All three final BMPs are byte-for-byte identical before and after the optimization (zero differing bytes). Small timing changes include normal measurement variation; this is incremental cleanup, not a solution to the remaining terrain/reflection cost.

An initial run with another browser preview actively rendering produced misleadingly high timings; those results were discarded. The table uses runs after closing the test preview and native interactive viewer. The browser day/night controls were visually verified separately at 60 FPS with automatic resolution reaching 1280 × 720 and no reported WebGPU errors. Browser startup shader compilation still takes several minutes on a first load.

Validation: 19 Node tests, all CPU suites including weather/solar continuity, six native GPU tests, and successful GitHub Pages artifact packaging.

## Shoreline root-cause isolation

A separate diagnostic copy under `.native/shore-probe` was built with temporary bypass switches; these switches are not in the shipped renderer. Seed 884, shore view, automatic weather, noon, 1280 × 720, 180 frames:

| Diagnostic | Primary terrain/water pass | Reflection pass |
| --- | ---: | ---: |
| Complete renderer | 3.717 ms | 4.229 ms |
| Bypass reflected terrain | 3.732 ms | 0.193 ms |
| Bypass reflected weather sky | 3.762 ms | 4.197 ms |
| Bypass primary terrain | 0.472 ms | 5.046 ms |
| Replace displaced-water intersection with flat plane | 3.347 ms | 5.445 ms |

Bypasses change visibility and consequently later work. Compare the directly affected pass, not total frame times or the unrelated downstream passes. Diagnostic output is not a proposed quality reduction.

A CPU instrumentation copy of the shared CUDA sampled 3,600 shoreline pixels at simulation time 3 seconds. Primary rays averaged 54.59 terrain-height calls (53.54 inside the full procedural evaluator), median 32, 95th percentile 177, maximum 492. Of 2,015 water reflection rays, only 114 hit land (5.66%). Nevertheless, reflection rays averaged 49.79 height calls (48.52 full evaluations), median 36, 95th percentile 135, maximum 591.

Extrapolating the sampled full-evaluation counts to 1280 × 720 gives roughly 74 million procedural terrain evaluations per frame across these two searches. This is a sampling estimate, not a GPU counter. Each evaluation computes several terrain-noise layers. Coarse island boxes bound the search, but there is no internal terrain hierarchy, so many grazing rays repeatedly evaluate terrain just to establish a miss. Uneven iteration counts can also reduce parallel efficiency, though hardware occupancy/divergence was not measured here.

Conclusion: repeated procedural terrain traversal dominates this view. Bush billboards, the FFT preparation pass and reflected clouds are not the principal cause. The architectural fix is GPU-generated reusable terrain tiles with conservative min/max bounds for empty-space skipping, retaining procedural refinement at intersections. Any new bounds need reference-ray and image validation; reducing march iterations or simply disabling reflections would trade away quality and was not applied.

## Implemented terrain-bounds cache

`kernels/terrain-cache.cu` generates conservative lower/upper height tiles for the current 4.8 km world cell and its eight neighbours. Each cell has 512 × 512 leaves (9.375 metres per leaf) and nine min/max reduction levels. Value-noise extrema are bounded at rectangle corners and lattice crossings, and interval arithmetic covers ridge shaping, domain warping, coastal deposition and every filtered detail level. The cache does not replace the procedural terrain surface with interpolated low-resolution geometry.

Primary and reflection rays inspect the finest bound first, climb to larger safe intervals, and skip only space proven above all possible terrain. Near intersections they use the original procedural height evaluator and refinement. Queries beyond the cached nine cells retain procedural traversal. The hierarchy shares the existing storage buffer, adding about 24 MiB without another per-pixel buffer binding. Native CUDA and WebGPU use the same `.cu` implementation.

The cache rebuilds on seed or integer-origin changes, not camera motion within a cell, sun/time, weather or waves. A native single-frame run including cold preparation measured 9.03 ms total, with 0.47 ms in preparation; timing varies with seed and hardware.

Measured native RTX 5080, 1280 × 720, seed 884, 120 frames, same time progression:

| Scene / pass | Reference | Cached |
| --- | ---: | ---: |
| Shore total | 10.04 ms | 7.63 ms |
| Shore primary terrain/water | 3.71 ms | 2.36 ms |
| Shore reflections | 4.14 ms | 3.08 ms |
| Rainy scrub total | 5.16 ms | 4.73 ms |

The shoreline improves by about 24% in total GPU time. In the sampled shoreline workload, procedural height calls fall from 54.59 to 15.69 per primary ray and 49.79 to 5.30 per reflection ray. The median reflection ray now performs zero procedural height evaluations.

Validation includes 576,000 height samples (including tile corners and multiple detail footprints) across four seeds, large-origin/rebase bounds, and 5,000 reference rays with identical terrain hit/miss classification. Intersection distances differ by at most 0.947 metres in that suite, below the original traversal's one-metre minimum march step; refined surface residuals are checked independently. A host test verifies cache reuse and invalidation. All 20 Node tests, six CPU suites and six native GPU tests pass.

Images are not bit-identical: changing the march path changes final intersection rounding and therefore some fine material/reflection samples. The 720p shore comparison averages about 0.11 of a 255-level colour step per channel; 0.15% of pixels differ by more than 10 in any channel. The scrub comparison averages about 0.04, with 0.018% of pixels above that threshold. Resolution, render range, terrain noise, surface materials, foliage and per-pixel reflection directions are unchanged.

The WebGPU shoreline was also visually verified after shader compilation, with no console errors. Browser frame rate was not used for the comparison because the native viewer was running concurrently. Pages packaging succeeds. First-load browser shader compilation remains slow and is not addressed by this frame-rendering optimization.
