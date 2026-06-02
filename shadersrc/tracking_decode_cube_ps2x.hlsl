// ═══════════════════════════════════════════════════════════════════
//  Pass 1 — Glowing world-space cube with edge highlights + encode
// ═══════════════════════════════════════════════════════════════════
//  Renders a lit, edge-highlighted cube via ray-box intersection and
//  encodes the cube's screen-space center into pixels (0,0) and (1,0)
//  for pass 2 (black-hole warp).
//
//  Encode layout:
//    pixel (0,0)  R = centerUV.x hi, G = lo, B = valid flag (1=visible)
//    pixel (1,0)  R = centerUV.y hi, G = lo, B = valid flag
//    decode:  hi + lo / 255.0  →  screen UV [0,1]
//
//  Inputs:
//    TexBase          framebuffer
//    Tex1             _rt_Camera (anchor patches)
//    Constants0.xyz   cube world position (from $c0_x/y/z via proxy)
//    Constants2.xyz   player world position
//    TexBaseSize      (1/w, 1/h)
// ═══════════════════════════════════════════════════════════════════

#include "common.hlsl"

#define POS_SCALE     1
#define TAN_HALF_VFOV 0.75
static const float PI = 3.14159265;

// ── anchors ──────────────────────────────────────────────────────
static const float3 A1 = float3(8000.0,    0.0,    0.0);
static const float3 A2 = float3(   0.0, 8000.0,    0.0);
static const float3 A3 = float3(   0.0,    0.0, 8000.0);
static const float3 A4 = float3(8000.0, 8000.0, 8000.0);

#define ANCHOR_UV_1   float2(0.1797, 0.6855)
#define ANCHOR_UV_2   float2(0.8203, 0.6836)
#define ANCHOR_UV_3   float2(0.5000, 0.1309)
#define ANCHOR_UV_4   float2(0.5000, 0.5000)

// ── cube ─────────────────────────────────────────────────────────
static float3  TEST_CENTER = float3(Constants0.x, Constants0.y, Constants0.z);
static const float3 TEST_HALF = float3(60.0, 60.0, 60.0);

// ── look ─────────────────────────────────────────────────────────
#define FACE_COLOR    float3(0.40, 0.72, 0.95)          // cool blue faces
#define EDGE_COLOR    float3(0.90, 0.97, 1.00)          // hot white-cyan edges
#define GLOW_COLOR    float3(0.35, 0.75, 1.00)          // outer halo
#define GLOW_WIDTH    90.0
#define GLOW_STRENGTH 0.85
#define EDGE_WIDTH    0.10                               // fraction of half-extent
#define FACE_OPACITY  0.65                               // face see-through amount
static const float3 LIGHT_DIR = float3(0.577, 0.577, -0.577);   // ≈ normalize(1,1,-1)

#define VM_EPSILON    0.5

// ═════════════════════════════════════════════════════════════════
//  Anchor helpers
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
//  Ray vs AABB (slab method)
// ═════════════════════════════════════════════════════════════════
float2 rayBox(float3 ro, float3 rd, float3 bmin, float3 bmax)
{
    float3 inv   = 1.0 / rd;
    float3 t0    = (bmin - ro) * inv;
    float3 t1    = (bmax - ro) * inv;
    float3 tsmall = min(t0, t1);
    float3 tbig   = max(t0, t1);
    float tNear = max(max(tsmall.x, tsmall.y), tsmall.z);
    float tFar  = min(min(tbig.x,   tbig.y),   tbig.z);
    return float2(tNear, tFar);
}

// ═════════════════════════════════════════════════════════════════
//  Main
// ═════════════════════════════════════════════════════════════════
float4 main(PS_INPUT i) : COLOR
{
    // ── 1. anchor decode ────────────────────────────────────────
    float3 P = Constants2.xyz / POS_SCALE;

    float c1 = readCos(ANCHOR_UV_1);
    float c2 = readCos(ANCHOR_UV_2);
    float c3 = readCos(ANCHOR_UV_3);
    float c4 = readCos(ANCHOR_UV_4);

    float3 d1 = normalize(A1 - P);
    float3 d2 = normalize(A2 - P);
    float3 d3 = normalize(A3 - P);
    float3 d4 = normalize(A4 - P);

    float m00 = d1.x*d1.x + d2.x*d2.x + d3.x*d3.x + d4.x*d4.x;
    float m11 = d1.y*d1.y + d2.y*d2.y + d3.y*d3.y + d4.y*d4.y;
    float m22 = d1.z*d1.z + d2.z*d2.z + d3.z*d3.z + d4.z*d4.z;
    float m01 = d1.x*d1.y + d2.x*d2.y + d3.x*d3.y + d4.x*d4.y;
    float m02 = d1.x*d1.z + d2.x*d2.z + d3.x*d3.z + d4.x*d4.z;
    float m12 = d1.y*d1.z + d2.y*d2.z + d3.y*d3.z + d4.y*d4.z;

    float3 b = c1*d1 + c2*d2 + c3*d3 + c4*d4;

    float C00 = m11*m22 - m12*m12;
    float C11 = m00*m22 - m02*m02;
    float C22 = m00*m11 - m01*m01;
    float C01 = m02*m12 - m01*m22;
    float C02 = m01*m12 - m02*m11;
    float C12 = m02*m01 - m00*m12;

    float det    = m00*C00 + m01*C01 + m02*C02;
    float invdet = 1.0 / (abs(det) < 1e-6 ? 1e-6 : det);

    float3 f;
    f.x = (C00*b.x + C01*b.y + C02*b.z) * invdet;
    f.y = (C01*b.x + C11*b.y + C12*b.z) * invdet;
    f.z = (C02*b.x + C12*b.y + C22*b.z) * invdet;
    f = normalize(f);

    // ── 2. view basis ───────────────────────────────────────────
    float2 fh    = normalize(f.xy);
    float3 right = float3(fh.y, -fh.x, 0.0);
    float3 up    = cross(right, f);

    // ── 3. project cube centre → screen UV (for pass 2) ────────
    float3 toTarget = TEST_CENTER - P;
    float viewZ = dot(toTarget, f);
    float viewX = dot(toTarget, right);
    float viewY = dot(toTarget, up);
    bool  cubeVisible = (viewZ > 0.0);

    float2 centerUV = float2(0.0, 0.0);
    if (cubeVisible)
    {
        float aspect = TexBaseSize.y / TexBaseSize.x;          // w / h
        centerUV = float2(
            viewX / (viewZ * TAN_HALF_VFOV * aspect) * 0.5 + 0.5,
            0.5 - viewY / (viewZ * TAN_HALF_VFOV) * 0.5);
    }

    // ── 4. encode pixels (0,0) and (1,0) ────────────────────────
    #define DIST_MAX 4000.0
    float dist    = length(TEST_CENTER - P);
    float distEnc = saturate(dist / DIST_MAX);

    float2 px = floor(i.uv / float2(TexBaseSize.x, TexBaseSize.y));
    if (px.y < 0.5 && px.x < 2.5)
    {
        float val;
        if (px.x < 0.5)
            val = saturate(centerUV.x);
        else if (px.x < 1.5)
            val = saturate(centerUV.y);
        else
            val = distEnc;

        float hi    = floor(val * 255.0) / 255.0;
        float lo    = frac(val * 255.0);
        float valid = cubeVisible ? 1.0 : 0.0;
        return float4(hi, lo, valid, 1.0);
    }

    // ── 5. per-pixel view ray ───────────────────────────────────
    float ndcx = (i.uv.x - 0.5) *  2.0;
    float ndcy = (0.5 - i.uv.y) *  2.0;
    float3 rd  = normalize(f
                 + right * (ndcx * TAN_HALF_VFOV * (TexBaseSize.y / TexBaseSize.x))
                 + up    * (ndcy * TAN_HALF_VFOV));

    // ── 6. ray-box intersection ─────────────────────────────────
    float3 bmin = TEST_CENTER - TEST_HALF;
    float3 bmax = TEST_CENTER + TEST_HALF;
    float2 tb   = rayBox(P, rd, bmin, bmax);
    bool   hit  = (tb.y >= max(tb.x, 0.0)) && (tb.y > 0.0);

    // ── 7. scene colour + viewmodel mask ────────────────────────
    float4 base = tex2D(TexBase, i.uv);
    float3 col  = base.rgb;
    bool occludedByVM = (base.a < VM_EPSILON);

    // ── 8. glow SDF (outside the box) ───────────────────────────
    float  tc  = dot(TEST_CENTER - P, rd);
    float3 pc  = P + rd * max(tc, 0.0);
    float3 q   = abs(pc - TEST_CENTER) - TEST_HALF;
    float  sdf = length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);

    // ── 9. render ───────────────────────────────────────────────
    if (!occludedByVM)
    {
        if (hit)
        {
            float3 hitP = P + rd * tb.x;
            float3 rel  = abs(hitP - TEST_CENTER) / TEST_HALF;

            // — face normal & edge distance —
            float3 n;
            float  edgeDist;
            if (rel.x > rel.y && rel.x > rel.z)
            {
                n = float3(sign(hitP.x - TEST_CENTER.x), 0.0, 0.0);
                edgeDist = min(1.0 - rel.y, 1.0 - rel.z);
            }
            else if (rel.y > rel.z)
            {
                n = float3(0.0, sign(hitP.y - TEST_CENTER.y), 0.0);
                edgeDist = min(1.0 - rel.x, 1.0 - rel.z);
            }
            else
            {
                n = float3(0.0, 0.0, sign(hitP.z - TEST_CENTER.z));
                edgeDist = min(1.0 - rel.x, 1.0 - rel.y);
            }

            // — directional light —
            float ndotl    = saturate(dot(n, LIGHT_DIR));
            float lighting = 0.20 + 0.80 * ndotl;

            // — edge glow (squared falloff for a crisp neon line) —
            float edge = 1.0 - saturate(edgeDist / EDGE_WIDTH);
            edge *= edge;

            // — Fresnel (brighter at glancing angles) —
            float fres = 1.0 - abs(dot(n, rd));
            fres = fres * fres;

            // — compose face —
            float3 faceCol = FACE_COLOR * lighting + fres * GLOW_COLOR * 0.35;
            float  alpha   = FACE_OPACITY + edge * (1.0 - FACE_OPACITY);
            col = lerp(base.rgb, lerp(faceCol, EDGE_COLOR, edge), alpha);
        }
        else if (sdf < GLOW_WIDTH && tc > 0.0)
        {
            float g = 1.0 - saturate(sdf / GLOW_WIDTH);
            g = g * g;
            col = lerp(base.rgb, GLOW_COLOR, g * GLOW_STRENGTH);
        }
    }

    return float4(col, 1.0);
}

// ═══════════════════════════════════════════════════════════════════
//  Pass-2 decode snippet:
//
//    float2 t  = float2(TexBaseSize.x, TexBaseSize.y);
//    float2 p0 = float2(0.5, 0.5) * t;       // pixel (0,0) centre
//    float2 p1 = float2(1.5, 0.5) * t;       // pixel (1,0) centre
//
//    float4 ex = tex2D(TexBase, p0);
//    float4 ey = tex2D(TexBase, p1);
//
//    bool  valid   = (ex.b > 0.5);
//    float2 cubeUV = float2(ex.r + ex.g / 255.0,
//                           ey.r + ey.g / 255.0);
// ═══════════════════════════════════════════════════════════════════
