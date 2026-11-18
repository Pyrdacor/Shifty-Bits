#!/bin/sh
# Builds Shifty Bits for Linux: bin/shiftybits.
#
# MiniFB (window, keyboard, mouse) is built once from its sources into lib/linux/libminifb.a, at the version whose
# headers are in include/. Needs git, cmake, a C compiler and the development files of X11, Xrandr, xkbcommon, OpenGL and ALSA
# (Debian/Ubuntu: sudo apt install git cmake build-essential libx11-dev libxrandr-dev libxkbcommon-dev libgl-dev
# libasound2-dev),
# and cshiftc on the PATH (or in $CSHIFTC).
set -e
cd "$(dirname "$0")/.."

MINIFB_COMMIT=3cece1f72d1e43742051d114d36bded76e1327be

if [ ! -f lib/linux/libminifb.a ]; then
    rm -rf obj/minifb
    git clone --quiet https://github.com/emoon/minifb.git obj/minifb
    git -C obj/minifb checkout --quiet "$MINIFB_COMMIT"
    cmake -S obj/minifb -B obj/minifb/build -DCMAKE_BUILD_TYPE=Release -DMINIFB_BUILD_EXAMPLES=OFF \
        -DMINIFB_BUILD_VERSION_INFO=OFF -DCMAKE_POSITION_INDEPENDENT_CODE=ON
    cmake --build obj/minifb/build --parallel
    mkdir -p lib/linux
    cp obj/minifb/build/libminifb.a lib/linux/
fi

"${CSHIFTC:-cshiftc}" build platform/linux
