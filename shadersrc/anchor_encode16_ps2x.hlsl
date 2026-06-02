//  Anchor cube encoder — 16-bit cosine   (ps_2_b)
//
//  Goes on each of the 4 anchor cube faces. Reads the PlayerView proxy
//  (forward (dot) dir-to-this-anchor) and writes it as a 16-BIT value split
//  across red (coarse) and green (fine), so the decode can reconstruct
//  the cosine ~256x finer than an 8-bit single channel.
//
//  REQUIRES on the material:
//    $linearwrite 1   -- MANDATORY. Without it the sRGB curve bends both
//                        bytes nonlinearly and the low (fine) byte becomes
//                        garbage. 16-bit only works with a linear write.
//    PlayerView proxy -> a material var read here (Constants0.x below).
//    scale 1 on the proxy (so the value is the raw dot, range [-1,1]).
//
//  The face must be a flat solid color (whole face encodes ONE value) so
//  the decoder can box-average safely if it wants.

#include "common.hlsl"

#define PlayerViewVal  Constants0.x     // PlayerView proxy result (scale 1 -> [-1,1])

float4 main( PS_INPUT i ) : COLOR
{
    // cosine [-1,1] -> [0,1]
    float v = saturate(PlayerViewVal * 0.5 + 0.5);

    // 16-bit hi/lo split:
    //   hi = coarse byte (the value quantized to 1/255)
    //   lo = fine byte   (the remainder within one coarse step, rescaled to [0,1])
    float vs = v * 255.0;
    float hi = floor(vs) / 255.0;       // coarse, stored in RED
    float lo = frac(vs);                // fine,   stored in GREEN

    // blue/alpha unused here (free for future data); alpha 1 so it's opaque
    return float4(hi, lo, 0.0, 1.0);
}
