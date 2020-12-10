# Copyright 2018 Google
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Executes a CMake build of the external dependencies, which will pull them
# as ExternalProjects, under an "external" subdirectory.
function(download_external_sources)
  file(MAKE_DIRECTORY ${PROJECT_BINARY_DIR}/external)

  # Setup cmake environment.
  # These commands are executed from within the currect context, which has set
  # variables for the target platform. We use "env -i" to clear these
  # variables, and manually keep the PATH to regular bash path.
  if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
    # Windows doesn't have an 'env' command
    set(ENV_COMMAND "")
  else()
    set(firebase_command_line_path "$ENV{PATH}")
    set(ENV_COMMAND env -i PATH=${firebase_command_line_path})
  endif()

  if(IOS)
    set(external_platform "IOS")
  elseif(ANDROID)
    set(external_platform "ANDROID")
  else()
    set(external_platform "DESKTOP")
  endif()

  # When building with Firestore, use the NanoPB source from that instead.
  if(FIREBASE_INCLUDE_FIRESTORE)
    set(FIRESTORE_BINARY_DIR ${PROJECT_BINARY_DIR}/external/src/firestore-build)
    set(NANOPB_SOURCE_DIR ${FIRESTORE_BINARY_DIR}/external/src/nanopb)
  endif()

  # Set variables to indicate if local versions of third party libraries should
  # be used instead of downloading them.
  function(check_use_local_directory NAME)
    if (EXISTS ${${NAME}_SOURCE_DIR})
      set(DOWNLOAD_${NAME} OFF PARENT_SCOPE)
    else()
      set(DOWNLOAD_${NAME} ON PARENT_SCOPE)
    endif()
  endfunction()
  check_use_local_directory(BORINGSSL)
  check_use_local_directory(CURL)
  check_use_local_directory(FLATBUFFERS)
  check_use_local_directory(LIBUV)
  check_use_local_directory(NANOPB)
  check_use_local_directory(UWEBSOCKETS)
  check_use_local_directory(ZLIB)
  check_use_local_directory(FIREBASE_IOS_SDK)

  execute_process(
    COMMAND
      ${ENV_COMMAND} cmake
      -DCMAKE_INSTALL_PREFIX=${FIREBASE_INSTALL_DIR}
      -DFIREBASE_DOWNLOAD_DIR=${FIREBASE_DOWNLOAD_DIR}
      -DFIREBASE_EXTERNAL_PLATFORM=${external_platform}
      -DDOWNLOAD_BORINGSSL=${DOWNLOAD_BORINGSSL}
      -DDOWNLOAD_CURL=${DOWNLOAD_CURL}
      -DDOWNLOAD_FLATBUFFERS=${DOWNLOAD_FLATBUFFERS}
      -DDOWNLOAD_GOOGLETEST=${FIREBASE_CPP_BUILD_TESTS}
      -DDOWNLOAD_LIBUV=${DOWNLOAD_LIBUV}
      -DDOWNLOAD_NANOPB=${DOWNLOAD_NANOPB}
      -DDOWNLOAD_UWEBSOCKETS=${DOWNLOAD_UWEBSOCKETS}
      -DDOWNLOAD_ZLIB=${DOWNLOAD_ZLIB}
      -DDOWNLOAD_FIREBASE_IOS_SDK=${DOWNLOAD_FIREBASE_IOS_SDK}
      -DFIREBASE_CPP_BUILD_TESTS=${FIREBASE_CPP_BUILD_TESTS}
      ${PROJECT_SOURCE_DIR}/cmake/external
    OUTPUT_FILE ${PROJECT_BINARY_DIR}/external/output_cmake_config.txt
    WORKING_DIRECTORY ${PROJECT_BINARY_DIR}/external
  )

  # Run downloads in parallel if we know how
  if(CMAKE_GENERATOR STREQUAL "Unix Makefiles")
    set(cmake_build_args -j)
  endif()

  execute_process(
    COMMAND ${ENV_COMMAND} cmake --build . -- ${cmake_build_args}
    OUTPUT_FILE ${PROJECT_BINARY_DIR}/external/output_cmake_build.txt
    WORKING_DIRECTORY ${PROJECT_BINARY_DIR}/external
  )

  if(NOT ANDROID AND NOT IOS)
    # CMake's find_package(OpenSSL) doesn't quite work right with BoringSSL
    # unless the header file contains OPENSSL_VERSION_NUMBER.
    file(READ ${PROJECT_BINARY_DIR}/external/src/boringssl/src/include/openssl/opensslv.h TMP_HEADER_CONTENTS)
    if (NOT TMP_HEADER_CONTENTS MATCHES OPENSSL_VERSION_NUMBER)
      file(APPEND ${PROJECT_BINARY_DIR}/external/src/boringssl/src/include/openssl/opensslv.h
      "\n#ifndef OPENSSL_VERSION_NUMBER\n# define OPENSSL_VERSION_NUMBER  0x10010107L\n#endif\n")
    endif()
    # Also add an #include <stdlib.h> since openssl has it and boringssl
    # doesn't, and some of our code depends on the transitive dependency (this
    # is a bug).
    file(READ ${PROJECT_BINARY_DIR}/external/src/boringssl/src/include/openssl/rand.h TMP_HEADER2_CONTENTS)
    if (NOT TMP_HEADER2_CONTENTS MATCHES "<stdlib.h>")
      file(APPEND ${PROJECT_BINARY_DIR}/external/src/boringssl/src/include/openssl/rand.h
      "\n#include <stdlib.h>\n")
    endif()

    # Firestore's nanopb implementation needs to know not to run protoc if we are crosscompiling
    # (e.g. building for arm64 on an x86 mac).
    file(READ ${PROJECT_BINARY_DIR}/external/src/firestore/Firestore/Protos/CMakeLists.txt TMP_CMAKE_CONTENTS)
    if (NOT TMP_CMAKE_CONTENTS MATCHES "CMAKE_CROSSCOMPILING")
      string(REPLACE
             "if(WIN32 OR IOS OR ANDROID)"
             "if(WIN32 OR IOS OR ANDROID OR CMAKE_CROSSCOMPILING)"
             TMP_CMAKE_CONTENTS_NEW
             "${TMP_CMAKE_CONTENTS}")
      file(WRITE ${PROJECT_BINARY_DIR}/external/src/firestore/Firestore/Protos/CMakeLists.txt "${TMP_CMAKE_CONTENTS_NEW}")
    endif()
  endif()
endfunction()

# Builds a subset of external dependencies that need to be built before everything else.
function(build_external_dependencies)
  # Setup cmake environment.
  # These commands are executed from within the currect context, which has set
  # variables for the target platform. We use "env -i" to clear these
  # variables, and manually keep the PATH to regular bash path.
  if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
    # Windows doesn't have an 'env' command
    set(ENV_COMMAND "")
  else()
    set(firebase_command_line_path "$ENV{PATH}")
    set(firebase_command_line_home "$ENV{HOME}")
    set(ENV_COMMAND env -i PATH=${firebase_command_line_path} HOME=${firebase_command_line_home} )
  endif()

  message("CMake generator: ${CMAKE_GENERATOR}")
  message("CMake generator platform: ${CMAKE_GENERATOR_PLATFORM}")
  message("CMake toolchain file: ${CMAKE_TOOLCHAIN_FILE}")

  set(CMAKE_SUBBUILD_OPTIONS -G "${CMAKE_GENERATOR}")

  if (CMAKE_BUILD_TYPE)
    # If Release or Debug were specified, pass it along.
    set(CMAKE_SUBBUILD_OPTIONS
        ${CMAKE_SUBBUILD_OPTIONS}
        -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE}")
  endif()
  
  if(APPLE)
    # Propagate MacOS build flags.
    if(CMAKE_OSX_ARCHITECTURES)
      set(CMAKE_SUBBUILD_OPTIONS
          ${CMAKE_SUBBUILD_OPTIONS}
          -DCMAKE_OSX_ARCHITECTURES="${CMAKE_OSX_ARCHITECTURES}")
    endif()
  elseif(MSVC)
    # Propagate MSVC build flags.
    if(MSVC_RUNTIME_LIBRARY_STATIC)
      if (CMAKE_BUILD_TYPE STREQUAL "Debug")
        set(SUBBUILD_MSVC_RUNTIME_FLAG "/MTd")
      else()
        set(SUBBUILD_MSVC_RUNTIME_FLAG "/MT")
      endif()
    else()
      if (CMAKE_BUILD_TYPE STREQUAL "Debug")
        set(SUBBUILD_MSVC_RUNTIME_FLAG "/MDd")
      else()  # build type
        set(SUBBUILD_MSVC_RUNTIME_FLAG "/MD")
      endif()
    endif()
    set(CMAKE_SUBBUILD_OPTIONS
        ${CMAKE_SUBBUILD_OPTIONS}
        -DCMAKE_C_FLAGS=${SUBBUILD_MSVC_RUNTIME_FLAG}
        -DCMAKE_CXX_FLAGS=${SUBBUILD_MSVC_RUNTIME_FLAG}
        -A "${CMAKE_GENERATOR_PLATFORM}")
  else()
    # Propagate Linux build flags.
    if("${CMAKE_CXX_FLAGS}" MATCHES "-D_GLIBCXX_USE_CXX11_ABI=0")
      set(SUBBUILD_USE_CXX11_ABI 0)
    else()
      set(SUBBUILD_USE_CXX11_ABI 1)
    endif()
    set(CMAKE_SUBBUILD_OPTIONS
        ${CMAKE_SUBBUILD_OPTIONS}
          -DCMAKE_C_FLAGS="-D_GLIBCXX_USE_CXX11_ABI=${SUBBUILD_USE_CXX11_ABI}"
          -DCMAKE_CXX_FLAGS="-D_GLIBCXX_USE_CXX11_ABI=${SUBBUILD_USE_CXX11_ABI}")
    if(CMAKE_TOOLCHAIN_FILE)
      set(CMAKE_SUBBUILD_OPTIONS
          ${CMAKE_SUBBUILD_OPTIONS}
          -DCMAKE_TOOLCHAIN_FILE=${CMAKE_TOOLCHAIN_FILE})
    endif()
  endif()
  message("Sub-build options: ${CMAKE_SUBBUILD_OPTIONS}")

  if(NOT ANDROID AND NOT IOS)
    execute_process(
      COMMAND ${ENV_COMMAND} cmake -DOPENSSL_NO_ASM=TRUE ${CMAKE_SUBBUILD_OPTIONS} ../boringssl/src
      WORKING_DIRECTORY ${PROJECT_BINARY_DIR}/external/src/boringssl-build
      RESULT_VARIABLE boringssl_configure_status
    )
    if (boringssl_configure_status AND NOT boringssl_configure_status EQUAL 0)
      message(FATAL_ERROR "BoringSSL configure failed: ${boringssl_configure_status}")
    endif()
  
    # Run builds in parallel if we know how
    if(CMAKE_GENERATOR STREQUAL "Unix Makefiles")
      set(cmake_build_args -j)
    endif()
  
    execute_process(
      COMMAND ${ENV_COMMAND} cmake --build . --target ssl crypto -- ${cmake_build_args}
      WORKING_DIRECTORY ${PROJECT_BINARY_DIR}/external/src/boringssl-build
      RESULT_VARIABLE boringssl_build_status
    )
    if (boringssl_build_status AND NOT boringssl_build_status EQUAL 0)
      message(FATAL_ERROR "BoringSSL build failed: ${boringssl_build_status}")
    endif()
  endif()
endfunction()

# Populates directory variables for the given name to the location that name
# would be in after a call to download_external_sources, if the variable is
# not already a valid directory.
# Adds the source directory as a subdirectory if a CMakeLists file is found.
function(add_external_library NAME)
  cmake_parse_arguments(optional "" "BINARY_DIR" "" ${ARGN})

  if(optional_BINARY_DIR)
      set(BINARY_DIR "${optional_BINARY_DIR}")
  else()
      set(BINARY_DIR "${FIREBASE_BINARY_DIR}")
  endif()

  string(TOUPPER ${NAME} UPPER_NAME)
  if (NOT EXISTS ${${UPPER_NAME}_SOURCE_DIR})
    set(${UPPER_NAME}_SOURCE_DIR "${BINARY_DIR}/external/src/${NAME}")
    set(${UPPER_NAME}_SOURCE_DIR "${${UPPER_NAME}_SOURCE_DIR}" PARENT_SCOPE)
  endif()

  if (NOT EXISTS ${${UPPER_NAME}_BINARY_DIR})
    set(${UPPER_NAME}_BINARY_DIR "${${UPPER_NAME}_SOURCE_DIR}-build")
    set(${UPPER_NAME}_BINARY_DIR "${${UPPER_NAME}_BINARY_DIR}" PARENT_SCOPE)
  endif()

  message(STATUS "add_ext... ${UPPER_NAME}_SOURCE_DIR: ${${UPPER_NAME}_SOURCE_DIR}")
  message(STATUS "add_ext... ${UPPER_NAME}_BINARY_DIR: ${${UPPER_NAME}_BINARY_DIR}")

  if (EXISTS "${${UPPER_NAME}_SOURCE_DIR}/CMakeLists.txt")
    add_subdirectory(${${UPPER_NAME}_SOURCE_DIR} ${${UPPER_NAME}_BINARY_DIR}
            EXCLUDE_FROM_ALL)
  elseif (EXISTS "${${UPPER_NAME}_SOURCE_DIR}/src/CMakeLists.txt")
    add_subdirectory(${${UPPER_NAME}_SOURCE_DIR}/src ${${UPPER_NAME}_BINARY_DIR}
            EXCLUDE_FROM_ALL)
  endif()
endfunction()

# Copies a variable definition from a subdirectory into the parent scope
macro(copy_subdirectory_definition DIRECTORY VARIABLE)
  get_directory_property(
    ${VARIABLE}
    DIRECTORY ${DIRECTORY}
    DEFINITION ${VARIABLE}
  )
endmacro()
