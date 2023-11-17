include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(marcel_supports_sanitizers)
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

macro(marcel_setup_options)
  option(marcel_ENABLE_HARDENING "Enable hardening" ON)
  option(marcel_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    marcel_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    marcel_ENABLE_HARDENING
    OFF)

  marcel_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR marcel_PACKAGING_MAINTAINER_MODE)
    option(marcel_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(marcel_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(marcel_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(marcel_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(marcel_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(marcel_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(marcel_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(marcel_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(marcel_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(marcel_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(marcel_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(marcel_ENABLE_PCH "Enable precompiled headers" OFF)
    option(marcel_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(marcel_ENABLE_IPO "Enable IPO/LTO" ON)
    option(marcel_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(marcel_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(marcel_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(marcel_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(marcel_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(marcel_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(marcel_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(marcel_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(marcel_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(marcel_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(marcel_ENABLE_PCH "Enable precompiled headers" OFF)
    option(marcel_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      marcel_ENABLE_IPO
      marcel_WARNINGS_AS_ERRORS
      marcel_ENABLE_USER_LINKER
      marcel_ENABLE_SANITIZER_ADDRESS
      marcel_ENABLE_SANITIZER_LEAK
      marcel_ENABLE_SANITIZER_UNDEFINED
      marcel_ENABLE_SANITIZER_THREAD
      marcel_ENABLE_SANITIZER_MEMORY
      marcel_ENABLE_UNITY_BUILD
      marcel_ENABLE_CLANG_TIDY
      marcel_ENABLE_CPPCHECK
      marcel_ENABLE_COVERAGE
      marcel_ENABLE_PCH
      marcel_ENABLE_CACHE)
  endif()

  marcel_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (marcel_ENABLE_SANITIZER_ADDRESS OR marcel_ENABLE_SANITIZER_THREAD OR marcel_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(marcel_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(marcel_global_options)
  if(marcel_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    marcel_enable_ipo()
  endif()

  marcel_supports_sanitizers()

  if(marcel_ENABLE_HARDENING AND marcel_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR marcel_ENABLE_SANITIZER_UNDEFINED
       OR marcel_ENABLE_SANITIZER_ADDRESS
       OR marcel_ENABLE_SANITIZER_THREAD
       OR marcel_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${marcel_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${marcel_ENABLE_SANITIZER_UNDEFINED}")
    marcel_enable_hardening(marcel_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(marcel_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(marcel_warnings INTERFACE)
  add_library(marcel_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  marcel_set_project_warnings(
    marcel_warnings
    ${marcel_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(marcel_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    configure_linker(marcel_options)
  endif()

  include(cmake/Sanitizers.cmake)
  marcel_enable_sanitizers(
    marcel_options
    ${marcel_ENABLE_SANITIZER_ADDRESS}
    ${marcel_ENABLE_SANITIZER_LEAK}
    ${marcel_ENABLE_SANITIZER_UNDEFINED}
    ${marcel_ENABLE_SANITIZER_THREAD}
    ${marcel_ENABLE_SANITIZER_MEMORY})

  set_target_properties(marcel_options PROPERTIES UNITY_BUILD ${marcel_ENABLE_UNITY_BUILD})

  if(marcel_ENABLE_PCH)
    target_precompile_headers(
      marcel_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(marcel_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    marcel_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(marcel_ENABLE_CLANG_TIDY)
    marcel_enable_clang_tidy(marcel_options ${marcel_WARNINGS_AS_ERRORS})
  endif()

  if(marcel_ENABLE_CPPCHECK)
    marcel_enable_cppcheck(${marcel_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(marcel_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    marcel_enable_coverage(marcel_options)
  endif()

  if(marcel_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(marcel_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(marcel_ENABLE_HARDENING AND NOT marcel_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR marcel_ENABLE_SANITIZER_UNDEFINED
       OR marcel_ENABLE_SANITIZER_ADDRESS
       OR marcel_ENABLE_SANITIZER_THREAD
       OR marcel_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    marcel_enable_hardening(marcel_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
