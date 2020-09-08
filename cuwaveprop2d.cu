#include <iostream>
#include <rsf.hh>
#include "cuda.h"
#include "cuda_runtime.h"

using namespace std;

// Constant device memory
__constant__ float c_coef[5]; /* coefficients for 8th order fd */
__constant__ int c_nx;        /* x dim */
__constant__ int c_ny;        /* y dim */
__constant__ int c_nr;        /* num of receivers */
__constant__ int c_nxy;       /* total number of elements in the snap array (border included)*/
__constant__ int c_nb;        /* border size */
__constant__ int c_nt;        /* time steps */
__constant__ float c_dt2dx2;  /* dt2 / dx2 for fd*/

__global__ void taper_gpu (float *d_tapermask, float *campo)
{
    unsigned int gx = blockIdx.x * blockDim.x + threadIdx.x;
    unsigned int gy = blockIdx.y * blockDim.y + threadIdx.y;
    unsigned int gid = gx * c_ny + gy;

    if(gid < c_nxy){
        campo[gid] *= d_tapermask[gid];
    }
}

#define PI 3.14159265359

// Padding for FD scheme
#define HALO 4
#define HALO2 8

// FD stencil coefficients
#define a0  -2.8472222f
#define a1   1.6000000f
#define a2  -0.2000000f
#define a3   0.0253968f
#define a4  -0.0017857f

// Block dimensions
#define BDIMX 32
#define BDIMY 32

// Shared memory tile dimenstions
#define SDIMX BDIMX + HALO2
#define SDIMY BDIMY + HALO2

// Check error codes for CUDA functions
#define CHECK(call)                                                \
    {                                                              \
        cudaError_t error = call;                                  \
        if (error != cudaSuccess)                                  \
        {                                                          \
            fprintf(stderr, "Error: %s:%d, ", __FILE__, __LINE__); \
            fprintf(stderr, "code: %d, reason: %s\n", error,       \
                    cudaGetErrorString(error));                    \
        }                                                          \
    }

#include "cudaKernels.cu"

// Save snapshot as a binary, filename snap/snap_tag_it_ny_nx
void saveSnapshotIstep(int it, float *data, int nx, int ny, const char *tag, int shot)
{
    /*
    it      :timestep id
    data    :pointer to an array in device memory
    nx, ny  :model dimensions
    tag     :user-defined file identifier
    */

    // Array to store wavefield
    unsigned int isize = nx * ny * sizeof(float);
    float *iwave = (float *)malloc(isize);
    CHECK(cudaMemcpy(iwave, data, isize, cudaMemcpyDeviceToHost));

    char fname[32];
    sprintf(fname, "snap/snap_%s_s%i_%i_%i_%i", tag, shot, it, ny, nx);

    FILE *fp_snap = fopen(fname, "w");

    fwrite(iwave, sizeof(float), nx * ny, fp_snap);
    printf("\tSave...%s: nx = %i ny = %i it = %i tag = %s\n", fname, nx, ny, it, tag);
    fflush(stdout);
    fclose(fp_snap);

    free(iwave);
    return;
}


void modeling(int nx, int ny, int nb, int nr, int nt, int gxbeg, int gxend, int isrc, int jsrc, float dx, float dy, float dt, float *h_vpe, float *h_dvpe, float *h_tapermask, float *h_data, float *h_directwave, float * h_wavelet, bool snaps, int nshots, int incShots, sf_file Fonly_directWave, sf_file Fdata_directWave, sf_file Fdata)
{
    size_t nxy = nx * ny;
    int nxb = nx + 2 * nb;
    int nyb = ny + 2 * nb;
    float dt2dx2 = (dt * dt) / (dx * dx);   /* const for fd stencil */
    size_t nbxy = nxb * nyb;
    size_t nbytes = nbxy * sizeof(float);/* bytes to store nx * ny */
    size_t dbytes = nr * nt * sizeof(float);
    size_t tbytes = nt * sizeof(float);
    int snap_step = round(0.1 * nt);   /* save snapshot every ... steps */

    // Allocate memory on device
    printf("Allocate and copy memory on the device...\n");
    float *d_u1, *d_u2, *d_vp, *d_wavelet, *d_tapermask, *d_data, *d_directwave, *d_dvp;
    CHECK(cudaMalloc((void **)&d_u1, nbytes))       /* wavefield at t-2 */
    CHECK(cudaMalloc((void **)&d_u2, nbytes))       /* wavefield at t-1 */
    CHECK(cudaMalloc((void **)&d_vp, nbytes))       /* velocity model */
    CHECK(cudaMalloc((void **)&d_dvp, nbytes))       /* velocity model */
    CHECK(cudaMalloc((void **)&d_wavelet, tbytes)); /* source term for each time step */
    CHECK(cudaMalloc((void **)&d_tapermask, nbytes));
    CHECK(cudaMalloc((void **)&d_data, dbytes));
    CHECK(cudaMalloc((void **)&d_directwave, dbytes));

    // Fill allocated memory with a value
    CHECK(cudaMemset(d_u1, 0, nbytes))
    CHECK(cudaMemset(d_u2, 0, nbytes))
    CHECK(cudaMemset(d_data, 0, dbytes))

    // Copy arrays from host to device
    CHECK(cudaMemcpy(d_vp, h_vpe, nbytes, cudaMemcpyHostToDevice));
    CHECK(cudaMemcpy(d_dvp, h_dvpe, nbytes, cudaMemcpyHostToDevice));
    CHECK(cudaMemcpy(d_tapermask, h_tapermask, nbytes, cudaMemcpyHostToDevice));
    CHECK(cudaMemcpy(d_wavelet, h_wavelet, tbytes, cudaMemcpyHostToDevice));

    // Copy constants to device constant memory
    float coef[] = {a0, a1, a2, a3, a4};
    CHECK(cudaMemcpyToSymbol(c_coef, coef, 5 * sizeof(float)));
    CHECK(cudaMemcpyToSymbol(c_nx, &nxb, sizeof(int)));
    CHECK(cudaMemcpyToSymbol(c_ny, &nyb, sizeof(int)));
    CHECK(cudaMemcpyToSymbol(c_nr, &nr, sizeof(int)));
    CHECK(cudaMemcpyToSymbol(c_nxy, &nbxy, sizeof(int)));
    CHECK(cudaMemcpyToSymbol(c_nb, &nb, sizeof(int)));
    CHECK(cudaMemcpyToSymbol(c_nt, &nt, sizeof(int)));
    CHECK(cudaMemcpyToSymbol(c_dt2dx2, &dt2dx2, sizeof(float)));
    printf("\t%f MB\n", (4 * nbytes + tbytes)/1024/1024);
    printf("OK\n");

    // Print out specs of the main GPU
    //cudaDeviceProp deviceProp;
    //CHECK(cudaGetDeviceProperties(&deviceProp, 0));
    //printf("GPU0:\t%s\t%d.%d:\n", deviceProp.name, deviceProp.major, deviceProp.minor);
    //printf("\t%lu GB:\t total Global memory (gmem)\n", deviceProp.totalGlobalMem / 1024 / 1024 / 1000);
    //printf("\t%lu MB:\t total Constant memory (cmem)\n", deviceProp.totalConstMem / 1024);
    //printf("\t%lu MB:\t total Shared memory per block (smem)\n", deviceProp.sharedMemPerBlock / 1024);
    //printf("\t%d:\t total threads per block\n", deviceProp.maxThreadsPerBlock);
    //printf("\t%d:\t total registers per block\n", deviceProp.regsPerBlock);
    //printf("\t%d:\t warp size\n", deviceProp.warpSize);
    //printf("\t%d x %d x %d:\t max dims of block\n", deviceProp.maxThreadsDim[0], deviceProp.maxThreadsDim[1], deviceProp.maxThreadsDim[2]);
    //printf("\t%d x %d x %d:\t max dims of grid\n", deviceProp.maxGridSize[0], deviceProp.maxGridSize[1], deviceProp.maxGridSize[2]);
    CHECK(cudaSetDevice(0));

    // Print out CUDA domain partitioning info
    //printf("CUDA:\n");
    //printf("\t%i x %i\t:block dim\n", BDIMY, BDIMX);
    //printf("\t%i x %i\t:shared dim\n", SDIMY, SDIMX);
    //printf("CFL:\n");
    //printf("\t%f\n", _vp * dt / dx);

    // Setup CUDA run
    dim3 block(BDIMX, BDIMY);
    dim3 grid((nxb + block.x - 1) / block.x, (nyb + block.y - 1) / block.y);

    // MAIN LOOP
    for(int shot=0; shot<nshots; shot++){
        cerr<<"\nShot "<<shot<<" gxbeg = "<<gxbeg<<", jsrc = "<<jsrc<<", isrc = "<<isrc<<
            ", incShots = "<<incShots<<"\n"<<endl;

        CHECK(cudaMemset(d_u1, 0, nbytes))
        CHECK(cudaMemset(d_u2, 0, nbytes))

        printf("Time loop...\n");
        for (int it = 0; it < nt; it++)
        {
            taper_gpu<<<grid,block>>>(d_tapermask, d_u1);
            taper_gpu<<<grid,block>>>(d_tapermask, d_u2);

            // These kernels are in the same stream so they will be executed one by one
            kernel_add_wavelet<<<grid, block>>>(d_u2, d_wavelet, it, jsrc, isrc);
            kernel_2dfd<<<grid, block>>>(d_u1, d_u2, d_vp);
            //CHECK(cudaDeviceSynchronize());
            receptors<<<(nr + 32) / 32, 32>>>(it, nr, gxbeg, d_u1, d_data);

            // Exchange time steps
            float *d_u3 = d_u1;
            d_u1 = d_u2;
            d_u2 = d_u3;

            // Save snapshot every snap_step iterations
            if ((it % snap_step == 0) && snaps == true)
            {
                printf("%i/%i\n", it+1, nt);
                saveSnapshotIstep(it, d_u3, nxb, nyb, "u3", shot);
            }
        }

        CHECK(cudaMemset(d_u1, 0, nbytes))
        CHECK(cudaMemset(d_u2, 0, nbytes))

        for (int it = 0; it < nt; it++)
        {
            taper_gpu<<<grid,block>>>(d_tapermask, d_u1);
            taper_gpu<<<grid,block>>>(d_tapermask, d_u2);

            // These kernels are in the same stream so they will be executed one by one
            kernel_add_wavelet<<<grid, block>>>(d_u2, d_wavelet, it, jsrc, isrc);
            kernel_2dfd<<<grid, block>>>(d_u1, d_u2, d_dvp);
            //CHECK(cudaDeviceSynchronize());
            receptors<<<(nr + 32) / 32, 32>>>(it, nr, gxbeg, d_u1, d_directwave);

            // Exchange time steps
            float *d_u3 = d_u1;
            d_u1 = d_u2;
            d_u2 = d_u3;

            // Save snapshot every snap_step iterations
            if ((it % snap_step == 0) && snaps == true)
            {
                printf("%i/%i\n", it+1, nt);
                saveSnapshotIstep(it, d_u3, nxb, nyb, "u3", shot);
            }
        }

        CHECK(cudaMemcpy(h_data, d_data, dbytes, cudaMemcpyDeviceToHost));
        CHECK(cudaMemcpy(h_directwave, d_directwave, dbytes, cudaMemcpyDeviceToHost));

        sf_floatwrite(h_data, nr * nt, Fdata_directWave);

        for(int i=0; i<nr * nt; i++){
            h_data[i] = h_data[i] - h_directwave[i];
        }

        sf_floatwrite(h_data, nr * nt, Fdata);

        sf_floatwrite(h_directwave, nr * nt, Fonly_directWave);

        gxbeg += incShots;
        jsrc += incShots;
    }


    printf("OK\n");

    CHECK(cudaGetLastError());


    CHECK(cudaFree(d_u1));
    CHECK(cudaFree(d_u2));
    CHECK(cudaFree(d_tapermask));
    CHECK(cudaFree(d_data));
    CHECK(cudaFree(d_vp));
    CHECK(cudaFree(d_wavelet));
    printf("OK saigo\n");
    CHECK(cudaDeviceReset());
}
