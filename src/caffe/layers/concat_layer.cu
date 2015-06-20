#include <vector>

#include "caffe/layer.hpp"
#include "caffe/util/math_functions.hpp"
#include "caffe/vision_layers.hpp"

#ifdef USE_GREENTEA
#include "caffe/greentea/greentea.hpp"
#include "caffe/greentea/greentea_math_functions.hpp"
#endif

namespace caffe {

#ifdef USE_CUDA
template<typename Dtype>
__global__ void Concat(const int nthreads, const Dtype* in_data,
                       const bool forward, const int num_concats,
                       const int concat_size, const int top_concat_axis,
                       const int bottom_concat_axis,
                       const int offset_concat_axis, Dtype* out_data) {
  CUDA_KERNEL_LOOP(index, nthreads) {
    const int total_concat_size = concat_size * bottom_concat_axis;
    const int concat_num = index / total_concat_size;
    const int concat_index = index % total_concat_size;
    const int top_index = concat_index
        + (concat_num * top_concat_axis + offset_concat_axis) * concat_size;
    if (forward) {
      out_data[top_index] = in_data[index];
    } else {
      out_data[index] = in_data[top_index];
    }
  }
}
#endif  // USE_CUDA

template<typename Dtype>
void ConcatLayer<Dtype>::Forward_gpu(const vector<Blob<Dtype>*>& bottom,
                                     const vector<Blob<Dtype>*>& top) {
  Dtype* top_data = top[0]->mutable_gpu_data();
  int offset_concat_axis = 0;
  const int top_concat_axis = top[0]->shape(concat_axis_);
  const bool kForward = true;
  for (int i = 0; i < bottom.size(); ++i) {
    const Dtype* bottom_data = bottom[i]->gpu_data();
    const int bottom_concat_axis = bottom[i]->shape(concat_axis_);
    const int bottom_concat_size = bottom_concat_axis * concat_input_size_;
    const int nthreads = bottom_concat_size * num_concats_;

    if (this->device_context_.backend() == BACKEND_CUDA) {
#ifdef USE_CUDA
      // NOLINT_NEXT_LINE(whitespace/operators)
      Concat<Dtype> CUDA_KERNEL(CAFFE_GET_BLOCKS(nthreads),
                                CAFFE_CUDA_NUM_THREADS)(
          nthreads, bottom_data, kForward, num_concats_, concat_input_size_,
          top_concat_axis, bottom_concat_axis, offset_concat_axis, top_data);
#endif  // USE_CUDA
    } else {
#ifdef USE_GREENTEA

      viennacl::ocl::context &ctx = viennacl::ocl::get_context(
          this->device_context_.id());
      viennacl::ocl::program &program = Caffe::Get().GetDeviceProgram(
          this->device_context_.id());

      viennacl::ocl::kernel &oclk_concat = program.get_kernel(
          CL_KERNEL_SELECT("concat"));
      viennacl::ocl::enqueue(
          oclk_concat(nthreads, WrapHandle((cl_mem) bottom_data, &ctx),
                      kForward ? 1 : 0, num_concats_, concat_input_size_,
                      top_concat_axis, bottom_concat_axis, offset_concat_axis,
                      WrapHandle((cl_mem) top_data, &ctx)),
          ctx.get_queue());
#endif  // USE_GREENTEA
    }
    offset_concat_axis += bottom_concat_axis;
  }
}

template<typename Dtype>
void ConcatLayer<Dtype>::Backward_gpu(const vector<Blob<Dtype>*>& top,
                                      const vector<bool>& propagate_down,
                                      const vector<Blob<Dtype>*>& bottom) {
  const Dtype* top_diff = top[0]->gpu_diff();
  int offset_concat_axis = 0;
  const int top_concat_axis = top[0]->shape(concat_axis_);
  const bool kForward = false;
  for (int i = 0; i < bottom.size(); ++i) {
    if (!propagate_down[i]) {
      continue;
    }
    Dtype* bottom_diff = bottom[i]->mutable_gpu_diff();
    const int bottom_concat_axis = bottom[i]->shape(concat_axis_);
    const int bottom_concat_size = bottom_concat_axis * concat_input_size_;
    const int nthreads = bottom_concat_size * num_concats_;

    if (this->device_context_.backend() == BACKEND_CUDA) {
#ifdef USE_CUDA
      // NOLINT_NEXT_LINE(whitespace/operators)
      Concat<Dtype> CUDA_KERNEL(CAFFE_GET_BLOCKS(nthreads),
                                CAFFE_CUDA_NUM_THREADS)(
          nthreads, top_diff, kForward, num_concats_, concat_input_size_,
          top_concat_axis, bottom_concat_axis, offset_concat_axis, bottom_diff);
#endif  // USE_CUDA
    } else {
#ifdef USE_GREENTEA

      viennacl::ocl::context &ctx = viennacl::ocl::get_context(
          this->device_context_.id());
      viennacl::ocl::program &program = Caffe::Get().GetDeviceProgram(
          this->device_context_.id());

      viennacl::ocl::kernel &oclk_concat = program.get_kernel(
          CL_KERNEL_SELECT("concat"));
      viennacl::ocl::enqueue(
          oclk_concat(nthreads, WrapHandle((cl_mem) top_diff, &ctx),
                      kForward ? 1 : 0, num_concats_, concat_input_size_,
                      top_concat_axis, bottom_concat_axis, offset_concat_axis,
                      WrapHandle((cl_mem) bottom_diff, &ctx)),
          ctx.get_queue());
#endif  // USE_GREENTEA
    }

    offset_concat_axis += bottom_concat_axis;
  }
}

INSTANTIATE_LAYER_GPU_FUNCS(ConcatLayer);

}  // namespace caffe
