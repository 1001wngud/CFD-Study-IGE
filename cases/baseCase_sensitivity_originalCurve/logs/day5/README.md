# Day5 Logs

- 01_foamRun_ref_0to300.log: baseline ref run from 0 to 300.
- 02_foamRun_continue_300to500_diverged.log: first continuation attempt (numerical divergence around ~500).
- 03_foamRun_continue_300to1000_stabilized.log: continuation rerun with lower relaxation factors; reached 1000 without fatal error.
- 05_foamRun_diag_1000to1050.log: diagnostic short run after adding function-object monitors (Uavg_propeller, phi_farField, phi_top).
- 06_foamRun_parse_check.log: quick parse/startup check after adding propellerCurve outOfBounds warning.
- 07_foamRun_ref_reset_0to300.log: reset-to-start run with revised pressure BC (farField fixedValue 0); J became worse (very high).
- 08_blockMesh_domain_expand.log: blockMesh for expanded domain/mesh resolution.
- 09_createZones_domain_expand.log: createZones rerun after mesh expansion.
- 10_checkMesh_domain_expand.log: mesh quality/topology verification on expanded mesh.
- 11_foamRun_ref_domain_expand_0to120.log: ref run on expanded domain; unstable/oscillatory trend observed.
- 12_foamRun_ref_domain_expand_curveScaled_0to120.log: ref run after scaling propellerCurve (0.1x) and extending low-J points; completed to 120.
- nScan/foamRun_n*_0to40.log: B-baseline(n-scan) short runs for n = 6, 8, 10, 15, 26.
- nScan/diag_n*.txt: per-n diagnostics (J/Jcorr bounds, T/Q variability, monitor tails).
- nScan/ref_n*.{txt,json,csv}: per-n extracted reference metrics and status.
- 13_foamRun_Bbaseline_n6_0to120.log: B-baseline long run with original curve and n=6 (0->120).
- 13_diag_Bbaseline_n6_window50.txt: diagnostics after long run (window 50).
- 13_ref_Bbaseline_n6_window100.txt: extracted ref metrics/status after long run (window 100).
