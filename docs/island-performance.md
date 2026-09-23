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

This hierarchy is not implemented by the foliage cleanup. Current tests establish native correctness and continuity; browser shader translation passes, but the new foliage appearance was visually inspected in native CUDA only.

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
