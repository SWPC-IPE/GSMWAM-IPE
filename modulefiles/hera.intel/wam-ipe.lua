help([[
  loads NEMS WAM-IPE prerequisites for Hera/Intel"
]])

prepend_path("MODULEPATH", "/contrib/sutils/modulefiles")
load("sutils")

prepend_path("MODULEPATH", "/scratch1/NCEPDEV/nems/role.epic/spack-stack/spack-stack-1.6.0/envs/unified-env-rocky8/install/modulefiles/Core")

stack_intel_ver=os.getenv("stack_intel_ver") or "2021.5.0"
load(pathJoin("stack-intel", stack_intel_ver))

stack_intel_oneapi_mpi_ver=os.getenv("intel_ver") or "2021.5.1"
load(pathJoin("stack-intel-oneapi-mpi", stack_intel_oneapi_mpi_ver))

hdf5_ver=os.getenv("hdf5_ver") or "1.14.0"
load(pathJoin("hdf5", hdf5_ver))

netcdf_c_ver=os.getenv("netcdf_c_ver") or "4.9.2"
load(pathJoin("netcdf-c", netcdf_c_ver))

netcdf_fortran_ver=os.getenv("netcdf_fortran_ver") or "4.6.1"
load(pathJoin("netcdf-fortran", netcdf_fortran_ver))

nemsio_ver=os.getenv("nemsio_ver") or "2.5.4"
load(pathJoin("nemsio", nemsio_ver))

sp_ver=os.getenv("sp_ver") or "2.5.0"
load(pathJoin("sp", sp_ver))

parallelio_ver=os.getenv("parallelio_ver") or "2.5.10"
load(pathJoin("parallelio", parallelio_ver))

esmf_ver=os.getenv("esmf_ver") or "8.6.0"
load(pathJoin("esmf", esmf_ver))

setenv("CC", "mpiicc")
setenv("CXX", "mpiicpc")
setenv("FC", "mpiifort")

-- comio load occurs out of $HOMEwfs/modulefiles and is implicitly specified
-- by build.ver as the version of COMIO that is checked out comes from build.ver.
if os.getenv("HOMEwfs") then
  prepend_path("MODULEPATH", pathJoin(os.getenv("HOMEwfs"), "modulefiles"))
else
  append_path("MODULEPATH", "/scratch1/NCEPDEV/swpc/Adam.Kubaryk/modulefiles")
end
comio_ver=os.getenv("comio_ver") or "0.0.10"
load(pathJoin("comio", comio_ver))

anaconda_ver=os.getenv("anaconda_ver") or "anaconda3-2024.02"
load(pathJoin("anaconda", anaconda_ver))

setenv("I_MPI_ADJUST_ALLTOALLV", "0")

whatis("Description: WAM-IPE build environment")
