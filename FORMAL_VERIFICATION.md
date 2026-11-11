# Source-bound CTL and refractory checks

Run from the project directory on Windows with native CPython 3.11 installed:

```powershell
python -m tools.setup_formal_tools
python -m tools.run_formal_checks
```

Setup downloads official NuSMV 2.7.1, verifies its published archive SHA256,
and installs the pinned YoWASP Yosys dependencies from
`requirements-formal.txt` under ignored `build/formal_tools/`. Downloads
retain TLS certificate verification. No system installation is changed.
The checker uses the native Python executable under
`%LOCALAPPDATA%/Programs/Python/Python311/python.exe`.

Yosys reads production RTL and the harnesses in `formal/`, flattens them,
and exports SMV. NuSMV checks CTL over that generated transition relation.
One model transition represents one rising clock edge. Unconstrained inputs
become state variables allowed to change freely each step. Solver models,
scripts, logs, package versions, executable hash and production source hashes
are saved in `build/formal_checks/`; the versioned snapshot is
`verification/formal/`. No production RTL or timing constraints are modified.

## AER fairness

`formal/aer_scheduler.v` instantiates the actual BDD selector and stateful
arbiter. A pending queue head remains pending until served. Reset occurs
initially and is then deasserted. Payload is opaque (width one); payload bits
do not influence the production selection/control logic.

For each port, NuSMV proves:

```
AG (pending -> AF served)
```

This uses `FAIRNESS acknowledge`: the downstream receiver acknowledges
infinitely often. This assumption permits arbitrary finite stalls and
excludes a receiver that stops forever. Reachability checks show requests
and service are possible, preventing a vacuous empty-only result.

`formal/aer_queues.v` also instantiates all four production depth-16 FIFO
controllers, with requests held until acceptance and opaque data. It proves
eventual FIFO acceptance of a pending external request and eventual service
of each nonempty FIFO under the same fair receiver assumption. FIFO ordering,
finite capacity and continuous per-port service give queued packets progress;
the CTL properties observe acceptance/nonempty service rather than tracking
an individual payload value.

These are component proofs. They do not include the framed collect/compute/
emit controller, hardware encoder, host/DMA or complete SoC. Full framed
progress additionally requires each active producer to finish its tick with
END, eventual completion of computation, output acknowledgement progress,
and no infinite resets. Composition of those assumptions with the complete
controller remains an outstanding project requirement. Simulation checks
framed integration but does not replace that proof.

## Refractory safety

`formal/lif_refractory.v` instantiates the actual full-width `lif_transition`.
An uncut Yosys SAT check proves, for every 16-bit membrane/refractory/config,
32-bit signed input current and leak shift:

```
refractory_before != 0 -> spike_next == 0
refractory_before != 0 -> membrane_next == reset_value
                         && refractory_next == refractory_before - 1
```

The CTL safety check is `AG safe`. For tractable BDD checking, its generated
SMV model replaces only the arithmetic threshold comparator's result with
an unconstrained Boolean. This allows both outcomes on every step, adds
behaviors and preserves the actual refractory guard. Proving safety on this
overapproximation is sound; it is distinct from the uncut full-width SAT
proof above. Reachability checks include nonzero refractory and firing.

The property uses the counter **before** the update. A firing update may
legitimately load a positive refractory counter while setting the spike bit.
It does not assert that a retained post-update spike vector must be zero
whenever the post-update refractory counter is positive. The proofs cover
the transition unit; its connection to all 256 stored states is also exercised
by the full-population simulations, not yet a composed formal proof.

## Results and negative controls

| Check | Expected result |
|---|---|
| Production scheduler, fair receiver | All 6 CTL checks true |
| Four depth-16 queues and scheduler, fair receiver | All 10 CTL checks true |
| Refractory overapproximation | All 3 CTL checks true |
| Full-width, uncut refractory SAT | Safety and countdown proven |
| Same scheduler without receiver fairness | 4 liveness failures, 2 reachability checks true |
| Temporary fixed-priority selector | Ports 1..3 can starve despite fair receiver |
| Temporary LIF with refractory guard removed | CTL safety fails; uncut SAT supplies counterexample |

Mutants are generated only under ignored `build/`. The runner requires the
negative checks to fail, as well as the production properties to pass.

Tool references: [NuSMV official distribution](https://nusmv.fbk.eu/downloads.html),
[NuSMV manuals](https://nusmv.fbk.eu/userman/),
[Yosys model checking documentation](https://yosyshq.readthedocs.io/projects/yosys/en/latest/using_yosys/more_scripting/model_checking.html).
