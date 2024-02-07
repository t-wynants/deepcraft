include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(deepcraft_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(deepcraft_setup_options)
  option(deepcraft_ENABLE_HARDENING "Enable hardening" ON)
  option(deepcraft_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    deepcraft_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    deepcraft_ENABLE_HARDENING
    OFF)

  deepcraft_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR deepcraft_PACKAGING_MAINTAINER_MODE)
    option(deepcraft_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(deepcraft_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(deepcraft_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(deepcraft_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(deepcraft_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(deepcraft_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(deepcraft_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(deepcraft_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(deepcraft_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(deepcraft_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(deepcraft_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(deepcraft_ENABLE_PCH "Enable precompiled headers" OFF)
    option(deepcraft_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(deepcraft_ENABLE_IPO "Enable IPO/LTO" ON)
    option(deepcraft_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(deepcraft_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(deepcraft_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(deepcraft_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(deepcraft_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(deepcraft_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(deepcraft_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(deepcraft_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(deepcraft_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(deepcraft_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(deepcraft_ENABLE_PCH "Enable precompiled headers" OFF)
    option(deepcraft_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      deepcraft_ENABLE_IPO
      deepcraft_WARNINGS_AS_ERRORS
      deepcraft_ENABLE_USER_LINKER
      deepcraft_ENABLE_SANITIZER_ADDRESS
      deepcraft_ENABLE_SANITIZER_LEAK
      deepcraft_ENABLE_SANITIZER_UNDEFINED
      deepcraft_ENABLE_SANITIZER_THREAD
      deepcraft_ENABLE_SANITIZER_MEMORY
      deepcraft_ENABLE_UNITY_BUILD
      deepcraft_ENABLE_CLANG_TIDY
      deepcraft_ENABLE_CPPCHECK
      deepcraft_ENABLE_COVERAGE
      deepcraft_ENABLE_PCH
      deepcraft_ENABLE_CACHE)
  endif()

  deepcraft_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (deepcraft_ENABLE_SANITIZER_ADDRESS OR deepcraft_ENABLE_SANITIZER_THREAD OR deepcraft_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(deepcraft_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(deepcraft_global_options)
  if(deepcraft_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    deepcraft_enable_ipo()
  endif()

  deepcraft_supports_sanitizers()

  if(deepcraft_ENABLE_HARDENING AND deepcraft_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR deepcraft_ENABLE_SANITIZER_UNDEFINED
       OR deepcraft_ENABLE_SANITIZER_ADDRESS
       OR deepcraft_ENABLE_SANITIZER_THREAD
       OR deepcraft_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${deepcraft_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${deepcraft_ENABLE_SANITIZER_UNDEFINED}")
    deepcraft_enable_hardening(deepcraft_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(deepcraft_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(deepcraft_warnings INTERFACE)
  add_library(deepcraft_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  deepcraft_set_project_warnings(
    deepcraft_warnings
    ${deepcraft_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(deepcraft_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    configure_linker(deepcraft_options)
  endif()

  include(cmake/Sanitizers.cmake)
  deepcraft_enable_sanitizers(
    deepcraft_options
    ${deepcraft_ENABLE_SANITIZER_ADDRESS}
    ${deepcraft_ENABLE_SANITIZER_LEAK}
    ${deepcraft_ENABLE_SANITIZER_UNDEFINED}
    ${deepcraft_ENABLE_SANITIZER_THREAD}
    ${deepcraft_ENABLE_SANITIZER_MEMORY})

  set_target_properties(deepcraft_options PROPERTIES UNITY_BUILD ${deepcraft_ENABLE_UNITY_BUILD})

  if(deepcraft_ENABLE_PCH)
    target_precompile_headers(
      deepcraft_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(deepcraft_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    deepcraft_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(deepcraft_ENABLE_CLANG_TIDY)
    deepcraft_enable_clang_tidy(deepcraft_options ${deepcraft_WARNINGS_AS_ERRORS})
  endif()

  if(deepcraft_ENABLE_CPPCHECK)
    deepcraft_enable_cppcheck(${deepcraft_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(deepcraft_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    deepcraft_enable_coverage(deepcraft_options)
  endif()

  if(deepcraft_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(deepcraft_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(deepcraft_ENABLE_HARDENING AND NOT deepcraft_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR deepcraft_ENABLE_SANITIZER_UNDEFINED
       OR deepcraft_ENABLE_SANITIZER_ADDRESS
       OR deepcraft_ENABLE_SANITIZER_THREAD
       OR deepcraft_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    deepcraft_enable_hardening(deepcraft_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
