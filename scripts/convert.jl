using Test
using Statistics
using Amica

using PyMNE

vhdr = "/home/fapra_morlock/Amica.jl/test/benchmark/eeg/sub-001_task-arithmetic_eeg.vhdr"

raw = PyMNE.io.read_raw_brainvision(vhdr; preload=true)
raw.filter(l_freq=1.0, h_freq=nothing)
data = Float32.(pyconvert(Array, raw.get_data(picks="eeg")))  # size = (n_channels, n_times)

write("small.bin", data)

raw = PyMNE.io.read_raw_fif("/home/fapra_morlock/sub-030_ses-001_task-Default_run-1_proc-filt_raw.fif"; preload=true)
data = Float32.(pyconvert(Array, raw.get_data()))

write("big.bin", data)
