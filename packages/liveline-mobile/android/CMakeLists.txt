cmake_minimum_required(VERSION 3.9.0)
project(LivelineMobile)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# The C++ library Nitrogen expects (LivelineMobileOnLoad.cpp loads "LivelineMobile").
add_library(LivelineMobile SHARED src/main/cpp/liveline.cpp)

# Adds the Nitrogen-generated C++ sources, includes and links (fbjni, RN, Nitro).
include(${CMAKE_SOURCE_DIR}/../nitrogen/generated/android/LivelineMobile+autolinking.cmake)
