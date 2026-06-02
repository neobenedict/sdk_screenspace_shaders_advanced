// ═══════════════════════════════════════════════════════════════════
//  Anchor decode + world-split effect   (ps_2_b)
// ═══════════════════════════════════════════════════════════════════
//  Reconstructs camera via anchor patches, ray-casts each pixel
//  against the room box, then DISPLACES the framebuffer UV so the
//  world appears to pull apart at y = 0.  Content on the +y side
//  shifts in +y, content on -y shifts in -y, and the gap fills
//  with glowing white.
//
//  The split traces across the floor, up both x-walls, and across
//  the ceiling automatically — anywhere the room surface crosses
//  y = 0.
//
//  Inputs:
//    TexBase           framebuffer
//    Tex1              _rt_Camera (anchor patches)
//    Constants0.x      gap half-width in world units (0 = off)
//    Constants2.xyz    player world position
//    TexBaseSize       (1/w, 1/h)
// ═══════════════════════════════════════════════════════════════════

#include "common.hlsl"

#define POS_SCALE     1
#define TAN_HALF_VFOV 0.75
static const float PI = 3.14159265;

// ── anchor positions ─────────────────────────────────────────────
static const float3 A1 = float3(8000.0,    0.0,    0.0);
static const float3 A2 = float3(   0.0, 8000.0,    0.0);
static const float3 A3 = float3(   0.0,    0.0, 8000.0);
static const float3 A4 = float3(8000.0, 8000.0, 8000.0);

#define ANCHOR_UV_1   float2(0.1797, 0.6855)
#define ANCHOR_UV_2   float2(0.8203, 0.6836)
#define ANCHOR_UV_3   float2(0.5000, 0.1309)
#define ANCHOR_UV_4   float2(0.5000, 0.5000)

// ── room geometry (adjust to match your map) ─────────────────────
#define FLOOR_Z    Constants0.z
#define CEIL_Z     Constants1.x
#define WALL_X     Constants1.y
#define ROOM_Y     16384.0

static const float3 ROOM_MIN = float3(-WALL_X, -ROOM_Y, FLOOR_Z);
static const float3 ROOM_MAX = float3( WALL_X,  ROOM_Y, CEIL_Z);

// ── split appearance ─────────────────────────────────────────────
#define GLOW_RANGE    48.0
#define GLOW_COLOR    float3(1.0, 1.0, 1.0)
#define GLOW_POWER    2.0

// ── viewmodel rejection ──────────────────────────────────────────
#define VM_EPSILON    Constants0.y

// ═════════════════════════════════════════════════════════════════
//  Anchor readback
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
    // ── 1. anchor least-squares solve ───────────────────────────
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
    f   = normalize(f);

    // ── 2. view basis (no roll) ─────────────────────────────────
    float2 fh    = normalize(f.xy);
    float3 right = float3(fh.y, -fh.x, 0.0);
    float3 up    = cross(right, f);

    // ── 3. per-pixel view ray ───────────────────────────────────
    float ndcx = (i.uv.x - 0.5) *  2.0;
    float ndcy = (0.5 - i.uv.y) *  2.0;
    float aspect = TexBaseSize.y / TexBaseSize.x;
    float3 rd = normalize( f
                + right * (ndcx * TAN_HALF_VFOV * aspect)
                + up    * (ndcy * TAN_HALF_VFOV) );

    // ── 4. scene passthrough ────────────────────────────────────
    float4 base = tex2D(TexBase, i.uv);
    float3 col  = base.rgb;

    float gapHalf = Constants0.x;
    bool occludedByVM = (base.a < VM_EPSILON);

    if (gapHalf > 0.01 && !occludedByVM)
    {
        // ── 5. ray vs room interior ─────────────────────────────
        float3 invD = 1.0 / rd;
        float3 t0   = (ROOM_MIN - P) * invD;
        float3 t1   = (ROOM_MAX - P) * invD;
        float3 tFar = max(t0, t1);
        float  tHit = min(min(tFar.x, tFar.y), tFar.z);

        if (tHit > 0.0)
        {
            float3 hitP = P + rd * tHit;
            float  dist = abs(hitP.y);

            if (dist < gapHalf)
            {
                // ── inside the gap: solid white ─────────────────
                col = GLOW_COLOR;
            }
            else
            {
                // ── displace: pull content away from the split ──
                // The +y half moved +gapHalf, -y half moved -gapHalf.
                // To find what's now visible at this pixel, sample
                // from where the content originally was: y ∓ gapHalf.
                float3 srcP = hitP;
                srcP.y -= sign(hitP.y) * gapHalf;

                // reproject the source point back to screen UV
                float3 srcDir = normalize(srcP - P);
                float  vz = dot(srcDir, f);

                if (vz > 0.001)
                {
                    float sx = dot(srcDir, right);
                    float sy = dot(srcDir, up);
                    float2 srcUV = float2(
                        sx / (vz * TAN_HALF_VFOV * aspect) * 0.5 + 0.5,
                        0.5 - sy / (vz * TAN_HALF_VFOV) * 0.5
                    );
                    srcUV = saturate(srcUV);

                    col = tex2D(TexBase, srcUV).rgb;
                }
                else
                {
                    col = GLOW_COLOR;
                }

                // ── glow halo near the gap edge ─────────────────
                float edgeDist = dist - gapHalf;
                if (edgeDist < GLOW_RANGE)
                {
                    float g = 1.0 - edgeDist / GLOW_RANGE;
                    g = pow(g, GLOW_POWER);
                    col = lerp(col, GLOW_COLOR, g);
                }
            }
        }
    }

    return float4(col, 1);
}
