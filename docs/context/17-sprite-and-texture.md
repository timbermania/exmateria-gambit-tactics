# Sprite and texture

The foundational two-term vocabulary every rendering cluster builds on.
A **texture** is the file (bytes); a **sprite** is the rendered concept
that paints from one. Sprites come in several kinds — unit body, unit
weapon, unit effect-layer, status text, particle, projectile, portrait —
each with its own pipeline (shader, composition data, identity scheme).
Distinct kinds of sprite are not interchangeable; the word "sprite"
without a subject qualifier is the smell this cluster retires.

Both terms belong to `Sprite Rig`, which extraction #4 publishes as an addon.
The rig's settled published spellings are tabulated once, at the head of
[sprite layers](18-sprite-layers.md).

**Texture**:
Raw on-disc image data. Bytes (.tga in this project, lossless per
ADR-0009-era importer defaults), optionally with a sibling palette file
(`NN.tga` + `NN.palette.tga`, `WEP1.tga` + `WEP1.palette.tga`, …) when
the texture is indexed-color per ADR-0022. Lives across several
directories — `assets/sprites/textures/` (ROM-extracted body / WEP1 /
EFF1 / TRAP1 / OTHER), `assets/effects/E###/texture.tga` (per-effect
particle textures), `assets/fonts/font_atlas.tga`, `assets/ui/frame.tga`,
`assets/maps/MAP###/` — and is always *just bytes*: no framing, no
animation, no semantics beyond pixels + (optionally) palette indices and
the PSX STP alpha convention. A sprite *uses* a texture; a texture *is
not* a sprite.
_Avoid_: calling a `.tga` a "sprite" (it's the texture; the sprite is
what the shader composes from it); assuming every texture under
`assets/sprites/textures/` is a unit sprite — `WEP1.tga`/`EFF1.tga` are
unit overlay layers, but `TRAP1.tga` is a [particle
sprite](15-effect-orchestration.md) texture that just happens to live in the
same folder for ROM-extraction reasons.

**Sprite**:
A textured 2D billboard rendered in the 3D scene (or canvas in UI),
composed from one or more textures + a shader + framing/composition
data. **Always qualified by subject when used** — the kinds in this
project are:
- **[Unit body sprite](18-sprite-layers.md)** — the character image on the
  BODY layer of a unit's billboard. Identity = [body sprite
  ID](18-sprite-layers.md). Composition = `TYPE1.SHP / SEQ` (or sibling
  template per [sprite type](18-sprite-layers.md)). Shader: `unit.gdshader`
  BODY path.
- **Unit weapon sprite** — the held weapon image on the WEAPON layer.
  Identity = equipped weapon's `wep1_v_offset` row in `WEP1.tga`.
  Composition = `WEP1.SHP / SEQ` (TYPE1) or `WEP2.SHP / SEQ` (TYPE2).
  Shader: `unit.gdshader` WEP1 path.
- **Unit effect-layer sprite** — the small unit-attached overlay
  (sparks, swing blurs) on the EFFECT layer. Composition = `EFF1.SHP
  / SEQ`. Shader: `unit.gdshader` EFF1 path. Not to be confused with
  the [particle](15-effect-orchestration.md) subsystem.
- **Status text sprite** — damage numbers / status word graphics
  painted on the unit's STATUS_TEXT layer.
- **[Particle sprite](15-effect-orchestration.md)** — one quad of many
  spawned by an effect cast (E### or TRAP1 family). Composition =
  per-emitter framesets. Shader: `effect_particle_mode*.gdshader`.
- **Projectile sprite** — single billboard quad for an in-flight
  thrown weapon / item. Shader: `projectile_sprite.gdshader`.
- **Portrait sprite** — UI face image, reuses the portrait region of
  the unit body texture. Shader: `unit_portrait_3d.gdshader`.

_Avoid_: the bare word "sprite" without a subject qualifier — pick the
one above that fits and use it; calling a particle a "particle sprite"
in *most* discussion (the particle subsystem is what owns the rendering;
"particle" alone is sufficient — the "sprite" qualifier is only for the
glossary clarification that a particle *is* one kind of sprite); using
"sprite" interchangeably with "texture" (one is rendered, one is bytes);
expecting all sprite kinds to share a pipeline — they don't (each kind
has its own shader and composition data, and the boundary is intentional
per ADR-0019 for unit layers, ADR-0011 for particles).
