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
    vec2 pnt,
    vec2 segStart,
    vec2 segDir,
    float segLen
) {
    float dp = clamp(dot(segDir, pnt - segStart), 0, segLen);
    return segStart + segDir*dp;
}

float projectPoint(
    vec2  lightOrigin, 
    float lightRadius,
    vec2 segStart,
    vec2 segLight
) {
    vec2 ab = segLight - lightOrigin;
    float projFactor = lightRadius * length(ab);
    return projFactor/dot(ab, segStart - lightOrigin);
}


float projectShadowPointsMulLimit(
    vec2  lightOrigin, 
    float lightRadius,
    vec2 segStart, 
    vec2 segdir_a, float seglen_a, 
    vec2 segdir_b, float seglen_b
) {
    vec2 segLightA = projectOntoSegment(lightOrigin, segStart, segdir_a, seglen_a);
    vec2 segLightB = projectOntoSegment(lightOrigin, segStart, segdir_b, seglen_b);
    float multA = projectPoint(lightOrigin, lightRadius, segStart, segLightA);
    float multB = projectPoint(lightOrigin, lightRadius, segStart, segLightB);
    return max(multA, multB);
}

vec3 shadowMainInf(vec3 lightOrigin, float lightRadius, int segment_id, int quadtri_id, vec3 vertex_world) {

    float len_a = segments[segment_id].len2;

    vec2 dir_a = dirToWorld(float[]( 1, 1,-1, 1,-1,-1)[quadtri_id]*segments[segment_id].dir2);

    float len_b = float[](
        segments[segment_id].len1, segments[segment_id].len1, segments[segment_id].len3,
        segments[segment_id].len1, segments[segment_id].len3, segments[segment_id].len3
    )[quadtri_id];

    vec2 dir_b = dirToWorld(vec2[](
        -segments[segment_id].dir1, -segments[segment_id].dir1,  segments[segment_id].dir3,
        -segments[segment_id].dir1,  segments[segment_id].dir3,  segments[segment_id].dir3
    )[quadtri_id]);

    vec3  from_light     = vertex_world - lightOrigin;
    float from_light_len = length(from_light);
    vec3  from_light_dir = from_light/from_light_len;

    float mult = max(1.01, projectShadowPointsMulLimit(
        lightOrigin.xy,
        lightRadius*1.05,
        vertex_world.xy,
        dir_a, len_a,
        dir_b, len_b
    )*max(from_light_len, 1e-4));//from_light_dir.z >= 0 ? multLim :  min(multCast, multLim));

    return vertex_world + vec3(from_light_dir.xy, from_light_dir.z)*mult;
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
    // OB = Original B
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

    int quadtri_id = love_VertexID % 6;
    int segment_id = love_VertexID / 6;

    vec2 vertex_world = pointToWorld(vec2[](
        segments[segment_id].pntA, segments[segment_id].pntA, segments[segment_id].pntB,
        segments[segment_id].pntA, segments[segment_id].pntB, segments[segment_id].pntB
    )[quadtri_id]);
    
    vec2 normal      = dirToWorld(vec2(-segments[segment_id].dir2.y, segments[segment_id].dir2.x));
    vec2 light_delta = LightOrigin.xy - vertex_world.xy;

    vec4 vertex_world_final = vec4(vertex_world.xy, max(CasterHeight, 0), 1);
    if ((float[](0,1,1, 0,1,0)[quadtri_id] != 0) && (dot(normal, light_delta) <= 0)) {
        vertex_world_final = vec4(
            shadowMainInf(
                LightOrigin,
                LightRadius,
                segment_id,
                quadtri_id,
                vec3(vertex_world, max(CasterHeight, 0))
            ),
            1
        );
    } 
    height = vertex_world_final.z;
    love_Position = ProjectionMatrix * ViewMatrix * vertex_world_final;
}

#endif


#ifdef PIXEL

layout(location = 0) out vec4 love_PixelColor;

void pixelmain() {
    love_PixelColor = vec4(height,CasterHeight,0,1);
}

#endif
