/*
Hello world of wave propagation in CUDA. FDTD acoustic wave propagation in homogeneous medium. Second order accurate in time and eigth in space.

Oleg Ovcharenko
Vladimir Kazei, 2019

oleg.ovcharenko@kaust.edu.sa
vladimir.kazei@kaust.edu.sa
*/

#include <rsf.hh>
#include <iostream>
#include <string>
#include "stdio.h"
#include "math.h"
#include "stdlib.h"
#include "string.h"

#include "btree.cuh"

using namespace std;

/*
Add this to c_cpp_properties.json if linting isn't working for CUDA libraries
"includePath": [
                "/usr/local/cuda-10.0/targets/x86_64-linux/include",
                "${workspaceFolder}/**"
            ],
*/

//typedef struct{
    //int nShots;
    //int srcPosX;
    //int srcPosY;
    //int firstReceptorPos;
    //int nReceptors;
    //int lastReceptorPos;
    //int incShots;
    //int incRec;
    //int modelNx;
    //int modelNy;
    //int modelNxBorder;
    //int modelNyBorder;
    //float modelDx;
    //float modelDy;
    //int taperBorder;
    //// Auxiliaries
    //size_t nxy;
    //size_t nbxy;
    //size_t nbytes;
//} geometry;

//typedef struct{
    //float *velField;
    //float *extVelField;
    //float *firstLayerVelField;
    //float *reflecitivy;
    //float maxVel;
//} velocity;

//typedef struct{
    //float timeStep;
    //int timeSamplesNt;
    //float *seismogram;
//} seismicData;

//#include "cuwaveprop2d.cu"

//using namespace std;

//void dummyVelField(int nxb, int nyb, int nb, float *h_vpe, float *h_dvpe)
//{
    //for (int i = 0; i < nyb; i++){
        //for (int j = 0; j < nxb; j++){
            //h_dvpe[j * nyb + i]  = h_vpe[j * nyb + nb];
        //}
    //}
//}

//void expand(int nb, int nyb, int nxb, int nz, int nx, float *a, float *b)
//[>< expand domain of 'a' to 'b':  a, size=nz*nx; b, size=nyb*nxb;  ><]
//{
    //int iz,ix;
    //for     (ix=0;ix<nx;ix++) {
        //for (iz=0;iz<nz;iz++) {
            //b[(nb+ix)*nyb+(nb+iz)] = a[ix*nz+iz];
        //}
    //}
    //for     (ix=0; ix<nxb; ix++) {
        //for (iz=0; iz<nb; iz++)         b[ix*nyb+iz] = b[ix*nyb+nb];//top
        //for (iz=nz+nb; iz<nyb; iz++) b[ix*nyb+iz] = b[ix*nyb+nb+nz-1];//bottom
    //}
    //for (iz=0; iz<nyb; iz++){
        //for(ix=0; ix<nb; ix++)  b[ix*nyb+iz] = b[nb*nyb+iz];//left
        //for(ix=nb+nx; ix<nxb; ix++)     b[ix*nyb+iz] = b[(nb+nx-1)*nyb+iz];//right
    //}
//}

//void abc_coef (int nb, float *abc)
//{
    //for(int i=0; i<nb; i++){
        //abc[i] = exp (-pow(0.002 * (nb - i + 1),2.0));
    //}
//}

//void taper (int nx, int ny, int nb, float *abc, float *campo)
//{
    //int nxb = nx + 2 * nb;
    //int nyb = ny + 2 * nb;
    //for(int j=0; j<nxb; j++){
        //for(int i=0; i<nb; i++){
            //campo[j * nyb + i] *= abc[i];
            //campo[j * nyb + (nb + ny + i)] *= abc[nb - i - 1];
        //}
    //}
    //for(int i=0; i<nyb; i++){
        //for(int j=0; j<nb; j++){
            //campo[j * nyb + i] *= abc[j];
            //campo[(nb + nx + j) * nyb + i] *= abc[nb - j - 1];
        //}
    //}
//}

//sf_file createFile3D (const char *name, int dimensions[3], float spacings[3], int origins[3])
//{
    //sf_file Fdata = NULL;
    //Fdata = sf_output(name);
    //char key_n[6],key_d[6],key_o[6];
    //for (int i = 0; i < 3; i++){
        //sprintf(key_n,"n%i",i+1);
        //sprintf(key_d,"d%i",i+1);
        //sprintf(key_o,"o%i",i+1);
        //sf_putint(Fdata,key_n,dimensions[i]);
        //sf_putint(Fdata,key_d,spacings[i]);
        //sf_putint(Fdata,key_o,origins[i]);
    //}

    //return Fdata;
//}

//geometry getParameters(sf_file FvelModel, sf_file Fshots)
//{
    //geometry param;
    //sf_histint(Fshots,"n2",&param.nReceptors);
    //sf_histint(Fshots,"sybeg",&param.srcPosY);
    //sf_histint(Fshots,"sxbeg",&param.srcPosX);
    //sf_histint(Fshots,"gxbeg",&param.firstReceptorPos);
    //sf_histint(Fshots,"n3",&param.nShots);
    //sf_histint(Fshots,"incShots",&param.incShots);
    //sf_histint(Fshots,"incRec",&param.incRec);
    //sf_histint(FvelModel, "n1",&param.modelNy);
    //sf_histint(FvelModel, "n2", &param.modelNx);
    //sf_histfloat(FvelModel, "d1",&param.modelDy);
    //sf_histfloat(FvelModel, "d2", &param.modelDx);
    //param.lastReceptorPos = param.firstReceptorPos + param.nReceptors;
    //param.taperBorder = 0.3 * param.modelNx;
    //param.nxy = param.modelNx * param.modelNy;
    //param.modelNxBorder = param.modelNx + 2 * param.taperBorder;
    //param.modelNyBorder = param.modelNy + 2 * param.taperBorder;
    //param.nbxy = param.modelNxBorder * param.modelNyBorder;
    //param.nbytes = param.nbxy * sizeof(float); // bytes to store modelNxBorder * modelNyBorder
    //return param;
//}

//velocity getVelFields(sf_file FvelModel, geometry param)
//{
    //velocity h_model;

    //h_model.velField = new float[param.nxy];
    //sf_floatread(h_model.velField, param.nxy, FvelModel);

    //h_model.extVelField = new float[param.nbxy];
    //memset(h_model.extVelField,0,param.nbytes);
    //expand(param.taperBorder, param.modelNyBorder, param.modelNxBorder, param.modelNy, param.modelNx, h_model.velField, h_model.extVelField);

    //h_model.maxVel = h_model.velField[0];
    //for(int i=1; i < param.nxy; i++){
        //if(h_model.velField[i] > h_model.maxVel){
            //h_model.maxVel = h_model.velField[i];
        //}
    //}

    //h_model.firstLayerVelField = new float[param.nbxy];
    //dummyVelField(param.modelNxBorder, param.modelNyBorder, param.taperBorder, h_model.extVelField, h_model.firstLayerVelField);

    ////printf("MODEL:\n");
    ////printf("\t%i x %i\t:param.modelNy x param.modelNx\n", param.modelNy, param.modelNx);
    ////printf("\t%f\t:param.modelDx\n", param.modelDx);
    ////printf("\t%f\t:h_model.velField[0]\n", h_model.velField[0]);
    //return h_model;
//}

//float* tapermask(geometry param)
//{
    //float *h_abc = new float[param.taperBorder];
    //float *h_tapermask = new float[param.nbxy];
    //for(int i=0; i < param.nbxy; i++){
        //h_tapermask[i] = 1;
    //}
    //abc_coef(param.taperBorder, h_abc);
    //taper(param.modelNx, param.modelNy, param.taperBorder, h_abc, h_tapermask);
    //delete[] h_abc;
    //return h_tapermask;
//}

//seismicData allocHostSeisData(geometry param, sf_file Fshots)
//{
    //seismicData h_seisData;
    //sf_histfloat(Fshots,"d1",&h_seisData.timeStep);
    //sf_histint(Fshots,"n1",&h_seisData.timeSamplesNt);
    //h_seisData.seismogram = new float[param.nShots * param.nReceptors * h_seisData.timeSamplesNt];
    //sf_floatread(h_seisData.seismogram, param.nShots * param.nReceptors * h_seisData.timeSamplesNt, Fshots);
    //return h_seisData;
//}


//float* fillSrc(geometry param, velocity h_model, seismicData h_seisData)
//{
    //float* wavelet;

    //float f0 = 10.0;                    // source dominawavelet.timeSamplesNt frequency, Hz <]
    //float t0 = 1.2 / f0;                // source padding to move wavelet from left of zero <]

    //float tbytes = h_seisData.timeSamplesNt * sizeof(float);
    //float* time = (float *)malloc(tbytes);
    //wavelet = (float *)malloc(tbytes);

    //// Fill source waveform vector
    //float a = PI * PI * f0 * f0;            // const for wavelet <]
    //float dt2dx2 = (h_seisData.timeStep * h_seisData.timeStep) / (param.modelDx * param.modelDx);   // const for fd stencil <]
    //for (int it = 0; it < h_seisData.timeSamplesNt; it++)
    //{
        //time[it] = it * h_seisData.timeStep;
        //// Ricker wavelet (Mexican hat), second derivative of Gaussian
        //wavelet[it] = 1e10 * (1.0 - 2.0 * a * pow(time[it] - t0, 2)) * exp(-a * pow(time[it] - t0, 2));
        //wavelet[it] *= dt2dx2;
    //}
    //delete[] time;
    ////printf("TIME STEPPING:\n");
    ////printf("\t%e\t:h_seisData.timeStep\n", h_seisData.timeStep);
    ////printf("\t%i\t:h_seisData.timeSamplesNt\n", h_seisData.timeSamplesNt);
    //return wavelet;
//}

//void test_getParameters (geometry param, seismicData h_seisData)
//{
    //cerr<<"param.incShots: "<<param.incShots<<endl;
    //cerr<<"param.incShots: "<<param.incShots<<endl;
    //cerr<<"param.modelDims nx = "<<param.modelNx<<" ny = "<<param.modelNy<<endl;
    //cerr<<"param.modelDx = "<<param.modelDx<<" param.modelDy = "<<param.modelDy<<endl;
    //cerr<<"param.taperBorder = "<<param.taperBorder<<endl;
    //cerr<<"param.nShots "<<param.nShots<<endl;
    //cerr<<"param.nReceptors "<<param.nReceptors<<endl;
    //cerr<<"param.firstReceptorPos "<<param.firstReceptorPos<<endl;
    //cerr<<"param.lastReceptorPos "<<param.lastReceptorPos<<endl;
    //cerr<<"h_seisData.timeSamplesNt "<<h_seisData.timeSamplesNt<<endl;
    //cerr<<"h_seisData.timeStep "<<h_seisData.timeStep<<endl;
//}


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
    sf_file Fshots=NULL;
    Fshots = sf_input("shots");

    // Getting command line parameters
    geometry param = getParameters(Fvel, Fshots);

    // Allocate memory for velocity model
    velocity h_model = getVelFields (Fvel, param);

    cerr<<"vp = "<<h_model.maxVel<<endl;
    cerr<<"param.taperBorder = "<<param.taperBorder<<endl;

    // Taper mask
    float *h_tapermask = tapermask(param);

    // Data
    seismicData h_seisData = allocHostSeisData(param, Fshots);

    // Time stepping
    float* h_wavelet = fillSrc(param, h_model, h_seisData);

    // Set Output files
    int dimensions[3] = {param.modelNy,param.modelNx,1};
    float spacings[3] = {1,1,1};
    int origins[3] = {0,0,0};
    sf_file Fdata = createFile3D("rtm",dimensions,spacings,origins);

    test_getParameters(param, h_seisData);

    // ===================MODELING======================
    rtm(param, h_model, h_wavelet, h_tapermask, h_seisData, Fdata);
    // =================================================

    //printf("Clean memory...");
    delete[] h_model.velField;
    delete[] h_model.extVelField;
    delete[] h_model.firstLayerVelField;
    delete[] h_seisData.seismogram;
    delete[] h_tapermask;

    sf_close();
    return 0;
}
