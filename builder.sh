#!/usr/bin/env bash
set -e

# Confirmation
read -p "Warning: this script may break your system. It manually installs \
files system-wide, which can create conflicts with important components of \
DGX OS. It also installs and removes packages using apt. Press Enter to \
continue or Ctrl + C to exit."
# NVIDIA OptiX SDK
if [ ! -f "$HOME/NVIDIA-OptiX-SDK-9.0.0-linux64-aarch64/include/optix.h" ]; then
    printf "NVIDIA OptiX SDK not found.\n\
Expected ~/NVIDIA-OptiX-SDK-9.0.0-linux64-aarch64/include/optix.h to exist.\n\
>> https://developer.nvidia.com/designworks/optix/download <<\n"
    exit 1
fi

set -x

export SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

sudo apt-get update
sudo apt-get install libxinerama-dev libxcursor-dev libxi-dev libglfw3-dev libboost-iostreams-dev libblosc-dev libjack-dev libpulse-dev libpipewire-0.3-dev libsndfile-dev libavdevice-dev libswscale-dev libavfilter-dev libavcodec-dev libavformat-dev curl git git-lfs libxrandr-dev ninja-build libjpeg-dev libepoxy-dev libshaderc-dev libfreetype-dev libjemalloc-dev libpugixml-dev libtiff-dev libwebp-dev libpotrace-dev libopenal-dev libfftw3-dev libglew-dev libglut-dev liblcms2-dev libyaml-cpp-dev libexpat-dev libpystring-dev pybind11-dev libosd-dev libimath-dev librubberband-dev libopenexr-dev cmake pkg-config libxcb1-dev libx11-dev libxrandr-dev
cd "$SCRIPT_DIR"

# Download, verify, and extract Python, ISPC, and the Vulkan SDK
[ -f "python.tar.xz" ]    || curl -Lo python.tar.xz 'https://www.python.org/ftp/python/3.14.6/Python-3.14.6.tar.xz'
[ -f "ispc.tar.gz" ]      || curl -Lo ispc.tar.gz 'https://github.com/ispc/ispc/releases/download/v1.31.0/ispc-v1.31.0-linux.aarch64.tar.gz'
[ -f "vulkansdk.tar.xz" ] || curl -Lo vulkansdk.tar.xz 'https://sdk.lunarg.com/sdk/download/1.4.350.1/linux/vulkansdk-linux-x86_64-1.4.350.1.tar.xz'
[ -f "ceres.tar.gz" ]     || curl -Lo ceres.tar.gz 'http://ceres-solver.org/ceres-solver-2.2.0.tar.gz'
echo "143b1dddefaec3bd2e21e3b839b34a2b7fb9842272883c576420d605e9f30c63 python.tar.xz"    | sha256sum -c
echo "660ccac47ff7e0980b89b00a3ebd70201acf55f9e816c127fc28e868ab456193 ispc.tar.gz"      | sha256sum -c
echo "6cce33c7e5383814150c5041820769d93c65a1fd883002e5949b067045a07daa vulkansdk.tar.xz" | sha256sum -c
tar xf python.tar.xz
tar xf ispc.tar.gz
tar xf vulkansdk.tar.xz

# Clone required repos
cd "$SCRIPT_DIR"
[ -d "sse2neon" ]    || git clone https://github.com/DLTcollab/sse2neon
[ -d "oneTBB" ]      || git clone https://github.com/uxlfoundation/oneTBB
[ -d "OpenImageIO" ] || git clone https://github.com/AcademySoftwareFoundation/OpenImageIO
[ -d "blender" ]     || git clone https://projects.blender.org/blender/blender.git
[ -d "oidn" ]        || git clone --recursive https://github.com/OpenImageDenoise/oidn.git
[ -d "embree" ]      || git clone https://github.com/RenderKit/embree
[ -d "openvdb" ]     || git clone https://github.com/AcademySoftwareFoundation/openvdb
[ -d "openjpeg" ]    || git clone https://github.com/uclouvain/openjpeg.git
[ -d "OpenColorIO" ] || git clone https://github.com/AcademySoftwareFoundation/OpenColorIO.git
[ -d "minizip-ng" ]  || git clone https://github.com/zlib-ng/minizip-ng.git

# Python
if ! command -v python3.13 > /dev/null 2>&1; then
    cd Python-3.13.12
    # installed libssl-dev at the end?
    ./configure --without-doc-strings --enable-optimizations
    make -j18
    sudo make altinstall
fi

# oneTBB
mkdir -pv "$SCRIPT_DIR"/oneTBB/build
cd "$SCRIPT_DIR"/oneTBB/build
cmake -DTBB_TEST=OFF ..
cmake --build .
sudo cmake --install .
cd "$SCRIPT_DIR"/OpenImageIO
cmake -B build -DOpenImageIO_BUILD_MISSING_DEPS=all -S .
cmake --build build --target install

# OpenImageDenoise
cd "$SCRIPT_DIR"
mkdir -pv oidn/build
cd oidn/build
cmake -G Ninja -D ISPC_EXECUTABLE="$SCRIPT_DIR"/ispc-v1.30.0-linux.aarch64/bin/ispc ..
ninja

# Vulkan
cd "$SCRIPT_DIR"/1.4.350.1
./vulkansdk --skip-installing-deps --maxjobs vulkan-loader shaderc
for dir in bin lib include share; do
    sudo cp -rv "$SCRIPT_DIR"/1.4.350.1/aarch64/$dir /usr/$dir/
done

# Embree
mkdir -pv "$SCRIPT_DIR"/embree/build
cd "$SCRIPT_DIR"/embree/build
cmake ..
make -j18
sudo make install

# OpenVDB
mkdir -pv "$SCRIPT_DIR"/openvdb/build
cd "$SCRIPT_DIR"/openvdb/build
cmake -DOPENVDB_BUILD_NANOVDB=ON ..
make -j18
sudo make install

# OpenJPEG
mkdir -pv "$SCRIPT_DIR"/openjpeg/build
cd "$SCRIPT_DIR"/openjpeg/build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j18
sudo make install

# OpenColorIO
mkdir -pv "$SCRIPT_DIR"/OpenColorIO/build
cd "$SCRIPT_DIR"/OpenColorIO/build
cmake ..
sudo make -j18
sudo make install

# ceres
# http://ceres-solver.org/installation.html#linux
# cmake -DUSE_CUDA=false ../ceres-solver-2.2.0

# Blender
cd "$SCRIPT_DIR"/blender
git switch blender-v5.2-release
mkdir -pv ../cmake-make
cd ../cmake-make
#set +e
#make
#set -e
# Needs mold libfmt-dev libmetis-dev libceres-dev [which has dep on libblas-dev] ?
# Use the later Launchpad .debs of libfmt-dev?
cmake -G 'Unix Makefiles' -DOPTIX_INCLUDE_DIR="$HOME"/NVIDIA-OptiX-SDK-9.0.0-linux64-aarch64/include \
-DWITH_CYCLES_CUDA_BINARIES=ON -DWITH_ALEMBIC=OFF -DWITH_MOD_FLUID=ON \
-DWITH_BLENDER_THUMBNAILER=ON -DWITH_BUILDINFO=OFF -DWITH_BULLET=ON \
-DWITH_CODEC_FFMPEG=ON -DWITH_CODEC_SNDFILE=ON -DWITH_CYCLES_DEBUG=ON \
-DWITH_CYCLES_DEVICE_OPTIX=ON -DWITH_CYCLES_OSL=OFF -DWITH_CYCLES_PATH_GUIDING=OFF -DWITH_DRACO=ON \
-DWITH_FFTW3=ON -DWITH_FREESTYLE=ON -DWITH_GHOST_XDND=OFF -DWITH_GMP=OFF -DWITH_HARU=OFF -DWITH_HYDRA=OFF -DWITH_IK_ITASC=ON -DWITH_IK_SOLVER=ON \
-DWITH_IMAGE_CINEON=ON -DWITH_IMAGE_OPENEXR=ON \
-DWITH_IMAGE_OPENJPEG=ON -DWITH_IMAGE_WEBP=ON -DWITH_INPUT_IME=OFF -DWITH_INPUT_NDOF=ON -DWITH_IO_GREASE_PENCIL=ON \
-DWITH_OPENAL=ON -DWITH_OPENVDB=ON -DOPENVDB_LIBRARY=/usr/local/lib/libopenvdb.so \
-DOPENVDB_INCLUDE_DIR=/usr/local/include/openvdb -DWITH_OPENVDB_BLOSC=ON -DWITH_PIPEWIRE=OFF -DWITH_PULSEAUDIO=ON \
-DWITH_PYTHON_INSTALL_NUMPY=ON -DWITH_PYTHON_INSTALL_REQUESTS=ON -DWITH_PYTHON_INSTALL_ZSTANDARD=OFF \
-DWITH_PYTHON_NUMPY=ON -DWITH_PYTHON_SAFETY=ON -DWITH_QUADRIFLOW=OFF -DWITH_UI_TESTS_HEADLESS=OFF \
-DWITH_X11_XFIXES=OFF -DWITH_X11_XINPUT=OFF -DWITH_MOD_REMESH=ON -DWITH_PYTHON_INSTALL=ON \
-DWITH_GHOST_X11=ON -DWITH_GHOST_WAYLAND=OFF -DWITH_GHOST_WAYLAND_DYNLOAD=OFF -DWITH_OPENCOLORIO=ON \
-DWITH_XR_OPENXR=OFF -DWITH_USD=OFF -DWITH_CYCLES_DEVICE_CUDA=ON -DWITH_CYCLES_DEVICE_HIP=OFF \
-DWITH_NANOVDB=ON -DWITH_VULKAN_BACKEND=ON -DWITH_CYCLES=ON -DWITH_CYCLES_PARALLEL_DEVICE_KERNEL_BUILD=ON \
-DOPENIMAGEDENOISE_LIBRARY="$SCRIPT_DIR"/oidn/build/libOpenImageDenoise.so \
-DOPENIMAGEDENOISE_OPENIMAGEDENOISE_LIBRARY="$SCRIPT_DIR"/oidn/build/libOpenImageDenoise.so \
-DOPENIMAGEDENOISE_COMMON_LIBRARY="$SCRIPT_DIR"/oidn/build/libOpenImageDenoise.so \
-DOPENIMAGEDENOISE_INCLUDE_DIR="$SCRIPT_DIR"/oidn/include \
-DSSE2NEON_INCLUDE_DIR="$SCRIPT_DIR"/sse2neon \
-DCMAKE_PREFIX_PATH="$SCRIPT_DIR"/OpenImageIO/dist \
-DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_VERBOSE_MAKEFILE=ON -DPYTHON_NUMPY_INCLUDE_DIRS=/usr/local/lib/python3.14/site-packages/numpy/_core/include \
-DOPENCOLORIO_INCLUDE_DIR=/usr/local/include -DWITH_AUDASPACE=OFF -DWITH_SYSTEM_GLOG=ON \
-DVulkan_INCLUDE_DIR="$VULKAN_SDK/include" -DVulkan_LIBRARY="$VULKAN_SDK/lib/VulkanLoader/lib/libvulkan.so" \
-DCMAKE_C_FLAGS="-I$VULKAN_SDK/include" -DCMAKE_CXX_FLAGS="-I$VULKAN_SDK/include" ../blender

# Blender launcher
cat > "$SCRIPT_DIR"/launchBlender <<EOL
#!/usr/bin/env bash
export LD_LIBRARY_PATH=/usr/local/lib:$SCRIPT_DIR/embree/build:$SCRIPT_DIR/oidn/build:$SCRIPT_DIR/OpenImageIO/dist/lib
$SCRIPT_DIR/build_linux/bin/blender
EOL
chmod +x "$SCRIPT_DIR"/launchBlender
make -j18

## Missing from builder.sh: alembic OpenColorIO openssl openvdb
