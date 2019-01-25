#!/usr/bin/env bash

# urls for downloadable tools/dependencies

# FIXME: add libpng, libjpeg, libtiff
# FIXME: compile cmake and enable openjpeg builds

declare -a SRCURLS=(
	"https://github.com/tesseract-ocr/tesseract/archive/4.0.0.tar.gz"
	"https://github.com/DanBloomberg/leptonica/archive/1.77.0.tar.gz"
	"https://github.com/ImageMagick/ImageMagick/archive/7.0.8-24.tar.gz"
	"https://github.com/uclouvain/openjpeg/archive/v2.3.0.tar.gz"
	"https://github.com/Kitware/CMake/archive/v3.13.3.tar.gz"
)

# urls for language files

LANGS="eng osd fra spa ara deu rus ell grc"
LANGFMT="https://github.com/tesseract-ocr/tessdata_best/raw/master/%s.traineddata"
declare -a LANGURLS=($(for lang in $LANGS; do printf "${LANGFMT}\n" "$lang"; done))

# directories

THISDIR="$(pwd -P)"
BASEDIR="${THISDIR}/base"

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

# functions

function die ()
{
	echo "error: $@"
	exit 1
}

function initialize_environment ()
{
	rm -rf "$BASEDIR" || die "init rm"

	mkdir -p "$BINDIR" "$SRCDIR" "$LANGDIR" "$BUILDDIR" "$INSTALLDIR" "$DISTDIR" "$ZIPDIR" || die "init mkdir"

	export PATH="${PATH}:${BINDIR}"
	export PKG_CONFIG_PATH="${PKG_CONFIG_PATH}:${INSTALLDIR}/lib/pkgconfig"
}

function download_dependencies ()
{
	pushd "$SRCDIR" > /dev/null || die "src pushd"

	for url in ${SRCURLS[@]}; do
		curl -sSLOJ "$url" || die "src curl"
	done

	ls -laF

	popd > /dev/null
}

function download_languages ()
{
	pushd "$LANGDIR" > /dev/null || die "lang pushd"

	for url in ${LANGURLS[@]}; do
		curl -sSLOJ "$url" || die "lang curl"
	done

	ls -laF

	popd > /dev/null
}

function install_leptonica ()
{
	LEPTTGZ="$(echo "$SRCDIR"/leptonica-*gz)"
	[ -f "$LEPTTGZ" ] || die "cannot work with this: [$LEPTTGZ]"
	LEPTDIR="$(gunzip < "$LEPTTGZ" | tar tf - | grep "^[^/]*/configure.ac$" | cut -d/ -f1)"
	rm -rf "$LEPTDIR" || die "remove existing leptonica build dir"
	gunzip < "$LEPTTGZ" | tar xf -
	pushd "$LEPTDIR" > /dev/null || die "could not change to directory: [$LEPTDIR]"
	./autogen.sh || die "could not autogen leptonica"
	./configure --prefix="$INSTALLDIR" --disable-static --disable-dependency-tracking || die "could not configure leptonica"
	make install-strip || die "could not build or install leptonica"
	popd > /dev/null || die "popd leptonica"
}

function install_tesseract ()
{
	TESSTGZ="$(echo "$SRCDIR"/tesseract-*.gz)"
	[ -f "$TESSTGZ" ] || die "cannot work with this: [$TESSTGZ]"
	TESSDIR="$(gunzip < "$TESSTGZ" | tar tf - | grep "^[^/]*/configure.ac$" | cut -d/ -f1)"
	rm -rf "$TESSDIR" || die "remove existing tesseract build dir"
	gunzip < "$TESSTGZ" | tar xf -
	pushd "$TESSDIR" > /dev/null || die "could not change to directory: [$TESSDIR]"
	./autogen.sh || die "could not autogen tesseract"
	./configure --prefix="$INSTALLDIR" --disable-static --disable-dependency-tracking --disable-graphics --disable-legacy || die "could not configure tesseract"
	make install-strip || die "could not build or install tesseract"
	popd > /dev/null || die "popd tesseract"
}

function install_imagemagick ()
{
	IMGKTGZ="$(echo "$SRCDIR"/ImageMagick-*.gz)"
	[ -f "$IMGKTGZ" ] || die "cannot work with this: [$IMGKTGZ]"
	IMGKDIR="$(gunzip < "$IMGKTGZ" | tar tf - | grep "^[^/]*/configure.ac$" | cut -d/ -f1)"
	rm -rf "$IMGKDIR" || die "remove existing imagemagick build dir"
	gunzip < "$IMGKTGZ" | tar xf -
	pushd "$IMGKDIR" > /dev/null || die "could not change to directory: [$IMGKDIR]"
	./configure --prefix="$INSTALLDIR" --disable-static --disable-dependency-tracking || die "could not configure imagemagick"
	make install-strip || die "could not build or install imagemagick"
	popd > /dev/null || die "popd imagemagick"
}

function install_openjpeg ()
{
	OJTGZ="$(echo "$SRCDIR"/openjpeg-*.gz)"
	[ -f "$OJTGZ" ] || die "cannot work with this: [$OJTGZ]"
	OJDIR="$(gunzip < "$OJTGZ" | tar tf - | grep "^[^/]*/CMakeLists.txt$" | cut -d/ -f1)"
	rm -rf "$OJDIR" || die "remove existing openjpeg build dir"
	gunzip < "$OJTGZ" | tar xf -
	pushd "$OJDIR" > /dev/null || die "could not change to directory: [$OJDIR]"
	mkdir "build" || die "mkdir"
	pushd "build" || die "pushd"
	cmake .. -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$INSTALLDIR"
	make install || die "could not build or install openjpeg"
	popd > /dev/null || die "popd build"
	popd > /dev/null || die "popd openjpeg"
}

function install_tessdata ()
{
	TESSDATA="${INSTALLDIR}/share/tessdata"

	mv "$LANGDIR"/* "$TESSDATA"/ || die "lang mv"
}

function create_payload ()
{
	mkdir -p "$DISTDIR"/{bin,etc,lib,share} || die "dist subdirs mkdir"

	cp "$LAMBDABIN" "${DISTDIR}/lambda" || die "dist bin cp lambda"

	cp "${INSTALLDIR}/bin/tesseract" "${DISTDIR}/bin/" || die "dist bin cp tesseract"
	cp "${INSTALLDIR}/bin/magick" "${DISTDIR}/bin/" || die "dist bin cp magick"

	cp -R "${INSTALLDIR}/etc/ImageMagick-7" "${DISTDIR}/etc" || die "dist etc cp"
	cp -R "${INSTALLDIR}/share/tessdata" "${DISTDIR}/share" || die "dist share cp"

	while read line; do
		lib="$(echo "$line" | awk '{print $1}')"
		res="$(echo "$line" | awk '{print $3}')"
		cp "$res" "$DISTDIR"/lib/ || die "dist lib cp: [$lib]"
	done < <(ldd "$DISTDIR"/bin/* | egrep "/lib(jbig|jpeg|lept|openjp2|png|tesseract|tiff|Magick)")

	find "$DISTDIR" \( \( -type d \) -o \( -type f -a -perm /a+x \) \) -print0 | xargs -0r chmod 755
	find "$DISTDIR" -type f -a \! -perm /a+x -print0 | xargs -0r chmod 644

	pushd "$DISTDIR" > /dev/null || die "dist cd"
	zip -r "$LAMBDAZIP" . || die "zip"
	popd > /dev/null || die "popd zip"
}

function install_dependencies ()
{
	pushd "$BUILDDIR" > /dev/null || die "install pushd"

	install_leptonica
	install_tesseract
	#install_openjpeg
	install_imagemagick
	install_tessdata

	popd > /dev/null || die "install popd"
}

### script starts here

initialize_environment

download_dependencies
download_languages

install_dependencies

create_payload

ldd "$DISTDIR"/bin/*

exit 0
