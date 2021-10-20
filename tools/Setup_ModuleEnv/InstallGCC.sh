#!/bin/bash

#==============================================================================
# title       : InstallGCC.sh
# description : This script installs the gcc compiler with a specified version
#               as given below via GCCVERSION='X.X.X'
# date        : Nov 27, 2019
# version     : 1.0
# usage       : bash InstallGCC.sh
# notes       :
#==============================================================================

# Check privilege
if [[ "$EUID" -ne 0 ]]; then
  echo "Please run as root"
  exit 1
fi

# --------------------------------------------------------------------------------------------------
# Colors
# --------------------------------------------------------------------------------------------------

if test -t 1; then # if terminal
  NbrOfColors=$(which tput > /dev/null && tput colors) # supports color
  if test -n "$NbrOfColors" && test $NbrOfColors -ge 8; then
    TERMCOLS=$(tput cols)
    BOLD="$(tput bold)"
    UNDERLINE="$(tput smul)"
    STANDOUT="$(tput smso)"
    NORMAL="$(tput sgr0)"
    NC="$(tput sgr0)"
    BLACK="$(tput setaf 0)"
    RED="$(tput setaf 1)"
    GREEN="$(tput setaf 2)"
    YELLOW="$(tput setaf 3)"
    BLUE="$(tput setaf 4)"
    MAGENTA="$(tput setaf 5)"
    CYAN="$(tput setaf 6)"
    WHITE="$(tput setaf 7)"
  fi
fi

# --------------------------------------------------------------------------------------------------
# Settings
# --------------------------------------------------------------------------------------------------

NBROFCORES=$(grep ^cpu\\scores /proc/cpuinfo | uniq |  awk '{print $4}')
INSTALLDIR=/opt
SOURCESDIR=/opt/sources
MODULETEMPLATEDIR=/opt/sources/moduletemplates

cd $INSTALLDIR
if [ ! -e "${SOURCESDIR}" ]; then
  mkdir -p ${SOURCESDIR}
fi

# NOTE:
#GCC depends on:
#
#    GMP: GNU Multiple Precision Arithmetic Library
#    MPFR: GNU Multiple-precision floating-point rounding library
#    MPC: GNU Multiple-precision C library
#    ELF: Executable and Linkable Format library
#    PPL: Parma Polyhedra Library (optional, for memory optimizations)


# DOWNLOAD and INSTALL GCC COMPILER (example gcc-7.4.0)
#GCCVERSION='7.4.0'
#GCCVERSION='8.3.0'

# 9.3.0: Building GCC requires: GMP 4.2+, MPFR 2.4.0+ and MPC 0.8.0+
# sudo apt-get install libmpfr-dev
# sudo apt-get install libmpc-dev
#GCCVERSION='9.3.0'

# 10.1.0: Building GCC requires GMP 4.2+, MPFR 3.1.0+ and MPC 0.8.0+
# sudo apt-get install libmpfr-dev
# sudo apt-get install libmpc-dev
#GCCVERSION='10.1.0'
#GCCVERSION='10.3.0'

# 10.1.0: Building GCC requires GMP 4.2+, MPFR 3.1.0+ and MPC 0.8.0+.
# sudo apt-get install libmpfr-dev
# sudo apt-get install libmpc-dev
GCCVERSION='11.2.0'

# --------------------------------------------------------------------------------------------------
# Check pre-requisites
# --------------------------------------------------------------------------------------------------

if [[ ${GCCVERSION} == '9.3.0' ]] || [[ ${GCCVERSION} == '10.1.0' ]] || [[ ${GCCVERSION} == '10.3.0' ]] || [[ ${GCCVERSION} == '11.2.0' ]]; then
  sudo apt-get install libmpfr-dev -y
  sudo apt-get install libmpc-dev -y
fi

# --------------------------------------------------------------------------------------------------
# Install Module GCC
# --------------------------------------------------------------------------------------------------

MODULEFILEDIR=${INSTALLDIR}/modules/modulefiles/compilers/gcc
MODULEFILE=${MODULEFILEDIR}/${GCCVERSION}
BUILDDIR=${SOURCESDIR}/gcc-${GCCVERSION}/build
COMPILERDIR=${INSTALLDIR}'/compiler/gcc/'${GCCVERSION}
TARFILE=${SOURCESDIR}/gcc-${GCCVERSION}.tar.gz

# Remove INSTALL module directory during re-run
if [[ -n ${1} ]]; then
  if [[ ${1} =~ ^-r(erun)?$ ]] && [[ -f ${MODULEFILE} ]]; then
    #read -p "Delete ${MODULEFILE}?"
    rm ${MODULEFILE}
  fi
fi

if [ ! -e "${MODULEFILE}" ]; then
  echo ""
  echo -e "This will install GCC compiler version ${GREEN}${GCCVERSION}${NC}.\nCompilation in parallel will be executed with ${GREEN}${NBROFCORES} threads${NC}."
  read -p "Press enter to continue!"

  cd ${SOURCESDIR}

  # Remove SOURCE tar.gz file during re-run
  if [[ ${1} =~ ^-r(erun)?$ ]] && [[ -f ${TARFILE} ]]; then
    #read -p "Delete ${TARFILE}?"
    rm ${TARFILE}
  fi

  # Download tar.gz file from FTP server
  if [ ! -f ${TARFILE} ]; then
    wget -O gcc-${GCCVERSION}.tar.gz "ftp://ftp.fu-berlin.de/unix/languages/gcc/releases/gcc-${GCCVERSION}/gcc-${GCCVERSION}.tar.gz"
  fi

  # Check if tar.gz file was correctly downloaded, abort script if non-existent
  if [ ! -f ${TARFILE} ]; then
    echo "no gcc install-file downloaded for GCC-${GCCVERSION}"
    echo "check if ftp://ftp.fu-berlin.de/unix/languages/gcc/releases/gcc-${GCCVERSION}/gcc-${GCCVERSION}.tar.gz exists"
    exit
  fi

  # Extract tar.gz file
  tar -xzf ${TARFILE}

  # Create build directory
  if [ ! -d ${BUILDDIR} ]; then
    mkdir -p gcc-${GCCVERSION}/build
  fi

  # Remove SOURCE cmake-X.Y.Z/build/* directory during re-run
  if [[ ${1} =~ ^-r(erun)?$ ]] ; then
    #DELETE=$(echo ${BUILDDIR}/*)
    #read -p "Delete ${DELETE} ?"
    rm ${BUILDDIR}/*
  fi

  cd ${BUILDDIR}

  ../configure -v \
    --prefix=${COMPILERDIR} \
    --enable-languages=c,c++,objc,obj-c++,fortran \
    --enable-shared \
    --disable-multilib \
    --disable-bootstrap \
    --enable-checking=release \
    --with-sysroot=/ \
    --with-system-zlib
    # --enable-valgrind-annotations

  make -j${NBROFCORES} 2>&1 | tee make.out

  if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo " "
    echo "${RED}Failed: [make -j 2>&1 | tee make.out]${NC}"
    echo "${RED}Try setting NBROFCORES=2 (compiling with two threads) in this script and re-run with '-r'${NC}"
    exit
  else
    make install 2>&1 | tee install.out
  fi

  if [ ! -d "${MODULEFILEDIR}" ]; then
    mkdir -p ${MODULEFILEDIR}
  fi

  # Check if installation was successful by checking if gcc and gfortran executable are existent
  if [ -e "${COMPILERDIR}/bin/gcc" ] && [ -e "${COMPILERDIR}/bin/gfortran" ]; then

    # Copy module template file and insert the module version tag
    cp ${MODULETEMPLATEDIR}/compilers/gcc/v_temp ${MODULEFILE}
    sed -i 's/versionflag/'${GCCVERSION}'/gI' ${MODULEFILE}

    # Remove SOURCE tar.gz file after successful installation
    if [[ -f ${TARFILE} ]]; then
      rm -rf ${TARFILE}
    fi

  else
    echo "${RED}compiler not installed, no modulefile created${NC}"
  fi

else
  echo "${YELLOW}Compiler GCC-${GCCVERSION} already created (module file exists). Run with -r to remove and re-install.${NC}"
fi
