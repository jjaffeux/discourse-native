"""Generate the test profile with Little CMS 2, independently of OS profiles."""

import ctypes as c
import ctypes.util
from pathlib import Path
import sys


class XY(c.Structure):
    _fields_ = [("x", c.c_double), ("y", c.c_double), ("Y", c.c_double)]


class Primaries(c.Structure):
    _fields_ = [("red", XY), ("green", XY), ("blue", XY)]


library = c.CDLL(sys.argv[1] if len(sys.argv) > 1 else ctypes.util.find_library("lcms2"))
library.cmsCreate_sRGBProfile.restype = c.c_void_p
library.cmsReadTag.argtypes = [c.c_void_p, c.c_uint32]
library.cmsReadTag.restype = c.c_void_p
library.cmsCreateRGBProfile.argtypes = [c.POINTER(XY), c.POINTER(Primaries), c.POINTER(c.c_void_p)]
library.cmsCreateRGBProfile.restype = c.c_void_p
library.cmsSaveProfileToMem.argtypes = [c.c_void_p, c.c_void_p, c.POINTER(c.c_uint32)]
library.cmsCloseProfile.argtypes = [c.c_void_p]
srgb = library.cmsCreate_sRGBProfile()
curve = library.cmsReadTag(srgb, int.from_bytes(b"rTRC", "big"))
curves = (c.c_void_p * 3)(curve, curve, curve)
white = XY(0.3127, 0.3290, 1)
primaries = Primaries(XY(0.68, 0.32, 1), XY(0.265, 0.69, 1), XY(0.15, 0.06, 1))
profile = library.cmsCreateRGBProfile(c.byref(white), c.byref(primaries), curves)
size = c.c_uint32()
assert library.cmsSaveProfileToMem(profile, None, c.byref(size))
data = c.create_string_buffer(size.value)
assert library.cmsSaveProfileToMem(profile, data, c.byref(size))
Path(__file__).with_name("display_p3.icc").write_bytes(data.raw)
library.cmsCloseProfile(profile)
library.cmsCloseProfile(srgb)
