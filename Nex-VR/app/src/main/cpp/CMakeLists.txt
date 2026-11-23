# Nex VR — Stage 74: native el kinematiği kitaplığı (libnxhand.so)
cmake_minimum_required(VERSION 3.18.1)
project(nxhand CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(nxhand SHARED hand_kinematics.cpp jni_bridge.cpp)

# Hız için: -O2 + hızlı matematik yok (NaN denetimleri çalışsın diye -ffast-math KULLANILMAZ).
target_compile_options(nxhand PRIVATE -O2 -fno-exceptions -fno-rtti -Wall -Wextra)
# Android 15+ 16 KB sayfa boyutu uyumluluğu
target_link_options(nxhand PRIVATE "-Wl,-z,max-page-size=16384")
