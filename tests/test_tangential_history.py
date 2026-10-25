import unittest,json,math
from experiments.deposition.tangential_history import update_tangent,advance_histories,snapshot,restore

class TangentialHistoryTests(unittest.TestCase):
    def test_stored_force_at_zero_slip_and_unloading_reversal(self):
        loaded=update_tangent(None,.01,10,100,.5)
        held=update_tangent(loaded.state,0,10,100,.5)
        unloaded=update_tangent(held.state,-.01,10,100,.5)
        reversed_state=update_tangent(unloaded.state,-.01,10,100,.5)
        self.assertEqual(held.force,-1)
        self.assertEqual(unloaded.force,0)
        self.assertEqual(reversed_state.force,1)
        self.assertEqual(update_tangent(None,0,10,100,.5).force,0)

    def test_yield_cap_and_plastic_slip(self):
        r=update_tangent(None,.1,2,100,.5)
        self.assertEqual(r.force,-1)
        self.assertAlmostEqual(r.state.elastic_slip,.01)
        self.assertAlmostEqual(r.plastic_dissipation,.09)

    def test_discrete_energy_balance_through_load_changes(self):
        previous=None;old_energy=0.
        for i in range(300):
            slip=.017*math.sin(i*.37);normal=1+math.sin(i*.11)
            r=update_tangent(previous,slip,normal,100,.5)
            self.assertGreaterEqual(r.plastic_dissipation,-1e-15)
            self.assertAlmostEqual(r.work_into_contact-(r.elastic_energy-old_energy),r.plastic_dissipation+r.implicit_dissipation,places=13)
            previous=r.state;old_energy=r.elastic_energy

    def test_reorder_snapshot_and_replay(self):
        samples=[((1,4),.01,10),((2,9),-.02,10)]
        a,_,_=advance_histories({},samples,100,.5)
        b,_,_=advance_histories({},list(reversed(samples)),100,.5)
        self.assertEqual(a,b)
        saved=json.loads(json.dumps(snapshot(a)))
        next_samples=[((2,9),.005,3),((1,4),-.03,2)]
        self.assertEqual(advance_histories(a,next_samples,100,.5),advance_histories(restore(saved),next_samples,100,.5))

    def test_open_contact_releases_energy_and_recontact_is_new(self):
        a,_,_=advance_histories({},[((1,4),.01,10)],100,.5)
        empty,_,released=advance_histories(a,[],100,.5)
        self.assertAlmostEqual(released,.005)
        _,responses,_=advance_histories(empty,[((1,4),0,10)],100,.5)
        self.assertEqual(responses[(1,4)].force,0)

    def test_failed_batch_preserves_original(self):
        old,_,_=advance_histories({},[((1,4),.01,10)],100,.5)
        before=snapshot(old)
        with self.assertRaises(ValueError):advance_histories({},[],0,.5)
        with self.assertRaises(ValueError):advance_histories(old,[((1,4),.01,10),((2,9),0,-1)],100,.5)
        self.assertEqual(snapshot(old),before)
        with self.assertRaises(ValueError):advance_histories(old,[((1,4),0,1)]*2,100,.5)
        with self.assertRaises(ValueError):update_tangent(old[(1,4)],0,1,200,.5)

    def test_snapshot_rejects_duplicate_and_bad_version(self):
        with self.assertRaises(ValueError):restore({'version':2,'contacts':[]})
        record={'ids':[1,4],'elastic_slip':0,'stiffness':100}
        with self.assertRaises(ValueError):restore({'version':1,'contacts':[record,record]})
