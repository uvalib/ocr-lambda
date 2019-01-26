#!/usr/bin/env bash

# urls for downloadable tools/dependencies

declare -a SRCURLS=(
	"https://github.com/tesseract-ocr/tesseract/archive/4.0.0.tar.gz"
	"https://github.com/DanBloomberg/leptonica/archive/1.77.0.tar.gz"
	"https://github.com/ImageMagick/ImageMagick/archive/7.0.8-24.tar.gz"
	"https://github.com/uclouvain/openjpeg/archive/v2.3.0.tar.gz"
	"https://github.com/libjpeg-turbo/libjpeg-turbo/archive/2.0.1.tar.gz"
	"https://download.osgeo.org/libtiff/tiff-4.0.10.tar.gz"
	"https://download.sourceforge.net/libpng/libpng-1.6.36.tar.gz"
	"https://github.com/Kitware/CMake/releases/download/v3.13.3/cmake-3.13.3-Linux-x86_64.tar.gz"
	"https://www.nasm.us/pub/nasm/releasebuilds/2.14.02/nasm-2.14.02.tar.gz"
)

# urls for tesseract language files

LANGS="eng osd fra spa ara deu rus ell grc"
LANGFMT="https://github.com/tesseract-ocr/tessdata_best/raw/master/%s.traineddata"
declare -a LANGURLS=($(for lang in $LANGS; do printf "${LANGFMT}\n" "$lang"; done))

# directories

THISDIR="$(pwd -P)"
BASEDIR="${THISDIR}/payload"

BINDIR="${BASEDIR}/bin"
SRCDIR="${BASEDIR}/src"
LANGDIR="${BASEDIR}/lang"
BUILDDIR="${BASEDIR}/build"
INSTALLDIR="${BASEDIR}/install"
DISTDIR="${BASEDIR}/dist"
ZIPDIR="${BASEDIR}/zip"

# files

LAMBDABIN="${THISDIR}/bin/ocr-lambda"
LAMBDAZIP="${ZIPDIR}/lambda.zip"

# misc

SCRIPTNAME="$(basename $0)"

# functions

function die ()
{
	msg "ERROR: $@"
	exit 1
}

function msg ()
{
	echo "${SCRIPTNAME}: $@"
}

function initialize_environment ()
{
	export PATH="${PATH}:${BINDIR}"
	export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:${INSTALLDIR}/lib64:${INSTALLDIR}/lib"
	export PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:${INSTALLDIR}/lib64/pkgconfig:${INSTALLDIR}/lib/pkgconfig"
	export CFLAGS="${CFLAGS} -I${INSTALLDIR}/include"
	export CXXFLAGS="${CXXFLAGS} -I${INSTALLDIR}/include"
	export CPPFLAGS="${CPPFLAGS} -I${INSTALLDIR}/include"
	export LDFLAGS="${LDFLAGS} -L${INSTALLDIR}/lib64 -L${INSTALLDIR}/lib"
}

function clean_directories ()
{
	msg "[$FUNCNAME]"

	rm -rf "$BASEDIR" || die "init rm"

	mkdir -p "$BINDIR" "$SRCDIR" "$LANGDIR" "$BUILDDIR" "$INSTALLDIR" "$DISTDIR" "$ZIPDIR" || die "init mkdir"
	mkdir -p "$INSTALLDIR"/bin || die "init mkdir install subdirs"
}

function download_dependencies ()
{
	msg "[$FUNCNAME]"

	pushd "$SRCDIR" > /dev/null || die "src pushd"

	for url in ${SRCURLS[@]}; do
		msg "downloading: [$url]"
		curl -sSLOJ "$url" || die "src curl"
	done

	popd > /dev/null
}

function download_languages ()
{
	msg "[$FUNCNAME]"

	pushd "$LANGDIR" > /dev/null || die "lang pushd"

	for url in ${LANGURLS[@]}; do
		msg "downloading: [$url]"
		curl -sSLOJ "$url" || die "lang curl"
	done

	popd > /dev/null
}

function extract_and_enter ()
{
	local srcpfx
	local dirpat
	local src
	local dir

	srcpfx="$1"
	dirpat="$2"

	cd "$BUILDDIR" || die "could not cd to build dir"

	src="$(echo "$SRCDIR/$srcpfx"-*)"
	[ -f "$src" ] || die "not a source file: [$src]"

	dir="$(tar tzf "$src" | grep "$dirpat" | cut -d/ -f1)"
	rm -rf "$dir" || die "could not remove directory: [$dir]"

	tar xzf "$src" || die "could not extract source file: [$src]"

	pushd "$dir" > /dev/null || die "could not change to directory: [$dir]"
}

function install_leptonica_from_source ()
{
	msg "[$FUNCNAME]"

	extract_and_enter "leptonica" "^[^/]*/configure.ac$"

	./autogen.sh || die "could not autogen leptonica"
	./configure --prefix="$INSTALLDIR" --disable-static --disable-dependency-tracking || die "could not configure leptonica"
	make install || die "could not build or install leptonica"

	popd > /dev/null || die "popd leptonica"
}

function install_tesseract_from_source ()
{
	msg "[$FUNCNAME]"

	extract_and_enter "tesseract" "^[^/]*/configure.ac$"

	./autogen.sh || die "could not autogen tesseract"
	./configure --prefix="$INSTALLDIR" --disable-static --disable-dependency-tracking --disable-graphics --disable-legacy || die "could not configure tesseract"
	make install || die "could not build or install tesseract"

	TESSDATA="${INSTALLDIR}/share/tessdata"
	mv "$LANGDIR"/* "$TESSDATA"/ || die "lang mv"

	popd > /dev/null || die "popd tesseract"
}

function install_imagemagick_from_source ()
{
	msg "[$FUNCNAME]"

	extract_and_enter "ImageMagick" "^[^/]*/configure.ac$"

	./configure --prefix="$INSTALLDIR" --disable-static --disable-dependency-tracking || die "could not configure imagemagick"
	make install || die "could not build or install imagemagick"

	popd > /dev/null || die "popd imagemagick"
}

function install_libjpeg_from_source ()
{
	msg "[$FUNCNAME]"

	extract_and_enter "libjpeg-turbo" "^[^/]*/CMakeLists.txt$"

	mkdir "build" || die "could not create build subdir"
	pushd "build" || die "pushd libjpeg build"

	cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$INSTALLDIR" || die "could not cmake libjpeg"
	make install || die "could not build or install libjpeg"

	popd > /dev/null || die "popd libjpeg build"

	popd > /dev/null || die "popd libjpeg"
}

function install_libtiff_from_source ()
{
	msg "[$FUNCNAME]"

	extract_and_enter "tiff" "^[^/]*/configure.ac$"

	./configure --prefix="$INSTALLDIR" --disable-static --disable-dependency-tracking || die "could not configure libtiff"
	make install || die "could not build or install libtiff"

	popd > /dev/null || die "popd libtiff"
}

function install_libpng_from_source ()
{
	msg "[$FUNCNAME]"

	extract_and_enter "libpng" "^[^/]*/configure.ac$"

	./configure --prefix="$INSTALLDIR" --disable-static --disable-dependency-tracking || die "could not configure libpng"
	make install || die "could not build or install libpng"

	popd > /dev/null || die "popd libpng"
}

function install_cmake_from_source ()
{
	msg "[$FUNCNAME]"

	extract_and_enter "CMake" "^[^/]*/bootstrap$"

	./configure --prefix="$INSTALLDIR" || die "could not configure cmake"
	make install || die "could not build or install cmake"
	cp "$INSTALLDIR"/bin/cmake "$BINDIR"/ || die "could not copy cmake into bin dir"

	popd > /dev/null || die "popd cmake"
}

function install_cmake_from_binary ()
{
	msg "[$FUNCNAME]"

	extract_and_enter "cmake" "^[^/]*/bin/cmake$"

	cp bin/cmake "$INSTALLDIR"/bin

	popd > /dev/null || die "popd cmake"
}

function install_nasm_from_source ()
{
	msg "[$FUNCNAME]"

	extract_and_enter "nasm" "^[^/]*/configure.ac$"

	./autogen.sh || die "could not autogen nasm"
	./configure --prefix="$INSTALLDIR" --disable-static --disable-dependency-tracking || die "could not configure nasm"
	make install || die "could not build or install nasm"
	cp "$INSTALLDIR"/bin/nasm "$BINDIR"/ || die "could not copy nasm into bin dir"

	popd > /dev/null || die "popd nasm"
}

function install_nasm_from_binary ()
{
	msg "[$FUNCNAME]"

	src="$(echo "$SRCDIR"/nasm-*)"
	[ -f "$src" ] || die "not a source file: [$src]"

	mkdir "nasm" || die "could not create nasm subdir"
	pushd "nasm" || die "pushd nasm"

	rpm2cpio "$src" | cpio -idmv || die "nasm cpio"

	cp usr/bin/nasm "$BINDIR"/

	popd > /dev/null || die "popd nasm"
}

function install_openjpeg_from_source ()
{
	msg "[$FUNCNAME]"

	extract_and_enter "openjpeg" "^[^/]*/CMakeLists.txt$"

	mkdir "build" || die "could not create build subdir"
	pushd "build" || die "pushd openjpeg build"

	cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$INSTALLDIR" || die "could not cmake openjpeg"
	make install || die "could not build or install openjpeg"

	popd > /dev/null || die "popd openjpeg build"

	popd > /dev/null || die "popd openjpeg"
}

function create_payload ()
{
	msg "[$FUNCNAME]"

	rm -rf "$DISTDIR"/ "$LAMBDAZIP" || die "dist rm"
	mkdir -p "$DISTDIR"/{bin,etc,lib,share} || die "dist subdirs mkdir"

	cp "$LAMBDABIN" "$DISTDIR"/ || die "dist bin cp lambda"

	cp "${INSTALLDIR}/bin/tesseract" "${DISTDIR}/bin/" || die "dist bin cp tesseract"
	cp "${INSTALLDIR}/bin/magick" "${DISTDIR}/bin/" || die "dist bin cp magick"

	cp -R "${INSTALLDIR}/etc/ImageMagick-7" "${DISTDIR}/etc" || die "dist etc cp"
	cp -R "${INSTALLDIR}/share/tessdata" "${DISTDIR}/share" || die "dist share cp"

	while read line; do
		lib="$(echo "$line" | awk '{print $1}')"
		res="$(echo "$line" | awk '{print $2}')"
		cp "$res" "$DISTDIR"/lib/ || die "dist lib cp: [$lib]"
	done < <(ldd "$DISTDIR"/bin/* | awk '{if (/ => \//) printf "%s %s\n", $1, $3}' | sort -u | egrep "/lib(jbig|jpeg|lept|openjp2|png|tesseract|tiff|Magick)")
#	done < <(ldd "$DISTDIR"/bin/* | awk '{if (/ => \//) printf "%s %s\n", $1, $3}' | sort -u)

	echo "[libs]"
	libs="$(ldd "$DISTDIR"/{bin,lib}/*)"
	echo "$libs"

	echo "[libs] unique"
	libs="$(echo "$libs" | awk '{if (/ => \//) printf "%s %s\n", $1, $3}' | sort -u)"
	echo "$libs"

	find "$DISTDIR" \( \( -type d \) -o \( -type f -a -perm /a+x \) \) -print0 | xargs -0r chmod 755
	find "$DISTDIR" -type f -a \! -perm /a+x -print0 | xargs -0r chmod 644

	pushd "$DISTDIR" > /dev/null || die "dist cd"
	zip -r "$LAMBDAZIP" . || die "zip"
	popd > /dev/null || die "popd zip"
}

function install_cmake ()
{
	msg "[$FUNCNAME]"

	# if it already exists, no need to install
	type -p cmake > /dev/null 2>&1 && return

	# install dependencies first

	# now install
	install_cmake_from_binary
}

function install_nasm ()
{
	msg "[$FUNCNAME]"

	# if it already exists, no need to install
	type -p nasm > /dev/null 2>&1 && return

	# install dependencies first

	# now install
	install_nasm_from_source
}

function install_libjpeg ()
{
	msg "[$FUNCNAME]"

	# install dependencies first
	install_cmake
	install_nasm

	# now install
	install_libjpeg_from_source
}

function install_libtiff ()
{
	msg "[$FUNCNAME]"

	# install dependencies first

	# now install
	install_libtiff_from_source
}

function install_openjpeg ()
{
	msg "[$FUNCNAME]"

	# install dependencies first
	install_cmake

	# now install
	install_openjpeg_from_source
}

function install_libpng ()
{
	msg "[$FUNCNAME]"

	# install dependencies first

	# now install
	install_libpng_from_source
}

function install_imagemagick ()
{
	msg "[$FUNCNAME]"

	# install dependencies first

	# now install
	install_imagemagick_from_source
}

function install_leptonica ()
{
	msg "[$FUNCNAME]"

	# install dependencies first
	install_libjpeg
	install_libtiff
	install_libpng
	install_openjpeg

	# now install
	install_leptonica_from_source
}

function install_tesseract ()
{
	msg "[$FUNCNAME]"

	# install dependencies first
	install_leptonica

	# now install
	install_tesseract_from_source
}

function install_dependencies ()
{
	msg "[$FUNCNAME]"

	pushd "$BUILDDIR" > /dev/null || die "install pushd"

	install_tesseract
	install_imagemagick

	popd > /dev/null || die "install popd"
}

### script starts here

initialize_environment

case $1 in
	-d )
		# just download files
		download_dependencies
		download_languages
		;;

	-f )
		# everything from scratch
		clean_directories

		download_dependencies
		download_languages

		install_dependencies

		create_payload
		;;

	-i )
		# just install software
		install_dependencies
		;;

	-x )
		# execute the specified function
		$2
		;;

	-z )
		# just create the payload
		create_payload
		;;

	* )
		msg "usage: $0 [ -d | -f | -i | -z ]"
		exit 1
		;;
esac

exit 0
