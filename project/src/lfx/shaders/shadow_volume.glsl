#pragma language glsl4

// Copyright 2026 Natalie Baker // AGPLv3 //

struct ShadowSegment {
    vec2 pntA;
    vec2 pntB;

    vec2 dir1;
    vec2 dir2;
    vec2 dir3;

    float len1;
    float len2;
    float len3;
};

layout(std430) readonly buffer ShadowSegments {
    ShadowSegment segments[];
};

uniform float CasterHeight;

uniform mat4  ViewMatrix;

uniform vec3  LightOrigin;
uniform float LightRadius;

varying float height;

#ifdef VERTEX

vec2 dirToWorld(vec2 v) {
    return (TransformMatrix*vec4(v,0,0)).xy;
}

vec2 pointToWorld(vec2 v) {
    return (TransformMatrix*vec4(v,0,1)).xy;
}

vec2 projectOntoSegment(
    vec2  pnt,
    vec2  segStart,
    vec2  segDir,
    float segLen
) {
    float dp = clamp(dot(segDir, pnt - segStart), 0, segLen);
    return segStart + segDir*dp;
}

float projectPoint(
    vec2  lightOrigin, 
    float lightRadius,
    vec2  segStart,
    vec2  segLight
) {
    vec2 ab = segLight - lightOrigin;
    float projFactor = lightRadius * length(ab);
    return projFactor/dot(ab, segStart - lightOrigin);
}


float projectShadowPointsMulLimit(
    vec2  lightOrigin, 
    float lightRadius,
    vec2  segStart, 
    vec2  segDirA, float segLenA, 
    vec2  segDirB, float segLenB
) {
    vec2 segLightA = projectOntoSegment(lightOrigin, segStart, segDirA, segLenA);
    vec2 segLightB = projectOntoSegment(lightOrigin, segStart, segDirB, segLenB);
    float multA = projectPoint(lightOrigin, lightRadius, segStart, segLightA);
    float multB = projectPoint(lightOrigin, lightRadius, segStart, segLightB);
    return max(multA, multB);
}

vec3 shadowMainInf(vec3 lightOrigin, float lightRadius, int segmentId, int quadTriId, vec3 vertexWorld) {

    float lenA = segments[segmentId].len2;

    vec2 dirA = dirToWorld(float[]( 1, 1,-1, 1,-1,-1)[quadTriId]*segments[segmentId].dir2);

    float lenB = float[](
        segments[segmentId].len1, segments[segmentId].len1, segments[segmentId].len3,
        segments[segmentId].len1, segments[segmentId].len3, segments[segmentId].len3
    )[quadTriId];

    vec2 dirB = dirToWorld(vec2[](
        -segments[segmentId].dir1, -segments[segmentId].dir1,  segments[segmentId].dir3,
        -segments[segmentId].dir1,  segments[segmentId].dir3,  segments[segmentId].dir3
    )[quadTriId]);

    vec3  fromLight    = vertexWorld - lightOrigin;
    float fromLightLen = length(fromLight);
    vec3  fromLightDir = fromLight/fromLightLen;

    float mult = max(1.01, projectShadowPointsMulLimit(
        lightOrigin.xy,
        lightRadius*1.05,
        vertexWorld.xy,
        dirA, lenA,
        dirB, lenB
    )*max(fromLightLen, 1e-4));//fromLightDir.z >= 0 ? multLim :  min(multCast, multLim));

    return vertexWorld + vec3(fromLightDir.xy, fromLightDir.z)*mult;
}

void vertexmain() {

    ////////////////////
    //
    // CA---------CB
    //  |        /|
    //  |      /  |
    //  |    /    |
    //  |  /      |
    //  |/        |
    // OA========>OB
    //  |         |
    //  v         v
    // D1         D3
    //
    // OA = Original A
    // OB = Original BvertexWorldFinal
    // CA = Cast A
    // CB = Cast B
    // =>  = Dir 2 / Segment
    // D1  = Dir 1
    // D3  = Dir 3
    //
    // Tri1 OA, CA, CB
    // Tri2 OA, CB, OB
    //
    ////////////////////

    int quadTriId = love_VertexID % 6;
    int segmentId = love_VertexID / 6;

    vec2 vertexWorld = pointToWorld(vec2[](
        segments[segmentId].pntA, segments[segmentId].pntA, segments[segmentId].pntB,
        segments[segmentId].pntA, segments[segmentId].pntB, segments[segmentId].pntB
    )[quadTriId]);
    
    vec2 normal     = dirToWorld(vec2(-segments[segmentId].dir2.y, segments[segmentId].dir2.x));
    vec2 lightDelta = LightOrigin.xy - vertexWorld.xy;

    vec4 vertexWorldFinal = vec4(vertexWorld.xy, max(CasterHeight, 0), 1);
    if ((float[](0,1,1, 0,1,0)[quadTriId] != 0) && (dot(normal, lightDelta) <= 0)) {
        vertexWorldFinal = vec4(
            shadowMainInf(
                LightOrigin,
                LightRadius,
                segmentId,
                quadTriId,
                vec3(vertexWorld, max(CasterHeight, 0))
            ),
            1
        );
    } 
    height = vertexWorldFinal.z;
    love_Position = ProjectionMatrix * ViewMatrix * vertexWorldFinal;
}

#endif


#ifdef PIXEL

layout(location = 0) out vec4 love_PixelColor;

void pixelmain() {
    love_PixelColor = vec4(height,CasterHeight,0,1);
}

#endif
