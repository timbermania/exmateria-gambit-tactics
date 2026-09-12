# Limiting is a bus stage, and the DOMAIN bus is where it goes (supersedes ADR-0050 decision 1)

## Status

Accepted (2026-08-25)

Supersedes decision 1 of
[ADR-0050](0050-sfx-bus-is-soft-limited-isolation-stays-byte-faithful.md)
(`BusLimiter` replaces the clamp). ADR-0050 decision 2 (**one cast per unit**)
survives untouched and is in fact what this rests on. Ratifies
[`D3` dec. 4](https://github.com/timbermania/fft-monorepo/issues/376#issuecomment-5382704245)
and settles §3a of `B3` task 3 ([#385](https://github.com/timbermania/fft-monorepo/issues/385)).

## Context

Two records were in direct conflict and neither cited the other.

`D3` dec. 4 says `BusLimiter` "does not survive… Delete both instances" — in
GDScript it cost **2.3× the SPU render it protected**. ADR-0050 is Accepted and
enshrines that same class as the thing standing between concurrent casts and
"the harsh, buzzy hardware-issue distortion".

They do not actually disagree, and the sentence that shows it is `D3` dec. 4's
own: **"Its job is `AudioEffectHardLimiter` on a real bus."** The job is
*re-homed*, not deleted. What no record settled — and what four sessions'
handoffs kept deferring — is **which** bus.

Two answers were defensible:

1. **Master only.** Keeps the contract `B3` task 2 published (the addon ships
   Music/SFX/Ambient with empty racks; limiting is the consumer's, on `Master`)
   and needs no new code at all — `MasterBus._install_master_limiter` has put an
   Amplify → HardLimiter at −0.3 dBFS there since ADR-0050's own follow-up #122.
2. **The domain buses too**, which is what `_limiter` / `_bg_limiter` were
   actually doing: bounding SFX and the ambient bed *separately, before* they
   met anything else.

### The measurement that decided it

`SfxPopDiagTest` fires N simultaneous **Fire (E016)** casts and reports the
summed SFX peak before any limiting — exactly what the SFX bus carries once
`BusLimiter` is gone:

| concurrent casts | 1 | 2 | 3 | 4 | 6 |
|---|---|---|---|---|---|
| untamed SFX-bus peak | 0.69 | 1.42 | 2.13 | 2.84 | **4.26** |
| gain reduction required | — | −3.0 dB | −6.6 dB | −9.1 dB | **−12.6 dB** |
| `min_gain` `BusLimiter` was applying | 1.00 | 0.70 | 0.47 | 0.35 | 0.23 |

**Fire is a mid-size effect — it peaks at 0.69 alone.** ADR-0050 measured Shiva
and Ifrit at **1.0 alone**, so this table is a floor, not a worst case.

Master-only limiting hands all of that to a limiter sitting downstream of the
SFX **and music** sum, so a six-cast burst ducks **the whole mix, music
included, by up to 12.6 dB**. That is precisely the pumping ADR-0050 built its
two-limiter split to prevent — relocated from the ambient bed onto the music
bus. It is also a regression against what ships today: `_limiter` bounds SFX to
≤ 1.0 *before* Master, which is why #122 measured the Master sum at only
1.15–1.34.

## Decision

1. **`BusLimiter` is deleted** — the class, both instances (`_limiter`,
   `_bg_limiter`), and the GDScript mix stage around them (`_combine_limited`,
   `_scale_pcm`, and the live half of `_render_unit_group` / `_sum_pcm`).
2. **One `AudioEffectHardLimiter` on `SFX` and one on `Ambient`**, installed by
   the **host** (`MasterBus._install_domain_limiters`), **ceiling 0.0 dB**. These
   two and no others — the code looped all three domain buses until the amendment
   below.
   - 0 dB rather than Master's −0.3 dB is load-bearing. It reproduces
     `BusLimiter`'s stated threshold: *"it acts only on the SUM crossing the
     ceiling, never on a single source sitting at it."* A lone full-scale summon
     sits exactly **at** 0 dB and passes untouched.
   - `SFX` is the measured case. **`Ambient` is not** — beds are
     replace-on-retrigger, so they rarely sum. It gets the same treatment
     because deleting `_bg_limiter` outright would be an *unmeasured* removal,
     and a 0 dB-ceiling limiter is transparent at rest. Recorded as
     preservation, not as evidence.
3. **`Master` keeps its Amplify → HardLimiter rack at −0.3 dBFS**, unchanged
   (`D3` dec. 6). It is now the device guard over three already-bounded buses
   rather than the only limiter in the chain. **Three bounded, two limited** —
   `Music` is bounded by the SPU's in-core clip, not by a bus effect; see the
   amendment, which is where that read as a contradiction.
4. **The addon still ships transparent routing.** The `AudioBusLayout` resource
   carries empty racks on every bus; the limiting is the host's. The README line
   *"Any limiting is yours to place on `Master`"* widens to *"on `Master` or on
   the domain buses"*.

## Consequences

- **The distortion ADR-0050 was written against cannot occur at all now**, and
  by a stronger mechanism than a limiter: with one `ExMateriaSpuStream` per
  `Spu`, the cross-unit sum happens in **float on a real bus**. Nothing clamps
  at the sum. ADR-0050 decision 2 (one cast per unit) is what makes that true —
  it is why each stream carries exactly one cast's in-core-clipped output.
- **Per-cast in-core clipping is untouched.** Within one cast its own voices
  still sum and clip inside its C++ core. That is the faithful solo sound and
  ADR-0050 explicitly keeps it.
- **The ambient/combat decoupling is now a property of the ROUTING**, not of two
  hand-rolled limiters sharing one buffer — a strictly better mechanism, and one
  a test can see directly. `AmbientAudioPathTest` used to assert it by checking
  that a `bg_limiter` stats dictionary *existed*; it now asserts that bed units
  play on `Ambient` and combat units on `SFX`.
- **`_bg_level` is now the ambient players' `volume_db`.** Same knob, same range,
  same purpose, expressed as a level rather than as limiting — which is what
  ADR-0050's own note ("so a persistent bed can be seated UNDER combat SFX")
  asked for. It sits on the players rather than the bus so it still works in a
  host that declares no layout.
- **One ADR-0050 consequence was already false before this change.** It claims
  *"Isolation is byte-faithful… a lone full-scale effect is unchanged."*
  Follow-up #122 put a −0.3 dBFS HardLimiter on `Master`, which attenuates a
  lone Shiva at 1.0. Byte-faithfulness has held only up to the Master rack since
  2026-06-19. This decision does not change that; it is recorded because the ADR
  still says otherwise.
- **Guards.** `AudioBusLayoutTest` asserts both halves — the layout **resource**
  ships empty racks, and the host installs **exactly one** HardLimiter per
  **limited** bus at `DOMAIN_CEILING_DB` — so a layout that shipped its own rack
  cannot silently double them. It also asserts the negative: an unlimited domain
  bus carries **no effect at all** (see the amendment). `SfxBusLimiterTest` is
  deleted with the class it specified; what it locked is now carried by that
  guard plus `B3` task 4's per-`Spu` parity gate.
- **`SpuClippingMetricsTest`'s bus stage is now MEASURED, not reported.** It read
  `BusLimiter`'s stats dictionary; a Godot bus effect has none. It taps the SFX
  bus with an `AudioEffectCapture` instead. Left as-is, the deleted key would
  have read 0 and made its saturation gate vacuous — the exact failure that rig
  exists to catch.

## Amendment: the limited set is two buses, and the code was looping three

Decision 2 names `SFX` and `Ambient`. `MasterBus._install_domain_limiters`
shipped in `6606a9cef` looping `DOMAIN_BUSES` — `["Music", "SFX", "Ambient"]` —
so **Music got a limiter this decision never authorised**. The commit's own body
says "a HardLimiter at 0 dB on SFX and on Ambient", so the code and the prose
that shipped together already disagreed.

The mechanism is constant reuse, and it is visible in the source. `DOMAIN_BUSES`'
docstring describes the **routing** (`Master <- {Music, SFX, Ambient}`, `D3`
dec. 6), but `grep -rn DOMAIN_BUSES godot-learning/` found exactly one consumer —
the limiter installer. It had no routing consumer at all. The test made the same
conflation from the other side: `AudioBusLayoutTest.SENDING_BUSES` is documented
as the routing list and `:93` looped it asserting each bus "carries exactly one
HardLimiter". Neither package could express *"Music routes to Master but takes no
limiter"*, which is what decision 2 decided.

**Resolved in favour of the decision**: `MasterBus` now carries `DOMAIN_BUSES`
(routing, three) and `LIMITED_BUSES` (`["SFX", "Ambient"]`), and the installer
loops the latter. The test keeps `SENDING_BUSES` for its routing assertions and
reads `MasterBus.LIMITED_BUSES` for its limiter ones rather than restating the
set.

**Decision 3's "three already-bounded buses" is still true, and does not imply a
third limiter.** Music is bounded by a different mechanism: every SPU output
frame leaves the native core through `clip_pcm16` and is scaled by `1/32767`
(`exmateria_psx_spu.cpp`), and the Music bus carries exactly **one** stream
(`smd_player.gd`'s single `AudioStreamPlayer` on `OUTPUT_BUS := &"Music"`) at
unity, with the whole-game Amplify riding downstream on `Master`. So nothing sums
on that bus and it cannot reach above 0 dBFS — the 4.26 peak that justifies SFX's
limiter is a **sum of concurrent casts** with no analogue on Music. A 0 dB-ceiling
limiter there is inert by construction, which is why removing it changes no audio;
what it changes is the record and what a future reader concludes from it. It also
restores ADR-0050's own argument in full: combat gain-reduction must not reach the
music, and a limiter on Music can only ever gain-reduce the music.

**The guard now has both arms.** `AudioBusLayoutTest` asserts an unlimited domain
bus carries zero effects, not merely that it is missing a limiter, so a limiter
reappearing on Music fails the rig. Seeded: re-adding one to Music reds
`UNLIMITED bus 'Music' carries no effect at all (has 1, 1 of them HardLimiters)`.
