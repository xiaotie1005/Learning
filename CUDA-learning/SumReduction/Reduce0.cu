#include "MyCuda.h"

/**
* 在GPU利用 Interleaved Addressing 法上计算数组的和
* Interleaved Addressing 的核心思想在于交错寻址，即典型的树状模型
* 问题：1.每个warp中都会出现分支，效率低；2.取余操作效率较低
* globalInputData  输入数据，位于全局内存
* globalOutputData 输出数据，位于全局内存
*/
__global__ void reduce0(float *globalInputData, float *globalOutputData, unsigned int n)
{
	__shared__ float sdata[BLOCK_SIZE];

	// 坐标索引
	unsigned int tid = threadIdx.x;
	unsigned int index = blockIdx.x*blockDim.x + threadIdx.x;

	// 数据读入共享内存
	sdata[tid] = (index < n) ? globalInputData[index] : 0; // 超出范围的置0

	__syncthreads(); // 同步，等待同一个block内的数据都拷贝到共享内存

	// 在共享内存中对每一个块进行规约计算
	for (unsigned int s = 1; s < blockDim.x; s *= 2)
	{
		// 取余操作速度很慢
		if ((tid % (2 * s)) == 0)
		{
			sdata[tid] += sdata[tid + s];
		}

		__syncthreads(); // 等待每一次的迭代计算完成
	}

	// 把计算结果从共享内存写回全局内存
	if (tid == 0)
	{
		globalOutputData[blockIdx.x] = sdata[0];
	}
}

/**
* 计算reduce0函数的时间
* fMatrix_Host  矩阵头指针
* iRow          矩阵行数
* iCol          矩阵列数
* @return       和
*/
float RuntimeOfReduce0(float *fMatrix_Host, const int iRow, const int iCol)
{

	// 检查矩阵维度是否正确
	if (iRow <= 0 || iCol <= 0)
	{
		std::cout << "The size of the matrix is error!" << std::endl;
		return 0.0;
	}

	float *fReuslt = (float*)malloc(sizeof(float));;
	float *fMatrix_Device; // 指向设备显存
	int iMatrixSize = iRow * iCol; // 矩阵元素个数

	HANDLE_ERROR(cudaMalloc((void**)&fMatrix_Device, iMatrixSize * sizeof(float))); // 在显存中为矩阵开辟空间
	HANDLE_ERROR(cudaMemcpy(fMatrix_Device, fMatrix_Host, iMatrixSize * sizeof(float), cudaMemcpyHostToDevice)); // 将数据拷贝到显存

	// 记录起始时间
	cudaEvent_t start_GPU, end_GPU;
	float elaspsedTime;

	cudaEventCreate(&start_GPU);
	cudaEventCreate(&end_GPU);
	cudaEventRecord(start_GPU, 0);

	for (int i = 1, int iNum = iMatrixSize; i < iMatrixSize; i = i*BLOCK_SIZE)
	{
		int iBlockNum = (iNum + BLOCK_SIZE - 1) / BLOCK_SIZE;
		reduce0<<<iBlockNum, BLOCK_SIZE>>>(fMatrix_Device, fMatrix_Device, iNum);
		iNum = iBlockNum;
	}

	HANDLE_ERROR(cudaMemcpy(fReuslt, fMatrix_Device, sizeof(float), cudaMemcpyDeviceToHost)); // 将数据拷贝到内存

	// 计时结束
	cudaEventRecord(end_GPU, 0);
	cudaEventSynchronize(end_GPU);
	cudaEventElapsedTime(&elaspsedTime, start_GPU, end_GPU);
	cudaEventDestroy(start_GPU);
	cudaEventDestroy(end_GPU);

	std::cout << "Reduce0 的运行时间为：" << elaspsedTime << "ms." << std::endl;

	HANDLE_ERROR(cudaFree(fMatrix_Device));// 释放显存空间

	return fReuslt[0];
}