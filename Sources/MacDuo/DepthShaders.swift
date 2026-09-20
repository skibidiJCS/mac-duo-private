import Foundation

/// The whole effect in one fragment shader.
///
/// Each screen pixel maps back into the picture through the inverse
/// perspective, then takes one sample from a centered blur pyramid at a level
/// chosen by the blur wanted there. The texture already holds the picture on
/// black, so the two blur together and the picture edge needs no special
/// handling.
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
        float4 light;            // dim floor, dim strength, dim reach, unused
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

    vertex float4 depthVertex(uint vertexID [[vertex_id]]) {
        const float2 corners[3] = { float2(-1.0, -3.0), float2(-1.0, 1.0), float2(3.0, 1.0) };
        return float4(corners[vertexID], 0.0, 1.0);
    }

    fragment float4 depthFragment(float4 position [[position]],
                                   constant Uniforms &uniforms [[buffer(0)]],
                                   texture2d<float> picture [[texture(0)]]) {
        constexpr sampler linearSampler(filter::linear, mip_filter::linear, address::clamp_to_edge);

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
        float3 mapped = screenToPicture * float3(screenPoint, 1.0);
        if (abs(mapped.z) < 1e-6) { return float4(0.0, 0.0, 0.0, 1.0); }
        float2 picturePoint = mapped.xy / mapped.z;

        float2 unit = (picturePoint - paddedOrigin) / paddedSize;
        if (unit.x < 0.0 || unit.x > 1.0 || unit.y < 0.0 || unit.y > 1.0) {
            return float4(0.0, 0.0, 0.0, 1.0);
        }
        float2 texCoord = float2(unit.x, 1.0 - unit.y);

        // Frost belongs to the physical glass, not the projected desktop.
        float height = clamp(screenPoint.y / screenSize.y, 0.0, 1.0);
        float blur = strength * (blurFloor + (1.0 - blurFloor) * height);
        // Naming this `level` would shadow Metal's level() selector.
        // Convert a radius on the glass to source texels. Opening can magnify
        // the picture; using an unadjusted source radius magnifies its blur too.
        float2 texelsPerPoint = float2(picture.get_width(), picture.get_height()) / paddedSize;
        float2 dx = (uniforms.column0.xy - picturePoint * uniforms.column0.z) / mapped.z;
        float2 dy = (uniforms.column1.xy - picturePoint * uniforms.column1.z) / mapped.z;
        float footprint = max(length(dx * texelsPerPoint), length(dy * texelsPerPoint)) / pixelScale;
        float mipLevel = clamp(log2(max(max(blur * maxRadius, 1.0) * footprint, 1.0)), 0.0, maxLevel);

        float4 colour = picture.sample(linearSampler, texCoord, level(mipLevel));
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
