host=$(shell hostname)
ifeq ($(host),JurosComposto)
    LDFLAGS= -I$(RSFROOT)/include -L$(RSFROOT)/lib -lrsf++ -lrsf -lm -ltirpc -lfftw3f -lfftw3 -O3
endif
ifeq ($(host),marreca)
    LDFLAGS= -I$(RSFROOT)/include -L$(RSFROOT)/lib -lrsf++ -lrsf -lm -lfftw3f -lfftw3 -O3
endif

CULIBS= -L /opt/cuda/lib -I /opt/cuda/include -lcudart -lcuda -lstdc++ -lcufft

ODIR = ../../library
IDIR = ../../include

#SOURCE = $(wildcard $(ODIR)/*.cu)
#OBJ = $(SOURCE:.cu=.o)

_OBJ = rtm.o snap.o io.o
OBJ = $(patsubst %,$(ODIR)/%,$(_OBJ))

DEPS = $(wildcard $(IDIR)/*.cuh)

CFLAGS = -I$(IDIR) -arch=sm_30

PROG = rtm

dFold=testData
shots=../FD-Seismic-data/testData/seismicData.rsf
vel=vel.rsf
rtm=rtm.rsf

$(PROG): main.o $(OBJ)
	nvcc main.o $(OBJ) $(CFLAGS) $(LDFLAGS) -o $@

main.o: main.cu $(DEPS)
	nvcc -x cu $(CFLAGS) $(LDFLAGS) -o $@ -dc $<

$(ODIR)/%.o: $(ODIR)/%.cu $(DEPS)
	nvcc -x cu $(CFLAGS) $(LDFLAGS) -o $@ -dc $<

run: $(PROG)
	./$(PROG) rtm=$(dFold)/$(rtm) vel=$(dFold)/$(vel) shots=$(shots)
	sfgrey <$(dFold)/$(rtm) >rtm.vpl
	#sfimage <$(dFold)/$(data)
	#sfgrey <$(dFold)/$(data) | sfpen &
	#ximage n1=645 < snap/upgoing_u3_s0_1600_645_588

profile: $(PROG)
	nvprof ./mod nr=400 nshots=2 incShots=100 isrc=0 jsrc=200 gxbeg=0 vel=$(dFold)/$(vel) data=$(dFold)/$(data) OD=$(dFold)/$(OD) comOD=$(dFold)/$(comOD)

PHONY: clean

clean:
	rm -f $(ODIR)/*.o $(PROG) *.o

