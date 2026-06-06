// Copyright 2026 Natalie Baker // AGPLv3 //

uniform Image TexSource;

varying vec2 uv;

#ifdef VERTEX

void vertexmain() {
    vec2 pos = vec2((love_VertexID << 1) & 2, love_VertexID & 2);
    love_Position = vec4(pos * 2.0 - 1.0, 0.0, 1.0);
    uv = vec2(pos.x, 1-pos.y);
}

#endif

#ifdef PIXEL

layout(location = 0) out vec4 OutColour;

void pixelmain() {
    OutColour = Texel(TexSource, uv);
}

#endif
