# Animation reference review

Reference: [This iPhone Duo Animation — Marques Brownlee](https://www.youtube.com/shorts/uJdjKOBikTE). Reviewed in the YouTube player at 1080p, with paused close-up frames around 10.52 and 11.21 seconds and the earlier opening sequence.

Observed: content remains substantial beneath a blur increasing across the moving display. The visible effect suggests looking through frosted glass at a layer behind it. It does not uniformly collapse the entire home screen into a thin strip against black. Physical camera/phone motion and the phone's layout change cannot be directly transferred to a MacBook.

Mac adaptation: rotate the hinge axis to the bottom edge, hold the original desktop plane and an assumed eye position, cast rays through the moving panel, and crop rather than resize-to-fit. Use one mapped screenshot with strong edge blur and symmetric opaque dark sides; do not composite an unmapped desktop behind it. Suppress extreme magnification gradually through blur, avoiding a hard scale clamp or perspective singularity.

The clip does not provide hinge telemetry, implementation parameters, or a calibrated view, so exact angles and settling constants cannot be extracted reliably. The implementation and timings remain an approximation, requiring physical comparison by the user. No camera or head tracking is introduced.
