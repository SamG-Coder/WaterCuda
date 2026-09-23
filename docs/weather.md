# Seeded dynamic weather

Weather is generated in `kernels/weather.cu`, shared by native CUDA and the CUDA-to-WGSL browser renderer. The JavaScript and C++ hosts only pass controls and dispatch kernels.

## Regional behaviour

Automatic weather samples a continuous seeded field on 4.8 km world groups. Adjacent groups blend smoothly; distant islands can have different weather at the same time. The field drifts with a slowly changing direction and blends between seeded patterns over 20-minute epochs. The same world seed, position and simulation time reproduce the same weather, including after floating-origin rebasing.

Cloud cover, rain intensity and storm activity follow this field. Three moving cloud layers add smaller-scale shape and lit edges. Waves respond to the local field with a delayed amplitude and slope multiplier; storm waves are stronger and clear-weather waves calmer. The existing FFT wind direction and spectrum shape are retained.

## Rain and wet surfaces

Near-camera rain uses seeded world-space columns and falling-drop phases. Surface impact rings sample the same column and phase at the already known visible surface point. This avoids particle simulation, collision queries and per-drop storage. The primary depth prevents rain appearing through terrain, and rain is excluded below water.

Wetness samples recent rain history, so surfaces stay darker and more reflective after a passing shower and gradually dry. This is an approximate finite history, not a persistent water-volume simulation. Surface rings are an approximation on exposed upward-facing surfaces; there is no runoff, pooling or canopy interception model.

Clouds use bounded procedural layers rather than a volumetric ray march. Thunderstorms include seeded flashes and visible lightning, but no thunder audio. Lightning is currently composited against the sky rather than resolving physical ground strikes.

## Controls

- Browser: **Weather** selects Auto, Clear, Overcast, Rain or Thunderstorm. URL values are `weather=auto`, `clear`, `overcast`, `rain`, or `storm`.
- Native: **T** cycles those modes; `--weather storm` selects a mode at launch.
- **Pause world** / native **P** freezes waves and weather together.
- Forced modes override the entire scene and wetness immediately; Auto provides regional variation and rain history.
- Coral study/family views keep their inspection lighting and suppress weather shading.

Examples on the local server:

- [Automatic coast](http://localhost:8090/?seed=884&view=coast&weather=auto)
- [Thunderstorm](http://localhost:8090/?seed=884&view=coast&weather=storm)
- [Rain close to terrain](http://localhost:8090/?seed=884&view=scrub&weather=rain)

## Cost and validation

There are no weather particle buffers or collision passes. Ocean metadata adds 16 bytes. Rain tracing is restricted to 30 metres with at most 64 grid steps, impact detail is footprint-filtered, and lightning geometry is evaluated only during flashes.

Initial native RTX 5080 measurements at 1280 × 720 over 30 frames were 4.51 ms GPU time for clear coast, 7.25 ms for automatic coast, 6.97 ms for storm coast, and 5.20 ms for rain at the scrub view. These are specific scene measurements, not browser FPS guarantees.

`npm test` checks shader compilation, host contracts and paused weather invalidation. `npm run test:native` includes weather continuity, seeded regional variation, wetness history, large-coordinate rebasing, rain-column/impact phase agreement, bounded wave gain and finite sky output. Native CTest also renders a forced storm on the GPU.

The browser storm preview also reached a rendered frame without reported WebGPU errors and showed 60 FPS at its automatically selected 832 × 472 resolution. Its first shader compilation took several minutes. The native and browser resolution measurements are not directly comparable.

## Shared world clock and sky

The default sky now follows a 24-minute day/night cycle (one simulated hour per real minute), starting at noon. Sun motion, atmospheric colour, twilight cloud lighting, surface brightness and water reflections use the same solar direction in `kernels/common.cu`. The previous static cloud layer has been removed; all cloud cover comes from the seeded weather system.

Night adds a world-seeded star field, a simplified full moon opposite the sun, subdued ambient moonlight and a moon highlight on water. Weather clouds occlude celestial features and reduce moonlight. This is an artistic day/night model, not astronomical ephemerides, lunar phases or physical multiple scattering.

Browser controls:

- **Day / night cycle** enables the clock.
- **World time** selects the current hour without resetting weather, waves or their elapsed time.
- **Sun elevation** or choosing a Sea & light look selects manual lighting. The day/night checkbox restores the cycle.
- **Sun direction** rotates the solar path while the clock runs.
- **Pause world** freezes the shared animation clock.
- URL `hour=18` opens at sunset; `hour=0` opens at midnight. Add `clock=manual` to preserve a manual sea/light preset.

Native controls: `--hour 18`, **J/K** to move one hour backward/forward, **L** for manual lighting looks, **P** to pause. J/K restore the solar clock after a manual look.

The existing 16-float control buffer is retained: `C[8] >= 10` encodes the starting hour plus 10; lower values retain manual solar elevation. `C[5]` remains elapsed simulation seconds. Changing the starting hour offsets solar time without changing weather history. Automated checks cover daylight versus midnight radiance, continuity across midnight, the 24-minute period, and time-independent manual overrides.
