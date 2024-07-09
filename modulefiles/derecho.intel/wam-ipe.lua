help([[
  loads GSMWAM-IPE prerequisites on WCOSS2
]])

setenv("LMOD_TMOD_FIND_FIRST", "yes")

ncarenv_ver=os.getenv("ncarenv") or "23.09"
load(pathJoin("ncarenv", ncarenv_ver))

prepend_path("MODULEPATH", "/glade/work/epicufsrt/contrib/spack-stack/derecho/modulefiles")

ecflow_ver=os.getenv("ecflow_ver") or "5.8.4"
load(pathJoin("ecflow", ecflow_ver))

mysql_ver=os.getenv("mysql_ver") or "8.0.33"
load(pathJoin("mysql", mysql_ver))

prepend_path("MODULEPATH", "/glade/work/epicufsrt/contrib/spack-stack/derecho/spack-stack-1.5.1/envs/unified-env/install/modulefiles/Core")

stack_intel_ver=os.getenv("stack_intel_ver") or "2021.10.0"
load(pathJoin("stack-intel", stack_intel_ver))

stack_cray_mpich_ver=os.getenv("stack_cray_mpich_ver") or "8.1.25"
load(pathJoin("stack-cray-mpich", stack_cray_mpich_ver))

stack_python_ver=os.getenv("stack_python_ver") or "3.10.8"
load(pathJoin("stack-python", stack_python_ver))

mkl_ver=os.getenv("mkl") or "2023.2.0"
load(pathJoin("mkl", mkl_ver))

nemsio_ver=os.getenv("nemsio_ver") or "2.5.4"
load(pathJoin("nemsio", nemsio_ver))

hdf5_ver=os.getenv("hdf5_ver") or "1.14.0"
load(pathJoin("hdf5", hdf5_ver))

netcdf_c_ver=os.getenv("netcdf_c_ver") or "4.9.2"
load(pathJoin("netcdf-c", netcdf_c_ver))

netcdf_fortran_ver=os.getenv("netcdf_fortran_ver") or "4.6.0"
load(pathJoin("netcdf-fortran", netcdf_fortran_ver))

parallel_netcdf_ver=os.getenv("parallel_netcdf_ver") or "1.12.2"
load(pathJoin("parallel-netcdf", parallel_netcdf_ver))

sp_ver=os.getenv("sp_ver") or "2.3.3"
load(pathJoin("sp", sp_ver))

parallelio_ver=os.getenv("parallelio_ver") or "2.5.10"
load(pathJoin("parallelio", parallelio_ver))

esmf_ver=os.getenv("esmf_ver") or "8.5.0"
load(pathJoin("esmf", esmf_ver))

-- comio load occurs out of $HOMEwfs/modulefiles and is implicitly specified
-- by build.ver as the version of COMIO that is checked out comes from build.ver.
if os.getenv("HOMEwfs") then
  prepend_path("MODULEPATH", pathJoin(os.getenv("HOMEwfs"), "modulefiles"))
else
  append_path("MODULEPATH", "/glade/work/akubaryk/contrib/modulefiles")
end
comio_ver=os.getenv("comio_ver") or "v0.0.10"
load(pathJoin("comio", comio_ver))

miniconda_ver=os.getenv("miniconda_ver") or "miniconda-23.11.0"
load(pathJoin("miniconda", miniconda_ver))

prod_util_ver=os.getenv("prod_util_ver") or "1.2.2"
load(pathJoin("prod_util", prod_util_ver))

-- set recommended Fortran compiler flags
setenv("FCFLAGS", "-O2 -fp-model precise -ftz -fast-transcendentals -no-prec-div -no-prec-sqrt -align array64byte -align sequence -march=core-avx2")

whatis("Description: WAM-IPE build environment")

