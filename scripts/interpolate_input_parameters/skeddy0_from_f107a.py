#!/usr/bin/env python
from math import atan, pi
from netCDF4 import Dataset

INPUT_FILE = 'input_parameters.nc'
INPUT_INDEX = 2160
INPUT_VAR = 'f107d'
SKEDDY0=70.

def skeddy_calc(skeddy0, f107a):
    return skeddy0 - 20. - 50 * (atan(0.05*(f107a-130)))/pi

def main():
    try:
        f107a = Dataset(INPUT_FILE).variables[INPUT_VAR][INPUT_INDEX]
    except Exception as e:
        print(e)
        print('WARNING/ERROR! No F10.7a value found!')
        return
    print('skeddy0={:0.2f}'.format(skeddy_calc(SKEDDY0, f107a)))

if __name__ == '__main__':
    main()
