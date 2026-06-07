// Copyright 2026 Natalie Baker // AGPLv3 //

const float M_PI     = 3.1415926535897932384626433832795;
const float M_PI_INV = 0.3183098861837906715377675267450;

uniform mat4 ViewMatrix;

uniform Image TexAlbedo;
uniform Image TexMaterial;
uniform Image TexNormal;
uniform Image TexShadow;

uniform vec3  LightPosition;
uniform float LightRadius;
uniform vec3  LightColor;

varying vec2 FragmentPosition;
varying vec2 FragmentTexCoord;

#ifdef VERTEX

layout(location = 0) in vec2 VertexPosition;

void vertexmain() {
    vec4 vertexPosition = TransformMatrix * vec4(VertexPosition, 0, 1);
    FragmentPosition = vertexPosition.xy;
    love_Position = ProjectionMatrix * ViewMatrix * vertexPosition;
    FragmentTexCoord = 0.5+0.5*love_Position.xy;
    FragmentTexCoord.y = 1-FragmentTexCoord.y;
}

#endif

#ifdef PIXEL

layout(location = 0) out vec4 OutAccum;

vec3 hemiOctToNorm(vec2 e) {
    vec2 t = vec2(e.x+e.y, e.x-e.y)*0.5;
    vec3 v = vec3(t, 1-abs(t.x)-abs(t.y));
    return normalize(v);
}

float lightAttenuation(float dist, float radius) {
    return 1/(1 + dist*dist) * (1-smoothstep(radius*0.5, radius, dist));
}

// Schlick’s Approximation Fresnel
vec3 termFresnel(vec3 dirView, vec3 dirHalf, vec3 albedo, float metalness) {
    vec3 f0 = mix(vec3(0.04), albedo, metalness);
    float cosTheta = max(dot(dirView, dirHalf), 0);
    float factor   = pow(1.0 - cosTheta, 5.0);
    return f0 + (1 - f0)*factor;
}

// GGX Normal Distribution
float termNormalDistribution(float dpNH, float alpha) {
    float alpha2 = alpha*alpha;
    float dpNH2 = dpNH*dpNH;
    float denom = dpNH2 * (alpha2-1) + 1;
    return alpha2/(M_PI * denom*denom);
}

// Schlick-GGX Geometric Shadowing G1
float termGeometricShadowingG1(float dpNX, float k) {
    return dpNX/(dpNX*(1-k) + k);
}

// GGX Geometric Shadowing
float termGeometricShadowing(
    float dpNV,
    float dpNL,
    float roughness
) {
    float r = roughness + 1;
    float k = (r*r)/8;
    return termGeometricShadowingG1(dpNV, k) * termGeometricShadowingG1(dpNL, k);
}

// Cook-Torrance
vec3 termSpecular(vec3 dirView, vec3 dirLight, vec3 dirNormal, vec3 dirHalf, float roughness, float metalness, vec3 f) {
    float alpha = roughness*roughness;

    float dpNL = dot(dirNormal, dirLight);
    float dpNV = dot(dirNormal, dirView );
    // Cook-Torrance only correct for DP > 0, prevent issues
    // with nearly 0 dot products where the camera or light
    // is close to 90 degrees from the normal.
    if ((dpNL < 1e-4) || (dpNV < 1e-4)) {
        return vec3(0.0);
    }

    float dpNH = max(dot(dirNormal, dirHalf ), 0);
    float d = termNormalDistribution(dpNH, alpha);
    float g = termGeometricShadowing(dpNV, dpNL, roughness);
    return (f*d*g)/(4*dpNL*dpNV);
}

void pixelmain() {
    vec4 sampA = Texel(TexAlbedo,   FragmentTexCoord).rgba;
    vec3 sampN = Texel(TexNormal,   FragmentTexCoord).xyz; 
    vec4 sampM = Texel(TexMaterial, FragmentTexCoord).rgba; 
    vec2 sampS = Texel(TexShadow,   FragmentTexCoord).rg;

    vec2 normalP = sampN.xy * 2 - 1;
    vec3 normal = normalize(vec3(
        normalP.x, 
        normalP.y,
        sqrt(max(0, 1 - dot(normalP, normalP))) 
    ));
    float height = sampN.z;
    vec3  albedo = sampA.rgb;
    float alpha  = sampA.a;
    float occlusion = sampM.r;
    float roughness = sampM.g;
    float metalness = sampM.b;

    float shadowHeight       = sampS.r;
    float shadowHeightCaster = sampS.g;
    float shadowMask         = 1-sign(shadowHeightCaster);

    vec2 shadowTerms = shadowHeight > height 
        ? vec2(
            0.5+shadowMask*0.5, // Indirect
            0.1+shadowMask*0.9  // Direct
        ) 
        : vec2(1);

    vec3 viewDir = vec3(0,0,1);

    vec3 lightDelta = LightPosition - vec3(FragmentPosition, height);
    lightDelta.z = sign(lightDelta.z) * max(abs(lightDelta.z), 1e-2);

    float lightDist = length(lightDelta);
    vec3 lightDir   = lightDelta/lightDist;
    vec3 lightIntensity = LightColor*lightAttenuation(lightDist, LightRadius);

    vec3 halfDir = normalize(lightDir + viewDir);

    vec3 fresnel  = max(termFresnel(viewDir, halfDir, albedo, metalness), 0.0); 
    vec3 specular = max(shadowTerms.y*termSpecular(viewDir, lightDir, normal, halfDir, roughness, metalness, fresnel), 0.0);

    float ambientSplit = 0.1;

    vec3 kd = (1-ambientSplit)*(1-fresnel) * (1-metalness);
    vec3 diffuse = max(kd*albedo*M_PI_INV, 0.0);

    vec3 ka = ambientSplit*(1-fresnel)*(1-metalness);
    vec3 ambient = ka*albedo*M_PI_INV;

    float incidence = max(dot(normal, lightDir), 0.0);
    vec3   directLighting = incidence*lightIntensity*(diffuse+specular);
    vec3 indirectLighting = occlusion*lightIntensity*ambient;
    OutAccum = vec4(
        shadowTerms.x*indirectLighting + shadowTerms.y*directLighting, 
        alpha
    );
}

#endif
