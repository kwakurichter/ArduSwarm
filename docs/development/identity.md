# Identity — One `MAV_SYSID`

Every vehicle in this port has one global identifier: `MAV_SYSID`.

It is simultaneously:

- the MAVLink system id,
- the nRF51 radio address low byte,
- the [SwarmMesh](ap_swarmmesh.md) mesh identity (`origin_id`),
- and the [UWB node id](ap_ranging.md).

`AP_Syslink::get_address()`, `AP_SwarmMesh_Backend::frontend_sysid()` and `AP_Ranging`'s node id all return `gcs().sysid_this_mav()`.

---

## Why this matters

**Give every vehicle a distinct `MAV_SYSID` before flying more than one.** Peers are indistinguishable otherwise, and the failure is confusing rather than obvious: frames decode correctly but get filtered, ground stations merge two vehicles into one, and ranging never matches a peer.

**The Crazyradio URI follows it.** A vehicle with `MAV_SYSID = 1` is `radio://0/<SYSL_CHAN>/<rate>/E7E7E7E701` — not the Crazyflie default of `...E7E7E7E7E7`.

**Ranging peer ids join directly against MAVLink sysids.** A `peer_id` in the ranging TUNNEL payload is the same number as that peer's MAVLink `sysid`, so a companion computer can join UWB ranges to mesh peer state with no mapping table at all. See [AI Deck](ai_deck.md#4-joining-the-two-streams).

---

## Retired parameters

`RNG_NODE_ID`, `RNG_NUM_NODES` and the old `CF_*` parameters are retired, and their parameter indices are marked so they are not reused. If you find references to them in the older documentation, they no longer exist as the single `MAV_SYSID` replaced all of them.

---

## See also

- [AP_Syslink](ap_syslink.md) · [AP_SwarmMesh](ap_swarmmesh.md) · [AP_Ranging](ap_ranging.md) · [AI Deck](ai_deck.md)