help([[
  loads GSMWAM-IPE prerequisites on WCOSS2
]])

setenv("LMOD_TMOD_FIND_FIRST", "yes")

prepend_path("MODULEPATH", "/nobackup/akubaryk/spack-stack/envs/pleiades-env/install/modulefiles/Core")

stack_intel_ver=os.getenv("stack_intel_ver") or "2020.4.304"
load(pathJoin("stack-intel", stack_intel_ver))

stack_mpt_ver=os.getenv("stack_mpt_ver") or "mpt.2.28_25Apr23_rhel87"
load(pathJoin("stack-mpt", stack_mpt_ver))

stack_python_ver=os.getenv("stack_python_ver") or "3.10.8"
load(pathJoin("stack-python", stack_python_ver))

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

prod_util_ver=os.getenv("prod_util_ver") or "1.2.2"
load(pathJoin("prod_util", prod_util_ver))

-- set recommended Fortran compiler flags
setenv("FCFLAGS", "-O2 -fp-model precise -ftz -fast-transcendentals -no-prec-div -no-prec-sqrt -align array64byte -align sequence -march=core-avx2")

whatis("Description: WAM-IPE build environment")

comio_ver=os.getenv("comio_ver") or "0.0.10"
load(pathJoin("comio", comio_ver))

py_numpy_ver=os.getenv("py_numpy_ver") or "1.22.3"
load(pathJoin("py-numpy", py_numpy_ver))
