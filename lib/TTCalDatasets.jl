"Define some helper functions for converting between arrays and TTCal Datasets."
module TTCalDatasets

export array_to_ttcal, array_to_ttcal!
export ttcal_to_array
export pack_jones_matrix, unpack_jones_matrix!

using TTCal

function array_to_ttcal(input, metadata, time, T)
    # Pack all frequency channels of the input array into a TTCal Dataset
    array_to_ttcal(input, metadata, 1:Nfreq(metadata), time, T)
end

function array_to_ttcal(input, metadata, frequencies, time, T)
    # Pack selected frequency channels of the input array into a TTCal Dataset
    metadata = deepcopy(metadata)
    TTCal.slice!(metadata, frequencies, axis=:frequency)
    TTCal.slice!(metadata, time,        axis=:time)
    output = TTCal.Dataset(metadata, polarization=T)
    array_to_ttcal!(output, input, frequencies, 1, T)
    output
end

function array_to_ttcal!(output, input, frequencies, time, T)
    # Pack selected frequency channels of the input array into a TTCal Dataset
    for (frequency, frequency′) in enumerate(frequencies)
        # `frequency`  refers to the channel index within the output TTCal Dataset
        # `frequency′` refers to the channel index within the input array
        visibilities = output[frequency, time]
        α = 1
        for antenna1 = 1:Nant(output), antenna2 = antenna1:Nant(output)
            J = pack_jones_matrix(input, frequency′, α, T)
            if J.xx != 0 && J.yy != 0
                visibilities[antenna1, antenna2] = J
            end
            α += 1
        end
    end
end

function pack_jones_matrix(array, frequency, α, ::Type{TTCal.Full})
    TTCal.JonesMatrix(array[1, frequency, α], array[2, frequency, α],
                      array[3, frequency, α], array[4, frequency, α])
end
function pack_jones_matrix(array, frequency, α, ::Type{TTCal.Dual})
    TTCal.DiagonalJonesMatrix(array[1, frequency, α], array[2, frequency, α])
end
function pack_jones_matrix(array, frequency, α, ::Type{TTCal.XX})
    array[1, frequency, α]
end
function pack_jones_matrix(array, frequency, α, ::Type{TTCal.YY})
    array[2, frequency, α]
end

function ttcal_to_array(ttcal_dataset)
    data = zeros(Complex128, 2, Nfreq(ttcal_dataset), Nbase(ttcal_dataset))
    for frequency in 1:Nfreq(ttcal_dataset)
        visibilities = ttcal_dataset[frequency, 1]
        α = 1
        for antenna1 = 1:Nant(ttcal_dataset), antenna2 = antenna1:Nant(ttcal_dataset)
            J = visibilities[antenna1, antenna2]
            unpack_jones_matrix!(data, frequency, α, J, TTCal.polarization(ttcal_dataset))
            α += 1
        end
    end
    data
end

function unpack_jones_matrix!(data, frequency, α, J, ::Type{TTCal.Full})
    data[1, frequency, α] = J.xx
    data[2, frequency, α] = J.xy
    data[3, frequency, α] = J.yx
    data[4, frequency, α] = J.yy
end
function unpack_jones_matrix!(data, frequency, α, J, ::Type{TTCal.Dual})
    data[1, frequency, α] = J.xx
    data[2, frequency, α] = J.yy
end
function unpack_jones_matrix!(data, frequency, α, J, ::Type{TTCal.XX})
    data[1, frequency, α] = J
end
function unpack_jones_matrix!(data, frequency, α, J, ::Type{TTCal.YY})
    data[2, frequency, α] = J
end

end

