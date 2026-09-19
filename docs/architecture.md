# Architecture and development direction

The reference project supplies a useful source-of-truth pattern: the same authored procedural definition drives primary visibility, reflected visibility and material evaluation. Its current city is finite. WaterCuda reuses its compiler/runtime and replaces the city descriptors, feature grammar and renderer.

## Current frame

1. JavaScript integrates input and rebases camera X/Z into local 4,800 m cells. It uploads 64 camera/control bytes and 16 integer origin/seed bytes.
2. `seedOcean` evaluates four seeded directional Phillips spectra and evolves their Hermitian Fourier coefficients. `oceanFft` runs row and column inverse transforms; `packOcean` produces height, derivatives and squared slope, and eight `oceanMip` dispatches form the filtered pyramid.
3. `tracePrimary` generates camera rays, intersects the spectral water and procedural terrain, and writes distance, material, footprint, variance, normal and water depth.
4. `reflectOcean` traces one reflection per visible water pixel through the same terrain definition. `shadeOcean` reads that pixel’s reflection, computes terrain shadows and materials, water absorption/refraction and highlights, and tone maps the result.
5. Output pixels copy directly to the WebGPU canvas. Input continues independently with a maximum of two queued frames. Optional timestamp readback runs periodically without blocking the frame loop.

Ocean storage is constant: four full mip chains and two complex FFT buffers (about 9.3 MiB total). Visibility, normals/depth, full-resolution reflections and output storage scale with render resolution, never distance travelled. The shader loader verifies source/configuration/compiler hashes before reusing generated code. The browser still compiles the generated WGSL into a native GPU pipeline.

## LOD evolution

The present LOD is continuous frequency filtering and bounded traversal. It is not yet the advanced hierarchy recommended for a large, densely detailed world.

For terrain, add camera-centred nested height-field regions with integer cell tags, GPU generation and conservative min/max mip pyramids. Traversal should descend where projected error warrants it and use the same filtered height definition at level boundaries. Chunk residency must affect acceleration only, not whether an island exists. Ray and reflection queries should share the hierarchy and geometry definition.

Water now has four spectral cascades with mip-filtered heights and derivatives. Mipmaps preserve mean squared slope; the difference between that energy and the filtered mean slope produces unresolved variance for the BRDF. Next add horizontal displacement and its Jacobian for choppy crests and foam injection. If a mesh presentation path is introduced, use snapped nested grids, transition stitching and camera-relative vertices.

For shorelines, introduce a camera-local shallow-water domain driven by actual bathymetry. Transfer incident wave energy from the spectral ocean into that domain, and blend displacement and derivatives through an overlap band. Advect foam density over time; use breaking/crest compression to inject foam rather than thresholding only instantaneous surface height.

Add temporal reprojection with depth/normal/material rejection for reflections and specular antialiasing. Water history needs displacement-aware motion vectors; stationary accumulation alone would smear animated waves.

## Known numerical limits

Terrain uses signed 32-bit cell indices and small local float positions. Integer hashing determines topology, while floating-point evaluation can differ slightly across GPU vendors. The world is deterministic on a device, not promised bit-identical in all floating-point outputs on all devices. Ocean coordinates wrap at each cascade's power-of-two patch size, with a combined 2,048 m repeat. Very long running sessions will eventually lose precision in the single-precision animation clock; a high/low time representation is a later improvement.

Terrain traversal currently uses a fixed step budget and a heuristic slope bound. The dense-ray test is regression coverage, not a proof of conservative traversal. Replacing that heuristic with verified min/max bounds is important before adding steeper cliffs, erosion or small surface objects.

## References

The spectral approach follows the Fourier-ocean model discussed in [NVIDIA GPU Gems, Effective Water Simulation from Physical Models](https://developer.nvidia.com/gpugems/gpugems/part-i-natural-effects/chapter-1-effective-water-simulation-physical-models) and [Tessendorf's ocean-surface notes](https://jerrytessendorf.blogspot.com/2011/10/simulating-ocean-surface-jerry.html). The FFT execution structure is adapted from the MIT-licensed CUDA FFT kernels already bundled in cuda-webshader. The renderer still uses a height field rather than overturning fluid geometry.

Island scale: 4,800 m cells, 1,100–1,500 m support radius, 180–440 m peak parameters, and 28% empty cells. The wider horizontal scale gives a gentler coastal ascent. Support disks remain separated even at maximum jitter. Terrain ray bounds cover the larger geometry with 4,352 one-metre minimum steps. Shallow-water caustics use weak, domain-warped noise contours (an artistic approximation), with smooth depth fading and an iterative refracted seabed lookup.

Terrain detail uses island-local metre coordinates independently of island radius: warped 310 m ridge noise, 95/31/9 m relief bands, 42/9 m vegetation variation, and filtered stone/strata detail. Only the outer island envelope is radius-normalized. Inland relief fades out over the beach and submerged shelf. These are procedural terrain features, not erosion simulation or vegetation geometry.

Close-up land shading has a separate projected pixel footprint with a 5 mm lower bound; geometry intersection filtering retains its 20 cm floor. Triplanar procedural colour detail at 40 cm, 9 cm and 2 cm scales fades with footprint. The coarser material band also perturbs lighting normals in the surface tangent plane. It does not displace silhouettes or create grass geometry.

Reflection quality pass: per-pixel rays replace 2 × 2 reconstruction. At 1280 × 1240 the reflection buffer grows from about 6.1 MiB to 24.2 MiB. A seed-884 coast observation remained at 60 FPS, around 10–11 ms GPU total; frame-to-frame ocean changes and driver timing mean this is not a controlled benchmark. Temporal reflection stability remains future work.
