# NVIDIA Image Scaling 1.0.3

`NIS_Scaler.h` and `NIS_Config.h` are upstream MIT-licensed sources from
https://github.com/NVIDIAGameWorks/NVIDIAImageScaling at revision
`35e13ba316c98eeecf16f37eae70ce88019911f6`. The original copyright and permission
notices are retained in both files and in the generated shader.

`node tools/build-nis.mjs` extracts the original six-tap filter banks, edge-map,
four directional filters, adaptive sharpening and ringing limiter into a GLSL ES
3.0 fragment shader (`src/nis-fragment.js`). It changes array layout and invocation
to suit WebGL2; the original compute shader's shared-memory tiling is not used.
Only SDR is implemented. Sharpness is 0.25. Each CPU image is upscaled exactly
2× (the SDK-supported maximum), then CSS fits it to the window. It is not a
temporal/AI reconstruction algorithm and does not manufacture missing detail.
