// ═══════════════════════════════════════════════════════════════════
//  Pass 2 — Gravitational lensing warp   (ps_2_b)
// ═══════════════════════════════════════════════════════════════════
//  Reads the cube's screen-space centre and world distance encoded
//  by pass 1, then warps the background using the Schwarzschild
//  thin-lens equation.  All effect radii scale with 1/distance so
//  the black hole shrinks as you walk away and grows as you
//  approach.
//
//  Encode layout (from pass 1):
//    pixel (0,0)  centre U   (16-bit hi/lo in RG, valid flag in B)
//    pixel (1,0)  centre V   (16-bit hi/lo in RG)
//    pixel (2,0)  distance   (16-bit, normalised to DIST_MAX)
//
//  Inputs:
//    TexBase          framebuffer (output of pass 1)
//    TexBaseSize      (1/w, 1/h)
//    Constants0.x     Einstein ring radius at reference distance
//    Constants0.y     event-horizon radius at reference distance
//    Constants0.z     warp strength (1.0 = physical thin-lens)
//    Constants0.w     swirl strength (0 = off)
//    Constants1.x     reference distance (world units — the distance
//                     at which the $c0 values look correct)
//
//  Suggested VMT values:
//    $c0_x  0.06      // Einstein ring radius
//    $c0_y  0.08      // event-horizon radius
//    $c0_z  1.0       // warp strength
//    $c0_w  0.132     // swirl
//    $c1_x  500.0     // reference distance (tune to taste)
// ═══════════════════════════════════════════════════════════════════

#include "common.hlsl"

// ── VMT-driven parameters ────────────────────────────────────────
#define iEinsteinR   Constants0.x
#define iHoleR       Constants0.y
#define iWarpStr     Constants0.z
#define iSwirl       Constants0.w
#define iRefDist     Constants1.x

// ── compile-time tunables ────────────────────────────────────────
#define DIST_MAX      4000.0   // must match pass 1
#define EARLY_OUT_MUL 5.0
#define FADE_BAND     2.5      // event-horizon softness (x holeR)
#define TAPER_START   0.6      // edge taper begins at this fraction of cutoff

// ═════════════════════════════════════════════════════════════════
float4 main(PS_INPUT i) : COLOR
{
    float2 t = float2(TexBaseSize.x, TexBaseSize.y);

    // ── 1. read pass-1 encode pixels ────────────────────────────
    float4 ex = tex2D(TexBase, float2(0.5, 0.5) * t);   // pixel (0,0) U
    float4 ey = tex2D(TexBase, float2(1.5, 0.5) * t);   // pixel (1,0) V
    float4 ed = tex2D(TexBase, float2(2.5, 0.5) * t);   // pixel (2,0) dist

    float4 scene = tex2D(TexBase, i.uv);

    if (ex.b < 0.5)
        return scene;

    // ── 2. decode centre UV + distance ──────────────────────────
    float2 bhUV = float2(ex.r + ex.g / 255.0,
                         ey.r + ey.g / 255.0);

    float dist      = (ed.r + ed.g / 255.0) * DIST_MAX;
    float distScale = iRefDist / max(dist, 1.0);

    // ── 3. scale radii by distance ──────────────────────────────
    float einsteinR = iEinsteinR * distScale;
    float holeR     = iHoleR     * distScale;

    // ── 4. aspect-corrected distance ────────────────────────────
    float aspect = TexBaseSize.y / TexBaseSize.x;          // w / h
    float2 delta = i.uv - bhUV;
    delta.x *= aspect;
    float r = length(delta);

    float maxR = einsteinR * EARLY_OUT_MUL;
    if (r > maxR)
        return scene;

    float2 dir = delta / (r + 1e-4);

    // ── 5. Schwarzschild thin-lens ──────────────────────────────
    float R2       = einsteinR * einsteinR * iWarpStr;
    float source_r = r - R2 / (r + 0.001);
    source_r = max(source_r, 0.0005);

    // ── 6. frame-dragging swirl ─────────────────────────────────
    float angle = iSwirl / (r * r + 0.01);
    float cs = cos(angle);
    float sn = sin(angle);
    float2 swirlDir = float2(dir.x * cs - dir.y * sn,
                             dir.x * sn + dir.y * cs);

    // ── 7. reconstruct lensed UV ────────────────────────────────
    float2 lensedUV = bhUV + swirlDir * source_r / float2(aspect, 1.0);
    lensedUV = clamp(lensedUV, float2(0.002, 0.002),
                               float2(0.998, 0.998));

    float4 bg = tex2D(TexBase, lensedUV);

    // ── 8. event-horizon darkening + edge taper ─────────────────
    float darkness = smoothstep(holeR, holeR * FADE_BAND, r);
    float edge     = 1.0 - smoothstep(maxR * TAPER_START, maxR, r);

    return float4(lerp(scene.rgb, bg.rgb * darkness, edge), 1.0);
}
