"""Meaningful checks for the reusable fit policy; no Blender dependency."""
import copy,json,unittest
from pathlib import Path
from cabin_fit import validate_config,fit_points,clearance_at,boundary_clearance_at
CONFIG=json.loads((Path(__file__).parent/'interior_config.json').read_text())
class FitTests(unittest.TestCase):
    def test_valid_component_keeps_dimensions(self):
        points=[(x,y,z) for x in (-.25,.25) for y in (-.55,.55) for z in (.75,1.30)]
        s,g=fit_points(points,CONFIG['envelope'],(0,0,1),CONFIG['fit'])
        self.assertEqual(s,1);self.assertGreaterEqual(g,CONFIG['envelope']['clearance'])
    def test_oversize_component_shrinks_to_clearance(self):
        points=[(x,y,z) for x in (-.25,.25) for y in (-.90,.90) for z in (.70,1.10)]
        s,g=fit_points(points,CONFIG['envelope'],(0,0,.9),CONFIG['fit'])
        self.assertLess(s,1);self.assertGreaterEqual(s,CONFIG['fit']['minimum_scale'])
        self.assertGreaterEqual(g,CONFIG['envelope']['clearance'])
    def test_bad_placement_is_rejected_instead_of_exporting(self):
        with self.assertRaises(ValueError):fit_points([(3,0,1),(3.1,.1,1.1)],CONFIG['envelope'],(3,0,1),CONFIG['fit'])
    def test_disabled_autofit_fails_on_oversize(self):
        policy={**CONFIG['fit'],'auto_fit':False}
        with self.assertRaises(ValueError):fit_points([(0,.90,1)],CONFIG['envelope'],(0,0,1),policy)
    def test_invalid_sizes_and_envelope_rejected(self):
        for mutate in [lambda c:c['front_seats'].__setitem__('width',-1),lambda c:c['envelope']['stations'][0].__setitem__('roof_z',float('nan'))]:
            c=copy.deepcopy(CONFIG);mutate(c)
            with self.assertRaises(ValueError):validate_config(c)
    def test_boundary_trim_limits_reject_outside_panels(self):
        self.assertLess(boundary_clearance_at(CONFIG['envelope'],(0,1.2,1),CONFIG['fit']['boundary_allowance']),0)
        self.assertGreater(boundary_clearance_at(CONFIG['envelope'],(0,.80,1.1),CONFIG['fit']['boundary_allowance']),0)
    def test_invalid_dashboard_size_rejected(self):
        c=copy.deepcopy(CONFIG);c['dashboard']['size'][0]=-1
        with self.assertRaises(ValueError):validate_config(c)
if __name__=='__main__':unittest.main()
