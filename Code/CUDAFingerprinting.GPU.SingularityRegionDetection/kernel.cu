﻿#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include <math_constants.h>

#include "ImageLoading.cuh"
#include "CUDAArray.cuh"
#include "Convolution.cuh"

#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <fstream>
#include <iostream>

using namespace std;

#define BigBlockSize 48
#define BlockSize 32
#define defaultBlockSize 16

extern "C"
{
	__declspec( dllexport ) void Detect (float* fPic, int* matrix, int width, int height);
}

__global__ void Module (CUDAArray<float> cMapReal, CUDAArray<float> cMapImaginary, CUDAArray<float> cMapAbs)
{
	int row = defaultRow ();
	int column = defaultColumn ();
	
	float R = cMapReal.At (row, column);
	float I = cMapImaginary.At (row, column);
	float value = sqrt (R * R + I * I);

	cMapAbs.SetAt (row, column, value);
}

__global__ void cudaRegularize (CUDAArray<float> source, CUDAArray<float> target)
{
	int row = blockIdx.y * defaultBlockSize + threadIdx.y;
	int column = blockIdx.x * defaultBlockSize + threadIdx.x;

	int tX = threadIdx.x;
	int tY = threadIdx.y;

	__shared__ float buf[defaultBlockSize][defaultBlockSize];
	__shared__ float linBuf[defaultBlockSize];
	buf[tX][tY] = source.At (row, column);

	__syncthreads();
	if ( tX == 0 )
	{
		float sum = 0;
		for ( int i = 0; i < defaultBlockSize; ++i )
		{
			sum += buf[i][tY];
		}
		linBuf[tY] = sum;
	}

	__syncthreads();
	if ( tX == 0 && tY == 0 )
	{
		float sum = 0;
		for ( int i = 0; i < defaultBlockSize; ++i )
		{
			sum += linBuf[i];
		}
		linBuf[0] = sum;
	}
	__syncthreads();

	float val = linBuf[0] / ( defaultBlockSize * defaultBlockSize );

	target.SetAt (row, column, val);
}

void Regularize (CUDAArray<float> source, CUDAArray<float> target)
{
	dim3 blockSize = dim3(defaultBlockSize, defaultBlockSize);
	dim3 gridSize = dim3(ceilMod(source.Width, defaultBlockSize), ceilMod(source.Height, defaultBlockSize));

	cudaRegularize <<< gridSize, blockSize >>> (source, target);
}

__device__ __inline__ float Sum (CUDAArray<float> source, int tX, int tY, int row, int column)
{
	__shared__ float buf[48][48];
	__shared__ float linBuf[32];

	if ( ( row - 16 >= 0 ) && ( row - 16 < source.Height ) && ( column - 16 >= 0 ) && ( column - 16 < source.Width ) )
	{
		buf[tX - 16][tY - 16] = source.At (row - 16, column - 16);
		buf[tX - 16][tY] = source.At (row - 16, column);
		buf[tX - 16][tY + 16] = source.At (row - 16, column + 16);
		buf[tX][tY - 16] = source.At (row, column - 16);
		buf[tX][tY] = source.At (row, column);
		buf[tX][tY + 16] = source.At (row, column + 16);
		buf[tX + 16][tY - 16] = source.At (row + 16, column - 16);
		buf[tX + 16][tY] = source.At (row + 16, column);
		buf[tX + 16][tY + 16] = source.At (row + 16, column + 16);
	}

	__syncthreads();
	if ( tX == 15 )
	{
		float sum = 0;
		for ( int i = 0; i < 32; ++i )
		{
			sum += buf[i][tY];
		}
		linBuf[tY] = sum;
	}

	__syncthreads();
	if ( tX == 15 && tY == 15 )
	{
		float sum = 0;
		for ( int i = 0; i < 32; ++i )
		{
			sum += linBuf[i];
		}
		linBuf[0] = sum;
	}
	__syncthreads();

	return linBuf[0];
}

__global__ void cudaStrengthen (CUDAArray<float> V_rReal, CUDAArray<float> V_rImaginary, CUDAArray<float> cMapAbs, CUDAArray<float> target)
{
	int row = defaultRow();
	int column = defaultColumn();

	int tX = threadIdx.x;
	int tY = threadIdx.y;

	float R = Sum (V_rReal, tX, tY, row, column);
	float I = Sum (V_rImaginary, tX, tY, row, column);

	float numerator = sqrt (R * R + I * I);
	float denominator = Sum (cMapAbs, tX, tY, row, column);

	float val = 1 - numerator / denominator;

	target.SetAt (row, column, val);
}

void Strengthen (CUDAArray<float> cMapReal, CUDAArray<float> cMapImaginary, CUDAArray<float> cMapAbs, float *str)
{
	CUDAArray<float> target = CUDAArray<float> (cMapReal.Width, cMapReal.Height);

	dim3 blockSize = dim3(defaultBlockSize, defaultBlockSize);
	dim3 gridSize = dim3(ceilMod(cMapReal.Width, defaultBlockSize), ceilMod(cMapReal.Height, defaultBlockSize));

	cudaStrengthen <<< gridSize, blockSize >>> (cMapReal, cMapImaginary, cMapAbs, target);
	cudaError_t error = cudaGetLastError ();
	target.GetData (str);
	target.Dispose ();
}

void SaveSegmentation (int width, int height, float* matrix)
{
	int* newPic = (int*) malloc (sizeof (int)*width*height);
	int capacity = width * height;

	for ( int i = 0; i < capacity; ++i )
	{
		newPic[i] = (int)(matrix[i] * 255);
	}

	saveBmp ("newPic.bmp", newPic, width, height);
	
	free (newPic);
}

__global__ void SinCos (CUDAArray<float> cMapReal, CUDAArray<float> cMapImaginary, CUDAArray<float> source)
{
	int row = defaultRow ();
	int column = defaultColumn ();
	
	cMapReal.SetAt (row, column, sin (2 * source.At(row, column)));
	cMapImaginary.SetAt (row, column, cos (2 * source.At(row, column)));	   
}

void Detect (float* fPic, int width, int height)
{
	CUDAArray<float> source = CUDAArray<float> (fPic, width, height);

	CUDAArray<float> cMapReal = CUDAArray<float>(width, height);
	CUDAArray<float> cMapImaginary = CUDAArray<float>(width, height);

	//CUDAArray<float> V_rReal = CUDAArray<float>(width, height);
	//CUDAArray<float> V_rImaginary = CUDAArray<float>(width, height);

	CUDAArray<float> cMapAbs = CUDAArray<float>(width, height);

	float* str = new float [width * height];

	dim3 blockSize = dim3(defaultBlockSize, defaultBlockSize);
	dim3 gridSize = dim3(ceilMod(cMapReal.Width, defaultBlockSize), ceilMod(cMapReal.Height, defaultBlockSize));

	SinCos <<< gridSize, blockSize >>> (cMapReal, cMapImaginary, source);
	Module <<< gridSize, blockSize >>> (cMapReal, cMapImaginary, cMapAbs);

    //Regularize(cMapReal, V_rReal);
	//Regularize(cMapImaginary, V_rImaginary);

    Strengthen(cMapReal, cMapImaginary, cMapAbs, str);
	SaveSegmentation (width, height, str);

	cMapReal.Dispose ();
	cMapImaginary.Dispose ();
	//V_rReal.Dispose ();
	//V_rImaginary.Dispose ();
}

__global__ void cudaSetOrientationInPixels(CUDAArray<float> orientation, CUDAArray<float> gradientX, CUDAArray<float> gradientY){
	int centerRow = defaultRow();
	int centerColumn = defaultColumn();

	//float gx = gradientX.At(centerRow, centerColumn);
	//float gy = gradientY.At(centerRow, centerColumn);
	//float sq = sqrt(gx*gx + gy*gy);
	//orientation.SetAt(centerRow, centerColumn, sq);

	const int size = 16;
	const int center = size / 2;
	const int upperLimit = center - 1;

	float product[size][size];
	float sqrdiff[size][size];

	for (int i = -center; i <= upperLimit; i++){
		for (int j = -center; j <= upperLimit; j++){
			if (i + centerRow < 0 || i + centerRow > gradientX.Height || j + centerColumn < 0 || j + centerColumn > gradientX.Width){		// выход за пределы картинки
				product[i + center][j + center] = 0;
				sqrdiff[i + center][j + center] = 0;
			}
			else{
				float GxValue = gradientX.At(i + centerRow, j + centerColumn);
				float GyValue = gradientY.At(i + centerRow, j + centerColumn);
				product[i + center][j + center] = GxValue * GyValue;						// поэлементное произведение
				sqrdiff[i + center][j + center] = GxValue * GxValue - GyValue * GyValue;	// разность квадратов
			}
		}
	}
	__syncthreads();  // ждем пока все нити сделают вычисления

	float numerator = 0;
	float denominator = 0;
	// вычисление сумм
	for (int i = 0; i < size; i++) {
		for (int j = 0; j < size; j++){
			numerator += product[i][j];
			denominator += sqrdiff[i][j];
		}
	}

	// определяем значение угла ориентации
	float angle = CUDART_PIO2_F;
	if (denominator != 0){
		angle = CUDART_PIO2_F + atan2(numerator*2.0f, denominator) / 2.0f;
		if (angle > CUDART_PIO2_F)
		{
			angle -= CUDART_PI_F;
		}
	}
	orientation.SetAt(centerRow, centerColumn, angle);
}

void SetOrientationInPixels(CUDAArray<float> orientation, CUDAArray<float> source, CUDAArray<float> gradientX, CUDAArray<float> gradientY){
	dim3 blockSize = dim3(defaultThreadCount, defaultThreadCount);
	dim3 gridSize =
		dim3(ceilMod(source.Width, defaultThreadCount),
		ceilMod(source.Height, defaultThreadCount));
	
	cudaSetOrientationInPixels << <gridSize, blockSize >> >(orientation, gradientX, gradientY);
	cudaError_t error = cudaGetLastError();
}

void OrientationFieldInPixels(float* orientation, float* sourceBytes, int width, int height){

	CUDAArray<float> source(sourceBytes, width, height);
	CUDAArray<float> Orientation(source.Width, source.Height);

	// фильтры Собеля
	float filterXLinear[9] = { -1, 0, 1, -2, 0, 2, -1, 0, 1 };
	float filterYLinear[9] = { -1, -2, -1, 0, 0, 0, 1, 2, 1 };
	// фильтры для девайса
	CUDAArray<float> filterX(filterXLinear, 3, 3);
	CUDAArray<float> filterY(filterYLinear, 3, 3);

	// Градиенты
	CUDAArray<float> Gx(width, height);
	CUDAArray<float> Gy(width, height);
	Convolve(Gx, source, filterX);
	Convolve(Gy, source, filterY);

	float* gx = Gx.GetData();
	
	SetOrientationInPixels(Orientation, source, Gx, Gy);
}

int main()
{
	cudaSetDevice (0);

	int width, height;
	int* pic = loadBmp ("d://1_1.bmp", &width, &height);

	float* fPic  = (float*) malloc (sizeof (float)*width*height);
	for ( int i = 0; i < width * height; i++ )
	{
		fPic[i] = (float) pic[i];
	}

	float* orient = new float[width * height];
	
	OrientationFieldInPixels (orient, fPic, width, height);

	Detect (orient, width, height);

	free(pic);
	free (fPic);
//	free (matrix);
	free (orient);

	return 0;
}