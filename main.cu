/*
Hello world of wave propagation in CUDA. FDTD acoustic wave propagation in homogeneous medium. Second order accurate in time and eigth in space.

Oleg Ovcharenko
Vladimir Kazei, 2019

oleg.ovcharenko@kaust.edu.sa
vladimir.kazei@kaust.edu.sa
*/

#include <rsf.hh>
#include <iostream>
#include "stdio.h"
#include "math.h"
#include "stdlib.h"
#include "string.h"
/*
Add this to c_cpp_properties.json if linting isn't working for CUDA libraries
"includePath": [
                "/usr/local/cuda-10.0/targets/x86_64-linux/include",
                "${workspaceFolder}/**"
            ],
*/

#include "cuwaveprop2d.cu"



using namespace std;

void modeling(int nx, int ny, int nb, int nr, int nt, int gxbeg, int gxend, int isrc, int jsrc, float dx, float dy, float dt, float *h_vpe, float *h_tapermask, float *h_data, float * h_wavelet, bool snaps);

void dummyVelField(int nxb, int nyb, int nb, float *h_vpe, float *h_dvpe)
{
    for (int i = 0; i < nyb; i++){
        for (int j = 0; j < nxb; j++){
            h_dvpe[j * nyb + i]  = h_vpe[j * nyb + nb];
        }
    }
}

void expand(int nb, int nyb, int nxb, int nz, int nx, float *a, float *b)
/*< expand domain of 'a' to 'b':  a, size=nz*nx; b, size=nyb*nxb;  >*/
{
    int iz,ix;
    for     (ix=0;ix<nx;ix++) {
	for (iz=0;iz<nz;iz++) {
	    b[(nb+ix)*nyb+(nb+iz)] = a[ix*nz+iz];
	}
    }
    for     (ix=0; ix<nxb; ix++) {
        for (iz=0; iz<nb; iz++)   	b[ix*nyb+iz] = b[ix*nyb+nb];//top
        for (iz=nz+nb; iz<nyb; iz++) b[ix*nyb+iz] = b[ix*nyb+nb+nz-1];//bottom
    }

    for (iz=0; iz<nyb; iz++){
        for(ix=0; ix<nb; ix++) 	b[ix*nyb+iz] = b[nb*nyb+iz];//left
        for(ix=nb+nx; ix<nxb; ix++)	b[ix*nyb+iz] = b[(nb+nx-1)*nyb+iz];//right
    }
}

void abc_coef (int nb, float *abc)
{
    for(int i=0; i<nb; i++){
        abc[i] = exp (-pow(0.008 * (nb - i + 1),2.0));
    }
}

void taper (int nx, int ny, int nb, float *abc, float *campo)
{
    int nxb = nx + 2 * nb;
    int nyb = ny + 2 * nb;
    for(int j=0; j<nxb; j++){
        for(int i=0; i<nb; i++){
            campo[j * nyb + i] *= abc[i];
            campo[j * nyb + (nb + ny + i)] *= abc[nb - i - 1];
        }
    }
    for(int i=0; i<nyb; i++){
        for(int j=0; j<nb; j++){
            campo[j * nyb + i] *= abc[j];
            campo[(nb + nx + j) * nyb + i] *= abc[nb - j - 1];
        }
    }
}


/*
===================================================================================
MAIN
===================================================================================
*/
int main(int argc, char *argv[])
{
    /* Main program that reads and writes data and read input variables */
    bool verb;
    sf_init(argc,argv); // init RSF
    if(! sf_getbool("verb",&verb)) verb=0;

    // Setting up I/O files
    sf_file Fvel=NULL;
    Fvel = sf_input("vel");

    // Getting command line parameters
    //sf_getint('sz',sz);
    //sf_getint('jsx',jsx);
    //sf_getint('gzbeg',gzbeg);
    //sf_getint('jgx',jgx);
    int nr; sf_getint("nr",&nr);
    int isrc; sf_getint("isrc",&isrc);
    int jsrc; sf_getint("jsrc",&jsrc);
    int gxbeg; sf_getint("gxbeg",&gxbeg);
    int gxend = gxbeg + nr;

    // R/W axes
    sf_axis ax,ay;
    int nx, ny, nb, nxb, nyb;
    float dx, dy;
    ay = sf_iaxa(Fvel,1); ny = sf_n(ay); dy = sf_d(ay);
    ax = sf_iaxa(Fvel,2); nx = sf_n(ax); dx = sf_d(ax);
    cerr<<"nx = "<<nx<<endl;
    cerr<<"ny = "<<ny<<endl;

    size_t nxy = nx * ny;
    nb = 0.2 * nx;
    nxb = nx + 2 * nb;
    nyb = ny + 2 * nb;
    size_t nbxy = nxb * nyb;
    size_t nbytes = nbxy * sizeof(float);/* bytes to store nx * ny */

    // Allocate memory for velocity model
    float *h_vp = new float[nxy]; sf_floatread(h_vp, nxy, Fvel);
    float *h_vpe = new float[nbxy];
    memset(h_vpe,0,nbytes);
    //extendVelField(nx, ny, nb, h_vp, h_vpe);
    expand(nb, nyb, nxb, ny, nx, h_vp, h_vpe);
    float _vp = h_vp[0];
    for(int i=1; i < nxy; i++){
        if(h_vp[i] > _vp){
            _vp = h_vp[i];
        }
    }

    // Allocate memory for dummy velocity model and seismogram
    float *h_dvpe = new float[nbxy];
    dummyVelField(nxb, nyb, nb, h_vpe, h_dvpe);

    cerr<<"vp = "<<_vp<<endl;
    cerr<<"nb = "<<nb<<endl;

    // Taper mask
    float *h_abc = new float[nb];
    float *h_tapermask = new float[nbxy];
    for(int i=0; i < nbxy; i++){
        h_tapermask[i] = 1;
    }
    abc_coef(nb, h_abc);
    taper(nx, ny, nb, h_abc, h_tapermask);

    //sf_file Fout=NULL;
    //Fout = sf_output("data");
    //sf_putint(Fout,"n1",nyb);
    //sf_putint(Fout,"n2",nxb);
    //sf_floatwrite(h_tapermask, nbxy, Fout);

    printf("MODEL:\n");
    printf("\t%i x %i\t:ny x nx\n", ny, nx);
    printf("\t%f\t:dx\n", dx);
    printf("\t%f\t:h_vp[0]\n", h_vp[0]);

    // Time stepping
    float t_total = 2.5;               /* total time of wave propagation, sec */
    float dt = 0.5 * dx / _vp;         /* time step assuming constant vp, sec */
    int nt = round(t_total / dt);      /* number of time steps */
    int snap_step = round(0.1 * nt);   /* save snapshot every ... steps */

    printf("TIME STEPPING:\n");
    printf("\t%e\t:t_total\n", t_total);
    printf("\t%e\t:dt\n", dt);
    printf("\t%i\t:nt\n", nt);

    // Data
    size_t dbytes = nxb * nt * sizeof(float);
    float *h_data = new float[nr * nt];
    float *h_directwave = new float[nr * nt];

    // Source
    float f0 = 10.0;                    /* source dominant frequency, Hz */
    float t0 = 1.2 / f0;                /* source padding to move wavelet from left of zero */
    //int isrc = round((float)nx / 2);    [> source location, ox <]
    //int jsrc = round((float)ny / 2);    [> source location, oz <]

    float *h_wavelet, *h_time;
    float tbytes = nt * sizeof(float);
    h_time = (float *)malloc(tbytes);
    h_wavelet = (float *)malloc(tbytes);

    // Fill source waveform vector
    float a = PI * PI * f0 * f0;            /* const for wavelet */
    float dt2dx2 = (dt * dt) / (dx * dx);   /* const for fd stencil */
    for (int it = 0; it < nt; it++)
    {
        h_time[it] = it * dt;
        // Ricker wavelet (Mexican hat), second derivative of Gaussian
        h_wavelet[it] = 1e10 * (1.0 - 2.0 * a * pow(h_time[it] - t0, 2)) * exp(-a * pow(h_time[it] - t0, 2));
        h_wavelet[it] *= dt2dx2;
    }

    printf("SOURCE:\n");
    printf("\t%f\t:f0\n", f0);
    printf("\t%f\t:t0\n", t0);
    printf("\t%i\t:isrc - ox\n", isrc);
    printf("\t%i\t:jsrc - oy\n", jsrc);
    printf("\t%e\t:dt2dx2\n", dt2dx2);
    printf("\t%f\t:min wavelength [m]\n",(float)_vp / (2*f0));
    printf("\t%f\t:ppw\n",(float)_vp / (2*f0) / dx);

    // ===================MODELING======================
    modeling(nx, ny, nb, nr, nt, gxbeg, gxend, isrc, jsrc, dx, dy, dt, h_vpe, h_tapermask, h_data, h_wavelet, true);
    modeling(nx, ny, nb, nr, nt, gxbeg, gxend, isrc, jsrc, dx, dy, dt, h_dvpe, h_tapermask, h_directwave, h_wavelet, false);
    // =================================================

    //sf_file Fout=NULL;
    //Fout = sf_output("data");
    //sf_putint(Fout,"n1",nyb);
    //sf_putint(Fout,"n2",nxb);
    //sf_floatwrite(h_vpe, nbxy, Fout);

    sf_file Fout3=NULL;
    Fout3 = sf_output("comOD");
    sf_putint(Fout3,"n1",nt);
    sf_putint(Fout3,"n2",nr);
    sf_floatwrite(h_data, nr * nt, Fout3);

    for(int i=0; i<nr * nt; i++){
        h_data[i] = h_data[i] - h_directwave[i];
    }

    sf_file Fout=NULL;
    Fout = sf_output("data");
    sf_putint(Fout,"n1",nt);
    sf_putint(Fout,"n2",nr);
    sf_floatwrite(h_data, nr * nt, Fout);

    sf_file Fout2=NULL;
    Fout2 = sf_output("OD");
    sf_putint(Fout2,"n1",nt);
    sf_putint(Fout2,"n2",nr);
    sf_floatwrite(h_directwave, nr * nt, Fout2);

    //FILE *fdata = fopen("oi.bin", "w");
    //fwrite(h_vpe, sizeof(float), nxb * nyb, fdata);
    //fflush(stdout);
    //fclose(fdata);

    printf("Clean memory...");
    delete[] h_vp;
    delete[] h_vpe;
    delete[] h_data;
    delete[] h_abc;
    delete[] h_tapermask;
    delete[] h_time;
    delete[] h_wavelet;


    return 0;
}
