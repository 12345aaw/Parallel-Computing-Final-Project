#include<stdlib.h>
#include<stdio.h>
#include<stdbool.h>
#include "timerc.h"
#define gpuErrchk(ans) {gpuAssert((ans),__FILE__,__LINE__);}

__device__ int global_num_areas = 32;
int global_num_areas_serial = 32;

__global__ void warmup(){

}

inline void gpuAssert(cudaError_t code, const char  *file, int line, bool abort = true){
  if (code != cudaSuccess){
    fprintf(stderr,"GPUassert: %s %s %d \n", cudaGetErrorString(code), file, line);
    if (abort) exit(code);
  }
}

__device__ bool isBetweenPointsInclusive(int a, int b, int x1, int x2 ){
  // Tests whether or not the segment exists between 2 given x coordinates
  // Holds true if (either of the points are inside the interval) or if (both are on opposite sides of the interval), but not if (both are on one side of the interval)
  if( (a <= x1 && b >= x2) || (a >= x1 && a <= x2) || (b >= x1 && b <= x2)  ){
    return true;
  }
  return false;
};

bool isBetweenPointsInclusiveSerial(int a, int b, int x1, int x2 ){
  // Tests whether or not the segment exists between 2 given x coordinates
  // Holds true if (either of the points are inside the interval) or if (both are on opposite sides of the interval), but not if (both are on one side of the interval)
  if( (a <= x1 && b >= x2) || (a >= x1 && a <= x2) || (b >= x1 && b <= x2)  ){
    return true;
  }
  return false;
};

__device__ void printLowerEnvelope(int * min_y, int size){
  for(int i = 0; i < size; i++){
    printf("The minimum y value between x = %d and x = %d is %d \n", i,i+1, min_y[i]);
  }
}

void printLowerEnvelopeSerial(int * min_y, int size){
  for(int i = 0; i < size; i++){
    printf("The minimum y value between x = %d and x = %d is %d \n", i,i+1, min_y[i]);
  }
}

int * lower_envelope(int * coordinate_array, int size){
  // Input is an array of non-intersecting segments
  // Output is an array of points where p_i's are endpoints of segments with increasing x coordinates
  // Output 2 is a corresponding label list that specifies which segment is visible between each adjacent pair of endpoints 
  // The coordinate array contains alternating x and y coordinates so that consecutive segments are defined
  // Each segment specifies 4 coordinates

  // CHANGE THIS TO SPECIFY X GRID SIZE
  int number_areas = global_num_areas_serial;


  int * min_y = (int *) malloc(number_areas * sizeof(int));
  // For each area between points
  for(int i = 0; i < number_areas; i++){
    min_y[i] = 99999;
    // For each segment update the min_y array if betweeen segment exists between the points x = i and x = i+1
    for(int j = 0; j < size - 1; j = j + 4){
      if(isBetweenPointsInclusiveSerial(coordinate_array[j],coordinate_array[j+2],i,i+1) && coordinate_array[j+1] < min_y[i]){
        min_y[i] = coordinate_array[j+1];
      }
    }
  }
  printLowerEnvelopeSerial(min_y,number_areas);
  return min_y;
};

__global__ void parallel_lower_envelope(int * coordinate_array, int number_of_threads, int coordinate_array_size, int * min_y){
  // Number of areas between x values
  int number_areas = global_num_areas;
  // For each area between points
  int numElementsPerThread = number_areas / (gridDim.x * blockDim.x);
  int cumulative_thread_id = threadIdx.x + (blockDim.x*blockIdx.x);
  int startPos = cumulative_thread_id * numElementsPerThread;
  // Each thread computes their own min_y index
  for(int i = 0; i < numElementsPerThread; i++){
    int i_thread = i + startPos;
    min_y[i_thread] = 99999;
    // For each segment update the min_y array if betweeen segment exists between the points x = i and x = i+1
    for(int j = 0; j < coordinate_array_size - 1; j = j + 4){
      if(isBetweenPointsInclusive(coordinate_array[j],coordinate_array[j+2],i_thread,i_thread+1) && coordinate_array[j+1] < min_y[i_thread]){
        min_y[i_thread] = coordinate_array[j+1];
      }
    }   
  }
  __syncthreads();
  if(cumulative_thread_id == 0){
    printLowerEnvelope(min_y,number_areas);
  }
};

int main(){
  int * segment_array;
  int * device_input;
  int * device_output;

  // Initial memory allocation
  segment_array = (int *) malloc(16 * sizeof(int));
  segment_array[0] = 1;  // s1.p1.x = 1
  segment_array[1] = 1;  // s1.p1.y = 1
  segment_array[2] = 3;  // s1.p2.x = 3
  segment_array[3] = 3;  // s1.p2.y = 3
  segment_array[4] = 0;  // s2.p1.x = 0
  segment_array[5] = 0;  // s2.p1.y = 0
  segment_array[6] = 2;  // s2.p2.x = 2
  segment_array[7] = 2;  // s2.p2.y = 2
  segment_array[8] = 4;  // s3.p1.x = 4
  segment_array[9] = 4;  // s3.p1.y = 4
  segment_array[10] = 5; // s3.p2.x = 5
  segment_array[11] = 5; // s3.p2.y = 5
  segment_array[12] = 3;
  segment_array[13] = 3;
  segment_array[14] = 0;
  segment_array[15] = 0;

  float CPUtime;

  cstart();
  lower_envelope(segment_array,16);
  cend(&CPUtime);
  
  printf("Naive CPU time is %f \n", CPUtime);

  cudaMalloc((void **) &device_input, 16 * sizeof(int));
  cudaMemcpy(device_input,segment_array,16 * sizeof(int),cudaMemcpyHostToDevice);

  float GPUtime;
  
  cudaMalloc((void **) &device_output, global_num_areas_serial * sizeof(int));

  warmup<<<1,1>>>();

  gstart();
  parallel_lower_envelope<<<4,4>>>(device_input,4,16,device_output); 
  gend(&GPUtime);
  printf("Naive GPU time is %f \n", GPUtime);
  gpuErrchk(cudaPeekAtLastError());
  gpuErrchk(cudaDeviceSynchronize());

  cudaDeviceSynchronize();
 return 0;
}
