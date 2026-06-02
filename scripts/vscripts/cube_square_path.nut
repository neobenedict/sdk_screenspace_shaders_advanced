// cube_square_path.nut
// Moves a point in a square from (-400,-400) to (400,400) over 10 seconds.
// EntityGroup[0] = cube_mover_x  (material_modify_control)
// EntityGroup[1] = cube_mover_y  (material_modify_control)

mover_x    <- EntityGroup[0]
mover_y    <- EntityGroup[1]
start_time <- Time()

function Think()
{
    local frac = ((Time() - start_time) % 10.0) / 10.0

    local x = 0.0
    local y = 0.0

    if (frac < 0.25)
    {
        local s = frac * 4.0
        x = -400.0 + 800.0 * s
        y = -400.0
    }
    else if (frac < 0.5)
    {
        local s = (frac - 0.25) * 4.0
        x =  400.0
        y = -400.0 + 800.0 * s
    }
    else if (frac < 0.75)
    {
        local s = (frac - 0.5) * 4.0
        x =  400.0 - 800.0 * s
        y =  400.0
    }
    else
    {
        local s = (frac - 0.75) * 4.0
        x = -400.0
        y =  400.0 - 800.0 * s
    }

    EntFireByHandle(mover_x, "SetMaterialVar", x.tostring(), 0, null, null)
    EntFireByHandle(mover_y, "SetMaterialVar", y.tostring(), 0, null, null)

    return 0
}

AddThinkToEnt(self, "Think")
