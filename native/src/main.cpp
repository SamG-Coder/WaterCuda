#include "renderer.hpp"
#include <algorithm>
#include <chrono>
#include <cmath>
#include <fstream>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <thread>
#ifdef _WIN32
#include <windows.h>
#include <windowsx.h>
#endif
void Scene::preset(const std::string& name){
 const char* names[]={"coast","aerial","water","shore","scrub","bars","reef","coral","family","ship"};
 const float views[][5]={{1250,210,650,.52f,-.10f},{-300,1400,-300,.7f,-.34f},{1550,7,1100,.52f,.025f},{1850,25,1250,.15f,-.30f},{2810.9f,11.51f,1131.74f,0,-.20f},{3370,42,2770,-1.4f,-.23f},{4377,-7,2784,0,-.12f},{4377,-7.3f,2810.8f,0,-.18f},{4377,-6.5f,2805,0,-.23f},{682,16,612,-.70f,-.035f}};
 for(int i=0;i<10;i++)if(name==names[i]){std::copy(views[i],views[i]+5,camera.begin());camera[14]=name=="ship"?3:(name=="family"?2:(name=="coral"?1:0));if(name=="ship"){camera[16]=650;camera[17]=0;camera[18]=650;camera[19]=0;camera[23]=100;camera[3]=-.6f;camera[4]=-.18f;camera[19]=camera[3];camera[32]=camera[19];camera[33]=camera[34]=0;camera[24]=camera[25]=0;}origin[0]=origin[1]=0;rebase();return;}
 throw std::runtime_error("Unknown view: "+name);
}
void Scene::rebase(){
 for(int axis:{0,2}){double shift=std::floor(double(camera[axis])/4800);int slot=axis==0?0:1;double next=origin[slot]+shift;
  if(!std::isfinite(next)||next < -2147480000.0||next>2147480000.0)throw std::runtime_error("World coordinate limit reached.");
  origin[slot]=int(next);camera[axis]=float(double(camera[axis])-shift*4800);if(camera[14]>=3){camera[axis+16]-=float(shift*4800);camera[axis+29]-=float(shift*4800);}}
}
void saveBmp(const std::string& path,const std::vector<std::uint32_t>& rgba,int width,int height){
 std::ofstream file(path,std::ios::binary);if(!file)throw std::runtime_error("Cannot create "+path);
 auto word=[&](std::uint32_t v,int n){for(int i=0;i<n;i++)file.put(char(v>>(8*i)));};
 file.write("BM",2);word(54+width*height*4,4);word(0,4);word(54,4);word(40,4);word(width,4);word(std::uint32_t(-height),4);word(1,2);word(32,2);word(0,4);word(width*height*4,4);for(int i=0;i<4;i++)word(0,4);
 for(auto v:rgba)word((v&0xff00ff00u)|((v&255)<<16)|((v>>16)&255),4);
 if(!file)throw std::runtime_error("Failed writing "+path);std::cout<<"Saved "<<path<<"\n";
}
struct Options {float orbit=std::numeric_limits<float>::quiet_NaN();int width=1280,height=720,frames=0,seed=884,hour=12;bool headless=false,selfTest=false,hidden=false;std::string view="coast",weather="auto",output;};
int integer(const std::string& text){size_t end=0;long long n=std::stoll(text,&end);if(end!=text.size()||n<0||n>2147483647)throw std::runtime_error("Invalid integer: "+text);return int(n);}
Options parse(int argc,char** argv){Options o;for(int i=1;i<argc;i++){
 std::string arg=argv[i];auto value=[&](){if(i+1>=argc)throw std::runtime_error("Missing value after "+arg);return std::string(argv[++i]);};
 if(arg=="--headless")o.headless=true;else if(arg=="--self-test")o.selfTest=true;else if(arg=="--hidden")o.hidden=true;
 else if(arg=="--orbit"){o.orbit=std::stof(value());if(!std::isfinite(o.orbit))throw std::runtime_error("Invalid orbit angle");}else if(arg=="--width")o.width=integer(value());else if(arg=="--height")o.height=integer(value());else if(arg=="--seed")o.seed=integer(value());else if(arg=="--frames")o.frames=integer(value());else if(arg=="--hour")o.hour=integer(value())%24;else if(arg=="--weather")o.weather=value();else if(arg=="--view")o.view=value();else if(arg=="--output")o.output=value();
 else if(arg=="--help"){std::cout<<"WaterCuda native CUDA\n  --headless --frames N --output frame.bmp\n  --width 1280 --height 720 --seed 884\n  --view coast|aerial|water|shore|scrub|bars|reef|coral|family|ship\n  --weather auto|clear|overcast|rain|storm --hour 0..23\n  --self-test  Compare real GPU samples against the shared reference\n\nWindows viewer: WASD fly, Q/E vertical, Shift boost, Z slow, drag to look,\nF mouse capture, Esc release/exit, wheel changes speed without an upper cap,\n1..8 views, P pause world, R reflections, C caustics, N debug, L light,\nJ/K hour, T weather, G next seed, +/- render resolution, H help, F12 save watercuda-native.bmp.\n";std::exit(0);}
 else throw std::runtime_error("Unknown option: "+arg);
 }if(o.hidden&&!o.frames)throw std::runtime_error("--hidden requires a finite --frames count.");if(o.width<64||o.width>7680||o.height<64||o.height>4320)throw std::runtime_error("Dimensions must be 64..7680 by 64..4320.");return o;}
void checkPixels(const std::vector<std::uint32_t>& pixels){if(pixels.empty())throw std::runtime_error("Empty rendered frame.");auto first=pixels.front();bool varied=false;for(auto p:pixels){if((p>>24)!=255)throw std::runtime_error("Non-opaque render output.");varied|=p!=first;}if(!varied)throw std::runtime_error("Uniform render output.");}
#ifdef _WIN32
struct Viewer {
 Scene scene;Renderer& renderer;Options options;HWND window{};bool keys[256]{},drag=false,steeringDrag=false,locked=false,paused=false,help=true,save=false,quit=false;POINT last{};double speed=60;int look=0;std::vector<std::uint32_t> display;int renderWidth=0,renderHeight=0;
 void unlock(){if(!locked)return;locked=false;ClipCursor(nullptr);ShowCursor(TRUE);}
 void clear(){std::fill(std::begin(keys),std::end(keys),false);drag=false;steeringDrag=false;ReleaseCapture();unlock();}
 void aim(float dx,float dy){if(scene.camera[14]==3&&(locked||steeringDrag)){scene.camera[32]+=dx*.0022f;scene.camera[33]=std::clamp(scene.camera[33]-dy*.0022f,-1.f,1.f);return;}scene.camera[3]=std::remainder(scene.camera[3]+dx*.0022f,6.2831853f);scene.camera[4]=std::clamp(scene.camera[4]-dy*.0022f,-1.54f,1.54f);}
 void paint(){if(display.empty())return;RECT rc;GetClientRect(window,&rc);HDC dc=GetDC(window);BITMAPINFO bmi{};bmi.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);bmi.bmiHeader.biWidth=renderWidth;bmi.bmiHeader.biHeight=-renderHeight;bmi.bmiHeader.biPlanes=1;bmi.bmiHeader.biBitCount=32;
  StretchDIBits(dc,0,0,rc.right,rc.bottom,0,0,renderWidth,renderHeight,display.data(),&bmi,DIB_RGB_COLORS,SRCCOPY);
  if(help){SetBkMode(dc,OPAQUE);SetBkColor(dc,RGB(12,34,40));SetTextColor(dc,RGB(220,240,230));RECT text{16,16,rc.right-16,120};DrawTextA(dc,"WATERCUDA / NATIVE CUDA\nV exit / enter ship | B reset | W/S move | Left drag orbit | Right drag / F steer and pitch | A/D turn | Wheel speed | Shift boost | F capture\n1..8 free camera | P pause | R reflections | C caustics | L manual light | J/K hour | T weather | G seed\n+/- resolution | N debug | H help | F12 image | Esc release / exit",-1,&text,DT_LEFT|DT_NOPREFIX);}
  ReleaseDC(window,dc);
 }
 void key(WPARAM key){if(key=='J'||key=='K'){float hour=scene.camera[8]>=10?std::fmod(scene.camera[8]-10+scene.camera[5]/60,24.f):12;hour=std::fmod(hour+(key=='K'?1:23),24.f);scene.camera[8]=10+std::fmod(hour-std::fmod(scene.camera[5]/60,24.f)+24,24.f);}else if(key=='T')scene.camera[15]=(float)(((int)scene.camera[15]+1)%5);else if(key=='P')paused=!paused;else if(key=='H')help=!help;else if(key=='R')scene.camera[9]=1-scene.camera[9];else if(key=='C')scene.camera[13]=1-scene.camera[13];else if(key=='N')scene.camera[10]=float((int(scene.camera[10])+1)%3);else if(key=='G')scene.origin[2]=scene.origin[2]==2147483647?0:scene.origin[2]+1;
  else if(key=='V'){if(scene.camera[14]==3){scene.camera[14]=4;scene.camera[24]=0;}else if(scene.camera[14]==4){scene.camera[14]=3;scene.camera[3]=scene.camera[19];scene.camera[4]=scene.camera[25]-.18f;scene.camera[32]=scene.camera[19];scene.camera[33]=scene.camera[25];}}
  else if(key=='B'){scene.preset("ship");speed=25;}
  else if(key>= '1'&&key<='8'){const char* views[]={"coast","aerial","water","shore","scrub","bars","reef","coral","family","ship"};scene.preset(views[key-'1']);if(key=='8')speed=2;}
  else if(key=='L'){look=(look+1)%3;float values[][5]={{1,-.7f,.7f,1,1.5f},{.65f,1.05f,.16f,.95f,1.3f},{1.85f,-.45f,.48f,.94f,.7f}};auto v=values[look];scene.camera[6]=v[0];scene.camera[7]=v[1];scene.camera[8]=v[2];scene.camera[11]=v[3];scene.camera[12]=v[4];}
  else if(key==VK_ADD||key==VK_OEM_PLUS)options.width=std::min(3840,options.width+128);else if(key==VK_SUBTRACT||key==VK_OEM_MINUS)options.width=std::max(320,options.width-128);
  else if(key==VK_F12)save=true;else if(key==VK_ESCAPE){if(locked)unlock();else quit=true;}
  else if(key=='F'){if(locked)unlock();else{locked=true;RECT rc;GetClientRect(window,&rc);POINT a{rc.left,rc.top},b{rc.right,rc.bottom};ClientToScreen(window,&a);ClientToScreen(window,&b);RECT bounds{a.x,a.y,b.x,b.y};ClipCursor(&bounds);ShowCursor(FALSE);}}
 }
 void advance(double dt){auto& c=scene.camera;float forward=float(keys['W']||keys[VK_UP])-float(keys['S']||keys[VK_DOWN]),side=float(keys['D']||keys[VK_RIGHT])-float(keys['A']||keys[VK_LEFT]),vertical=float(keys['E']||keys[VK_SPACE])-float(keys['Q']);
  double x=std::sin(c[3])*std::cos(c[4])*forward+std::cos(c[3])*side,y=std::sin(c[4])*forward+vertical,z=std::cos(c[3])*std::cos(c[4])*forward-std::sin(c[3])*side,length=std::max(1.0,std::sqrt(x*x+y*y+z*z));
  if(c[14]==3){
   if(!paused){c[29]=c[16];c[30]=c[17];c[31]=c[18];c[26]=float(dt);float immersed=std::clamp(-c[17]/8,0.f,1.f);float targetSpeed=forward*float(speed)/(1+immersed*(2+float(speed)*.035f))*(keys[VK_SHIFT]?3:1)*(keys['Z']?.2f:1);
    c[24]+=(targetSpeed-c[24])*(1-std::exp(-float(dt)*(forward?1.8f:1.15f)));
    c[32]+=side*float(dt)*.65f;float turn=std::remainder(c[32]-c[19],6.2831853f);c[19]+=std::clamp(turn*(1-std::exp(-float(dt)*4)),-float(dt)*.8f,float(dt)*.8f);
    float pitchTarget=std::abs(c[33])<.035f?0:std::clamp(c[33],-1.f,1.f);c[25]+=(pitchTarget-c[25])*(1-std::exp(-float(dt)*3));
    if(locked||steeringDrag){float delta=std::remainder(c[19]-c[3],6.2831853f);c[3]+=delta*(1-std::exp(-float(dt)*3));c[4]+=(c[25]-.18f-c[4])*(1-std::exp(-float(dt)*3));}float velocity=c[24];
    float step=velocity*float(dt);c[16]+=std::sin(c[19])*std::cos(c[25])*step;c[18]+=std::cos(c[19])*std::cos(c[25])*step;c[17]=std::clamp(c[17]+std::sin(c[25])*step,-110.f,12000.f);c[5]+=float(dt);
   }
   float pitch=c[4];c[0]=c[16]-std::sin(c[3])*std::cos(pitch)*c[23];c[1]=c[17]+10-std::sin(pitch)*c[23];c[2]=c[18]-std::cos(c[3])*std::cos(pitch)*c[23];scene.rebase();return;
  }
  double step=speed*dt*(keys[VK_SHIFT]?5:1)*(keys['Z']?.2:1)/length;
  c[0]+=float(x*step);c[1]+=float(y*step);c[2]+=float(z*step);c[1]=std::clamp(c[1],-110.f,12000.f);scene.rebase();if(!paused)c[5]+=float(dt);
 }
};
LRESULT CALLBACK windowProc(HWND window,UINT message,WPARAM w,LPARAM l){auto* v=reinterpret_cast<Viewer*>(GetWindowLongPtr(window,GWLP_USERDATA));if(message==WM_NCCREATE){v=static_cast<Viewer*>(reinterpret_cast<CREATESTRUCT*>(l)->lpCreateParams);v->window=window;SetWindowLongPtr(window,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(v));}if(!v)return DefWindowProc(window,message,w,l);
 switch(message){case WM_CLOSE:v->quit=true;return 0;case WM_DESTROY:PostQuitMessage(0);return 0;case WM_KILLFOCUS:v->clear();return 0;
 case WM_KEYDOWN:if(w<256)v->keys[w]=true;if(!(l&(1LL<<30)))v->key(w);return 0;case WM_KEYUP:if(w<256)v->keys[w]=false;return 0;
 case WM_RBUTTONDOWN:v->steeringDrag=true;v->drag=true;v->last={GET_X_LPARAM(l),GET_Y_LPARAM(l)};SetCapture(window);SetFocus(window);return 0;
 case WM_LBUTTONDOWN:v->steeringDrag=false;v->drag=true;v->last={GET_X_LPARAM(l),GET_Y_LPARAM(l)};SetCapture(window);SetFocus(window);return 0;
 case WM_RBUTTONUP:case WM_LBUTTONUP:v->steeringDrag=false;v->drag=false;ReleaseCapture();return 0;
 case WM_MOUSEMOVE:if(v->drag&&!v->locked){POINT p{GET_X_LPARAM(l),GET_Y_LPARAM(l)};v->aim(float(p.x-v->last.x),float(p.y-v->last.y));v->last=p;}return 0;
 case WM_MOUSEWHEEL:{double speed=v->speed*std::pow(1.25,double(GET_WHEEL_DELTA_WPARAM(w))/WHEEL_DELTA);if(std::isfinite(speed))v->speed=std::max(3.0,speed);return 0;}
 case WM_INPUT:{RAWINPUT input{};UINT size=sizeof(input);if(GetRawInputData(reinterpret_cast<HRAWINPUT>(l),RID_INPUT,&input,&size,sizeof(RAWINPUTHEADER))!=UINT(-1)&&input.header.dwType==RIM_TYPEMOUSE&&v->locked)v->aim(float(input.data.mouse.lLastX),float(input.data.mouse.lLastY));break;}
 case WM_ERASEBKGND:return 1;case WM_PAINT:{PAINTSTRUCT ps;BeginPaint(window,&ps);EndPaint(window,&ps);v->paint();return 0;}
 }return DefWindowProc(window,message,w,l);
}
void runWindow(Renderer& renderer,Scene scene,const Options& options){
 SetProcessDPIAware();Viewer v{scene,renderer,options};if(scene.camera[14]==3)v.speed=25;else if(scene.camera[14]>.5f)v.speed=2;WNDCLASSA wc{};wc.lpfnWndProc=windowProc;wc.hInstance=GetModuleHandle(nullptr);wc.lpszClassName="WaterCudaNative";wc.hCursor=LoadCursor(nullptr,IDC_ARROW);if(!RegisterClassA(&wc)&&GetLastError()!=ERROR_CLASS_ALREADY_EXISTS)throw std::runtime_error("Cannot register window class.");
 RECT bounds{0,0,options.width,options.height};AdjustWindowRect(&bounds,WS_OVERLAPPEDWINDOW,FALSE);HWND window=CreateWindowA(wc.lpszClassName,"WaterCuda native CUDA",WS_OVERLAPPEDWINDOW,CW_USEDEFAULT,CW_USEDEFAULT,bounds.right-bounds.left,bounds.bottom-bounds.top,nullptr,nullptr,wc.hInstance,&v);if(!window)throw std::runtime_error("Cannot create native window.");
 RAWINPUTDEVICE mouse{1,2,0,window};if(!RegisterRawInputDevices(&mouse,1,sizeof(mouse))){DestroyWindow(window);throw std::runtime_error("Cannot register raw mouse input.");}
 if(!options.hidden)ShowWindow(window,SW_SHOW);
 auto last=std::chrono::steady_clock::now(),stats=last;int frames=0,interval=0;
 try{while(!v.quit){MSG msg;while(PeekMessage(&msg,nullptr,0,0,PM_REMOVE)){if(msg.message==WM_QUIT)v.quit=true;TranslateMessage(&msg);DispatchMessage(&msg);}if(v.quit)break;
  auto now=std::chrono::steady_clock::now();double dt=std::min(.1,std::chrono::duration<double>(now-last).count());last=now;
  if(IsIconic(window)){std::this_thread::sleep_for(std::chrono::milliseconds(20));continue;}
  v.advance(dt);RECT rc;GetClientRect(window,&rc);if(rc.right<=0||rc.bottom<=0)continue;
  v.renderWidth=std::max(64,std::min(v.options.width,int(rc.right)));v.renderHeight=std::clamp(int(double(v.renderWidth)*rc.bottom/rc.right),64,4320);renderer.resize(v.renderWidth,v.renderHeight);
  const auto& rgba=renderer.render(v.scene);v.display.resize(rgba.size());for(size_t i=0;i<rgba.size();i++){auto p=rgba[i];v.display[i]=(p&0xff00ff00u)|((p&255)<<16)|((p>>16)&255);}v.paint();
  if(v.save){saveBmp("watercuda-native.bmp",rgba,v.renderWidth,v.renderHeight);v.save=false;}
  frames++;interval++;double elapsed=std::chrono::duration<double>(now-stats).count();if(elapsed>=.5){std::string title="WaterCuda native | "+renderer.deviceName()+" | "+std::to_string(int(interval/elapsed))+" FPS | GPU "+std::to_string(renderer.gpuMs())+" ms | speed "+std::to_string(v.speed)+" m/s | seed "+std::to_string(v.scene.origin[2])+" | "+(v.scene.camera[8]>=10?"hour "+std::to_string(std::fmod(v.scene.camera[8]-10+v.scene.camera[5]/60,24.f)):"manual light");SetWindowTextA(window,title.c_str());stats=now;interval=0;}
  if(options.frames&&frames>=options.frames){checkPixels(rgba);if(!options.output.empty())saveBmp(options.output,rgba,v.renderWidth,v.renderHeight);break;}
 }}catch(...){v.clear();DestroyWindow(window);throw;}v.clear();DestroyWindow(window);std::cout<<"Native window rendered "<<frames<<" frames; GPU "<<renderer.gpuMs()<<" ms\n";
}
#endif
int main(int argc,char** argv){try{
 Options o=parse(argc,argv);Scene scene;scene.camera[8]=10+(float)o.hour;const char* weatherNames[]={"auto","clear","overcast","rain","storm"};bool validWeather=false;for(int i=0;i<5;i++)if(o.weather==weatherNames[i]){scene.camera[15]=(float)i;validWeather=true;}if(!validWeather)throw std::runtime_error("Unknown weather: "+o.weather);scene.origin[2]=o.seed;scene.preset(o.view);if(std::isfinite(o.orbit))scene.camera[3]=o.orbit;Renderer renderer;std::cout<<"Native CUDA device: "<<renderer.deviceName()<<"\n";
 if(o.selfTest){renderer.selfTest();return 0;}
 if(o.headless){renderer.resize(o.width,o.height);double gpu=0;std::array<double,5> stages{};int frames=o.frames?o.frames:1;for(int i=0;i<frames;i++){scene.camera[5]=3+float(i)/60;const auto& pixels=renderer.render(scene);gpu+=renderer.gpuMs();auto times=renderer.stageMs();for(int k=0;k<5;k++)stages[k]+=times[k];if(i==frames-1){checkPixels(pixels);if(!o.output.empty())saveBmp(o.output,pixels,o.width,o.height);}}
  std::cout<<"PASS: "<<frames<<" native GPU frames, "<<o.width<<" x "<<o.height<<", mean GPU "<<gpu/frames<<" ms\n";const char* labels[]={"prepare","terrain/water","billboards","reflections","shading"};for(int k=0;k<5;k++)std::cout<<labels[k]<<": "<<stages[k]/frames<<" ms\n";return 0;}
#ifdef _WIN32
 runWindow(renderer,scene,o);
#else
 throw std::runtime_error("The interactive viewer currently requires Windows. Use --headless on this platform.");
#endif
 return 0;
 }catch(const std::exception& e){std::cerr<<"WaterCuda: "<<e.what()<<"\n";return 1;}}
