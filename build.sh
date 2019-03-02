#!/bin/bash

# This script will compile and install a static ffmpeg build with support for
# nvenc on ubuntu. See the prefix path and compile options if edits are needed
# to suit your needs.

#Authors:
#   Linux GameCast ( http://linuxgamecast.com/ )
#   Mathieu Comandon <strider@strycore.com>

set -e

ShowUsage() {
    echo "Usage: ./build.sh [--dest /path/to/ffmpeg] [--obs] [--help]"
    echo "Options:"
    echo "  -d/--dest: Where to build ffmpeg (Optional, defaults to ./ffmpeg-nvenc)"
    echo "  -o/--obs:  Build OBS Studio"
    echo "  -h/--help: This help screen"
    exit 0
}

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

params=$(getopt -n $0 -o d:oh --long dest:,obs,help -- "$@")
eval set -- $params
while true ; do
    case "$1" in
        -h|--help) ShowUsage ;;
        -o|--obs) build_obs=1; shift ;;
        -d|--dest) build_dir=$2; shift 2;;
        *) shift; break ;;
    esac
done

cpus=$(getconf _NPROCESSORS_ONLN)
source_dir="${root_dir}/source"
mkdir -p $source_dir
build_dir="${build_dir:-"${root_dir}/ffmpeg-nvenc"}"
mkdir -p $build_dir
bin_dir="${build_dir}/bin"
mkdir -p $bin_dir
inc_dir="${build_dir}/include"
mkdir -p $inc_dir

echo "Building FFmpeg in ${build_dir}"

export PATH=$bin_dir:$PATH

InstallDependencies() {
    echo "Installing dependencies"
    sudo apt-get -y install git autoconf automake build-essential libass-dev \
        libfreetype6-dev libgpac-dev libsdl1.2-dev libtheora-dev libtool libva-dev \
        libvdpau-dev libvorbis-dev libxcb1-dev libxcb-shm0-dev libxcb-xfixes0-dev \
        libqt5x11extras5-dev libxcb-xinerama0-dev libvlc-dev libv4l-dev   \
        pkg-config texi2html zlib1g-dev cmake libcurl4-openssl-dev \
        libjack-jackd2-dev libxcomposite-dev x11proto-composite-dev \
        libx264-dev libgl1-mesa-dev libglu1-mesa-dev libasound2-dev \
        libpulse-dev libx11-dev libxext-dev libxfixes-dev \
        libxi-dev qt5-default qttools5-dev qt5-qmake qtbase5-dev
}

# TODO Detect running system
InstallDependenciesOpenSUSE() {
   echo "Installing dependencies"
   sudo zypper in -y git autoconf automake libass-devel libfreetype6 libgpac-devel \
       libSDL-devel libtheora-devel libtool libva-devel libvdpau-devel libvorbis-devel \
       libxcb-devel pkg-config libxcb-shm0 libvlc5 vlc-devel xcb-util-devel \
       libv4l-devel v4l-utils-devel-tools texi2html zlib-devel cmake \
       libcurl-devel libfdk-aac1
}

InstallNvidiaSDK() {
    echo "Installing the NVidia Video SDK"
    sdk_version="9.0.20"
    sdk_basename="Video_Codec_SDK_${sdk_version}"
    cd "$source_dir"
    if [ ! -f "${sdk_basename}.zip" ]; then
        echo "Please download ${sdk_basename} from the NVidia website and place it the source folder"
    fi
    unzip "${sdk_basename}.zip"
    cd $sdk_basename
    cp -a Samples/NvCodec/NvEncoder/* "$inc_dir"
}

InstallNvCodecIncludes() {
    echo "Installing Nv codec headers from https://github.com/FFmpeg/nv-codec-headers"
    cd "$source_dir"
    git clone https://github.com/FFmpeg/nv-codec-headers
    cd nv-codec-headers
    cp -a include/ffnvcodec "$inc_dir"
}

BuildNasm() {
    echo "Compiling nasm"
    cd $source_dir
    nasm_version="2.14.02"
    nasm_basename="nasm-${nasm_version}"
    wget -4 http://www.nasm.us/pub/nasm/releasebuilds/${nasm_version}/nasm-${nasm_version}.tar.gz
    tar xzf "${nasm_basename}.tar.gz"
    cd $nasm_basename
    ./configure --prefix="${build_dir}" --bindir="${bin_dir}"
    make -j${cpus}
    make install
}

BuildYasm() {
    echo "Compiling yasm"
    cd $source_dir
    yasm_version="1.3.0"
    yasm_basename="yasm-${yasm_version}"
    wget -4 http://www.tortall.net/projects/yasm/releases/${yasm_basename}.tar.gz
    tar xzf "${yasm_basename}.tar.gz"
    cd $yasm_basename
    ./configure --prefix="${build_dir}" --bindir="${bin_dir}"
    make -j${cpus}
    make install
}

BuildX264() {
    echo "Compiling libx264"
    cd $source_dir
    wget -4 http://download.videolan.org/pub/x264/snapshots/last_x264.tar.bz2
    tar xjf last_x264.tar.bz2
    cd x264-snapshot*
    ./configure --prefix="$build_dir" --bindir="$bin_dir" --enable-pic --enable-shared
    make -j${cpus}
    make install
}

BuildFdkAac() {
    echo "Compiling libfdk-aac"
    cd $source_dir
    wget -4 -O fdk-aac.zip https://github.com/mstorsjo/fdk-aac/zipball/master
    unzip fdk-aac.zip
    cd mstorsjo-fdk-aac*
    autoreconf -fiv
    ./configure --prefix="$build_dir" # --disable-shared
    make -j${cpus}
    make install
}

BuildLame() {
    echo "Compiling libmp3lame"
    cd $source_dir
    lame_version="3.99.5"
    lame_basename="lame-${lame_version}"
    wget -4 "http://downloads.sourceforge.net/project/lame/lame/3.99/${lame_basename}.tar.gz"
    tar xzf "${lame_basename}.tar.gz"
    cd $lame_basename
    ./configure --prefix="$build_dir" --enable-nasm # --disable-shared
    make -j${cpus}
    make install
}

BuildOpus() {
    echo "Compiling libopus"
    cd $source_dir
    opus_version="1.1"
    opus_basename="opus-${opus_version}"
    wget -4 "http://downloads.xiph.org/releases/opus/${opus_basename}.tar.gz"
    tar xzf "${opus_basename}.tar.gz"
    cd $opus_basename
    ./configure --prefix="$build_dir" # --disable-shared
    make -j${cpus}
    make install
}

BuildVpx() {
    echo "Compiling libvpx"
    cd $source_dir
    vpx_version="1.5.0"
    vpx_basename="libvpx-${vpx_version}"
    vpx_url="http://storage.googleapis.com/downloads.webmproject.org/releases/webm/${vpx_basename}.tar.bz2"
    wget -4 $vpx_url
    tar xjf "${vpx_basename}.tar.bz2"
    cd $vpx_basename
    ./configure --prefix="$build_dir" --disable-examples --enable-shared --disable-static
    make -j${cpus}
    make install
}

BuildFFmpeg() {
    echo "Compiling ffmpeg"
    cd $source_dir
    ffmpeg_version="4.1.1"
    if [ ! -f  ffmpeg-${ffmpeg_version}.tar.bz2 ]; then
        wget -4 http://ffmpeg.org/releases/ffmpeg-${ffmpeg_version}.tar.bz2
    fi
    tar xjf ffmpeg-${ffmpeg_version}.tar.bz2
    cd ffmpeg-${ffmpeg_version}
    PKG_CONFIG_PATH="${build_dir}/lib/pkgconfig" ./configure \
        --prefix="$build_dir" \
        --extra-cflags="-fPIC -m64 -I${inc_dir}" \
        --extra-ldflags="-L${build_dir}/lib" \
        --bindir="$bin_dir" \
        --incdir="$inc_dir" \
        --enable-gpl \
        --enable-libass \
        --enable-libfdk-aac \
        --enable-libfreetype \
        --enable-libmp3lame \
        --enable-libopus \
        --enable-libtheora \
        --enable-libvorbis \
        --enable-libvpx \
        --enable-libx264 \
        --enable-nonfree \
        --enable-nvenc \
        --enable-pic \
        --enable-libxcb \
        --extra-ldexeflags=-pie \
        --enable-shared
    make -j${cpus}
    make install

    # Below is the configuration of ffmpeg as provided in Ubuntu 18.10

    # ffmpeg version 4.0.2-2 Copyright (c) 2000-2018 the FFmpeg developers
    #   built with gcc 8 (Ubuntu 8.2.0-7ubuntu1)
    #   configuration: --prefix=/usr 
    #                  --extra-version=2 
    #                  --toolchain=hardened 
    #                  --libdir=/usr/lib/x86_64-linux-gnu 
    #                  --incdir=/usr/include/x86_64-linux-gnu 
    #                  --arch=amd64 
    #                  --enable-gpl 
    #                  --disable-stripping 
    #                  --enable-avresample 
    #                  --disable-filter=resample 
    #                  --enable-avisynth 
    #                  --enable-gnutls 
    #                  --enable-ladspa 
    #                  --enable-libaom 
    #                  --enable-libass 
    #                  --enable-libbluray 
    #                  --enable-libbs2b 
    #                  --enable-libcaca 
    #                  --enable-libcdio 
    #                  --enable-libcodec2 
    #                  --enable-libflite 
    #                  --enable-libfontconfig 
    #                  --enable-libfreetype
    #                  --enable-libfribidi
    #                  --enable-libgme 
    #                  --enable-libgsm 
    #                  --enable-libjack 
    #                  --enable-libmp3lame 
    #                  --enable-libmysofa 
    #                  --enable-libopenjpeg 
    #                  --enable-libopenmpt 
    #                  --enable-libopus 
    #                  --enable-libpulse 
    #                  --enable-librsvg 
    #                  --enable-librubberband 
    #                  --enable-libshine 
    #                  --enable-libsnappy 
    #                  --enable-libsoxr 
    #                  --enable-libspeex 
    #                  --enable-libssh 
    #                  --enable-libtheora 
    #                  --enable-libtwolame 
    #                  --enable-libvorbis 
    #                  --enable-libvpx 
    #                  --enable-libwavpack 
    #                  --enable-libwebp 
    #                  --enable-libx265 
    #                  --enable-libxml2 
    #                  --enable-libxvid 
    #                  --enable-libzmq 
    #                  --enable-libzvbi 
    #                  --enable-lv2 
    #                  --enable-omx 
    #                  --enable-openal
    #                  --enable-opengl
    #                  --enable-sdl2
    #                  --enable-libdc1394
    #                  --enable-libdrm
    #                  --enable-libiec61883
    #                  --enable-chromaprint
    #                  --enable-frei0r
    #                  --enable-libopencv
    #                  --enable-libx264
    #                  --enable-shared
    #   libavutil      56. 14.100 / 56. 14.100
    #   libavcodec     58. 18.100 / 58. 18.100
    #   libavformat    58. 12.100 / 58. 12.100
    #   libavdevice    58.  3.100 / 58.  3.100
    #   libavfilter     7. 16.100 /  7. 16.100
    #   libavresample   4.  0.  0 /  4.  0.  0
    #   libswscale      5.  1.100 /  5.  1.100
    #   libswresample   3.  1.100 /  3.  1.100
    #   libpostproc    55.  1.100 / 55.  1.100
}

BuildOBS() {
    cd $source_dir
    if [ -f $build_dir/bin/ffmpeg ]; then
        export FFmpegPath="${build_dir}/bin/ffmpeg"
    else
        echo "FFmpegPath not set, using default FFmpeg"
    fi

    if [ -d obs-studio ]; then
        cd obs-studio
        git pull
    else
        git clone https://github.com/obsproject/obs-studio
        cd obs-studio
    fi
    mkdir -p build
    cd build
    cmake -DUNIX_STRUCTURE=1 -DCMAKE_INSTALL_PREFIX=$build_dir ..
    make -j${cpus}
    make install
}

CleanAll() {
    rm -rf $source_dir
}

MakeScripts() {
    cd $build_dir
    mkdir -p scripts
    cd scripts
    echo "Creating launcher script for FFmpeg"
    cat <<EOF > ffmpeg.sh
#!/bin/bash
export LD_LIBRARY_PATH="${build_dir}/lib":\$LD_LIBRARY_PATH
cd "${build_dir}/bin"
./ffmpeg "\$@"
EOF
    chmod +x ffmpeg.sh

    if [ "$build_obs" ]; then
        echo "Creating launcher script for OBS"
        cat <<EOF > obs.sh
#!/bin/bash
export LD_LIBRARY_PATH="${build_dir}/lib":\$LD_LIBRARY_PATH
cd "${build_dir}/bin"
./obs "\$@"
EOF
        chmod +x obs.sh
    fi
}

MakeLauncherOBS() {
    cat <<EOF > ~/.local/share/applications/obs.desktop
[Desktop Entry]
Version=1.0
Name=OBS Studio
Comment=OBS Studio (NVenc enabled)
Categories=Video;
Exec=${build_dir}/scripts/obs.sh %U
Icon=obs
Terminal=false
Type=Application
EOF
    mkdir -p ~/.icons
    cp ${root_dir}/media/obs.png ~/.icons
    gtk-update-icon-cache -t ~/.icons
}

if [ $1 ]; then
    $1
else
    InstallDependencies
    InstallNvCodecIncludes
    BuildNasm
    BuildYasm
    BuildX264
    BuildFdkAac
    BuildLame
    BuildOpus
    BuildVpx
    BuildFFmpeg
    if [ "$build_obs" ]; then
        BuildOBS
        MakeLauncherOBS
    fi

    MakeScripts
fi
