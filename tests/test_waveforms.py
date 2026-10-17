"""Host-side definitions, rejection cases and 14-bit encoding checks."""
import sys, unittest, zlib
from pathlib import Path
import numpy as np
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'host'))
from waveforms import make_table,expression,actual_frequency
class Waveforms(unittest.TestCase):
    def test_shapes(self):
        for shape in ['sine','square','triangle','saw','dc','expression']:
            table=make_table(shape,.8,.5,.25)
            self.assertEqual(len(table),2048);self.assertEqual(table.dtype,np.dtype('<u2'))
            self.assertTrue(np.all((table>=1638)&(table<=14745)))
        square=make_table('square',1,.5,.25)
        self.assertEqual(np.count_nonzero(square==16383),512)
        triangle=make_table('triangle',1,.5,.25)
        self.assertEqual(np.argmax(triangle),512)
    def test_math_matches_builtin(self):
        np.testing.assert_array_equal(make_table('sine',1,.5),make_table('expression',1,.5,formula='sin(2*pi*t)'))
        np.testing.assert_array_equal(make_table('square',1,.5,.25),make_table('expression',1,.5,formula='where(t<0.25,1,-1)'))
    def test_reject(self):
        for source in ['__import__("os").system("x")','t[0]','[t for t in t]','sin.__call__(t)','1/0','sqrt(-1)','2*sin(2*pi*t)','2**100000000']:
            with self.assertRaises((ValueError,SyntaxError,TypeError)):expression(source)
        with self.assertRaises(ValueError):make_table('sine',1,.1)
        with self.assertRaises(ValueError):make_table('csv',1,.5,csv_values=[-1,2])
    def test_csv_and_frequency(self):
        table=make_table('csv',1,.5,csv_values=[-1,0,1,0])
        self.assertEqual(table[0],0);self.assertEqual(table[1024],16383)
        self.assertLess(abs(actual_frequency(1000)-1000),.006)
        self.assertEqual(zlib.crc32(table.tobytes()),zlib.crc32(table.astype('<u2').tobytes()))
if __name__=='__main__':unittest.main()
