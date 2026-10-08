# comfylogin.dll. 32-bit only: the 1.12 client is x86, so the DLL loaded into it must be too.
#   cmake -B build -A Win32 && cmake --build build --config Release
# The patch, patch-W.mpq, is built by build.js and does not need this.
cmake_minimum_required(VERSION 3.15)
# CMP0091 must be NEW before project() for CMAKE_MSVC_RUNTIME_LIBRARY to take effect.
cmake_policy(SET CMP0091 NEW)

# Static CRT: the DLL is dropped into a game folder that may have no VC++ redistributable.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

project(comfylogin CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(comfylogin SHARED
    src/dll/comfylogin.cpp
)

# crypt32 gives DPAPI and the base64 helpers.
target_link_libraries(comfylogin PRIVATE crypt32)

# comfylogin.dll, loaded by VanillaFixes from dlls.txt. It exports nothing. The DLL lands in the project
# root next to patch-W.mpq; the empty $<0:> stops MSVC adding a per-config subfolder.
set_target_properties(comfylogin PROPERTIES
    OUTPUT_NAME "comfylogin"
    PREFIX ""
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}$<0:>")

if(MSVC)
    target_compile_options(comfylogin PRIVATE /W3 /permissive- /GS- /utf-8)
endif()
