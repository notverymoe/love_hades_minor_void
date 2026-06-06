#pragma language glsl4

// Copyright 2026 Natalie Baker // AGPLv3 //

uniform mat4 ViewMatrix;

uniform ArrayImage TexAlbedo;
uniform ArrayImage TexMaterial;
uniform ArrayImage TexNormal;

uniform vec4 PBRAlbedoTint;
uniform vec3 PBRProperties; // texId, height, heightScale

varying vec2 FragmentTexCoord;

#ifdef VERTEX

layout(location = 0) in vec2 VertexPosition;
layout(location = 1) in vec2 VertexTexCoord;

void vertexmain() {
    FragmentTexCoord = VertexTexCoord;

    vec4 vertex_world = TransformMatrix * vec4(VertexPosition, PBRProperties.x, 1);
    love_Position = ProjectionMatrix * ViewMatrix * vertex_world;
}

#endif

#ifdef PIXEL

layout(location = 0) out vec4 OutAlbedo;
layout(location = 1) out vec4 OutMaterial;
layout(location = 2) out vec4 OutNormal;

float mip_map_level(vec2 uv) {
    vec2 dx = dFdx(uv);
    vec2 dy = dFdy(uv);
    float delta_max_sqr = max(dot(dx, dx), dot(dy, dy));
    return 0.5 * log2(delta_max_sqr);
}

void pixelmain() {
    float level = mip_map_level(FragmentTexCoord);

    vec4 albedo   = Texel(TexAlbedo,   vec3(FragmentTexCoord, PBRProperties.x)).rgba;
    vec4 material = Texel(TexMaterial, vec3(FragmentTexCoord, PBRProperties.x)).rgba;
    vec2 normalXY = Texel(TexNormal,   vec3(FragmentTexCoord, PBRProperties.x)).rg;
    vec4 normal = normalize(TransformMatrix * vec4(
        normalXY.x, 
        normalXY.y,
        sqrt(max(0, 1 - dot(normalXY, normalXY))),
        0
    ));

    OutAlbedo   = PBRAlbedoTint*albedo;
    OutMaterial = vec4(material.rgb, 1);
    OutNormal   = vec4(normal.xy, PBRProperties.y + (1 - material.a)*PBRProperties.z, 1);
}

#endif
