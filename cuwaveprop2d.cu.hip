#include "hip/hip_runtime.h"
#include <iostream>
#include <rsf.hh>
#include "hip/hip_runtime.h"
#include "hip/hip_runtime.h"

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
        hipError_t error = call;                                  \
        if (error != hipSuccess)                                  \
        {                                                          \
            fprintf(stderr, "Error: %s:%d, ", __FILE__, __LINE__); \
            fprintf(stderr, "code: %d, reason: %s\n", error,       \
                    hipGetErrorString(error));                    \
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
    CHECK(hipMemcpy(iwave, data, isize, hipMemcpyDeviceToHost));

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

void test_kernel_add_sourceArray(float *d_reflectivity, geometry param, dim3 grid, dim3 block)
{
    float *d_zeros;
    CHECK(hipMalloc((void **)&d_zeros, param.nbytes))       /* wavefield at t-2 */
    CHECK(hipMemset(d_zeros, 0, param.nbytes))
    hipLaunchKernelGGL(kernel_add_sourceArray, dim3(grid), dim3(block), 0, 0, d_zeros, d_reflectivity);

    float *h_zeros = new float[param.nbxy];
    CHECK(hipMemcpy(h_zeros, d_zeros, param.nbytes, hipMemcpyDeviceToHost));

    FILE *f_test = fopen("test_kernel_add_sourceArray", "w");

    fwrite(h_zeros, sizeof(float), param.nbxy, f_test);
    fclose(f_test);
}

//void test_kernel_applySourceArray(float dt, float *d_reflectivity, float *d_pField, float *d_vel, float *d_q)

//void modeling(int nx, int ny, int nb, int nr, int nt, int gxbeg, int gxend, int isrc, int jsrc, float dx, float dy, float dt, float *h_vpe, float *h_dvpe, float *h_tapermask, float *h_data, float *h_directwave, float * h_seisData. bool snaps, int nshots, int incShots, sf_file Fonly_directWave, sf_file Fdata_directWave, sf_file Fdata)
void modeling(geometry param, velocity h_model, float *h_wavelet, float *h_tapermask, seismicData h_seisData, sf_file Fdata)
{
    float dt2dx2 =
        (h_seisData.timeStep * h_seisData.timeStep) / (param.modelDx * param.modelDx);   /* const for fd stencil */
    size_t dbytes = param.nReceptors * h_seisData.timeSamplesNt * sizeof(float);
    size_t tbytes = h_seisData.timeSamplesNt * sizeof(float);

    // Allocate memory on device
    printf("Allocate and copy memory on the device...\n");
    float *d_u1, *d_u2, *d_q1, *d_q2, *d_vp, *d_wavelet, *d_tapermask, *d_data, *d_directwave, *d_reflectivity, *d_snapAux;
    CHECK(hipMalloc((void **)&d_u1, param.nbytes))       /* wavefield at t-2 */
    CHECK(hipMalloc((void **)&d_u2, param.nbytes))       /* wavefield at t-1 */
    CHECK(hipMalloc((void **)&d_q1, param.nbytes))       /* wavefield at t-2 */
    CHECK(hipMalloc((void **)&d_q2, param.nbytes))       /* wavefield at t-1 */
    CHECK(hipMalloc((void **)&d_vp, param.nbytes))       /* velocity model */
    CHECK(hipMalloc((void **)&d_wavelet, tbytes)); /* source term for each time step */
    CHECK(hipMalloc((void **)&d_tapermask, param.nbytes));
    CHECK(hipMalloc((void **)&d_data, dbytes));
    CHECK(hipMalloc((void **)&d_directwave, dbytes));
    CHECK(hipMalloc((void **)&d_snapAux, param.nbytes));

    // Fill allocated memory with a value
    CHECK(hipMemset(d_u1, 0, param.nbytes))
    CHECK(hipMemset(d_u2, 0, param.nbytes))
    CHECK(hipMemset(d_data, 0, dbytes))

    // Copy arrays from host to device
    CHECK(hipMemcpy(d_vp, h_model.extVelField, param.nbytes, hipMemcpyHostToDevice));
    CHECK(hipMemcpy(d_tapermask, h_tapermask, param.nbytes, hipMemcpyHostToDevice));
    CHECK(hipMemcpy(d_reflectivity, h_model.reflecitivy, param.nxy * sizeof(float), hipMemcpyHostToDevice));
    CHECK(hipMemcpy(d_wavelet, h_wavelet, tbytes, hipMemcpyHostToDevice));

    // Copy constants to device constant memory
    float coef[] = {a0, a1, a2, a3, a4};
    CHECK(hipMemcpyToSymbol(HIP_SYMBOL(c_coef), coef, 5 * sizeof(float)));
    CHECK(hipMemcpyToSymbol(HIP_SYMBOL(c_nx), &param.modelNxBorder, sizeof(int)));
    CHECK(hipMemcpyToSymbol(HIP_SYMBOL(c_ny), &param.modelNyBorder, sizeof(int)));
    CHECK(hipMemcpyToSymbol(HIP_SYMBOL(c_nr), &param.nReceptors, sizeof(int)));
    CHECK(hipMemcpyToSymbol(HIP_SYMBOL(c_nxy), &param.nbxy, sizeof(int)));
    CHECK(hipMemcpyToSymbol(HIP_SYMBOL(c_nb), &param.taperBorder, sizeof(int)));
    CHECK(hipMemcpyToSymbol(HIP_SYMBOL(c_nt), &h_seisData.timeSamplesNt, sizeof(int)));
    CHECK(hipMemcpyToSymbol(HIP_SYMBOL(c_dt2dx2), &dt2dx2, sizeof(float)));
    printf("\t%f MB\n", (4 * param.nbytes + tbytes)/1024/1024);
    printf("OK\n");

    // Print out specs of the main GPU
    hipDeviceProp_t deviceProp;
    CHECK(hipGetDeviceProperties(&deviceProp, 0));
    printf("GPU0:\t%s\t%d.%d:\n", deviceProp.name, deviceProp.major, deviceProp.minor);
    printf("\t%lu GB:\t total Global memory (gmem)\n", deviceProp.totalGlobalMem / 1024 / 1024 / 1000);
    printf("\t%lu MB:\t total Constant memory (cmem)\n", deviceProp.totalConstMem / 1024);
    printf("\t%lu MB:\t total Shared memory per block (smem)\n", deviceProp.sharedMemPerBlock / 1024);
    printf("\t%d:\t total threads per block\n", deviceProp.maxThreadsPerBlock);
    printf("\t%d:\t total registers per block\n", deviceProp.regsPerBlock);
    printf("\t%d:\t warp size\n", deviceProp.warpSize);
    printf("\t%d x %d x %d:\t max dims of block\n", deviceProp.maxThreadsDim[0], deviceProp.maxThreadsDim[1], deviceProp.maxThreadsDim[2]);
    printf("\t%d x %d x %d:\t max dims of grid\n", deviceProp.maxGridSize[0], deviceProp.maxGridSize[1], deviceProp.maxGridSize[2]);
    CHECK(hipSetDevice(0));

    // Print out CUDA domain partitioning info
    //printf("CUDA:\n");
    //printf("\t%i x %i\t:block dim\n", BDIMY, BDIMX);
    //printf("\t%i x %i\t:shared dim\n", SDIMY, SDIMX);
    //printf("CFL:\n");
    //printf("\t%f\n", _vp * h_seisData.timeStep / dx);

    // Setup CUDA run
    dim3 block(BDIMX, BDIMY);
    dim3 grid((param.modelNxBorder + block.x - 1) / block.x, (param.modelNyBorder + block.y - 1) / block.y);


    float* snapsBuffer = new float[param.nbxy];

    // MAIN LOOP
    for(int shot=0; shot<param.nShots; shot++){
        cerr<<"\nShot "<<shot<<" param.firstReceptorPos = "<<param.firstReceptorPos<<", param.srcPosX = "<<param.srcPosX<<", param.srcPosY = "<<param.srcPosY<<
            ", param.incShots = "<<param.incShots<<"\n"<<endl;

        CHECK(hipMemset(d_u1, 0, param.nbytes))
        CHECK(hipMemset(d_u2, 0, param.nbytes))

        float *d_u3;
        printf("Time loop...\n");
        for (int it = 0; it < h_seisData.timeSamplesNt; it++)
        {
            hipLaunchKernelGGL(taper_gpu, dim3(grid), dim3(block), 0, 0, d_tapermask, d_u1);
            hipLaunchKernelGGL(taper_gpu, dim3(grid), dim3(block), 0, 0, d_tapermask, d_u2);

            // These kernels are in the same stream so they will be executed one by one
            hipLaunchKernelGGL(kernel_2dfd, dim3(grid), dim3(block), 0, 0, d_u1, d_u2, d_vp);
            hipLaunchKernelGGL(kernel_add_wavelet, dim3(grid), dim3(block), 0, 0, d_u2, d_wavelet, it, param.srcPosX, param.srcPosY);

            CHECK(hipMemcpy(&snapsBuffer[it * param.nbxy], d_u1, param.nbytes, hipMemcpyDeviceToHost));

            // Exchange time steps
            d_u3 = d_u1;
            d_u1 = d_u2;
            d_u2 = d_u3;
        }

        for (int it = h_seisData.timeSamplesNt - 1; it >= 0; it++)
        {
            hipLaunchKernelGGL(taper_gpu, dim3(grid), dim3(block), 0, 0, d_tapermask, d_u1);
            hipLaunchKernelGGL(taper_gpu, dim3(grid), dim3(block), 0, 0, d_tapermask, d_u2);

            // These kernels are in the same stream so they will be executed one by one
            hipLaunchKernelGGL(kernel_2dfd, dim3(grid), dim3(block), 0, 0, d_u1, d_u2, d_vp);
            hipLaunchKernelGGL(kernel_add_seismicdata, dim3(grid), dim3(block), 0, 0, d_u2, d_wavelet, it, param.srcPosX, param.srcPosY);

            CHECK(hipMemcpy(d_snapAux, &snapsBuffer[it * param.nbxy], param.nbytes, hipMemcpyHostToDevice));
            hipLaunchKernelGGL(kernel_image_condition, dim3(grid), dim3(block), 0, 0, d_u1, d_snapAux)

            // Exchange time steps
            d_u3 = d_u1;
            d_u1 = d_u2;
            d_u2 = d_u3;
        }

        sf_floatwrite(h_seisData.seismogram, param.nReceptors * h_seisData.timeSamplesNt, Fdata);

        param.firstReceptorPos += param.incShots;
        param.srcPosX += param.incShots;
    }


    printf("OK\n");

    CHECK(hipGetLastError());


    delete snapsBuffer;
    CHECK(hipFree(d_u1));
    CHECK(hipFree(d_u2));
    CHECK(hipFree(d_tapermask));
    CHECK(hipFree(d_data));
    CHECK(hipFree(d_directwave));
    CHECK(hipFree(d_vp));
    CHECK(hipFree(d_wavelet));
    printf("OK saigo\n");
    CHECK(hipDeviceReset());
}
