# Simple Makefile for mean_test (OpenMP + MPI)

FC      = mpif90
MKLROOT = /home/fapra_morlock/intel/oneapi/2025.2
FFLAGS  = -O2 -w -cpp -fopenmp -ffree-line-length-none -I$(MKLROOT)/include
LDFLAGS = -fopenmp -L$(MKLROOT)/lib -lmkl_intel_lp64 -lmkl_sequential -lmkl_core -lpthread -lm -ldl

all: amica

amica: funmod2.f90 amica17.f90
	$(FC) $(FFLAGS) -o $@ $^ $(LDFLAGS)

clean:
	rm -f amica *.o *.mod

.PHONY: all clean
