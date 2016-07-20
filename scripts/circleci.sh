#!/usr/bin/env bash

set -eux
set -o pipefail

INSTALL_PREFIX=$1

if [[ ${INSTALL_PREFIX:-false} == false ]]; then
    echo "please provide install prefix as first arg"
    exit 1
fi

export CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# ensure we start inside the osrm-backend directory (one level up)
cd ${CURRENT_DIR}/../

# we pin the mason version to avoid changes in mason breaking builds
MASON_VERSION="b709931"

if [[ `which pkg-config` ]]; then
    echo "Success: Found pkg-config";
else
    echo "echo you need pkg-config installed";
    exit 1;
fi;

if [[ `which node` ]]; then
    echo "Success: Found node";
else
    echo "echo you need node installed";
    exit 1;
fi;

function dep() {
    ./.mason/mason install $1 $2
    ./.mason/mason link $1 $2
}

function all_deps() {
    dep clang 3.8.0 &
    dep cmake 3.2.2 &
    dep lua 5.3.0 &
    dep luabind e414c57bcb687bb3091b7c55bbff6947f052e46b &
    dep boost 1.61.0 &
    dep boost_libatomic 1.61.0 &
    dep boost_libchrono 1.61.0 &
    dep boost_libsystem 1.61.0 &
    dep boost_libthread 1.61.0 &
    dep boost_libfilesystem 1.61.0 &
    dep boost_libprogram_options 1.61.0 &
    dep boost_libregex 1.61.0 &
    dep boost_libiostreams 1.61.0 &
    dep boost_libtest 1.61.0 &
    dep boost_libdate_time 1.61.0 &
    dep expat 2.1.1 &
    dep stxxl 1.4.1 &
    dep bzip2 1.0.6 &
    dep zlib system &
    dep tbb 43_20150316 &
    wait
}

function setup_mason() {
    if [[ ! -d ./.mason ]]; then
        git clone https://github.com/mapbox/mason.git ./.mason
        (cd ./.mason && git checkout ${MASON_VERSION})
    else
        echo "Updating to latest mason"
        (cd ./.mason && git fetch && git checkout ${MASON_VERSION})
    fi
    export MASON_HOME=$(pwd)/mason_packages/.link
    export PATH=$(pwd)/.mason:$PATH
    export CXX=${CXX:-clang++}
    export CC=${CC:-clang}
}


function main() {
    if [[ -d build ]]; then
        echo "$(pwd)/build already exists, please delete before re-running"
        exit 1
    fi
    setup_mason
    all_deps
    set +eu
    source scripts/install_node.sh 4
    set -eu
    # put mason installed ccache on PATH
    # then osrm-backend will pick it up automatically
    export CCACHE_VERSION="3.2.4"
    ./.mason/mason install ccache ${CCACHE_VERSION}
    export PATH=$(./.mason/mason prefix ccache ${CCACHE_VERSION})/bin:${PATH}
    # put mason installed clang 3.8.0 on PATH
    export PATH=$(./.mason/mason prefix clang 3.8.0)/bin:${PATH}
    which clang++ || true
    CMAKE_EXTRA_ARGS=""
    if [[ ${AR:-false} != false ]]; then
        CMAKE_EXTRA_ARGS="${CMAKE_EXTRA_ARGS} -DCMAKE_AR=${AR}"
    fi
    if [[ ${RANLIB:-false} != false ]]; then
        CMAKE_EXTRA_ARGS="${CMAKE_EXTRA_ARGS} -DCMAKE_RANLIB=${RANLIB}"
    fi
    if [[ ${NM:-false} != false ]]; then
        CMAKE_EXTRA_ARGS="${CMAKE_EXTRA_ARGS} -DCMAKE_NM=${NM}"
    fi
    mkdir build && cd build
    ${MASON_HOME}/bin/cmake ../ -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX} \
      -DCMAKE_CXX_COMPILER="${CXX}" \
      -DBoost_NO_SYSTEM_PATHS=ON \
      -DTBB_INSTALL_DIR=${MASON_HOME} \
      -DCMAKE_INCLUDE_PATH=${MASON_HOME}/include \
      -DCMAKE_LIBRARY_PATH=${MASON_HOME}/lib \
      -DCMAKE_BUILD_TYPE=${BUILD_TYPE} \
      -DBoost_USE_STATIC_LIBS=ON \
      -DBUILD_TOOLS=1 \
      -DENABLE_CCACHE=ON \
      -DBUILD_SHARED_LIBS=${BUILD_SHARED_LIBS:-OFF} \
      -DCOVERAGE=${COVERAGE:-OFF} \
      ${CMAKE_EXTRA_ARGS}

    make --jobs=${JOBS}
    make tests --jobs=${JOBS}
    make benchmarks --jobs=${JOBS}
    make install
    export PKG_CONFIG_PATH=${INSTALL_PREFIX}/lib/pkgconfig
    cd ../
    mkdir -p example/build
    cd example/build
    ${MASON_HOME}/bin/cmake ../ -DCMAKE_BUILD_TYPE=${BUILD_TYPE}
    make
    cd ../../
    make -C test/data benchmark
    ./example/build/osrm-example test/data/monaco.osrm
    cd build
    ./unit_tests/library-tests ../test/data/monaco.osrm
    ./unit_tests/extractor-tests
    ./unit_tests/engine-tests
    ./unit_tests/util-tests
    ./unit_tests/server-tests
    cd ../
    npm test
}

main