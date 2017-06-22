function fix_flux_scale(dataset)
    spw = 4:2:18
    maps = readmaps(spws, dataset)

end

macro 

macro perley_spectrum(args...)
    flux = 10^args[1]
    coeff = [args[2:end]...]
    quote
        PowerLaw($flux, 0, 0, 0, 1e9, $coeff)
    end
end

function flux_calibrators()
    _3c_48  = PointSource("3C 48", Direction(dir"J2000", "01h37m41.2971s", "+33d09m35.118s"),
                          @perley_spectrum 1.3253 -0.7553 -0.1914 +0.0498)
    _per_b  = PointSource("Per B", Direction(dir"J2000", "04h37m04.3753s", "+29d40m13.819s"),
                          @perley_spectrum 1.8017 -0.7884 -0.1035 -0.0248 +0.0090)
    _3c_147 = PointSource("3C 147", Direction(dir"J2000", "05h42m36.2646s", "+49d51m07.083s"),
                          @perley_spectrum 1.4516 -0.6961 -0.2007 +0.0640 -0.0464 +0.0289)
    _lyn_a  = PointSource("Lyn A", Direction(dir"J2000", "08h13m36.05609s", "+48d13m02.6360s"),
                          @perley_spectrum 1.2872 -0.8530 -0.1534 -0.0200 +0.0201)
    _hya_a  = PointSource("Hya A", Direction(dir"J2000", "09h18m05.651s", "-12d05m43.99s"),
                          @perley_spectrum 1.7795 -0.9176 -0.0843 -0.0139 +0.0295)
    _vir_a  = PointSource("Vir A", Direction(dir"J2000", "12h30m49.42338s", "+12d23m28.0439s"),
                          @perley_spectrum 2.4466 -0.8116 -0.0483)
    _3c_286 = PointSource("3C 286", Direction(dir"J2000", "13h31m08.3s", "+30d30m33s"),
                          @perley_spectrum 1.2481 -0.4507 -0.1798 +0.0357)
    _3c_295 = PointSource("3C 295", Direction(dir"J2000", "14h11m20.467s", "+52d12m09.52s"),
                          @perley_spectrum 1.4701 -0.7658 -0.2780 -0.0347 +0.0399)
    #_3c_353 = PointSource("3C 353", Direction(dir"J2000", "17h20m28.147s", "-00d58m47.12s"),
    #                      @perley_spectrum 1.8627 -0.6938 -0.0998 -0.0732)
    #_3c_380 = PointSource("3C 380", Direction(dir"J2000", "18h29m31.72483s", "+48d44m46.9515s"),
    #                      @perley_spectrum 1.2320 -0.7909 +0.0947 +0.0976 -0.1794 -0.1566)
    _cyg_a  = PointSource("Cyg A", Direction(dir"J2000", "19h59m28.35663s", "+40d44m02.0970s"),
                          @perley_spectrum 3.3498 -1.0022 -0.2246 +0.0227 +0.0425)

end

