function interactive_baseline_flags(spw, filename)
    xx, yy, flags, b = interactive_baseline_flags_setup(spw, filename)
    interactive_baseline_flags_plot(spw, xx, yy, flags, b, filename)
end

function interactive_baseline_flags(spw, filename, direction)
    xx, yy, flags, b = interactive_baseline_flags_setup(spw, filename, direction)
    interactive_baseline_flags_plot(spw, xx, yy, flags, b, filename)
end

function interactive_baseline_flags_cyg(spw, filename)
    direction = Direction(dir"J2000", "19h59m28.35663s", "+40d44m02.0970s")
    interactive_baseline_flags(spw, filename, direction)
end

function interactive_baseline_flags_cas(spw, filename)
    direction = Direction(dir"J2000", "23h23m24s", "58d48m54s")
    interactive_baseline_flags(spw, filename, direction)
end

function interactive_baseline_flags_vir(spw, filename)
    direction = Direction(dir"J2000", "12h30m49.42338s", "+12d23m28.0439s")
    interactive_baseline_flags(spw, filename, direction)
end

function interactive_baseline_flags_tau(spw, filename)
    direction = Direction(dir"J2000", "05h34m31.94s", "+22d00m52.2s")
    interactive_baseline_flags(spw, filename, direction)
end

function interactive_baseline_flags_sun(spw, filename)
    direction = Direction(dir"SUN")
    interactive_baseline_flags(spw, filename, direction)
end

function interactive_mmode_baseline_flags(spw, filename, m)
    dir = getdir(spw)
    mmodes, mmode_flags = load(joinpath(dir, filename*".jld"), "blocks", "flags")
    if m == 0
        block = mmodes[1]
        flags = mmode_flags[1]
    elseif m > 0
        block = mmodes[m+1][1:2:end]
        flags = mmode_flags[m+1][1:2:end]
    else # m < 0
        block = mmodes[-m+1][2:2:end]
        flags = mmode_flags[-m+1][2:2:end]
    end
    b = getbaselinelengths()
    interactive_baseline_flags_plot(spw, block, block, flags, b, filename)
end

function interactive_baseline_flags_setup(spw, filename)
    dir = getdir(spw)
    mydata, myflags = load(joinpath(dir, filename*".jld"), "data", "flags")
    xx, yy, flags = sum_without_changing_phase_center(mydata, myflags)
    b = getbaselinelengths()
    xx, yy, flags, b
end

function interactive_baseline_flags_setup(spw, filename, direction)
    dir = getdir(spw)
    meta = getmeta(spw, "rainy")
    mytimes, mydata, myflags = load(joinpath(dir, filename*".jld"), "times", "data", "flags")
    xx, yy, flags = sum_with_new_phase_center(spw, mytimes, mydata, myflags, direction)
    b = getbaselinelengths()
    xx, yy, flags, b
end

function sum_without_changing_phase_center(data, flags)
    _, Nbase, Ntime = size(data)
    output_xx = zeros(Complex128, Nbase)
    output_yy = zeros(Complex128, Nbase)
    output_flags = ones(Bool, Nbase)
    for idx = 1:Ntime
        for α = 1:Nbase
            if !flags[α, idx]
                xx = data[1, α, idx]
                yy = data[2, α, idx]
                output_xx[α] += xx
                output_yy[α] += yy
                output_flags[α] = false
            end
        end
    end
    output_xx, output_yy, output_flags
end

function sum_with_new_phase_center(spw, times, data, flags, direction)
    meta = getmeta(spw, "rainy")
    meta.channels = meta.channels[55:55]
    meta.phase_center = Direction(dir"AZEL", 0degrees, 90degrees)
    center = PointSource("phase center", direction, PowerLaw(1, 0, 0, 0, 1e6, [0.0]))

    _, Nbase, Ntime = size(data)
    output_xx = zeros(Complex128, Nbase)
    output_yy = zeros(Complex128, Nbase)
    output_flags = ones(Bool, Nbase)
    for idx = 1:Ntime
        meta.time = Epoch(epoch"UTC", times[idx]*seconds)
        frame = TTCal.reference_frame(meta)
        if TTCal.isabovehorizon(frame, center)
            model = genvis(meta, [center])
            for α = 1:Nbase
                if !flags[α, idx]
                    xx = data[1, α, idx]
                    yy = data[2, α, idx]
                    J = JonesMatrix(xx, 0, 0, yy)
                    J /= model.data[α, 1]
                    output_xx[α] += J.xx
                    output_yy[α] += J.yy
                    output_flags[α] = false
                end
            end
        end
    end
    output_xx, output_yy, output_flags
end

function interactive_baseline_flags_plot(spw, xx, yy, flags, b, filename)
    figure(1); clf()
    xrange, yrange, red, blue = interactive_baseline_flags_do_the_plot(spw, xx, yy, flags, b)

    meta = getmeta(4, "rainy")
    ant1 = getfield.(meta.baselines, 1)
    ant2 = getfield.(meta.baselines, 2)
    c = Channel{Tuple{Int, Int}}(32)

    function find_nearest(xcoord, ycoord)
        xcoord === nothing && return
        ycoord === nothing && return
        nearest_pol = ""
        nearest_ant1 = 0
        nearest_ant2 = 0
        nearest_distance = Inf
        f = flags | (b.==0)
        x = abs(xx[!f])
        y = abs(yy[!f])
        xdistance = hypot((b[!f]-xcoord)/xrange[2], (x-ycoord)/yrange[2])
        ydistance = hypot((b[!f]-xcoord)/xrange[2], (y-ycoord)/yrange[2])
        xidx = indmin(xdistance)
        yidx = indmin(ydistance)
        if xdistance[xidx] < nearest_distance
            nearest_distance = xdistance[xidx]
            nearest_pol = "X"
            nearest_ant1 = ant1[!f][xidx]
            nearest_ant2 = ant2[!f][xidx]
        end
        if ydistance[yidx] < nearest_distance
            nearest_distance = ydistance[yidx]
            nearest_pol = "Y"
            nearest_ant1 = ant1[!f][yidx]
            nearest_ant2 = ant2[!f][yidx]
        end
        put!(c, (nearest_ant1, nearest_ant2))
    end

    x1 = y1 = -1
    function find_in_box(x2, y2)
        f = flags | (b.==0)
        x = abs(xx[!f])
        y = abs(yy[!f])
        if x1 > x2
            x1, x2 = x2, x1
        end
        if y1 > y2
            y1, y2 = y2, y1
        end
        inside = (x1 .< b[!f] .< x2) & ((y1 .< x .< y2) | (y1 .< y .< y2))
        inside_ant1 = ant1[!f][inside]
        inside_ant2 = ant2[!f][inside]
        for (myant1, myant2) in zip(inside_ant1, inside_ant2)
            put!(c, (myant1, myant2))
        end
    end

    function process_event(event)
        if event[:button] == 3 # right click
            if event[:key] == "b"
                if x1 != -1 && y1 != -1
                    @printf("\rbox(%f, %f, %e, %e)\n> ", x1, event[:xdata], y1, event[:ydata])
                    find_in_box(event[:xdata], event[:ydata])
                    x1 = y1 = -1
                else
                    x1 = event[:xdata]
                    y1 = event[:ydata]
                end
            else
                find_nearest(event[:xdata], event[:ydata])
            end
        end
    end
    cid = gcf()[:canvas][:mpl_connect]("button_press_event", process_event)

    newflags = Int[]
    newbaselines = zeros(Int, 0, 2)
    p = @async while true
        a1, a2 = take!(c)
        a1 == 0 && a2 == 0 && break
        @printf("\r@fl %02d %d&%d\n> ", spw, a1, a2)
        α = baseline_index(a1, a2)
        push!(newflags, α)
        newbaselines = vcat(newbaselines, [a1 a2])
    end

    println("q - quit")
    println("r - re-plot with new flags applied")
    println("w - write the baseline flags to disk")
    println("(right click to flag individual baselines)")
    println("(hold b and right click to mark the corners of a box)")
    while true
        print("> ")
        inp = chomp(readline())
        if inp == "q" # quit
            put!(c, (0, 0))
            gcf()[:canvas][:mpl_disconnect](cid)
            break
        elseif inp == "r" # re-plot
            red[:remove]()
            blue[:remove]()
            for α in newflags
                flags[α] = true
            end
            xrange, yrange, red, blue = interactive_baseline_flags_do_the_plot(spw, xx, yy, flags, b)
        elseif inp == "w" # write
            if contains(filename, "rainy")
                path = joinpath(Common.workspace, "flags", @sprintf("rainy-spw%02d.bl", spw))
                baselines = Calibration.read_baseline_flags(path)
                baselines = [baselines; newbaselines]
                baselines = unique(sortrows(baselines), 1)
                writedlm(path, baselines, '&')
            end
        end
    end

    wait(p)

    nothing
end

function interactive_baseline_flags_do_the_plot(spw, xx, yy, flags, b)
    xrange = (0, 1500)
    yrange = (0, 0)
    f = flags | (b.==0)
    x = abs(xx[!f])
    y = abs(yy[!f])
    red  = scatter(b[!f], x, c="r", s=20, lw=0)
    blue = scatter(b[!f], y, c="b", s=20, lw=0)
    yrange = (0, max(yrange[2], maximum(x), maximum(y)))
    #xlim(xrange[1], xrange[2])
    #ylim(yrange[1], yrange[2])
    title(@sprintf("spw%02d", spw))
    xlabel("baseline length / m")
    ylabel("amplitude / linear scale")
    grid("on")
    #tight_layout()
    xrange, yrange, red, blue
end

function getbaselinelengths()
    meta = getmeta(4, "rainy")
    b = zeros(Nbase(meta))
    for ant1 = 1:256, ant2 = ant1:256
        u = meta.antennas[ant1].position.x - meta.antennas[ant2].position.x
        v = meta.antennas[ant1].position.y - meta.antennas[ant2].position.y
        w = meta.antennas[ant1].position.z - meta.antennas[ant2].position.z
        α = baseline_index(ant1, ant2)
        b[α] = sqrt(u^2 + v^2 + w^2)
    end
    b
end

