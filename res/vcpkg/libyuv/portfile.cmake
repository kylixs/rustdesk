vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO kylixs/libyuv
    REF main
    SHA512 9ee540f088882d598457c65d736c01c8786723a05aaa8dec6257550657bbc646d0f045add32404f7812379504737ea5a015b7306258ada78e63e4d62a9dd7f40
    HEAD_REF main
)

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DCMAKE_BUILD_TYPE=Release
)

vcpkg_cmake_install()

# Fix cmake config path issue
if(EXISTS "${CURRENT_PACKAGES_DIR}/lib/cmake/libyuv")
    vcpkg_cmake_config_fixup(CONFIG_PATH lib/cmake/libyuv)
endif()

vcpkg_fixup_pkgconfig()

file(INSTALL "${SOURCE_PATH}/LICENSE" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}" RENAME copyright)
