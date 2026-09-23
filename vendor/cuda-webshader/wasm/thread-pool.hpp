#include <atomic>
#include <condition_variable>
#include <coroutine>
#include <exception>
#include <functional>
#include <mutex>
#include <thread>
#include <vector>
#include <cstddef>
// Reuse lane-frame storage per pthread. Otherwise every FFT row allocates 128
// coroutine frames through a contended shared allocator, hiding parallel gains.
alignas(std::max_align_t) static thread_local unsigned char cw_lane_arena[262144];
static thread_local size_t cw_lane_used=0;
static void* cw_lane_alloc(size_t size){size=(size+15)&~size_t(15);if(cw_lane_used+size>sizeof(cw_lane_arena))return ::operator new(size);void* p=cw_lane_arena+cw_lane_used;cw_lane_used+=size;return p;}
static void cw_lane_free(void* p){auto address=reinterpret_cast<uintptr_t>(p),base=reinterpret_cast<uintptr_t>(cw_lane_arena);if(address<base||address>=base+sizeof(cw_lane_arena))::operator delete(p);}
// Pthreads run independent workgroups concurrently. Cooperating lanes inside a
// workgroup are stackless coroutines: each barrier suspends every live lane.
struct CwLane {
 struct promise_type {
  static void* operator new(size_t size){return cw_lane_alloc(size);}
  static void operator delete(void* p,size_t){cw_lane_free(p);}
  int barrier=-1;
  CwLane get_return_object(){return {std::coroutine_handle<promise_type>::from_promise(*this)};}
  std::suspend_always initial_suspend() noexcept{return {};}
  std::suspend_always final_suspend() noexcept{return {};}
  void return_void() noexcept{}
  void unhandled_exception(){std::terminate();}
 };
 std::coroutine_handle<promise_type> handle;
};
struct CwBarrier {
 int site;
 bool await_ready() const noexcept{return false;}
 void await_suspend(std::coroutine_handle<CwLane::promise_type> h) const noexcept{h.promise().barrier=site;}
 void await_resume() const noexcept{}
};
static std::mutex cw_mutex;
static std::condition_variable cw_work,cw_done;
static std::vector<std::thread> cw_workers;
static std::function<void(unsigned)> cw_job;
static std::atomic<unsigned> cw_next{0};
static std::atomic<int> cw_fault{0};
static std::atomic<unsigned> cw_groups[8];
static thread_local unsigned cw_slot=0;
extern "C" unsigned cw_worker_groups(int slot){return slot>=0&&slot<8?cw_groups[slot].load():0;}
static unsigned cw_count=0,cw_epoch=0,cw_finished=0;
static bool cw_stop=false;
static void cw_consume(const std::function<void(unsigned)>& job){for(;;){unsigned i=cw_next.fetch_add(1,std::memory_order_relaxed);if(i>=cw_count)break;job(i);cw_groups[cw_slot]++;}}
extern "C" int cw_init(int count){
 if(!cw_workers.empty()||count<1||count>8)return -1;
 cw_stop=false;
 for(int i=1;i<count;i++)cw_workers.emplace_back([i]{
  cw_slot=i;
  unsigned epoch=0;
  for(;;){std::unique_lock<std::mutex> lock(cw_mutex);cw_work.wait(lock,[&]{return cw_stop||cw_epoch!=epoch;});if(cw_stop)return;epoch=cw_epoch;auto job=cw_job;lock.unlock();cw_consume(job);lock.lock();cw_finished++;cw_done.notify_one();}
 });return count;
}
extern "C" void cw_shutdown(){
 {std::lock_guard<std::mutex> lock(cw_mutex);cw_stop=true;}cw_work.notify_all();for(auto& t:cw_workers)t.join();cw_workers.clear();
}
static int cw_parallel(unsigned count,std::function<void(unsigned)> job){
 {std::lock_guard<std::mutex> lock(cw_mutex);cw_job=job;cw_count=count;cw_finished=0;cw_next=0;cw_fault=0;for(auto& n:cw_groups)n=0;cw_epoch++;}
 cw_work.notify_all();cw_consume(job);
 std::unique_lock<std::mutex> lock(cw_mutex);cw_done.wait(lock,[]{return cw_finished==cw_workers.size();});cw_job={};return cw_fault.load();
}
