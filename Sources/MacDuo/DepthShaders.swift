import Foundation

/// The whole effect in one fragment shader.
///
/// Held-plane and frosted background reconstruction share the same
/// edge-extended texture pyramid. No live stream or second image is needed.
enum DepthShaders {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    // All float4, so the layout cannot drift from the Swift side.
    struct Uniforms {
        float4 column0;          // screen-to-picture matrix, column 0 in xyz
        float4 column1;
        float4 column2;
        float4 screenAndOrigin;  // screen size, padded origin in picture points
        float4 paddedAndBlur;    // padded size, max radius in pixels, blur strength
        float4 shape;            // blur floor, max dim, pixel scale, max level
        float4 light;            // dim floor, dim strength, dim reach, closing amount
    };

    // Center every level on the same normalized image coordinates, including
    // odd-sized textures. Four bilinear taps form a symmetric tent filter.
    kernel void centeredDownsample(texture2d<float, access::sample> source [[texture(0)]],
                                   texture2d<float, access::write> target [[texture(1)]],
                                   uint2 id [[thread_position_in_grid]]) {
        if (id.x >= target.get_width() || id.y >= target.get_height()) { return; }
        constexpr sampler sampleCenter(filter::linear, address::clamp_to_edge);
        float2 uv = (float2(id) + 0.5) / float2(target.get_width(), target.get_height());
        float2 d = 0.75 / float2(source.get_width(), source.get_height());
        float4 colour = (source.sample(sampleCenter, uv + float2(-d.x, -d.y))
                      + source.sample(sampleCenter, uv + float2( d.x, -d.y))
                      + source.sample(sampleCenter, uv + float2(-d.x,  d.y))
                      + source.sample(sampleCenter, uv + float2( d.x,  d.y))) * 0.25;
        // Compute writes use an unorm view; preserve the sRGB encoding expected
        // by the read view and the fragment shader. Filtering is in linear light.
        float3 encoded = select(1.055 * pow(max(colour.rgb, 0.0), float3(1.0 / 2.4)) - 0.055,
                                12.92 * colour.rgb, colour.rgb <= 0.0031308);
        target.write(float4(encoded, colour.a), id);
    }

    // Cubic B-spline reconstruction removes visible low-resolution mip cells.
    // Four bilinear reads reconstruct one level; interpolate levels continuously.
    float4 cubicLevel(texture2d<float> image, float2 uv, uint lod) {
        constexpr sampler s(filter::linear, mip_filter::nearest, address::clamp_to_edge);
        float2 size = float2(image.get_width(lod), image.get_height(lod));
        float2 p = uv * size - 0.5;
        float2 base = floor(p), f = fract(p), inv = 1.0 - f;
        float2 w0 = inv * inv * inv / 6.0;
        float2 w1 = (3.0*f*f*f - 6.0*f*f + 4.0) / 6.0;
        float2 w2 = (-3.0*f*f*f + 3.0*f*f + 3.0*f + 1.0) / 6.0;
        float2 w3 = f*f*f / 6.0;
        float2 g0 = w0 + w1, g1 = w2 + w3;
        float2 lo = (base - 0.5 + w1 / g0) / size;
        float2 hi = (base + 1.5 + w3 / g1) / size;
        return image.sample(s, float2(lo.x, lo.y), level(lod)) * g0.x * g0.y
             + image.sample(s, float2(hi.x, lo.y), level(lod)) * g1.x * g0.y
             + image.sample(s, float2(lo.x, hi.y), level(lod)) * g0.x * g1.y
             + image.sample(s, float2(hi.x, hi.y), level(lod)) * g1.x * g1.y;
    }

    float4 softSample(texture2d<float> image, float2 uv, float lod, float maxLevel) {
        constexpr sampler s(filter::linear, mip_filter::linear, address::clamp_to_edge);
        // Compensate slightly for the reconstruction filter's own softness.
        lod = clamp(lod - 0.2 * smoothstep(1.0, 3.0, lod), 0.0, maxLevel);
        if (lod <= 1.0) { return image.sample(s, uv, level(lod)); }
        uint low = uint(floor(lod)), high = min(low + 1, uint(maxLevel));
        float4 smooth = mix(cubicLevel(image, uv, low), cubicLevel(image, uv, high), fract(lod));
        if (lod >= 2.0) { return smooth; }
        return mix(image.sample(s, uv, level(lod)), smooth, smoothstep(1.0, 2.0, lod));
    }

    vertex float4 depthVertex(uint vertexID [[vertex_id]]) {
        const float2 corners[3] = { float2(-1.0, -3.0), float2(-1.0, 1.0), float2(3.0, 1.0) };
        return float4(corners[vertexID], 0.0, 1.0);
    }

    fragment float4 depthFragment(float4 position [[position]],
                                   constant Uniforms &uniforms [[buffer(0)]],
                                   texture2d<float> picture [[texture(0)]]) {
        constexpr sampler linearSampler(filter::linear, mip_filter::linear, max_anisotropy(8), address::clamp_to_edge);

        float2 screenSize = uniforms.screenAndOrigin.xy;
        float2 paddedOrigin = uniforms.screenAndOrigin.zw;
        float2 paddedSize = uniforms.paddedAndBlur.xy;
        float maxRadius = uniforms.paddedAndBlur.z;
        float strength = uniforms.paddedAndBlur.w;
        float blurFloor = uniforms.shape.x;
        float maxDim = uniforms.shape.y;
        float pixelScale = uniforms.shape.z;
        float maxLevel = uniforms.shape.w;
        float dimFloor = uniforms.light.x;
        float dimStrength = uniforms.light.y;
        float dimReach = uniforms.light.z;

        // Fragment coordinates are pixels with y down; the geometry is points
        // with y up.
        float2 screenPoint = float2(position.x / pixelScale,
                                    screenSize.y - position.y / pixelScale);

        float3x3 screenToPicture = float3x3(uniforms.column0.xyz,
                                            uniforms.column1.xyz,
                                            uniforms.column2.xyz);
        float height = clamp(screenPoint.y / screenSize.y, 0.0, 1.0);
        float blur = strength * (blurFloor + (1.0 - blurFloor) * height);
        float radius = max(blur * maxRadius, 1.0);

        // A frosted continuation fills the panel beyond the held image. It is
        // sampled from the same frame and pyramid, with no second capture.
        float2 baseUnit = (screenPoint - paddedOrigin) / paddedSize;
        float2 baseUV = float2(baseUnit.x, 1.0 - baseUnit.y);
        float backgroundLevel = clamp(log2(max(strength * maxRadius * 1.6, 1.0)), 0.0, maxLevel);
        float4 background = softSample(picture, baseUV, backgroundLevel, maxLevel);

        float3 mapped = screenToPicture * float3(screenPoint, 1.0);
        float4 colour = background;
        if (mapped.z > 0.001) {
            float2 picturePoint = mapped.xy / mapped.z;
            float2 unit = (picturePoint - paddedOrigin) / paddedSize;
            float2 texCoord = float2(unit.x, 1.0 - unit.y);
            float2 dx = (uniforms.column0.xy - picturePoint * uniforms.column0.z) / mapped.z;
            float2 dy = (uniforms.column1.xy - picturePoint * uniforms.column1.z) / mapped.z;
            // Measure distance to the projected outline on the physical glass.
            // A centred feather softens both sides without moving the boundary.
            float sideDistance = min(picturePoint.x, screenSize.x - picturePoint.x)
                / max(length(float2(dx.x, dy.x)), 0.0001);
            float endDistance = min(picturePoint.y, screenSize.y - picturePoint.y)
                / max(length(float2(dx.y, dy.y)), 0.0001);
            float outlineDistance = min(sideDistance, endDistance);
            float edgeWidth = min(24.0, maxRadius / pixelScale * 0.75) * sqrt(strength);
            float feather = max(edgeWidth, 0.5 / pixelScale);
            float edgeBand = 1.0 - smoothstep(0.0, 2.0 * feather, abs(outlineDistance));
            radius = max(radius, edgeWidth * pixelScale * 0.7 * edgeBand);
            float edgeFade = strength > 0.00001 ? smoothstep(-feather, feather, outlineDistance) : 1.0;
            float sideCoverage = strength > 0.00001 ? smoothstep(-feather, feather, sideDistance) : 1.0;
            float2 uvPerPoint = float2(1.0, -1.0) / paddedSize;
            float2 gx = dx * uvPerPoint * radius / pixelScale;
            float2 gy = dy * uvPerPoint * radius / pixelScale;
            float4 held;
            float footprint = max(length(dx), length(dy));
            float blurLevel = log2(max(radius * footprint, 1.0));
            if (radius > 2.0 && blurLevel > 1.0) {
                float4 filtered = softSample(picture, texCoord, blurLevel, maxLevel);
                if (radius >= 4.0) { held = filtered; }
                else {
                    float4 sharp = picture.sample(linearSampler, texCoord, gradient2d(gx, gy));
                    held = mix(sharp, filtered, smoothstep(2.0, 4.0, radius));
                }
            } else {
                held = picture.sample(linearSampler, texCoord, gradient2d(gx, gy));
            }
            // Fade into frost before a grazing view can expose giant texels.
            // Singular values detect magnification in any direction, not just x/y.
            float aa = dot(dx, dx), bb = dot(dy, dy), ab = dot(dx, dy);
            float smallest = sqrt(max(0.0, 0.5 * (aa + bb - sqrt(max(0.0, (aa-bb)*(aa-bb) + 4.0*ab*ab)))));
            float detailFade = smoothstep(0.35, 0.75, smallest);
            colour = mix(background, held, edgeFade * detailFade);
            // Apply closing shadows after compositing, avoiding a double mask
            // that pinches the image inward. Opening keeps its frosted surround.
            colour.rgb *= mix(1.0, sideCoverage, uniforms.light.w);
        }
        // smoothstep rather than a clamped ratio, so the height where the
        // dimming reaches full strength leaves no visible edge.
        float spread = smoothstep(0.0, max(dimReach, 0.02), height);
        float fade = dimStrength * (dimFloor + (1.0 - dimFloor) * spread);
        // The sample is linear light. Raising the factor to 2.2 keeps the
        // dimming setting a fraction of the encoded brightness.
        colour.rgb *= pow(1.0 - maxDim * fade, 2.2);
        return float4(colour.rgb, 1.0);
    }
    """
}
