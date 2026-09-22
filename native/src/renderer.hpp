#pragma once
#include <array>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>
struct Scene {
 std::array<float,16> camera{1250,210,650,.52f,-.10f,3,1,-.7f,.7f,1,0,1,1.5f,1,0,0};
 std::array<int,4> origin{0,0,884,0};
 void preset(const std::string& name);
 void rebase();
};
class Renderer {
 struct Impl;std::unique_ptr<Impl> impl;
public:
 Renderer();~Renderer();
 Renderer(const Renderer&)=delete;Renderer& operator=(const Renderer&)=delete;
 void resize(int width,int height);
 const std::vector<std::uint32_t>& render(const Scene& scene);
 void selfTest();
 std::string deviceName() const;
 float gpuMs() const;
};
void saveBmp(const std::string& path,const std::vector<std::uint32_t>& rgba,int width,int height);
