// Copyright 2026 Natalie Baker // AGPLv3 //

uniform Image TexExposure;
uniform Image TexAccum;
uniform int   TexAccumMipCount;
uniform float MidtoneAdjustment;

uniform float ExposureMinEV;
uniform float ExposureFactor;

varying vec2 uv;

#ifdef VERTEX

void vertexmain() {
    vec2 pos = vec2((love_VertexID << 1) & 2, love_VertexID & 2);
    love_Position = vec4(pos * 2.0 - 1.0, 0.0, 1.0);
    uv = vec2(pos.x, 1-pos.y);
}

#endif

#ifdef PIXEL

layout(location = 0) out vec4 OutPixelColor;

vec3 tonemapAces(vec3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;

    vec3 num   = x*(a*x + b);
    vec3 denom = x*(c*x + d) + e;
    return clamp(num/denom, 0.0, 1.0);
}

void pixelmain() {
    float rawEV      = Texel(TexExposure, vec2(0.5)).r;
    float clampedEv  = max(ExposureMinEV, rawEV);
    float exposureEv = mix(rawEV, clampedEv, 0.5);
    float exposure   = ExposureFactor * exp2(-exposureEv);

    vec3 colorHDR = Texel(TexAccum, uv).rgb;
    vec3 colorSDR = clamp(tonemapAces(colorHDR * exposure), 0, 1);
    OutPixelColor = vec4(pow(colorSDR, vec3(1.0/MidtoneAdjustment)), 1);
}

#endif
