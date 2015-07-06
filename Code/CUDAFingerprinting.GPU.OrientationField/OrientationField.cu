#define _USE_MATH_DEFINES 
#include <stdio.h>
#include <stdlib.h>
#include <float.h>
#include <math.h>
#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#include "Convolution.cuh"
#include "constsmacros.h"
#include "CUDAArray.cuh"

__global__ void cudaSetOrientation(CUDAArray<float> orientation, CUDAArray<float> gradientX, CUDAArray<float> gradientY){
	float numerator = 0;
	float denominator = 0;
	int row = blockIdx.y;
	int column = blockIdx.x;

	// ���������� ��������� � �����������
	// ������� ����������� ��������������� �������� �������, ��������� �������� � shared ������
	__shared__ CUDAArray<float> product(gradientX);
	__shared__ CUDAArray<float> sqrdiff(gradientX);
	int column = defaultColumn();
	int row = defaultRow();
	int threadColumn = threadIdx.x;
	int threadRow = threadIdx.y;
	float gradientYValue = gradientY.At(row, column);

	product.SetAt(threadRow, threadColumn, product.At(threadRow, threadColumn) * gradientYValue); // �������� � ����� ������ ������������ ��������������� ��������� 
	sqrdiff.SetAt(threadRow, threadColumn, sqrdiff.At(threadRow, threadColumn) * sqrdiff.At(threadRow, threadColumn) - gradientYValue * gradientYValue); // �������� ���������
	__syncthreads();  // ���� ���� ��� ���� ������� ����������

	// ������ ����� �������������� �������� ������
	// ��������� �������� �����, ���������� ����� ����� � ������ ������� 
	for (int s = blockDim.x / 2; s > 0; s = s / 2) {		// ��������� ���, ����� ���� �� �������� � ����� � ��� �� �������
		if (threadColumn < s) {
			product.SetAt(threadRow, threadColumn, product.At(threadRow, threadColumn) + product.At(threadRow, threadColumn + s));
			sqrdiff.SetAt(threadRow, threadColumn, sqrdiff.At(threadRow, threadColumn) + sqrdiff.At(threadRow, threadColumn + s));
		}
		__syncthreads();
	}
	// ��������� �������� ������� �������, �������� ����� ����
	if (threadColumn == 0){
		for (int s = blockDim.y / 2; s > 0; s = s / 2) {		// ��������� ���, ����� ���� �� �������� � ����� � ��� �� �������
			if (threadRow < s) {
				product.SetAt(threadRow, threadColumn, product.At(threadRow, threadColumn) + product.At(threadRow + s, threadColumn));
				sqrdiff.SetAt(threadRow, threadColumn, sqrdiff.At(threadRow, threadColumn) + sqrdiff.At(threadRow + s, threadColumn));
			}
			__syncthreads();
		}
	}

	// ����� ������� ������ ���������� ����� ��������� � ���������� � product[0, 0] � sqrdiff[0, 0]
	numerator = 2 * product.At(0, 0);
	denominator = sqrdiff.At(0, 0);

	// ���������� �������� ���� ����������
	if (denominator == 0){
		orientation.SetAt(row, column, M_PI_2);
	}
	else{
		orientation.SetAt(row, column, M_PI_2 + atan2(2 * numerator, denominator) / 2.0);
		if (orientation.At(row, column) > M_PI_2){
			orientation.SetAt(row, column, orientation.At(row, column) - M_PI);
		}
	}
}



void SetOrientation(CUDAArray<float> orientation, CUDAArray<float> source, int defaultBlockSize, CUDAArray<float> gradientX, CUDAArray<float> gradientY){
	dim3 blockSize = dim3(defaultBlockSize, defaultBlockSize);
	dim3 gridSize =
		dim3(ceilMod(source.Width, defaultBlockSize),
		ceilMod(source.Height, defaultBlockSize));
	cudaSetOrientation <<<gridSize, blockSize >>>(orientation, gradientX, gradientY);
}

void OrientationField(CUDAArray<float> source, int sizeX, int sizeY){
	const int defaultBlockSize = 16;
	CUDAArray<float> Orientation(sizeY, sizeX);

	// ������� ������
	float filterXLinear[9] = { -1, 0, 1, -2, 0, 2, -1, 0, 1 };
	float filterYLinear[9] = { -1, -2, -1, 0, 0, 0, 1, 2, 1 };
	// ������� ��� �������
	CUDAArray<float> filterX(filterXLinear, 3, 3);
	CUDAArray<float> filterY(filterYLinear, 3, 3);

	// ���������
	CUDAArray<float> Gx;
	CUDAArray<float> Gy;
	Convolve(Gx, source, filterX);
	Convolve(Gy, source, filterX);

	// ��������� �����������
	SetOrientation(Orientation, source, defaultBlockSize, Gx, Gy);
}

