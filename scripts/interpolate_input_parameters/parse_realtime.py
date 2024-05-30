#!/usr/bin/env python
from __future__ import print_function
import xml.etree.ElementTree as ET
import sys
from sw_from_f107_kp import *
import numpy as np
from datetime import datetime, timedelta
from argparse import ArgumentParser, ArgumentDefaultsHelpFormatter
from collections import defaultdict
from math import exp
import glob
from collections import OrderedDict as od
from netCDF4 import Dataset, date2num
import traceback
from os.path import basename

# interpolate linearly between good values, only use decay on
# forecasted values

F107_MIN  = 75.0 # also used as F107_RELAX
F107A_MIN = F107_MIN
KP_RELAX = 2.0
KP_MAX  = 999
KPA_MAX = KP_MAX
WAM_INPUT_FMT = '%Y-%m-%dT%H:%M:%SZ'
FILE_FMT = '%Y%m%dT%H%M'
PATH_FMT = '%Y%m%d'
GEOSPACE_TIME_GAP  =  3 # minutes
AVERAGING_INTERVAL = 20 # minutes
L1_DELAY           = 50 # minutes
SW_DATE_BACKWARDS  = L1_DELAY + AVERAGING_INTERVAL
F10_DATE_BACKWARDS = 60*24*3
F10_DATE_FORWARDS  = 60*24*7
DELAY_INTERVAL     = L1_DELAY - GEOSPACE_TIME_GAP # minutes
TIME_CONSTANT      = 60*5
MAX_SEARCH_DIST    = 1
DEFAULT_PATH = '.'
DEFAULT_NAME = 'input_parameters.nc'
MAX_WAIT = 120 # minutes
EDATE = '999901010000'
F10_TIME_DELTA = timedelta(minutes=8*60) # we are moving from 12 UT -> 20 UT, the obs time
KP_TIME_DELTA = timedelta(minutes=90) # middle of the Kp window
F10_JUMP_LIMIT = 35
F10A_JUMP_LIMIT = F10_JUMP_LIMIT/41*3

def backwards_search(dict,search_time,relax_func):
    # relax_func takes an argument of the current time
    for i in range(1,MAX_SEARCH_DIST+1):
        st = search_time - timedelta(minutes=1)
        if st in dict:
            fac = exp(-i/TIME_CONSTANT)
            return relax_func(search_time) * (1-fac) + dict[st] * fac
    return relax_func(search_time)

class InputParameter(object):
    def __init__(self, search_func):
        self.dict = {}
        self.mean = None
        if isinstance(search_func, str) and search_func == 'self_avg':
            self.backwards_search = lambda dict, search_time: backwards_search(dict, search_time, lambda x: self.nanmean())
        else:
            self.backwards_search = lambda dict, search_time: backwards_search(dict, search_time, search_func)

    def values(self):
        return np.asarray(list(self.dict.values()))

    def nanmean(self):
        if self.mean is None:
            self.mean = np.nanmean(self.values())
        return self.mean

    def running_average(self, averaging_time):
        vals = np.asarray(list(self.dict.values()),dtype='float64')
        output = np.zeros(len(vals)+averaging_time,dtype='float64')
        output[averaging_time:] = vals
        output[:averaging_time] = np.ones(averaging_time)*vals[0]
        cumsum_vec = np.cumsum(np.insert(output, 0, 0))
        return dict(zip(self.dict.keys(), ((cumsum_vec[averaging_time:] - cumsum_vec[:-averaging_time])/averaging_time)[1:]))

class key_dependent_dict(defaultdict):
    def __init__(self, f_of_x, factory=iter([])):
        super().__init__(None, factory)
        self.f_of_x = f_of_x
    def __missing__(self, key):
        ret = self.f_of_x(self, key)
        self[key] = ret
        return ret

class InputParameters(object):
    _lookup_table = [   0,   2,   3,   4,   5,   6,   7,   9,  12,  15,
                       18,  22,  27,  32,  39,  48,  56,  67,  80,  94,
                      111, 132, 154, 179, 207, 236, 300, 400, 999 ]

    _var_names = [ 'f107', 'kp', 'f107d', 'kpa', 'nhp', 'nhpi', 'shp', 'shpi', 'swbt',
                   'swang', 'swvel', 'swbz', 'swden', 'ap', 'apa' ]
    _var_types = [ 'f4', 'f4', 'f4', 'f4', 'f4', 'i2', 'f4', 'i2', 'f4',
                   'f4', 'f4', 'f4', 'f4', 'f4', 'f4' ]
    _var_long_names = [ '10.7cm Solar Radio Flux' , 'Kp Index', '41-Day F10.7 Average', '24hr Kp Average',
                        'Northern Hemispheric Power', 'Northern Hemispheric Power Index',
                        'Southern Hemispheric Power', 'Southern Hemispheric Power Index',
                        'IMF Total B Strength', 'Solar Wind Angle', 'Solar Wind Velocity',
                        'IMF Bz Strength', 'Solar Wind Density', 'Ap Index', '24hr Ap Average' ]
    _var_units = [ 'sfu', None, 'sfu', None, 'GW', None, 'GW', None,
                   'nT', 'degrees', 'km/s', 'nT', 'cm^-3', None, None ]

    def __init__(self, start_date, mins, path, outfile, append, coupled, ewam, egeo, eaur, derive=False):
        self.start_date = start_date
        self.imf_date_list = [start_date + timedelta(minutes=i-SW_DATE_BACKWARDS) for i in range(mins+SW_DATE_BACKWARDS+MAX_WAIT)]
        self.f10_date_list = [start_date + timedelta(minutes=i-F10_DATE_BACKWARDS) for i in range(mins+F10_DATE_FORWARDS)]
        self.output_list = [start_date + timedelta(minutes=i) for i in range(mins)]

        self.derive = derive

        self.ewam_date = ewam
        self.egeo_date = egeo
        self.eaur_date = eaur

        self.fwam_date = ewam
        self.fgeo_date = egeo
        self.faur_date = eaur

        self.f107a = InputParameter(lambda x: F107A_MIN) # 'self_avg'
        self.f107  = InputParameter(lambda x: F107_MIN) # np.nanmean(self.f107d.values())
        self.apa   = InputParameter(lambda x: KP_RELAX)
        self.ap    = InputParameter(lambda x: KP_RELAX)
        self.kpa   = InputParameter(lambda x: KP_RELAX)
        self.kp    = InputParameter(lambda x: KP_RELAX)
        self.swbz  = InputParameter(lambda x: swbz_calc(swesw_calc(self.kp.dict[x]), self.swvel.dict[x]))
        self.swbzo = InputParameter(lambda x: swbz_calc(swesw_calc(self.kp.dict[x]), self.swvel.dict[x]))
        self.swbx  = InputParameter(lambda x: swby_calc())
        self.swbxo = InputParameter(lambda x: swby_calc())
        self.swby  = InputParameter(lambda x: swby_calc())
        self.swbyo = InputParameter(lambda x: swby_calc())
        self.swbt  = InputParameter(lambda x: swbt_calc(self.swbz.dict[x], self.swby.dict[x]))
        self.swvel = InputParameter(lambda x: swvel_calc(self.kp.dict[x]))
        self.swveo = InputParameter(lambda x: swvel_calc(self.kp.dict[x]))
        self.swang = InputParameter(lambda x: swang_calc(swby_calc(), self.swbz.dict[x]))
        self.swden = InputParameter(lambda x: swden_calc())
        self.swdeo = InputParameter(lambda x: swden_calc())
        self.hpn   = InputParameter(lambda x: hemi_pow_calc(self.kp.dict[x]))
        self.hpin  = InputParameter(lambda x: hpi_from_gw(self.hpn.dict[x]))
        self.hps   = InputParameter(lambda x: hemi_pow_calc(self.kp.dict[x]))
        self.hpis  = InputParameter(lambda x: hpi_from_gw(self.hps.dict[x]))

        self.path    = path
        self.outfile = outfile
        self.append  = append
        self.coupled = coupled

    def linear_int_missing_vals(self, mydict, relax_func, cutoff=False):
        try:
            sorted_keys = sorted(mydict.keys())
            b = np.asarray([mydict[k] for k in sorted_keys],dtype='float64')
            c = np.isnan(b)
            ok = ~c
            xp = ok.ravel().nonzero()[0]
            fp = b[ok]
            x = c.ravel().nonzero()[0]
            b[c] = np.interp(x,xp,fp)
            if cutoff:
                b = b[:np.where(ok)[0][-1]+1]
        except:
            b = []
        return key_dependent_dict(relax_func, zip(sorted_keys,b))

    def clean_f10(self, dict, limit=F10_JUMP_LIMIT):
        c = 0
        f = {k:v for k,v in dict.items() if v}
        sorted_keys = sorted(f.keys())
        for i,x in enumerate(sorted_keys[1:]):
            if abs(f[x] - f[sorted_keys[i-c]]) > limit:
                c+=1
                dict[x] = None

        return dict

    def ap_from_kp(self, v):
        lookup = v*3
        remainder = lookup - int(lookup)
        return (1 - remainder) * self._lookup_table[int(lookup)] + \
                    remainder  * self._lookup_table[int(lookup) + 1]

    def kp_from_ap(self, v):
        idx = list(x > v for x in self._lookup_table).index(True)
        return ((v - self._lookup_table[idx-1])/(self._lookup_table[idx]-self._lookup_table[idx-1]) + idx - 1) / 3

    def all_kp_from_ap(self):
        self.kp.dict = self.ap.dict.copy()
        for k,v in self.kp.dict.items():
            self.kp.dict[k] = self.kp_from_ap(v)

        self.kpa.dict = self.apa.dict.copy()
        for k,v in self.kpa.dict.items():
            self.kpa.dict[k] = self.kp_from_ap(v)

    def parse_geospace_input(self):
        swbz  = self.swbz.dict
        swby  = self.swby.dict
        swbx  = self.swbx.dict
        swden = self.swden.dict
        swvel = self.swvel.dict
#        for k in self.date_list:
#            swbz[k]  = None
#            swby[k]  = None
#            swbx[k]  = None
#            swden[k] = None
#            swvel[k] = None

        for date in self.imf_date_list:
            if self.derive:
                break
            if date - timedelta(minutes=DELAY_INTERVAL) > self.egeo_date:
                break
            try:
                fd = date - timedelta(minutes=DELAY_INTERVAL)
                file = '{}/{}/swpc/geospace_input-{}.xml'.format(self.path,\
                           fd.strftime(PATH_FMT),fd.strftime(FILE_FMT))
                item = ET.parse(file).getroot().find('data-item')
                swbz[date]  = float(item.find('mag_bz_gsm').text)
                swbx[date]  = float(item.find('mag_bx_gsm').text)
                swby[date]  = float(item.find('mag_by_gsm').text)
                swden[date] = float(item.find('proton_density').text)
                swvel[date] = float(item.find('proton_speed').text)
                self.fgeo_date = fd
            except:
                pass

        swbz  = self.linear_int_missing_vals(swbz,  self.swbz.backwards_search, True)
        swbx  = self.linear_int_missing_vals(swbx,  self.swbx.backwards_search, True)
        swby  = self.linear_int_missing_vals(swby,  self.swby.backwards_search, True)
        swvel = self.linear_int_missing_vals(swvel, self.swvel.backwards_search, True)
        swden = self.linear_int_missing_vals(swden, self.swden.backwards_search, True)

        # now backfill with all available data
        for k in self.imf_date_list:
            self.swvel.dict[k] = swvel[k]
            self.swbz.dict[k]  = swbz[k]
            self.swby.dict[k]  = swby[k]
            self.swbx.dict[k]  = swbx[k]
            self.swden.dict[k] = swden[k]

        # for solar wind, do averaging
        self.swbzo.dict = self.swbz.running_average(AVERAGING_INTERVAL)
        self.swbyo.dict = self.swby.running_average(AVERAGING_INTERVAL)
        self.swbxo.dict = self.swbx.running_average(AVERAGING_INTERVAL)
        self.swdeo.dict = self.swden.running_average(AVERAGING_INTERVAL)
        self.swveo.dict = self.swvel.running_average(AVERAGING_INTERVAL)

        # and get swbt and swang
        for k in self.output_list:
            self.swbt.dict[k]  = swbt_calc(self.swbzo.dict[k],self.swbyo.dict[k])
            self.swang.dict[k] = swang_calc(self.swbyo.dict[k],self.swbzo.dict[k])

    def parse_aurora_power(self):
        hpn  = self.hpn.dict.copy()
        hps  = self.hps.dict.copy()
        for k in self.imf_date_list:
            hpn[k] = None
            hps[k] = None

        days = sorted(list(set([datetime(dt.year, dt.month, dt.day) for dt in [date - timedelta(minutes=L1_DELAY) for date in self.imf_date_list]])))

        for day in days:
            if self.derive:
                break
            try:
                file = '{}/{}/swpc/wam/swpc_aurora_power_{}.txt'.format(self.path, \
                           day.strftime(PATH_FMT), day.strftime(PATH_FMT))
                with open(file) as f:
                    lines = list(filter(lambda s: not s.startswith('#') ,f.readlines()))
                for line in lines:
                    split = line.split()
                    dt = datetime.strptime(split[0],'%Y-%m-%d_%H:%M')
                    if dt > self.eaur_date:
                        break
                    self.faur_date = dt
                    dt += timedelta(minutes=L1_DELAY)

                    hpn[dt] = float(split[-2])
                    hps[dt] = float(split[-1])
            except Exception as e:
                # print(str(e))
                pass

        hpn  = self.linear_int_missing_vals(hpn,  self.hpn.backwards_search, True)
        hps  = self.linear_int_missing_vals(hps,  self.hps.backwards_search, True)
        # now backfill with all available data
        for k in self.imf_date_list:
            self.hpn.dict[k]  = hpn[k]
            self.hps.dict[k]  = hps[k]
            self.hpin.dict[k] = hpi_from_gw(self.hpn.dict[k])
            self.hpis.dict[k] = hpi_from_gw(self.hps.dict[k])

    def parse_wam_input(self):
        f107  = self.f107.dict
        f107a = self.f107a.dict
        ap    = self.ap.dict
        apa   = self.apa.dict

        for k in self.f10_date_list:
            f107[k]  = None
            f107a[k] = None
            ap[k]    = None
            apa[k]   = None

        days = set([dt.strftime('%Y%m%d') for dt in self.f10_date_list])
        files = sorted([i for day in days for i in glob.glob('{}/{}/swpc/wam/wam_input*'.format(self.path, day))])

        for file in files:
            fn = basename(file)
            dt = datetime.strptime(fn, 'wam_input-%Y%m%dT%H%M.xml')
            if dt > self.ewam_date: continue

            try:
                root = ET.parse(file).getroot()
                time = datetime.strptime(root.find('data-item').get('time-tag'), WAM_INPUT_FMT)
                for child in root.findall('data-item'):
                    time = datetime.strptime(child.get('time-tag'), WAM_INPUT_FMT)
                    if time.hour == 12:
                        f107[time+F10_TIME_DELTA]  = max(float(child.find('f10').text), F107_MIN)
                        f107a[time+F10_TIME_DELTA] = max(float(child.find('f10-41-avg').text), F107A_MIN)
                    ap[time+KP_TIME_DELTA]  = self.ap_from_kp(min(float(child.find('kp').text), KP_MAX))
                    apa[time+KP_TIME_DELTA] = self.ap_from_kp(min(float(child.find('kp-24-hr-avg').text), KPA_MAX))
                self.fwam_date = dt
            except:
                pass

        self.clean_f10(f107, F10_JUMP_LIMIT)
        self.clean_f10(f107a, F10A_JUMP_LIMIT)

        # and interpolate them
        f107  = self.linear_int_missing_vals(f107,  self.f107.backwards_search)
        f107a = self.linear_int_missing_vals(f107a, self.f107a.backwards_search)
        ap    = self.linear_int_missing_vals(ap,    self.ap.backwards_search)
        apa   = self.linear_int_missing_vals(apa,   self.apa.backwards_search)
        # now backfill with all available data
        for k in self.f10_date_list:
            self.f107.dict[k]  = f107[k]
            self.f107a.dict[k] = f107a[k]
            self.ap.dict[k]    = ap[k]
            self.apa.dict[k]   = apa[k]

        self.all_kp_from_ap()

    def parse(self):
        self.parse_wam_input()
        self.parse_geospace_input()
        self.parse_aurora_power()

    def output(self):
        mode = 'w'
        if self.append:
            mode = 'a'
        output_fields  = ['Date_Time','F10','Kp','F10Flag','KpFlag','F10_41dAvg','24HrKpAvg',\
                          'NHemiPow','NHemiPowIdx','SHemiPow','SHemiPowIdx','SW_Bt','SW_Angle','SW_Velocity','SW_Bz','SW_Den']
        header_formats = ['{:<20}','{:>12}','{:>12}','{:>12}','{:>12}','{:>12}','{:>12}',\
                          '{:>12}','{:>12}','{:>12}','{:>12}','{:>12}','{:>12}','{:>12}','{:>12}','{:>12}\n']
        output_formats = ['{:<20}','{:>12.7f}','{:>12.7f}','{:>12}','{:>12}','{:>12.7f}','{:>12.7f}',\
                          '{:>12.7f}','{:>12}','{:>12.7f}','{:>12}','{:>12.7f}','{:>12.7f}','{:>12.7f}','{:>12.7f}','{:>12.7f}\n']
        fields = lambda k: [k.strftime(WAM_INPUT_FMT),self.f107.dict[k],self.kp.dict[k],'2','1',self.f107a.dict[k],\
                            self.kpa.dict[k],self.hpn.dict[k],self.hpin.dict[k],self.hps.dict[k],self.hpis.dict[k],\
                            self.swbt.dict[k],self.swang.dict[k],self.swveo.dict[k],self.swbzo.dict[k],self.swdeo.dict[k]]
        with open(self.outfile, mode) as f:
            if not self.append:
                f.write('Issue Date          {}\n'.format(datetime.now().strftime(WAM_INPUT_FMT)))
                f.write('Flags:  0=Forecast, 1=Estimated, 2=Observed \n\n')
                for fmt, name in zip(header_formats,output_fields):
                    f.write(fmt.format(name))
                f.write('{}\n'.format('-'*(12*len(output_fields)+8)))
            for date in self.output_list:
                for fmt, field in zip(output_formats, fields(date)):
                    f.write(fmt.format(field))

    def netcdf_output(self):
        _mode = 'w'
        if self.append:
            _mode = 'a'

        _fields = lambda k: [date2num(k, 'days since 1970-01-01'),
                             self.f107.dict[k], self.kp.dict[k], self.f107a.dict[k], self.kpa.dict[k],
                             self.hpn.dict[k], self.hpin.dict[k], self.hps.dict[k], self.hpis.dict[k],
                             self.swbt.dict[k], self.swang.dict[k], self.swveo.dict[k], self.swbzo.dict[k],
                             self.swdeo.dict[k], self.ap.dict[k], self.apa.dict[k]]
        # Open
        _o = Dataset(self.outfile, _mode, format='NETCDF3_64BIT_OFFSET')
        _vars = []

        if self.coupled:
            _o.skip = 36*60
        else:
            _o.skip = 0
        _o.ifp_interval = 60

        _o.final_swfo_f10_kp_date  = self.fwam_date.strftime('%Y%m%d_%H%M%S')
        _o.final_imf_date          = self.fgeo_date.strftime('%Y%m%d_%H%M%S')
        _o.final_aurora_power_date = self.faur_date.strftime('%Y%m%d_%H%M%S')

        if not self.append:
            # Dimensions
            t_dim = _o.createDimension('time',  None)

            t_var = _o.createVariable('time', 'f8', ('time',))
            t_var.units     = 'days since 1970-01-01'

            _vars.append(t_var)

            # Variables
            for i in range(len(self._var_names)):
                _vars.append(_o.createVariable(self._var_names[i], self._var_types[i], ('time',)))
                _vars[-1].long_name = self._var_long_names[i]
                if self._var_units[i] is not None:
                    _vars[-1].units = self._var_units[i]

        else:
            t_var = _o.variables['time']
            _vars.append(t_var)
            for i in range(len(self._var_names)):
                _vars.append(_o.variables[self._var_names[i]])

        # Output
        _start = len(t_var[:])
        _len = len(self.output_list)
        _output_fields = []
        for date in self.output_list:
            _output_fields.append(_fields(date))
        _output_arr = np.asarray(_output_fields)
        for i, var in enumerate(_vars):
            var[_start:_start+_len] = _output_arr[:,i]
        _o.close()

def main():
    parser = ArgumentParser( \
               description='Parse KP, F10.7, 24hr average Kp, and hemispheric power files into binned data', \
               formatter_class=ArgumentDefaultsHelpFormatter \
             )
    parser.add_argument('-s', '--start_date', help='starting date of run (YYYYmmddHHMM)', type=str, default='202006010000')
    parser.add_argument('-d', '--duration',   help='duration (mins) of run',   type=int, default=24*60)
    parser.add_argument('-p', '--path',       help='path to input parameters', type=str, default=DEFAULT_PATH)
    parser.add_argument('-o', '--output',     help='full path to output file', type=str, default=DEFAULT_NAME)
    parser.add_argument('-a', '--append',     help='clobbers and writes header if false', default=False, action='store_true')
    parser.add_argument('-c', '--coupled',    help='setup for coupled model run',         default=True, action='store_true')
    parser.add_argument('-e', '--ewam_date',  help='end date of wam-input (YYYYmmddHHMM)',      type=str, default=EDATE)
    parser.add_argument('-f', '--egeo_date',  help='end date of geospace-input (YYYYmmddHHMM)', type=str, default=EDATE)
    parser.add_argument('-g', '--eaur_date',  help='end date of aurora_power (YYYYmmddHHMM)',   type=str, default=EDATE)
    parser.add_argument('-r', '--derive',     help='derive IMF, SW, HP from Kp', default=False, action='store_true')
    parser.add_argument('-i', '--input_file', type=str, default=None)
    args = parser.parse_args()

    start_date = datetime.strptime(args.start_date,'%Y%m%d%H%M')
    ewam_date  = datetime.strptime(args.ewam_date, '%Y%m%d%H%M')
    egeo_date  = datetime.strptime(args.egeo_date, '%Y%m%d%H%M')
    eaur_date  = datetime.strptime(args.eaur_date, '%Y%m%d%H%M')

    if args.input_file:
        nc_fid = Dataset(args.input_file)
        ewam_date = datetime.strptime(nc_fid.final_swfo_f10_kp_date, '%Y%m%d_%H%M%S')
        egeo_date = datetime.strptime(nc_fid.final_imf_date, '%Y%m%d_%H%M%S')
        eaur_date = datetime.strptime(nc_fid.final_aurora_power_date, '%Y%m%d_%H%M%S')
        nc_fid.close()

    ip = InputParameters(start_date, args.duration, args.path, args.output,
                         args.append, args.coupled, ewam_date, egeo_date,
                         eaur_date, args.derive)
    try:
        ip.parse()
        ip.netcdf_output()
        ip.outfile = 'wam_input_f107_kp.txt'
        ip.output()
    except Exception as e:
        traceback.print_exc()
        pass


if __name__ == '__main__':
    main()

