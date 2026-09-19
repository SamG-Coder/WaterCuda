# Sandbars and procedural scrub

The coastal ecology pass adds geometry to the existing CUDA scene. No plant meshes, billboard images or terrain textures are downloaded.

[![Sandbar and its sheltered shallow channel, exported from the browser renderer](images/watercuda-sandbars.png)](https://samg-coder.github.io/WaterCuda/?seed=884&view=bars&look=coastal)

## Coastal terrain

Seeded sediment bands follow selected sections of the island's original depth contours. Narrow offshore ridges leave the original deeper bed behind them, forming shallow channels. Noise breaks the ridges into sections; occasional wider deposits connect to the shore. A smooth capacity limit keeps offshore deposits below 1.8 m above mean water level. Low dune relief grows behind suitable beaches and is filtered by pixel footprint.

The relief stays inside the existing island bounds and is zero on the deep seabed and highlands. Primary rays, reflections, terrain normals, wet sand and water-depth optics all use the same modified height field. These are static seeded formations, not a sediment or tidal simulation. The FFT waves do not yet shoal or break according to these bars.

## Shrubs

[![Procedural scrub with curved individual leaves, exported from the browser renderer](images/watercuda-scrub.png)](https://samg-coder.github.io/WaterCuda/?seed=884&view=scrub&look=coastal)

Six-metre cells deterministically generate jittered plants with variation in size, branch layout, leaf orientation and colour. Habitat tests reject the wet shore, steep slopes and high terrain, and produce patches rather than uniform coverage. Habitat evaluation uses canonical island coordinates so crossing a floating-origin boundary does not change plant eligibility.

A CUDA kernel caches a 64 × 64 patch around the camera, using 65,552 bytes. It refreshes when the camera enters a new six-metre cell, when the origin changes, or when the seed changes. Wave time and wind changes do not regenerate habitat. The world does not accumulate plant instances as the camera travels.

The visibility pass traverses bounded cells and intersects curved branch and leaf primitives directly. Close plants have individually angled leaves and geometric gaps; distant plants use simplified canopy clusters. Leaf detail follows projected footprint, and canopy geometry shrinks away between 140 and 180 m. Farther hills retain the existing terrain vegetation material. Wind moves the sprigs, and shading includes terrain shadow, approximate canopy occlusion, contact darkening and a backlighting term. Nearby water reflections can include shrubs inside the cached patch.

This is a first procedural shrub family, not a botanical species library. Contact darkening is approximate, individual leaves do not cast fully traced shadows onto the ground, and the canopy LOD transition can still be noticeable. High aerial cameras use terrain coverage rather than individual shrubs.

## Checks

- All 12 CUDA entry points compile within the existing baseline storage-buffer limits.
- 17 Node tests include cache invalidation for movement, rebasing and seed changes.
- Native checks compare all 4,096 cached habitat entries with direct generation and exercise 523 cell-traversed shrub rays.
- A seed-884 survey checks 2,286 shrubs for habitat, cell bounds and rebasing; 2,243 test rays hit branches or foliage.
- The coastal survey finds 1,367 raised offshore samples and an exposed bar around 1.55 m above mean water level.
- Existing dense terrain traversal fixtures still have zero hit/miss mismatches; maximum distance difference is below 0.54 m.
- The browser's GPU checks include shrub-cache rebasing in addition to the ocean and terrain checks.

The Scrub and Sandbars presets are composed for seed 884. Other seeds can place their islands differently.

The local Edge preview passed all ten GPU checks, including the new habitat-cache check. The actual rendered sandbar and foliage views were visually inspected. A cold startup during testing took about 100 seconds to compile the viewing pipelines; later loads can reuse driver caches. This remains an optimisation target. Background-tab FPS is throttled, so those readings are not used as an interactive performance claim. The pre-existing hosted software-adapter CI failure is still documented in the coastal-light notes.
