cmake_minimum_required(VERSION 3.14)
project(PocketServerHosting LANGUAGES CXX)

include(FetchContent)
if(POLICY CMP0135)
  cmake_policy(SET CMP0135 NEW)
endif()
set(HTTPLIB_INSTALL OFF)
set(HTTPLIB_USE_OPENSSL_IF_AVAILABLE OFF)
set(HTTPLIB_USE_ZLIB_IF_AVAILABLE OFF)
set(HTTPLIB_USE_BROTLI_IF_AVAILABLE OFF)
set(HTTPLIB_USE_ZSTD_IF_AVAILABLE OFF)
FetchContent_Declare(pocketserver_httplib
  URL https://github.com/yhirose/cpp-httplib/archive/refs/tags/v0.66.0.tar.gz
  URL_HASH SHA256=537a77cdb96d3b4ad64d0b7103971de52eac75cd4ee03a2fdb84417b0d742459
)
FetchContent_MakeAvailable(pocketserver_httplib)

add_library(pocketserver_hosting STATIC loopback_site_server.cpp)
target_include_directories(pocketserver_hosting PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_features(pocketserver_hosting PUBLIC cxx_std_17)
target_link_libraries(pocketserver_hosting PRIVATE httplib::httplib)

option(POCKETSERVER_HOSTING_TESTS "Build loopback engine smoke tests" OFF)
if(POCKETSERVER_HOSTING_TESTS)
  enable_testing()
  add_executable(loopback_site_smoke test/loopback_site_smoke.cpp)
  target_link_libraries(loopback_site_smoke PRIVATE pocketserver_hosting httplib::httplib)
  add_test(NAME loopback_site_smoke COMMAND loopback_site_smoke)
  set_tests_properties(loopback_site_smoke PROPERTIES TIMEOUT 15)
endif()
