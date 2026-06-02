// ═══════════════════════════════════════════════════════════════════
//  Anchor decode + world-space cross marker   (ps_2_b)
// ═══════════════════════════════════════════════════════════════════
//  Same anchor-decode camera reconstruction as the cube shader.
//  Instead of ray-casting a 3D box, projects the target world point
//  into screen space and draws a fixed-pixel-size crosshair with a
//  dark outline for contrast.  World-locked: the cross sits at
//  TEST_CENTER and tracks correctly as you move and turn.
//
//  Debug bars (yaw green / pitch cyan) kept along the top.
//
//  Inputs:
//    TexBase        framebuffer
//    Tex1           _rt_Camera (4 anchor patches, 16-bit hi/lo in r/g)
//    Constants2.xyz player world position (un-scaled; POS_SCALE=1)
//    TexBaseSize    (1/w, 1/h) of the RT
// ═══════════════════════════════════════════════════════════════════

#include "common.hlsl"

// ── engine / anchor constants (same as cube shader) ──────────────
#define POS_SCALE     1
#define TAN_HALF_VFOV 0.75
static const float PI = 3.14159265;

static const float3 A1 = float3(8000.0,    0.0,    0.0);
static const float3 A2 = float3(   0.0, 8000.0,    0.0);
static const float3 A3 = float3(   0.0,    0.0, 8000.0);
static const float3 A4 = float3(8000.0, 8000.0, 8000.0);

#define ANCHOR_UV_4   float2(0.5000, 0.5000)
#define ANCHOR_UV_1   float2(0.1797, 0.6855)
#define ANCHOR_UV_2   float2(0.8203, 0.6836)
#define ANCHOR_UV_3   float2(0.5000, 0.1309)

// ── debug bars ───────────────────────────────────────────────────
#define YAW_BAR_Y0    0.04
#define YAW_BAR_Y1    0.07
#define PITCH_BAR_Y0  0.09
#define PITCH_BAR_Y1  0.12
#define BAR_X0        0.05
#define BAR_X1        0.95

// ── cross target ─────────────────────────────────────────────────
static const float3 TEST_CENTER = float3(400.0, 400.0, 125.0);

// ── cross appearance (all in pixels) ─────────────────────────────
#define CROSS_ARM_PX    12.0        // half-length of each arm
#define CROSS_THICK_PX   1.5        // half-thickness of each arm
#define CROSS_GAP_PX     3.0        // gap radius at center
#define OUTLINE_PX       1.0        // dark outline thickness
#define CROSS_COLOR     float3(0.35, 0.75, 1.0)   // cyan-blue
#define OUTLINE_COLOR   float3(0.0, 0.0, 0.0)

// ── viewmodel rejection ──────────────────────────────────────────
#define VM_EPSILON 0.5

// ═════════════════════════════════════════════════════════════════
//  Anchor readback helpers
// ═════════════════════════════════════════════════════════════════
float recon(float2 uv)
{
    float2 c = tex2D(Tex1, uv).rg;
    return c.r + c.g / 255.0;
}

float readCos(float2 uv)
{
    float2 t = float2(TexBaseSize.x, TexBaseSize.y);
    float s = recon(uv)
            + recon(uv + float2( 4, 0) * t)
            + recon(uv + float2(-4, 0) * t)
            + recon(uv + float2(0,  4) * t)
            + recon(uv + float2(0, -4) * t);
    return (s * 0.2) * 2.0 - 1.0;
}

// ═════════════════════════════════════════════════════════════════
//  Main
// ═════════════════════════════════════════════════════════════════
float4 main(PS_INPUT i) : COLOR
{
    // ── 1. decode view direction via anchor least-squares ────────
    float3 P = Constants2.xyz / POS_SCALE;

    float c1 = readCos(ANCHOR_UV_1);
    float c2 = readCos(ANCHOR_UV_2);
    float c3 = readCos(ANCHOR_UV_3);
    float c4 = readCos(ANCHOR_UV_4);

    float3 d1 = normalize(A1 - P);
    float3 d2 = normalize(A2 - P);
    float3 d3 = normalize(A3 - P);
    float3 d4 = normalize(A4 - P);

    // normal equations:  (D^T D) f = D^T c
    float m00 = d1.x*d1.x + d2.x*d2.x + d3.x*d3.x + d4.x*d4.x;
    float m11 = d1.y*d1.y + d2.y*d2.y + d3.y*d3.y + d4.y*d4.y;
    float m22 = d1.z*d1.z + d2.z*d2.z + d3.z*d3.z + d4.z*d4.z;
    float m01 = d1.x*d1.y + d2.x*d2.y + d3.x*d3.y + d4.x*d4.y;
    float m02 = d1.x*d1.z + d2.x*d2.z + d3.x*d3.z + d4.x*d4.z;
    float m12 = d1.y*d1.z + d2.y*d2.z + d3.y*d3.z + d4.y*d4.z;

    float3 b = c1*d1 + c2*d2 + c3*d3 + c4*d4;

    // cofactors of the symmetric 3x3
    float C00 = m11*m22 - m12*m12;
    float C11 = m00*m22 - m02*m02;
    float C22 = m00*m11 - m01*m01;
    float C01 = m02*m12 - m01*m22;
    float C02 = m01*m12 - m02*m11;
    float C12 = m02*m01 - m00*m12;

    float det = m00*C00 + m01*C01 + m02*C02;
    float invdet = 1.0 / (abs(det) < 1e-6 ? 1e-6 : det);   // singularity guard

    float3 f;
    f.x = (C00*b.x + C01*b.y + C02*b.z) * invdet;
    f.y = (C01*b.x + C11*b.y + C12*b.z) * invdet;
    f.z = (C02*b.x + C12*b.y + C22*b.z) * invdet;
    f = normalize(f);

    // ── 2. view basis (no roll, horizontal-only right vector) ───
    float2 fh  = normalize(f.xy);
    float3 right = float3(fh.y, -fh.x, 0.0);
    float3 up    = cross(right, f);

    // ── 3. project TEST_CENTER into screen UV ───────────────────
    float3 toTarget = TEST_CENTER - P;
    float viewZ = dot(toTarget, f);       // depth along forward
    float viewX = dot(toTarget, right);   // horizontal offset
    float viewY = dot(toTarget, up);      // vertical offset

    float4 base = tex2D(TexBase, i.uv);
    float3 col  = base.rgb;

    bool occludedByVM = (base.a < VM_EPSILON);

    // only draw when the point is in front of the camera
    if (viewZ > 0.0 && !occludedByVM)
    {
        // perspective divide -> NDC [-1, 1]
        float aspect = TexBaseSize.y / TexBaseSize.x;   // w / h
        float ndcX = viewX / (viewZ * TAN_HALF_VFOV * aspect);
        float ndcY = viewY / (viewZ * TAN_HALF_VFOV);

        // NDC -> UV [0, 1]
        float2 targetUV = float2(ndcX * 0.5 + 0.5,
                                 0.5 - ndcY * 0.5);

        // delta from this pixel to the projected point, in pixels
        // TexBaseSize = (1/w, 1/h), so dividing UV delta by it gives pixels
        float2 dpx = (i.uv - targetUV) / float2(TexBaseSize.x, TexBaseSize.y);
        float ax = abs(dpx.x);
        float ay = abs(dpx.y);

        // outer bounds = cross + outline
        float armO  = CROSS_ARM_PX  + OUTLINE_PX;
        float thkO  = CROSS_THICK_PX + OUTLINE_PX;
        float gapI  = max(CROSS_GAP_PX - OUTLINE_PX, 0.0);

        bool inHorizO = (ay < thkO)           && (ax < armO) && (ax > gapI);
        bool inVertO  = (ax < thkO)           && (ay < armO) && (ay > gapI);

        bool inHoriz  = (ay < CROSS_THICK_PX) && (ax < CROSS_ARM_PX) && (ax > CROSS_GAP_PX);
        bool inVert   = (ax < CROSS_THICK_PX) && (ay < CROSS_ARM_PX) && (ay > CROSS_GAP_PX);

        // draw outline first, then fill over it with the bright color
        if (inHorizO || inVertO)
            col = OUTLINE_COLOR;
        if (inHoriz || inVert)
            col = CROSS_COLOR;
    }

    // ── 4. debug bars ───────────────────────────────────────────
    float yaw   = -atan2(f.y, f.x);
    float pitch = -asin(f.z);
    float yawFill   = yaw   * (0.5 / PI) + 0.5;
    float pitchFill = pitch * (1.0 / PI) + 0.5;
    float barT = (i.uv.x - BAR_X0) / (BAR_X1 - BAR_X0);

    bool inYaw   = (i.uv.y >= YAW_BAR_Y0)   && (i.uv.y < YAW_BAR_Y1)
                && (i.uv.x >= BAR_X0)        && (i.uv.x < BAR_X1);
    bool inPitch = (i.uv.y >= PITCH_BAR_Y0)  && (i.uv.y < PITCH_BAR_Y1)
                && (i.uv.x >= BAR_X0)        && (i.uv.x < BAR_X1);

    if (inYaw)
        col = lerp(float3(0.10, 0.10, 0.10), float3(0.20, 0.95, 0.30),
                   step(barT, yawFill));
    if (inPitch)
        col = lerp(float3(0.10, 0.10, 0.10), float3(0.25, 0.75, 0.95),
                   step(barT, pitchFill));

    return float4(col, 1);
}
