#!/usr/bin/env python
import numpy as np
#numpy.set_printoptions(threshold='nan')
from argparse import ArgumentParser, ArgumentDefaultsHelpFormatter
from datetime import datetime, timedelta
from itertools import chain
from math import pi
from sw_from_f107_kp import *
from netCDF4 import Dataset, date2num

## takes 3hr-avg Kp, daily F10.7, and minute-binned hemispheric power and 24hr-avg Kp
## and translates them all to the same cadence (hard-coded 1 minute)

MINS_PER_KP_SEGMENT   = 3*60
MINS_PER_F107_SEGMENT = 24*60
MIDPOINT_F107         = 20*60
MIDPOINT_F107_FRACTION = float(MIDPOINT_F107)/MINS_PER_F107_SEGMENT
F107_MIDPOINT_STRING = '2000'
KP_MIDPOINT_STRING = '0130'
AVERAGING_INTERVAL = 20 # minutes, for magnetospheric response
L1_DELAY = 50 # minutes

def ap_from_kp(kp, kpa):
    ap  = kp.copy()
    apa = kpa.copy()

    for i,v in enumerate(ap):
        lookup = v*3
        remainder = lookup - int(lookup)
        ap[i]  = (1 - remainder) * LOOKUP_TABLE[int(lookup)] + \
                      remainder  * LOOKUP_TABLE[int(lookup) + 1]
    for i,v in enumerate(apa):
        lookup = v*3
        remainder = lookup - int(lookup)
        apa[i] = (1 - remainder) * LOOKUP_TABLE[int(lookup)] + \
                      remainder  * LOOKUP_TABLE[int(lookup) + 1]
    return ap, apa

def kp_from_ap(ap, apa):
    kp  = ap.copy()
    kpa = apa.copy()

    for i,v in enumerate(kp):
        idx = list(x > v for x in LOOKUP_TABLE).index(True)
        kp[i] = ((v - LOOKUP_TABLE[idx-1])/(LOOKUP_TABLE[idx]-LOOKUP_TABLE[idx-1]) + idx - 1) / 3

    for i,v in enumerate(kpa):
        idx = list(x > v for x in LOOKUP_TABLE).index(True)
        kpa[i] = ((v - LOOKUP_TABLE[idx-1])/(LOOKUP_TABLE[idx]-LOOKUP_TABLE[idx-1]) + idx - 1) / 3

    return kp, kpa

## future todo
# just rewrite this whole thing, it's awful

def running_average(arr, interval=AVERAGING_INTERVAL):
    vals = np.asarray(arr,dtype='float64')
    output = np.zeros(len(vals)+interval,dtype='float64')
    output[interval:] = vals
    output[:interval] = np.ones(interval)*vals[0]
    cumsum_vec = np.cumsum(np.insert(output, 0, 0))
    return ((cumsum_vec[interval:] - cumsum_vec[:-interval])/interval)[1:]

def compare_timestamp(date1,date2):
    return datetime.strptime(date1,'%Y%m%d%H') == datetime.strptime(date2,'%Y-%m-%dT%H:%M:%SZ')

def output_timestamp(start_date,delta=0):
    return (datetime.strptime(start_date,'%Y-%m-%dT%H:%M:%SZ') + timedelta(minutes=delta)).strftime('%Y-%m-%dT%H:%M:%SZ')

def compare_create(start_date):
    return datetime.strptime(start_date,'%Y-%m-%dT%H:%M:%SZ').strftime('%Y%m%d%H')

### weak failure handling

def failure(fail_point):
    ## fail_point: string
    print('error during '+fail_point)
    exit(0)

### YYYYMMDDHH functions

def hourless(string):
    ## convert YYYYMMDDHH string to YYYYMMDD
    return string[:-2]

def doy(date):
    ## date: YYYYMMDDHH string to return DOY for
    return datetime.strptime(date,'%Y%m%d%H').timetuple().tm_yday

def new_timestamp(init, diff):
    ## init: YYYYMMDDHH string
    ## diff: integer hours
    # get new YYYYMMDDHH for date + delta_hours
    dt = datetime.strptime(init, '%Y%m%d%H')
    return (dt+timedelta(0, 60*60*diff)).strftime('%Y%m%d%H')

def time_diff(start, compare):
    ## start:   YYYYMMDDHH
    ## compare: YYYYMMDDHH
    # get number of minutes between two YYYYMMDDHH strings
    start_time = datetime.strptime(start,   '%Y%m%d%H%M')
    comp_time  = datetime.strptime(compare, '%Y%m%d%H%M')
    return int((start_time-comp_time).total_seconds()/60)

def get_dates(start,end):
    ## get all dates YYYYMMDD(HH) encompassing start and end timestamps
    dates = [start]                        # start with the start day
    if hourless(start) != hourless(end):
        next = new_timestamp(dates[-1], 24)    # add 24 hours
        while hourless(next) != hourless(end): # check YYYYMMDD against the end day
            dates.append(next)                   # add string         ^
            next = new_timestamp(dates[-1], 24)  # add 24 hours ------^
        dates.append(end)
    return dates

### interpolation

def interpolate(arr, mins_per_segment):
    ## arr: array of values to linearly interpolate between
    ## mins_per_segment: integer number of values per interpolation pair
    output = [] # initialize
    for pair in zip(arr, arr[1:]): # pair the values in the array
        output = np.append(output, np.linspace(pair[0], pair[1], mins_per_segment+1)[:-1]) # take the linspace, dropping off the last value
    output = np.append(output, arr[-1]) # add the last value
    return output

### parsing

def get_f107_new(path, dates):
    f107 = []
    try:
        for cdate in dates:
            with open('{}/F107/{}'.format(path, cdate[:4])) as file:
                lines = file.readlines()
            doy = datetime.strptime(cdate, '%Y%m%d%H').timetuple().tm_yday
            f107.append(float(lines[doy-1].split()[2]))
    except Exception as e:
        print(e)
        failure('f107new read')

    f107a = running_average(f107, 41)
    return interpolate(np.array(f107), MINS_PER_F107_SEGMENT), interpolate(np.array(f107a), MINS_PER_F107_SEGMENT)

def get_kp_f107(path, dates):
    ## start: YYYYMMDDHH string for starting date
    ## end:   YYYYMMDDHH string for ending date
    # initialize
    kp    = []
    f107  = []
    try:
        for cdate in dates: # for each date to pull info for, open database file
            with open('{}/KP_AP_F107/{}'.format(path, cdate[:4])) as file:
                f = file.readlines()
                kp.extend([float(line[i:i+2])/10 for i in range(12, 28, 2) for line in f if line[:6] == hourless(cdate[2:])])
                f107.extend([float(line[65:71])                            for line in f if line[:6] == hourless(cdate[2:])])
    except Exception as e:
        print(e)
        failure('yearly kp_ap database read')
    # return the interpolated values
    f107a = running_average(f107, 41)
    kpa   = running_average(kp, 8)

    ap, apa = ap_from_kp(kp, kpa)

    ap, apa = interpolate(np.array(ap), MINS_PER_KP_SEGMENT), interpolate(np.array(apa), MINS_PER_KP_SEGMENT)

    kp, kpa = kp_from_ap(ap, apa)

    return kp, kpa, interpolate(np.array(f107), MINS_PER_F107_SEGMENT), interpolate(np.array(f107a), MINS_PER_F107_SEGMENT)

def kp_avg_date_fmt(date):
   return date[:4] + '_doy' + "{:03d}".format(doy(date)) + '_avgkp.dat'

def get_24hr_kp_avg(path, dates):
    kp_avg = []
    try:
        for cdate in dates:
            with open('{}/24HR_KP_AVG/{}/{}'.format(path, cdate[:4], kp_avg_date_fmt(cdate))) as file:
                for line in file:
                    kp_avg = np.append(kp_avg,float(line.rstrip()[-10:]))
    except:
        failure('24hr_kp_avg database read')

    return kp_avg

def hemi_date_fmt(date):
    return datetime.strptime(date,'%Y%m%d%H').strftime('%Y-%m-%d') + '-input.txt'

def get_solar_data(path, dates):
    swbt         = []
    swangle      = []
    swvel        = []
    swden        = []
    bz           = []
    hemi_pow     = []
    hemi_pow_idx = []

    try:
        for cdate in dates:
            with open('{}/AURORA_POWER/{}/{}'.format(path, cdate[:4], hemi_date_fmt(cdate))) as file:
                lines = np.array([[float(i) for i in line.split(' ')] for line in file.readlines()[95:]])
                swbt.extend(   lines[:,0])
                swangle.extend(lines[:,1])
                swvel.extend(  lines[:,3])
                swden.extend(  lines[:,4])
                bz.extend(     lines[:,5])
                hemi_pow.extend(lines[:,-1])
                hemi_pow_idx.extend(lines[:,-2])
    except Exception as e:
        print(str(e))
        failure('hemispheric power read')

    return np.array(swbt),  np.array(swangle), np.array(swvel), \
           np.array(swden), np.array(bz),      np.array(hemi_pow), np.array(hemi_pow_idx, dtype=int)

def start_fixed_data(fixed, mduration):
    # read f107, kp
    with open(fixed,'r') as f:
        lines = f.read().splitlines()
        return np.ones(mduration)*float(lines[0]), np.ones(mduration)*float(lines[1])

def finish_fixed_data(fixed, mduration):
    # read swvel, swden, swby, swbz, gwatts, HPI
    with open(fixed,'r') as f:
        lines = f.read().splitlines()
        return np.ones(mduration)*float(lines[2]), np.ones(mduration)*float(lines[3]), \
               np.ones(mduration)*float(lines[4]), np.ones(mduration)*float(lines[5]), \
               np.ones(mduration)*float(lines[6]), np.ones(mduration)*float(lines[7])

def parse(args, end_date):
    start_date = args.start_date
    ## start_date: YYYYMMDDHH string
    ## end_date:   YYYYMMDDHH string
    ## hduration:  integer hours to forecast, convert immediately to minutes+1 mduration
    mduration = args.duration*60+1

    starting_min = float(start_date[-2:])*60
    ending_min   = float(end_date[-2:])*60

    # first determine which dates we need to pull data for
    # the F10.7 is the dominating factor as the daily value, so we just check against that for Kp/F10.7
    if float(starting_min) / MINS_PER_F107_SEGMENT > MIDPOINT_F107_FRACTION: # start interpolation from current day
        min_f107 = new_timestamp(start_date, -24*40)
    else:                                                                    # start interpolation from prior day
        min_f107 = new_timestamp(start_date, -24*41)

    if float(ending_min) / MINS_PER_F107_SEGMENT > MIDPOINT_F107_FRACTION:   # end interpolation at next day
        max_f107 = new_timestamp(end_date,    24)
    else:                                                                    # end interpolation at current day
        max_f107 = end_date

    # KP/F107
    if args.mode[:4] == 'time':
        kp_offset     = time_diff(start_date+'00', hourless(min_f107) + KP_MIDPOINT_STRING)
        f107_offset   = time_diff(start_date+'00', hourless(min_f107) + F107_MIDPOINT_STRING)
        kp_avg_offset = kp_offset # time_diff(args.start_date+'00', hourless(min_f107) + '0000')
        kp, kp_avg, f107, f107a = get_kp_f107(args.path, get_dates(min_f107, max_f107))
        if args.new_f107:
            f107, f107a = get_f107_new(args.path, get_dates(min_f107, max_f107))
#        kp_avg          = get_24hr_kp_avg(get_dates(start_date,end_date))
    else: # fixed kp/f107
        kp_offset     = 0
        f107_offset   = 0
        kp_avg_offset = 0
        f107, kp = start_fixed_data(args.fixed, mduration)
        kp_avg = kp ; f107a = f107 # 24hr avg kp = kp, f10.7 avg = f10.7
    f107  = cap_min_max(f107,66,True)
    f107a = cap_min_max(f107a,66,True)
    # SOLAR WIND DATA
    if args.mode[-6:] != 'derive': # either timeobs (equation) or fixall (0)
        if args.mode[-3:] == 'obs': # get solar data from obs
            hemi_offset = time_diff(start_date+'00', hourless(start_date)+'0000') - L1_DELAY
            if hemi_offset < 0:
                start_date = new_timestamp(start_date, -24)
                hemi_offset += 24*60
            kp_avg_offset = kp_offset # time_diff(args.start_date+'00', hourless(min_f107) + '0000')
            swbt, swangle, swvel, swden, swbz, hemi_pow, hemi_pow_idx = get_solar_data(args.path, get_dates(start_date, end_date))
        else: # values are fixed from input
            hemi_offset = 0
            swvel, swden, swby, swbz, hemi_pow, hemi_pow_idx = finish_fixed_data(args.fixed, mduration)
            swbt = np.sqrt(swby**2 + swbz**2)
            swangle = np.arcsin(swby/swbt)/pi*180
    else: # use Tim's algorithms: https://github.com/SWPC-IPE/WAM-IPE/issues/126#issuecomment-374304207
        hemi_offset = 0
        swbt, swangle, swvel, swden, swbz, hemi_pow, hemi_pow_idx = calc_solar_data(kp[kp_offset:kp_offset+mduration])

    # return our subarrays

    swby = swbt * np.sin(swangle*pi/180)

    return kp[kp_offset:kp_offset+mduration], f107[f107_offset:f107_offset+mduration], f107a[f107_offset:f107_offset+mduration], \
           kp_avg[kp_avg_offset:kp_avg_offset+mduration], swbt[hemi_offset:hemi_offset+mduration], \
           swangle[hemi_offset:hemi_offset+mduration], swvel[hemi_offset:hemi_offset+mduration], \
           swden[hemi_offset:hemi_offset+mduration], swbz[hemi_offset:hemi_offset+mduration], \
           hemi_pow[hemi_offset:hemi_offset+mduration], hemi_pow_idx[hemi_offset:hemi_offset+mduration], swby[hemi_offset:hemi_offset+mduration]

def output_timestamp(start_date,delta=0):
    return (datetime.strptime(start_date,'%Y%m%d%H') + timedelta(minutes=delta)).strftime('%Y-%m-%dT%H:%M:%SZ')

def txt_output(args, file, kp, f107, f107a, kpa, swbt, swangle, swvel, swden, swbz, hemi_pow, hemi_pow_idx, swby, date, coupled=True):
    swbzo = running_average(swbz)
    swbyo = running_average(swby)
    swdeo = running_average(swden)
    swveo = running_average(swvel)
    swang = swang_calc(swbyo, swbzo)
    swbt  = swbt_calc(swbyo, swbzo)

    f = open(file,'w')
    f.write('Issue Date          \n')
    f.write('Flags:  0=Forecast, 1=Estimated, 2=Observed \n\n')

    f.write(" Date_Time                   F10          Kp     F10Flag      KpFlag  F10_41dAvg   24HrKpAvg    NHemiPow NHemiPowIdx    SHemiPow SHemiPowIdx       SW_Bt    SW_Angle SW_Velocity       SW_Bz      SW_Den   \n")
    f.write("--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------   \n")

    write_output = False

    for i in range(0,len(kp)):
        if not write_output:
            write_output = compare_timestamp(args.start_date,output_timestamp(date[0],i))
            if write_output: flip = i
        if write_output:
            f.write("{0}{1:>12.7f}{2:>12.7f}{3:>12}{4:>12}{5:>12.7f}{6:>12.7f}{7:>12.7f}{8:>12}{9:>12.7f}{10:>12}{11:>12.7f}{12:>12.7f}{13:>12.7f}{14:>12.7f}{15:>12.7f}\n".format( \
                     output_timestamp(date[0],i), f107[i], kp[i], '2', '1',
                     f107a[i], kpa[i], hemi_pow[i], hemi_pow_idx[i], hemi_pow[i],
                     hemi_pow_idx[i], swbt[i], swang[i], swveo[i], swbzo[i], swdeo[i]))

    for i in range(len(kp),args.duration*60+flip):
        f.write("{0}{1:>12.7f}{2:>12.7f}{3:>12}{4:>12}{5:>12.7f}{6:>12.7f}{7:>12.7f}{8:>12}{9:>12.7f}{10:>12}{11:>12.7f}{12:>12.7f}{13:>12.7f}{14:>12.7f}{15:>12.7f}\n".format( \
                 output_timestamp(date[0],i), f107[-1], kp[-1], '2', '1',
                 f107a[-1], kpa[-1], hemi_pow[-1], hemi_pow_idx[-1], hemi_pow[-1],
                 hemi_pow_idx[-1], swbt[-1], swang[-1], swveo[-1], swbzo[-1], swdeo[-1]))


def netcdf_output(args, file, kp, f107, f107a, kp_avg, swbt, swangle, swvel, swden, swbz, hemi_pow, hemi_pow_idx, swby, coupled=True):
    swbzo = running_average(swbz)
    swbyo = running_average(swby)
    swdeo = running_average(swden)
    swveo = running_average(swvel)
    swang = swang_calc(swbyo, swbzo)
    swbt  = swbt_calc(swbyo, swbzo)

    _mode = 'w'

    ap, apa = ap_from_kp(kp, kp_avg)

    _fields = lambda k: [f107[k], kp[k], f107a[k], kp_avg[k],
                         hemi_pow[k], hemi_pow_idx[k], hemi_pow[k], hemi_pow_idx[k],
                         swbt[k], swang[k], swveo[k], swbzo[k],
                         swdeo[k], ap[k], apa[k]]
    # Open
    _o = Dataset(file, _mode, format='NETCDF3_64BIT_OFFSET')
    _vars = []

    if coupled:
        _o.skip = 36*60
    else:
        _o.skip = 0

    _o.ifp_interval = 60

    # Dimensions
    t_dim = _o.createDimension('time',  None)
    t_var = _o.createVariable('time', 'f8', ('time',))
    t_var.units     = 'days since 1970-01-01'

    # Variables
    for i in range(len(VAR_NAMES)):
        _vars.append(_o.createVariable(VAR_NAMES[i], VAR_TYPES[i], ('time',)))
        if VAR_UNITS[i] is not None:
            _vars[-1].units = VAR_UNITS[i]

    # Output
    _start = len(t_var[:])
    _len = len(f107)
    _output_fields = []

    t_var[_start:_start+_len] = date2num([datetime.strptime(args.start_date, '%Y%m%d%H') + timedelta(minutes=i)
                                             for i in range(_len)], t_var.units)

    for i in range(_len):
        _output_fields.append(_fields(i))
    _output_arr = np.asarray(_output_fields)

    for i, var in enumerate(_vars):
        var[_start:_start+_len] = _output_arr[:,i]

    _o.close()


LOOKUP_TABLE = [   0,   2,   3,   4,   5,   6,   7,   9,  12,  15,
                  18,  22,  27,  32,  39,  48,  56,  67,  80,  94,
                 111, 132, 154, 179, 207, 236, 300, 400, 999 ]
VAR_NAMES = [ 'f107', 'kp', 'f107d', 'kpa', 'nhp', 'nhpi', 'shp', 'shpi', 'swbt',
                   'swang', 'swvel', 'swbz', 'swden', 'ap', 'apa' ]
VAR_TYPES = [ 'f4', 'f4', 'f4', 'f4', 'f4', 'i2', 'f4', 'i2', 'f4',
              'f4', 'f4', 'f4', 'f4', 'f4', 'f4' ]
VAR_LONG_NAMES = [ '10.7cm Solar Radio Flux' , 'Kp Index', '41-Day F10.7 Average', '24hr Kp Average',
                   'Northern Hemispheric Power', 'Northern Hemispheric Power Index',
                   'Southern Hemispheric Power', 'Southern Hemispheric Power Index',
                   'IMF Total B Strength', 'Solar Wind Angle', 'Solar Wind Velocity',
                   'IMF Bz Strength', 'Solar Wind Density', 'Ap Index', '24hr Ap Average' ]
VAR_UNITS = [ 'sfu', None, 'sfu', None, 'GW', None, 'GW', None,
              'nT', 'degrees', 'm/s', 'nT', 'cm^-3', None, None ]
### main function

def run(args):
    end_date = new_timestamp(args.start_date, args.duration)
    data = (parse(args, end_date))
    netcdf_output(args, args.output, *data)
    txt_output(args, 'wam_input_f107_kp.txt', *data, get_dates(new_timestamp(args.start_date,0), end_date))

def main():
    parser = ArgumentParser(description='Parse KP, F10.7, 24hr average Kp, and hemispheric power files into binned data', formatter_class=ArgumentDefaultsHelpFormatter)
    parser.add_argument('-i', '--interval',   help='interval length (minutes) (default=1)', type=int, default=1) # this feature doesn't work yet
    parser.add_argument('-d', '--duration',   help='duration of run (hours) (default=24)',  type=int, default=24)
    parser.add_argument('-s', '--start_date', help='starting date of run (YYYYMMDDhh)',     type=str, required=True)
    parser.add_argument('-p', '--path',       help='path to database files',                type=str, required=True)
    parser.add_argument('-o', '--output',     help='path to output file',                   type=str, default='input_parameters.nc')
    parser.add_argument('-m', '--mode', help='timeobs (time-varying from obs), timederive (time-varying kp/f10.7, derived solar wind drivers), '+\
                                         'fixderive (fixed kp/f10.7, derived solar wind drivers), or fixall (everything fixed)', type=str, default='timeobs')
    parser.add_argument('-f', '--fixed', help='full path to file containing fixed data for run', type=str, default='')
    parser.add_argument('-n', '--new_f107',   help='use new F10.7 database', default=False, action='store_true')

    args = parser.parse_args()

    run(args)

if __name__ == '__main__':
    main()
