#ifndef CUDAFINGERPRINTING_CREATETEMPLATE
#define CUDAFINGERPRINTING_CREATETEMPLATE
#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include "math_constants.h"
#include "VectorHelper.cuh"
#include "CUDAArray.cuh"
#include "CylinderHelper.cuh"

struct Consts
{
	const char radius = 70;
	const char baseCuboid = 8;
	const char heightCuboid = 5;
	const unsigned int numberCell = baseCuboid * baseCuboid * heightCuboid;
	const float baseCell = (2.0 * radius) / baseCuboid;
	const float heightCell = (2 * CUDART_PI) / heightCuboid;
	const float sigmaLocation = 28.0 / 3;
	const float sigmaDirection = 2 * CUDART_PI / 9;
	const float sigmoidParametrPsi = 0.01;
	const char omega = 50;
	const char minNumberMinutiae = 2;
};

struct Minutia
{
	float angle;
	int x;
	int y;
};

extern "C" __declspec(dllexport) void createTemplate(Minutia* minutiae, int lenght, Cylinder* cylinders, int* cylindersLenght);

__constant__ Consts constsGPU;
Point* hullGPU;
int* hullLenghtGPU;


__device__  Point* getPoint(Minutia *minutiae);
__device__ CUDAArray<Minutia*> getNeighborhood(CUDAArray<Minutia> *minutiaArr);
__device__  float angleHeight();
__device__ __host__ float gaussian1D(float x);
__device__ __host__ float gaussianLocation(Minutia *minutia, Point *point);
__device__ float gaussianDirection(Minutia *middleMinutia, Minutia *minutia, float anglePoint);
__inline__ __device__ bool equalsMinutae(Minutia* firstMinutia, Minutia* secondMinutia);
__device__ __host__ bool isValidPoint(Minutia* middleMinutia, Point* hull, int hullLength);
__device__ __host__ float sum(CUDAArray<Minutia*> neighborhood, Minutia* middleMinutia);
__device__ __host__ char stepFunction(float value);
void createTemplate(Minutia* minutiae, int lenght, Cylinder* cylinders, int* cylindersLenght);
__global__ void createValuesAndMasks(CUDAArray<Minutia> minutiae, CUDAArray<unsigned int> valuesAndMasks);
__global__ void getValidMinutias(CUDAArray<Minutia> minutiae, CUDAArray<bool> isValidMinutiae);
__global__ void getPoints(CUDAArray<Minutia> minutiae, CUDAArray<Point> points, int lenght);
__global__ void createCylinders(CUDAArray<Minutia> minutiae, CUDAArray<unsigned int> sum, CUDAArray<unsigned int> valuesAndMasks, CUDAArray<Cylinder> cylinders);
__global__ void createSum(CUDAArray<unsigned int> valuesAndMasks, CUDAArray<unsigned int> sum);

#define defaultX() threadIdx.x+1
#define defaultY() threadIdx.y+1
#define defaultZ() (blockIdx.y+1)*(threadIdx.z+1)
#define defaultMinutia() blockIdx.x

#define cudaCheckError() {\
	cudaError_t e = cudaGetLastError(); \
	if (e != cudaSuccess) {\
		printf("Cuda failure %s:%d: '%s'\n", __FILE__, __LINE__, cudaGetErrorString(e));\
		exit(0);\
						}\
}

#define linearizationIndex() (defaultZ()-1)*constsGPU.baseCuboid*constsGPU.baseCuboid+(defaultY()-1)*constsGPU.baseCuboid+defaultX()-1
#define curIndex() 2*(linearizationIndex()/32)+threadIdx.y
#endif