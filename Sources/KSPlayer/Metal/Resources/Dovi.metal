//
//  Shaders.metal
#include <metal_stdlib>
using namespace metal;
#import "Utility.metal"

struct dovi_metadata {
    // Colorspace transformation metadata
    float3x3 nonlinear;     // before PQ, also called "ycc_to_rgb"
    float3x3 linear;        // after PQ, also called "rgb_to_lms"
    simd_float3 nonlinear_offset;  // input offset ("ycc_to_rgb_offset")
    float minLuminance;
    float maxLuminance;
    struct reshape_data {
        float4 coeffs[8];
        float4 mmr[8*6];
        float pivots[7];
        float lo;
        float hi;
        uint8_t min_order;
        uint8_t max_order;
        uint8_t num_pivots;
        bool has_poly;
        bool has_mmr;
        bool mmr_single;
    } comp[3];
};

float reshape_mmr(float3 sig, float4 coeffs, float4 mmr[48], bool single, int min_order, int max_order)
{
    uint mmr_idx = 0;
    if (!single) {
        mmr_idx = coeffs.y;
    }
    if (min_order < max_order) {
        uint order = coeffs.w;
    }
    float s = coeffs.x;
    float4 sigX;
    s = coeffs.x;
    sigX.xyz = sig.xxy * sig.yzz;
    sigX.w = sigX.x * sig.z;
    s += dot(mmr[mmr_idx + 0].xyz, sig);
    s += dot(mmr[mmr_idx + 1], sigX);
    if (max_order >= 2) {
        float3 sig2 = sig * sig;
        float4 sigX2 = sigX * sigX;
        s += dot(mmr[mmr_idx + 2].xyz, sig2);
        s += dot(mmr[mmr_idx + 3], sigX2);
        if (max_order == 3) {
            if (min_order < 3) {
                s += dot(mmr[mmr_idx + 4].xyz, sig2 * sig);
                s += dot(mmr[mmr_idx + 5], sigX2 * sigX);
            }
        }
    }
    return s;
}

float reshape_poly(float s, float4 coeffs)
{
    s = (coeffs.z * s + coeffs.y) * s + coeffs.x;
    return s;
}
#define pivot(i) float4(bool4(s >= data.pivots[i]))
#define coef(i) data.coeffs[i]
float reshape(float3 sig, float s, dovi_metadata::reshape_data data) {
    float4 coeffs;
    if (data.num_pivots > 2) {
        coeffs = mix(mix(mix(coef(0), coef(1), pivot(0)),
                         mix(coef(2), coef(3), pivot(2)),
                         pivot(1)),
                     mix(mix(coef(4), coef(5), pivot(4)),
                         mix(coef(6), coef(7), pivot(6)),
                         pivot(5)),
                     pivot(3));
    } else {
        coeffs = data.coeffs[0];
    }
    // 先默认用poly，不用mmr。 不然有逻辑判断会很卡。后续想下要怎么优化。
    s = reshape_poly(s, coeffs);
    return clamp(s, data.lo, data.hi);
}

float3 reshape3(float3 rgb, constant dovi_metadata::reshape_data data[3]) {
    float3 sig = clamp(rgb, 0.0, 1.0);
    return float3(reshape(sig, sig.r, data[0]), reshape(sig, sig.g, data[1]), reshape(sig, sig.b, data[2]));
}

fragment float4 displayICtCpTexture(VertexOut in [[ stage_in ]],
                                    texture2d<half> yTexture [[ texture(0) ]],
                                    texture2d<half> uTexture [[ texture(1) ]],
                                    texture2d<half> vTexture [[ texture(2) ]],
                                    sampler textureSampler [[ sampler(0) ]],
                                    constant dovi_metadata& data [[ buffer(0) ]],
                                    constant uchar3& leftShift [[ buffer(1) ]])
{
    float3 rgb;
    rgb.x = yTexture.sample(textureSampler, in.textureCoordinate).r;
    rgb.y = uTexture.sample(textureSampler, in.textureCoordinate).r;
    rgb.z = vTexture.sample(textureSampler, in.textureCoordinate).r;
    rgb = reshape3(rgb, data.comp);
    rgb = rgb*float3(leftShift);
    rgb = data.nonlinear*(rgb + data.nonlinear_offset);
    rgb = pqEOTF(rgb);
    rgb = data.linear*rgb;
    rgb = pqOETF(rgb);
    return float4(rgb, 1);
}

fragment float4 displayICtCpBiPlanarTexture(VertexOut in [[ stage_in ]],
                                            texture2d<half> lumaTexture [[ texture(0) ]],
                                            texture2d<half> chromaTexture [[ texture(1) ]],
                                            sampler textureSampler [[ sampler(0) ]],
                                            constant dovi_metadata& data [[ buffer(0) ]],
                                            constant uchar3& leftShift [[ buffer(1) ]])
{
    float3 rgb;
    rgb.x = lumaTexture.sample(textureSampler, in.textureCoordinate).r;
    rgb.yz = float2(chromaTexture.sample(textureSampler, in.textureCoordinate).rg);
    rgb = reshape3(rgb, data.comp);
    rgb = rgb*float3(leftShift);
    rgb = data.nonlinear*(rgb + data.nonlinear_offset);
    rgb = pqEOTF(rgb);
    rgb = data.linear*rgb;
    rgb = pqOETF(rgb);
    return float4(rgb, 1);
    //    float3 colorOffset = {0, -128.0 / 255.0, -128.0 / 255.0};
    //    float3x3 yuvToBGRMatrix = {{1, 0.0, 1.5748},
    //        {1, -0.18732426, -0.46812427},
    //        {1,  1.8556, 0.0}};
    //    return float4(yuvToBGRMatrix*(rgb+colorOffset), 1);

}
