// Copyright 2026 Natalie Baker // AGPLv3 //

uniform Image TexExposureAvg;

uniform Image TexExposureP;
uniform float DeltaTime;
uniform float ExposureSpeed;

varying vec2 uv;

#ifdef VERTEX

void vertexmain() {
    vec2 pos = vec2((love_VertexID << 1) & 2, love_VertexID & 2);
    love_Position = vec4(pos * 2.0 - 1.0, 0.0, 1.0);
    uv = vec2(pos.x, 1-pos.y);
}

#endif

#ifdef PIXEL

layout(location = 0) out vec4 OutExposure;

float calcNextEV(float speed, float dt, float prevEV, float avgEv) {
    return mix(prevEV, avgEv, 1.0 - exp(-speed * dt));
}

void pixelmain() {
    float avgLum = max(Texel(TexExposureAvg, vec2(0.5)).r, 1e-4);
    float  avgEv = log2(avgLum);
    float prevEV = Texel(TexExposureP,   vec2(0.5)).r;
    float nextEV = calcNextEV(ExposureSpeed, DeltaTime, prevEV, avgEv);
    OutExposure = vec4(nextEV, nextEV, nextEV, 1);
}

#endif
