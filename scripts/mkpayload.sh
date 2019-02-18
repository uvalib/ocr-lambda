#!/usr/bin/env bash

# urls for downloadable tools/dependencies

declare -a SRCURLS=(
	"https://github.com/tesseract-ocr/tesseract/archive/4.0.0.tar.gz"
	"https://github.com/DanBloomberg/leptonica/archive/1.77.0.tar.gz"
	"https://github.com/ImageMagick/ImageMagick/archive/7.0.8-27.tar.gz"
	"https://github.com/uclouvain/openjpeg/archive/v2.3.0.tar.gz"
	"https://github.com/libjpeg-turbo/libjpeg-turbo/archive/2.0.2.tar.gz"
	"https://download.osgeo.org/libtiff/tiff-4.0.10.tar.gz"
	"https://download.sourceforge.net/libpng/libpng-1.6.36.tar.gz"
)

# urls for tesseract language files

LANGSREQ="eng osd"
LANGSOPT="ara deu ell fra grc lat rus spa"
LANGS="${LANGSREQ} ${LANGSOPT}"
# fast or best:
LANGTYPE="fast"
# master or specific branch:
LANGBRANCH="4.0.0"
LANGTEMPLATE="https://github.com/tesseract-ocr/tessdata_${LANGTYPE}/raw/${LANGBRANCH}/%s.traineddata"
declare -a LANGURLS=($(for lang in $LANGS; do printf "${LANGTEMPLATE}\n" "$lang"; done))

# directories

THISDIR="$(pwd -P)"
BASEDIR="${THISDIR}/payload"

SRCDIR="${BASEDIR}/src"
LANGDIR="${BASEDIR}/lang"
BUILDDIR="${BASEDIR}/build"
INSTALLDIR="${BASEDIR}/install"
DISTDIR="${BASEDIR}/dist"
ZIPDIR="${BASEDIR}/zip"

# files

LAMBDA="ocr-lambda"
LAMBDABIN="${THISDIR}/bin/${LAMBDA}"
LAMBDAZIP="${ZIPDIR}/lambda.zip"

# misc

SCRIPTNAME="$(basename $0)"

declare -A INSTALLED

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
	export PATH="${PATH}:${INSTALLDIR}/bin"
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

	mkdir -p "$SRCDIR" "$LANGDIR" "$BUILDDIR" "$INSTALLDIR" "$DISTDIR" "$ZIPDIR" || die "init mkdir"
}

function download_file ()
{
	local url="$1"

	msg "downloading: [$url]"

	curl -S -L -O -J "$url" || die "curl"
}

function download_dependencies ()
{
	msg "[$FUNCNAME]"

	pushd "$SRCDIR" > /dev/null || die "src pushd"

	for url in ${SRCURLS[@]}; do
		download_file "$url"
	done

	popd > /dev/null
}

function download_languages ()
{
	msg "[$FUNCNAME]"

	pushd "$LANGDIR" > /dev/null || die "lang pushd"

	for url in ${LANGURLS[@]}; do
		download_file "$url"
	done

	popd > /dev/null
}

function extract_and_enter ()
{
	local srcpfx="$1"
	local dirpat="$2"
	local src
	local dir

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
	./configure --prefix="$INSTALLDIR" --enable-shared --disable-dependency-tracking || die "could not configure leptonica"
	make install || die "could not build or install leptonica"

	popd > /dev/null || die "popd leptonica"
}

function install_tesseract_language_files ()
{
	msg "[$FUNCNAME]"

	TESSDATA="${INSTALLDIR}/share/tessdata"
	mv "$LANGDIR"/* "$TESSDATA"/ || die "lang mv"
}

function install_tesseract_from_source ()
{
	msg "[$FUNCNAME]"

	extract_and_enter "tesseract" "^[^/]*/configure.ac$"

	./autogen.sh || die "could not autogen tesseract"
	./configure --prefix="$INSTALLDIR" --enable-shared --disable-dependency-tracking --disable-graphics --disable-legacy || die "could not configure tesseract"
	make install || die "could not build or install tesseract"

	popd > /dev/null || die "popd tesseract"
}

function install_imagemagick_from_source ()
{
	msg "[$FUNCNAME]"

	extract_and_enter "ImageMagick" "^[^/]*/configure.ac$"

	./configure --prefix="$INSTALLDIR" --enable-shared --disable-dependency-tracking || die "could not configure imagemagick"
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

	./configure --prefix="$INSTALLDIR" --enable-shared --disable-dependency-tracking || die "could not configure libtiff"
	make install || die "could not build or install libtiff"

	popd > /dev/null || die "popd libtiff"
}

function install_libpng_from_source ()
{
	msg "[$FUNCNAME]"

	extract_and_enter "libpng" "^[^/]*/configure.ac$"

	./configure --prefix="$INSTALLDIR" --enable-shared --disable-dependency-tracking || die "could not configure libpng"
	make install || die "could not build or install libpng"

	popd > /dev/null || die "popd libpng"
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

	# copy in libraries needed by our binaries
	while read line; do
		lib="$(echo "$line" | awk '{print $1}')"
		res="$(echo "$line" | awk '{print $2}')"
		cp -f "$res" "$DISTDIR"/lib/ || die "dist bin lib cp: [$lib]"
	done < <(ldd "$DISTDIR"/bin/* | awk '{if (/ => \//) printf "%s %s\n", $1, $3}' | sort -u | egrep "/lib(jbig|jpeg|lept|openjp2|png|tesseract|tiff|z|Magick)")

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

function update_payload ()
{
	msg "[$FUNCNAME]"

	rm -rf "$DISTDIR"/ || die "dist rm"

	unzip -d "$DISTDIR" "$LAMBDAZIP" || die "unzip"

	rm -f "$LAMBDAZIP" || die "zip rm"

	rm -f "${DISTDIR}/${LAMBDA}" || die "rm lambda"

	cp "$LAMBDABIN" "$DISTDIR"/ || die "dist bin cp lambda"

	find "$DISTDIR" \( \( -type d \) -o \( -type f -a -perm /a+x \) \) -print0 | xargs -0r chmod 755
	find "$DISTDIR" -type f -a \! -perm /a+x -print0 | xargs -0r chmod 644

	pushd "$DISTDIR" > /dev/null || die "dist cd"
	zip -r "$LAMBDAZIP" . || die "zip"
	popd > /dev/null || die "popd zip"
}

function package_already_installed ()
{
	local pkg="$1"

	[ "$pkg" = "" ] && return 1

	if [ "${INSTALLED["$pkg"]}" = "y" ]; then
		msg "$pkg was already installed; skipping"
		return 0
	fi

	return 1
}

function package_mark_installed ()
{
	local pkg="$1"

	[ "$pkg" = "" ] && return

	INSTALLED["$pkg"]="y"
}

function install_libjpeg ()
{
	msg "[$FUNCNAME]"

	local pkg="libjpeg"

	package_already_installed "$pkg" && return

	# install dependencies first

	# now install
	install_libjpeg_from_source

	package_mark_installed "$pkg"
}

function install_libtiff ()
{
	msg "[$FUNCNAME]"

	local pkg="libtiff"

	package_already_installed "$pkg" && return

	# install dependencies first

	# now install
	install_libtiff_from_source

	package_mark_installed "$pkg"
}

function install_openjpeg ()
{
	msg "[$FUNCNAME]"

	local pkg="openjpeg"

	package_already_installed "$pkg" && return

	# install dependencies first

	# now install
	install_openjpeg_from_source

	package_mark_installed "$pkg"
}

function install_libpng ()
{
	msg "[$FUNCNAME]"

	local pkg="libpng"

	package_already_installed "$pkg" && return

	# install dependencies first

	# now install
	install_libpng_from_source

	package_mark_installed "$pkg"
}

function install_imagemagick ()
{
	msg "[$FUNCNAME]"

	local pkg="imagemagick"

	# install dependencies first

	package_already_installed "$pkg" && return

	# now install
	install_imagemagick_from_source

	package_mark_installed "$pkg"
}

function install_leptonica ()
{
	msg "[$FUNCNAME]"

	local pkg="leptonica"

	package_already_installed "$pkg" && return

	# install dependencies first
	install_libjpeg
	install_libtiff
	install_libpng
	install_openjpeg

	# now install
	install_leptonica_from_source

	package_mark_installed "$pkg"
}

function install_tesseract ()
{
	msg "[$FUNCNAME]"

	local pkg="tesseract"

	package_already_installed "$pkg" && return

	# install dependencies first
	install_leptonica

	# now install
	install_tesseract_from_source
	install_tesseract_language_files

	package_mark_installed "$pkg"
}

function install_dependencies ()
{
	msg "[$FUNCNAME]"

	rm -rf "$INSTALLDIR" || die "install rm"

	pushd "$BUILDDIR" > /dev/null || die "install pushd"

	install_tesseract
	install_imagemagick

	popd > /dev/null || die "install popd"
}

### script starts here

initialize_environment

case $1 in
	-c )
		# just clean directories
		clean_directories
		;;

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

	-p )
		# just create the payload
		create_payload
		;;

	-u )
		# update the existing payload with new lambda function
		update_payload
		;;

	-x )
		# execute the specified function
		shift
		$@
		;;

	* )
		msg "usage: $0 [ -d | -f | -i | -z ]"
		exit 1
		;;
esac

exit 0
