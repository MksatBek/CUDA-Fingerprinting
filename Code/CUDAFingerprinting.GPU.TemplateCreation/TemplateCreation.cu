#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include "constsmacros.h"
#include "BinTemplateCorrelation.cu"
#include "CylinderHelper.cuh"
#include "ConvexHull.cu"
#include "CUDAArray.cuh"
#include "math_constants.h"
#include "VectorHelper.cu"
#include "math.h"
#include "TemplateCreation.cuh"
#include "device_functions_decls.h"
#include "ConvexHullModified.cu"
#include "CylinderHelper.cuh"
#include <stdio.h>

__device__  Point* getPoint(Minutia *minutiae)
{
	return &Point(
		(float)
		((*minutiae).x + constsGPU[0].baseCell *
		(cos((*minutiae).angle) * (defaultX() - (constsGPU[0].baseCuboid + 1) / 2.0f) +
		sin((*minutiae).angle) * (defaultY() - (constsGPU[0].baseCuboid + 1) / 2.0f))),
		(float)
		((*minutiae).y + constsGPU[0].baseCell *
		(-sin((*minutiae).angle) * (defaultX() - (constsGPU[0].baseCuboid + 1) / 2.0f) +
		cos((*minutiae).angle) * (defaultY() - (constsGPU[0].baseCuboid + 1) / 2.0f)))
		);
}

__device__ Minutia** getNeighborhood(CUDAArray<Minutia> *minutiaArr, int *lenghtNeighborhood)
{
	int tmp = *lenghtNeighborhood;
	Minutia* neighborhood[150];
	for (size_t i = 0; i < (*minutiaArr).Height*(*minutiaArr).Width; i++)
	{
		if ((pointDistance(Point((float)(*minutiaArr).At(0, i).x, (float)((*minutiaArr).At(0, i).y)),
			*getPoint(&(*minutiaArr).At(0, defaultMinutia())))) < 3 * constsGPU[0].sigmaLocation &&
			(!equalsMinutae((*minutiaArr).AtPtr(0, i), (*minutiaArr).AtPtr(0, defaultMinutia()))))
		{
			
			neighborhood[tmp] = ((*minutiaArr).AtPtr(0, i));
			tmp++;
		}
	}
	*lenghtNeighborhood = tmp;
	return neighborhood;
}

__device__  float angleHeight()
{
	return (-CUDART_PI + (defaultZ() - 0.5) * constsGPU[0].heightCell);
}

__device__  float gaussian1D(float x)
{
	return expf(-(x * x) / (2 * constsGPU[0].sigmaLocation * constsGPU[0].sigmaLocation)) / (constsGPU[0].sigmaLocation * sqrtf(CUDART_PI * 2));
}

__device__ float getPointDistance(Point A, Point B)
{
	float diffX = B.x - A.x;
	float diffY = B.y - A.y;

	return sqrt(diffX * diffX + diffY * diffY);
}

__device__ float gaussianLocation(Minutia *minutia, Point *point)
{
	return gaussian1D(getPointDistance(Point((*minutia).x, (*minutia).y), *point));
}

__device__ float gaussianDirection(Minutia *middleMinutia, Minutia *minutia, float anglePoint)
{
	float common = sqrt(2.0) * constsGPU[0].sigmaDirection;
	double angle = getAngleDiff(anglePoint,
		getAngleDiff((*middleMinutia).angle, (*minutia).angle));
	double first = erf(((angle + constsGPU[0].heightCell / 2)) / common);
	double second = erf(((angle - constsGPU[0].heightCell / 2)) / common);
	return (first - second) / 2;
}

__inline__ __device__ bool equalsMinutae(Minutia* firstMinutia, Minutia* secondMinutia)
{
	return (
		(*firstMinutia).x == (*secondMinutia).x &&
		(*firstMinutia).y == (*secondMinutia).y &&
		abs((*firstMinutia).angle - (*secondMinutia).angle) < 1.401298E-45
		);
}

__device__ bool isValidPoint(Minutia* middleMinutia, Point* hullGPU, int* hullLenghtGPU)
{
	return  getPointDistance(Point((*middleMinutia).x, (*middleMinutia).y), *getPoint(middleMinutia)) < constsGPU[0].radius &&
		isPointInsideHull(*getPoint(middleMinutia), hullGPU, *hullLenghtGPU);
}

__device__ float sum(Minutia** neighborhood, Minutia* middleMinutia, int lenghtNeigborhood)
{
	double sum = 0;
	for (size_t i = 0; i < lenghtNeigborhood; i++)
	{
		sum += gaussianLocation(&(*neighborhood[i]), getPoint(middleMinutia)) * gaussianDirection(middleMinutia, neighborhood[i], angleHeight());
	}
	return sum;
}

__device__ char stepFunction(float value)
{
	return (char)(value >= constsGPU[0].sigmoidParametrPsi ? 1 : 0);
}

__global__ void getPoints(CUDAArray<Minutia> minutiae, CUDAArray<Point> points)
{
	if (threadIdx.x < minutiae.Width)
	{
		points.SetAt(0, threadIdx.x, Point(minutiae.At(0, threadIdx.x).x, minutiae.At(0, threadIdx.x).y));
	}
}

__global__ void getValidMinutiae(CUDAArray<Minutia> minutiae, CUDAArray<bool> isValidMinutiae)
{
	if (threadIdx.x >= minutiae.Width)
	{
		return;
	}
	int validMinutiaeLenght = 0;
	for (int i = 0; i < minutiae.Width; i++)
	{
		if (threadIdx.x == i)
		{
			continue;
		}
		validMinutiaeLenght = sqrt((float)
			((minutiae.At(0, threadIdx.x).x - minutiae.At(0, i).x)*(minutiae.At(0, threadIdx.x).x - minutiae.At(0, i).x) +
			minutiae.At(0, threadIdx.x).y - minutiae.At(0, i).y)*(minutiae.At(0, threadIdx.x).y - minutiae.At(0, i).y))
			< constsGPU[0].radius + 3 * constsGPU[0].sigmaLocation ? validMinutiaeLenght + 1 : validMinutiaeLenght;
	}
	isValidMinutiae.SetAt(0, threadIdx.x, validMinutiaeLenght >= constsGPU[0].minNumberMinutiae ? true : false);
}

__global__ void createSum(CUDAArray<unsigned int> valuesAndMasks, CUDAArray<unsigned int> sum)
{
	unsigned int x = __popc(valuesAndMasks.At(defaultMinutia(), threadIdx.x * 2 + blockIdx.x));
	atomicAdd(sum.AtPtr(0, threadIdx.x * 2 + blockIdx.x), x);
}


__global__ void createCylinders(CUDAArray<Minutia> minutiae, CUDAArray<unsigned int> sum,
	CUDAArray<unsigned int> valuesAndMasks, CUDAArray<Cylinder> cylinders)
{
	cylinders.SetAt(0, blockIdx.x, Cylinder(valuesAndMasks.AtPtr(blockIdx.x, 0), valuesAndMasks.Width,
		minutiae.At(0, blockIdx.x).angle, sqrt((float)(sum.At(0, blockIdx.x))), 0));
}


__global__ void createValuesAndMasks(CUDAArray<Minutia> minutiae, CUDAArray<unsigned int> valuesAndMasks, Point* hullGPU, int* hullLenghtGPU)
{
	int lenghtNeighborhood = 0;
	if (defaultX() > 16 || defaultY() > 16 || defaultZ() > 6 || defaultMinutia() > minutiae.Width)
	{
		return;
	}
	if (isValidPoint(&minutiae.At(0, defaultMinutia()), hullGPU, hullLenghtGPU))
	{
		char tempValue =
			(defaultY() % 2)*(stepFunction(sum(getNeighborhood(&minutiae, &lenghtNeighborhood), &(minutiae.At(0, defaultMinutia())), lenghtNeighborhood)));
		atomicOr(valuesAndMasks.AtPtr(defaultMinutia(), curIndex()), (tempValue - '0' + blockIdx.y) << linearizationIndex() % 32);
	}
	else
	{
		atomicOr(valuesAndMasks.AtPtr(defaultMinutia(), curIndex()), 0 << linearizationIndex() % 32);
	}
}

void createTemplate(Minutia* minutiae, int lenght, Cylinder** cylinders, int* cylindersLenght)
{
	cudaSetDevice(0);
	Consts *myConst = (Consts*)malloc(sizeof(Consts));
	myConst[0].radius = 70;
	myConst[0].baseCuboid = 16;
	myConst[0].heightCuboid = 6;
	myConst[0].numberCell = myConst[0].baseCuboid *  myConst[0].baseCuboid *  myConst[0].heightCuboid;
	myConst[0].baseCell = (2.0 *  myConst[0].radius) / myConst[0].baseCuboid;
	myConst[0].heightCell = (2 * CUDART_PI) / myConst[0].heightCuboid;
	myConst[0].sigmaLocation = 28.0 / 3;
	myConst[0].sigmaDirection = 2 * CUDART_PI / 9;
	myConst[0].sigmoidParametrPsi = 0.01;
	myConst[0].omega = 50;
	myConst[0].minNumberMinutiae = 2;

	cudaMemcpyToSymbol(constsGPU, myConst, sizeof(Consts));
	cudaCheckError();

	Point* points = (Point*)malloc(lenght * sizeof(Point));
	CUDAArray<Minutia> cudaMinutiae = CUDAArray<Minutia>(minutiae, lenght, 1);
	CUDAArray<Point> cudaPoints = CUDAArray<Point>(points, lenght, 1);
	free(points);
	getPoints << <1, lenght >> >(cudaMinutiae, cudaPoints);
	cudaCheckError();

	int hullLenght = 0;
	Point* hull = (Point*)malloc(lenght*sizeof(Point));
	getConvexHull(cudaPoints.GetData(), lenght, hull, &hullLenght);
	cudaPoints.Dispose();

	Point* extHull = extendHull(hull, hullLenght, myConst[0].omega);
	free(hull);

	int extLenght;
	extLenght = hullLenght * 2;

	Point* hullGPU;
	int* hullLenghtGPU;

	cudaMalloc((void**)&hullGPU, sizeof(Point)*(extLenght));
	cudaCheckError();

	cudaMemcpy(hullGPU, extHull, sizeof(Point)*(extLenght), cudaMemcpyHostToDevice);
	cudaCheckError();
	free(extHull);

	cudaMalloc((void**)&hullLenghtGPU, sizeof(int));
	cudaCheckError();

	cudaMemcpy(hullLenghtGPU, &extLenght, sizeof(int), cudaMemcpyHostToDevice);
	cudaCheckError();

	bool* isValidMinutiae = (bool*)malloc(lenght*sizeof(bool));
	CUDAArray<bool> cudaIsValidMinutiae = CUDAArray<bool>(isValidMinutiae, lenght, 1);


	getValidMinutiae << <1, lenght >> >(cudaMinutiae, cudaIsValidMinutiae);
	cudaCheckError();

	cudaMinutiae.Dispose();
	cudaIsValidMinutiae.GetData(isValidMinutiae);
	cudaIsValidMinutiae.Dispose();

	int validMinutiaeLenght = 0;
	Minutia* validMinutiae = (Minutia*)malloc(lenght*sizeof(Minutia));
	for (int i = 0; i < lenght; i++)
	{
		if (isValidMinutiae[i])
		{
			validMinutiae[validMinutiaeLenght] = minutiae[i];
			validMinutiaeLenght++;
		}
	}
	free(isValidMinutiae);

	validMinutiae = (Minutia*)realloc(validMinutiae, validMinutiaeLenght*sizeof(Minutia));
	cudaMinutiae = CUDAArray<Minutia>(validMinutiae, validMinutiaeLenght, 1);
	unsigned int** valuesAndMasks = (unsigned int**)malloc(validMinutiaeLenght*sizeof(unsigned int*));
	for (int i = 0; i < validMinutiaeLenght; i++)
	{
		valuesAndMasks[i] = (unsigned int*)malloc(2 * myConst[0].numberCell / 32 * sizeof(unsigned int));
	}
	CUDAArray <unsigned int> cudaValuesAndMasks = CUDAArray<unsigned int>(*valuesAndMasks, 2 * myConst[0].numberCell / 32, validMinutiaeLenght);
	for (int i = validMinutiaeLenght - 1; i >= 0; i--)
	{
		free(valuesAndMasks[i]);
	}
	free(valuesAndMasks);
	Minutia **neighborhood;
	cudaMalloc((void**)&neighborhood, sizeof(Minutia*)*(cudaMinutiae.Height));
	createValuesAndMasks << < dim3(validMinutiaeLenght, 2), dim3(myConst[0].baseCuboid, myConst[0].baseCuboid, myConst[0].heightCuboid / 2) >> >(cudaMinutiae, cudaValuesAndMasks, hullGPU, hullLenghtGPU);
	cudaCheckError();

	cudaFree(neighborhood);
	unsigned int* sumArr = (unsigned int*)malloc(2 * myConst[0].numberCell / 32 * sizeof(unsigned int));
	CUDAArray<unsigned int> cudaSumArr = CUDAArray<unsigned int>(sumArr, myConst[0].numberCell / 32, 1);
	free(sumArr);
	cudaCheckError();
	createSum << <2, validMinutiaeLenght >> >(cudaValuesAndMasks, cudaSumArr);
	cudaCheckError();
	CUDAArray<Cylinder> cudaCylinders = CUDAArray<Cylinder>();
	createCylinders << <validMinutiaeLenght * 2, 1 >> >(cudaMinutiae, cudaSumArr, cudaValuesAndMasks, cudaCylinders);
	cudaCheckError();
	*cylinders = cudaCylinders.GetData();
	cudaCylinders.Dispose();
	Cylinder* validCylinders = (Cylinder*)malloc(validMinutiaeLenght*sizeof(Cylinder));
	float maxNorm = 0;
	for (int i = 1; i < validMinutiaeLenght * 2; i += 2)
	{
		maxNorm = (*cylinders)[i].norm > maxNorm ? (*cylinders)[i].norm : maxNorm;
	}
	int validCylindersLenght = 0;
	for (int i = 1; i < validMinutiaeLenght * 2; i += 2)
	{
		if ((*cylinders)[i].norm >= 0.75*maxNorm)
		{
			validCylinders[validCylindersLenght++] = *cylinders[i - 1];
			validCylinders[validCylindersLenght++] = *cylinders[i];
		}
	}
	validCylinders = (Cylinder*)realloc(validCylinders, validCylindersLenght*sizeof(Cylinder));
	free(cylinders);
	*cylinders = validCylinders;
	*cylindersLenght = validCylindersLenght;
	cudaFree(hullGPU);
	cudaFree(hullLenghtGPU);
}

int main()
{
	Minutia* minutiae = (Minutia*)malloc(sizeof(Minutia) * 100);
	Minutia tmp;
	for (int i = 0; i < 100; i++)
	{
		tmp.x = i + 1;
		tmp.y = i + 1;
		tmp.angle = i*0.3;
		minutiae[i] = tmp;
	}
	Cylinder* cylinders;
	int lenght;
	createTemplate(minutiae, 100, &cylinders, &lenght);
	printf("%d", lenght);
	getchar();
	free(minutiae);
}
