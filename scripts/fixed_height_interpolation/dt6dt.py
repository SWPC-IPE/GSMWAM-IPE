import numpy as np
from scipy.interpolate import interp1d
from netCDF4 import Dataset
from sys import argv
from os.path import basename, dirname
from itertools import product, repeat
from multiprocessing import Pool

VARDIMS  = ('time', 'alt', 'lat', 'lon')

DIMENSIONS = ['lon', 'lat', 'time']
DNAMES     = ['lon', 'lat', 'time']

COPY_VARIABLES = ['lat', 'lon', 'time']
COPY_DIMS      = [('lat',), ('lon',), ('time',)]

CREATE_VARIABLES = ['qno', 'wtot', 'euv', 'uv', 'cp', 'rho']
LOG_INTERPOLATE_F = lambda x: True if x != 'cp' else False

HEIGHTS = np.arange(100000,250001,10000)

def par_interpolate(fn, vname):
    nc_fid = Dataset(fn)

    log = LOG_INTERPOLATE_F(vname)

    var = nc_fid.variables[vname][:]

    height = nc_fid.variables['z'][:]
    times, heights, lats, lons = height.shape

    output = np.zeros((times, len(HEIGHTS), lats, lons))

    adj = 0.

    if var.min() < 0.: adj = -var.min() * 1.000001
    if var.min() == 0.: adj = 0.000001

    print('interpolating', vname) # , log, var.min(), adj)

    if log: var = np.log(adj+var)

    for t, (_v, _h) in enumerate(zip(var, height)):
        for i, j in product(range(lats), range(lons)):
            f = interp1d(_h[:,i,j], _v[:,i,j], bounds_error=False,
                         fill_value=(_v[0,i,j],_v[-1,i,j]), kind='quadratic')
            output[t,:,i,j] = f(HEIGHTS)

    if log: output = np.exp(output) - adj

    return output


def create_netcdf(ncfid_i, ncfid_o, fn_i):
    for dname, d in zip(DIMENSIONS, DNAMES):
        dim = ncfid_i.dimensions[d]
        ncfid_o.createDimension(dname, dim.size)

    ncfid_o.createDimension('alt', len(HEIGHTS))
    varo = ncfid_o.createVariable('alt', 'f4', ('alt',))
    varo.units = 'm'
    varo.long_name = 'Geometric Height'
    varo[:] = HEIGHTS

    for v, d in zip(COPY_VARIABLES, COPY_DIMS):
        vari = ncfid_i.variables[v]
        varo = ncfid_o.createVariable(v, vari.datatype, d)
        varo[:] = vari[:]
        varo.units = vari.units
        varo.long_name = vari.long_name

    with Pool(processes=len(CREATE_VARIABLES)) as p:
        print('starting parallel')
        ovars = p.starmap(par_interpolate, zip(repeat(fn_i), CREATE_VARIABLES))

    for v, d, ovar in zip(CREATE_VARIABLES, repeat(VARDIMS), ovars):
        print('assigning',v)
        vari = ncfid_i.variables[v]
        varo = ncfid_o.createVariable(v, vari.datatype, d)
        varo.units = vari.units
        varo.long_name = vari.long_name
        varo[:] = ovar

    return ncfid_o

def main():
    fn_in = argv[1]
    fn_out = '{}/fixed_height.{}'.format(dirname(fn_in), basename(fn_in))

    ncfid_i = Dataset(fn_in)
    ncfid_o = Dataset(fn_out, 'w')

    create_netcdf(ncfid_i, ncfid_o, fn_in)

    ncfid_i.close()
    ncfid_o.close()

if __name__ == '__main__':
    main()
