vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO kylixs/aom
    REF main
    SHA512 f93c4c6cd5934e24fc0be91b1ed15b88fd19dbffffcd38e90ea08af9c779947c410e80c654b9f132492bb954d3c9217417d6534d8bc81728da3aeff0b10f4801
    HEAD_REF main
)

# Fix AVX2 compatibility for Ubuntu 18.04
vcpkg_replace_string("${SOURCE_PATH}/aom_dsp/flow_estimation/x86/disflow_avx2.c"
    "#include \"aom_dsp/flow_estimation/disflow.h\""
    "#include \"aom_dsp/flow_estimation/disflow.h\"
#ifndef _mm256_set_m128i
#define _mm256_set_m128i(hi, lo) _mm256_insertf128_si256(_mm256_castsi128_si256(lo), (hi), 1)
#endif"
)

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DCMAKE_BUILD_TYPE=Release
        -DENABLE_DOCS=OFF
        -DENABLE_EXAMPLES=OFF
        -DENABLE_TESTDATA=OFF
        -DENABLE_TESTS=OFF
        -DENABLE_TOOLS=OFF
        -DCONFIG_AV1_DECODER=1
        -DCONFIG_AV1_ENCODER=1
        -DCONFIG_MULTITHREAD=0
        -DCONFIG_RUNTIME_CPU_DETECT=0
        -DAOM_TARGET_CPU=generic
        -DENABLE_AVX2=OFF
        -DENABLE_SSE4_1=OFF
        -DENABLE_SSSE3=OFF
)

vcpkg_cmake_install()

# Fix cmake config path issue
if(EXISTS "${CURRENT_PACKAGES_DIR}/lib/cmake/aom")
    vcpkg_cmake_config_fixup(CONFIG_PATH lib/cmake/aom)
endif()

vcpkg_fixup_pkgconfig()

file(INSTALL "${SOURCE_PATH}/LICENSE" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}" RENAME copyright)
