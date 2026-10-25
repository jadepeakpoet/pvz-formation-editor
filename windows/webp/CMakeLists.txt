include(FetchContent)
FetchContent_Declare(pvz_webp_sdk
  URL https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-1.6.0-windows-x64.zip
  URL_HASH SHA256=48886f506b21f62e4661f0f4cbfca19800897c385128e8902542d29a950c93f1
)
FetchContent_MakeAvailable(pvz_webp_sdk)
add_library(pvz_webp SHARED thumbnail_webp.cpp)
target_include_directories(pvz_webp PRIVATE "${pvz_webp_sdk_SOURCE_DIR}/include")
target_link_libraries(pvz_webp PRIVATE "${pvz_webp_sdk_SOURCE_DIR}/lib/libwebp.lib")
# Resolve the SDK's C runtime calls through the app's dynamic CRT. All encoder
# allocations are released inside this DLL via PvzWebPFree.
target_link_options(pvz_webp PRIVATE /NODEFAULTLIB:LIBCMT)
install(TARGETS pvz_webp RUNTIME DESTINATION "${INSTALL_BUNDLE_LIB_DIR}" COMPONENT Runtime)
install(FILES COPYING PATENTS DESTINATION "${INSTALL_BUNDLE_DATA_DIR}/licenses/libwebp" COMPONENT Runtime)
