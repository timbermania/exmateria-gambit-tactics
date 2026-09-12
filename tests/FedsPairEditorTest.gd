extends Node
## TDD guard for the TIER-3 FEDS pair editor (ADR-0085 amendment 2026-08-11).
## The editor's read model is THE runtime decoder (`SoundOpcodes.decode_track`) —
## the code path the sequencer plays — extended to annotate each decoded event
## with its byte offset + size so the write path knows where every edited
## param byte lives (patch-in-place, never re-emit).
##
## Run: <GODOT> --path . --quit-after 400 res://tests/FedsPairEditorTest.tscn
## (NOT --quit-after 4: the page tests at the top of _ready `await` frames, so a
##  small frame budget kills the run BEFORE the summary and prints NOTHING —
##  no [PASS], no [FAIL], exit 0. Always check for the summary line itself.)

const SMD = preload("res://addons/exmateria_sound/runtime/sound_opcodes.gd")
const FedsBankScript = preload("res://addons/exmateria_sound/runtime/feds_bank.gd")
const PairModel = preload("res://src/effects/studio/FedsPairModel.gd")
const Target = preload("res://src/effects/studio/InspectionTarget.gd")
const Registry = preload("res://src/effects/studio/InspectorProjectorRegistry.gd")
const ContainerProjector = preload("res://src/effects/studio/SoundContainerProjector.gd")
const ContainerModel = preload("res://src/effects/studio/SoundContainerModel.gd")
const PairProjector = preload("res://src/effects/studio/FedsPairProjector.gd")
const Model = preload("res://src/effects/studio/EffectScoreModel.gd")
const EffectDataClass = ExMateriaEffects.EffectData
const Page = preload("res://src/effects/studio/EffectStudioPage.gd")
const Axis = preload("res://src/effects/studio/TimelineAxis.gd")
const NoOpPrune = preload("res://src/effects/studio/FedsNoOpPrune.gd")
const DragPlan = preload("res://src/effects/studio/SoundDragPlan.gd")
const FramesBar = preload("res://src/effects/studio/EffectFramesBar.gd")

var _passed: int = 0
var _failed: int = 0


func _ready() -> void:
	_test_decode_annotates_offsets_and_sizes()
	_test_pair_view_projects_lanes_ticks_and_offsets()
	_test_pair_view_stub_track_carries_flow_through_tell()
	_test_flow_through_span_decodes_stub_into_next_track()
	_test_flow_through_absent_for_sounding_track()
	_test_flow_through_field_rides_the_stub_track_view()
	_test_flow_through_crosses_pair_is_flagged()
	_test_null_slot_is_not_a_stub()
	_test_flow_through_span_refuses_a_null_slot()
	_test_pair_pips_ignore_a_null_slot()
	_test_stub_lane_carries_a_folded_noend_phantom()
	_test_unfolding_the_noend_reveals_borrowed_notes()
	_test_borrowed_note_click_selects_its_owner()
	_test_noend_phantom_joins_unwind_all()
	_test_stub_section_tell_names_what_it_borrows()
	_test_pair_view_provenance_names_referencing_containers()
	_test_pair_view_out_of_range_is_inert()
	_test_pair_target_kind_is_registered()
	_test_container_sections_link_to_referenced_pairs()
	_test_pair_projector_header_leads_with_provenance()
	_test_pair_projector_sections_render_track_lanes()
	_test_ring1_opcode_params_are_int_cells()
	_test_pitchbend16_is_a_single_signed_word_cell()
	_test_ring2_note_cells_share_the_data_byte()
	_test_ring2_explicit_form_note_shows_its_own_byte_read_only()
	_test_ring3_toggle_pairs_are_enum_substitutions()
	_test_inspector_widget_edit_lowers_sound_def_ref()
	_test_signed_byte_cell_round_trips_display_and_write()
	_test_range_hint_shows_typical_and_out_of_corpus_tell()
	_test_pair_pips_unroll_loops()
	_test_pair_pips_are_capped()
	_test_pair_pips_source_stub_from_flow_through()
	_test_model_threads_pips_onto_firing_spans()
	_test_page_scopes_pips_to_open_pair_or_selected_trigger()
	_test_timeline_ghost_rects_carry_pips()
	_test_score_build_threads_pair_views()
	_test_pair_overview_carries_audition_action()
	_test_page_computes_and_threads_pair_views()
	_test_panel_layout_places_ruler_sections_and_lanes()
	_test_panel_auto_selects_track_a_first_event()
	_test_panel_chips_are_typed_fixed_width()
	_test_panel_folded_state_hides_bodies_but_keeps_time()
	_test_a_pair_opens_with_every_loop_and_flow_unrolled()
	_test_panel_unwind_expands_in_place_per_loop()
	_test_panel_unroll_is_bounded_with_a_tell()
	_test_panel_coincident_chips_never_overlap()
	_test_opcode_verdicts_classify_each_kind()
	_test_panel_chips_carry_opcode_verdicts()
	_test_panel_chip_hover_speaks_the_verdict_reason()
	# Two-axis static "Muted" opcode verdict + hatch (ADR-0085 2026-08-12 amendment).
	_test_instrument_names_split_empty_from_gray_zone_clip()
	_test_model_threads_active_instrument_and_noise_armed()
	_test_muted_note_under_trusted_empty_instrument()
	_test_wholly_muted_track_hatches_every_event()
	_test_live_by_proxy_noise_clock_and_noise_armed_gate()
	_test_gray_zone_clip_note_is_faint_not_muted()
	_test_panel_carries_muted_faint_and_live_by_proxy()
	_test_render_track_energies_reports_absolute_raw_peak()
	_test_energy_band_shows_absolute_silent_in_isolation_marker()
	_test_panel_projects_onto_shared_frame_axis()
	_test_panel_draws_per_frame_orientation_grid()
	_test_panel_draws_playhead_from_shared_axis()
	_test_shared_peak_normalize_keeps_the_stub_flat()
	_test_render_track_energies_isolates_each_track()
	_test_panel_draws_per_track_energy_band()
	_test_panel_hit_test_routes_toggles_selects_and_inert_gutter()
	_test_panel_hover_peeks_fold_and_chip_detail()
	_test_overview_drops_the_inspector_hosted_strip()
	_test_camera_units_support_lookup_maps()
	_test_param_stats_load_the_shared_corpus_table()
	_test_param_semantics_translate_the_common_opcodes()
	_test_uncurated_params_get_labels_signedness_and_range()
	_test_event_section_applies_semantics()
	_test_panel_chip_hover_carries_semantics()
	_test_chip_hover_speaks_the_cell_labels()
	await _test_page_hosts_the_pair_lane_panel()
	await _test_page_anchors_pair_tick0_to_representative_trigger()
	await _test_page_trigger_click_lands_on_pair_code()

	# Per-instrument empirical usage range (ADR-0085 2026-08-12 amendment).
	_test_param_stats_bucket_by_instrument()
	_test_usage_range_conditions_on_instrument()
	_test_projector_attaches_instrument_range_when_active()
	_test_projector_marks_empty_bucket_and_no_instrument_states()
	_test_cell_renders_instrument_line_n_adaptive_and_empty_bucket()
	_test_cell_instrument_tell_is_gated_and_distinct()

	# No-op prune A/B active corroboration (ADR-0085 2026-08-12 amendment).
	_test_prune_substitutes_muted_note_deletes_inert_keeps_the_rest()
	_test_prune_keeps_total_ticks_and_hard_exclusions()
	_test_prune_loop_interior_muted_note_rests_every_iteration()
	_test_energy_diff_max_abs_and_peak_on_common_untrimmed_length()
	_test_noop_verdict_tiers_off_the_a_priori_constants()
	_test_render_pair_pruning_noops_builds_a_transient_pruned_bank()
	_test_noop_ab_runs_four_mixed_renders_and_attributes_per_track()
	_test_panel_layout_places_per_track_tell()
	_test_page_injects_and_invalidates_noop_ab_tells()
	# No-op A/B: audible pruned audition + joint (mixed) energy waveform.
	_test_build_pruned_bank_prunes_the_named_tracks_only()
	_test_render_pair_mixed_energy_is_the_joint_normalized_envelope()
	_test_noop_ab_joint_overlays_baseline_and_pruned_on_a_shared_scale()
	_test_panel_draws_joint_energy_band_and_overlay()

	# Prune-for-real (ADR-0085 2026-08-13 amendment): the commit seam + snapshot undo.
	_test_prune_feds_noops_swaps_the_bank_and_undo_restores()
	_test_prune_feds_noops_is_a_noop_when_nothing_to_prune()
	_test_pair_overview_carries_prune_commit_action()

	# Structural authoring (ADR-0085 2026-08-18b): lanes group by time, every event
	# shows its position in the stream.
	_test_time_carrying_events_all_share_the_one_time_kind()
	_test_spans_tile_the_track_as_notes_and_rests()
	_test_a_fermata_with_no_note_playing_is_a_rest_span()
	_test_time_regroup_leaves_verdicts_and_pruning_alone()
	_test_every_event_carries_its_ordinal_in_the_stream()
	_test_borrowed_and_ghost_copies_show_their_owners_ordinal()
	_test_insert_menu_is_the_corpus_ordered_by_coverage()
	_test_insert_menu_defaults_to_the_corpus_mode()
	_test_end_bar_is_offered_only_at_the_phantom_boundary()
	_test_insert_event_splices_an_opcode_after_its_anchor()
	_test_insert_at_the_track_start_is_addressable()
	_test_insert_refuses_a_boundary_that_is_not_an_event_edge()
	_test_delete_event_removes_the_addressed_bytes_only()
	_test_deleting_a_note_span_rests_it_byte_for_byte()
	_test_deleting_an_explicit_duration_note_shrinks_by_one_byte()
	_test_delete_refuses_a_rest_a_segment_and_a_tie()
	_test_resting_a_span_inside_a_loop_replays_every_iteration()
	_test_resting_a_span_re_derives_the_opcode_verdicts()
	_test_a_rest_span_has_no_delete_row()
	# The un-rest (ADR-0085 2026-08-19): delete's inverse, the verb §6 named and left unbuilt.
	_test_note_duration_writes_are_refused_at_the_encoder()
	_test_un_resting_a_span_sounds_it_at_the_corpus_velocity()
	_test_un_resting_a_non_table_duration_takes_the_explicit_form()
	_test_un_resting_a_legacy_note_form_rest_writes_the_corpus_note()
	_test_un_rest_refuses_a_note_a_segment_a_tie_and_a_zero_tick_span()
	_test_delete_then_un_rest_round_trips_the_corpus_note()
	_test_un_resting_a_span_re_derives_the_opcode_verdicts()
	_test_a_rest_span_offers_the_un_rest_row()
	_test_un_rest_undoes_by_snapshot()
	# The paint (ADR-0085 2026-08-19b §2): a note INSIDE a rest, splitting it. The only
	# time-lane verb that raises the event count, and the one that unblocks authoring.
	_test_painting_into_a_rest_splits_it_in_three()
	_test_painting_at_either_end_omits_the_empty_piece()
	_test_painting_the_whole_rest_is_the_un_rest_byte_for_byte()
	_test_painting_a_non_table_duration_takes_the_explicit_form()
	_test_paint_refuses_a_note_a_segment_a_tie_and_an_out_of_range_placement()
	_test_painting_re_derives_the_opcode_verdicts()
	_test_paint_undoes_by_snapshot()
	_test_a_rest_bar_offers_the_paint_row_at_the_grabbed_tick()
	# The DRAG's pure planner (ADR-0085 2026-08-19b §7 stage 2): spans in, new tiling out.
	_test_cells_fold_spans_bare_opcodes_and_flag_an_interior_one()
	_test_a_move_spends_one_side_and_absorbs_on_the_other()
	_test_a_move_clamps_at_a_wall_and_never_shortens_it()
	_test_a_move_with_no_rest_beside_it_spends_nothing()
	_test_the_run_stops_at_a_zero_tick_opcode()
	_test_the_cascade_crosses_a_run_of_rests_nearest_first()
	_test_a_deposit_with_no_rest_to_grow_inserts_one_beside_the_note()
	_test_a_resize_eats_the_rest_beside_it_and_clamps_at_the_wall()
	_test_a_shrink_makes_silence_and_needs_no_currency()
	_test_a_left_resize_moves_the_start_and_leaves_the_end_alone()
	_test_the_drag_refuses_a_rest_an_interior_opcode_and_a_multi_segment_resize()
	_test_a_resize_never_shortens_a_note_out_of_existence()
	# …and the verb that applies it (stage 4): move, resize-right, resize-left.
	_test_a_move_rewrites_the_two_rests_and_no_note_byte()
	_test_a_move_at_a_wall_splices_the_rest_out_and_makes_two_notes_adjacent()
	_test_a_deposit_beside_an_opcode_keeps_that_opcodes_firing_tick()
	_test_a_resize_keeps_the_notes_own_velocity_and_key()
	_test_a_shrink_between_two_notes_writes_the_rest_that_holds_the_clock()
	_test_the_drag_carries_untouched_bytes_verbatim()
	_test_drag_refuses_a_segment_a_rest_and_the_parked_shapes()
	_test_a_clamped_drag_still_swaps_so_the_picture_is_never_stale()
	_test_dragging_re_derives_the_opcode_verdicts()
	_test_one_drag_is_one_undo_and_every_motion_re_plans_from_pristine()
	# …and the GESTURE that drives it (stage 3): grips, the body drag, the tick read.
	_test_a_grip_is_drawn_only_where_a_drag_can_spend()
	_test_a_grip_band_straddles_the_boundary_and_is_capped_on_a_narrow_bar()
	_test_a_press_arms_the_gesture_the_bar_under_it_owns()
	_test_a_walled_note_and_a_parked_span_arm_nothing()
	_test_a_motion_reports_ticks_from_the_grab_not_the_axis()
	_test_a_paint_drag_reports_the_range_between_the_grab_and_the_cursor()
	_test_the_page_lowers_each_gesture_to_its_own_field_ref()
	# The OUTRO — the one verb that moves the clock (ADR-0085 amendment 2026-08-19c).
	_test_outro_is_the_rest_run_before_the_terminator()
	_test_an_opcode_between_the_rest_and_the_end_kills_the_outro()
	_test_a_stub_has_no_outro_and_the_view_says_so()
	_test_setting_the_outro_grows_the_tracks_clock()
	_test_setting_an_existing_outro_replaces_it_rather_than_appending()
	_test_trimming_the_outro_to_zero_splices_it_out()
	_test_a_long_outro_chunks_into_a_run_of_rests()
	_test_the_outro_carries_the_bytes_past_the_end_bar_verbatim()
	_test_the_outro_refuses_a_stub_a_negative_count_and_an_absurd_one()
	_test_the_new_outro_is_a_rest_span_the_paint_reaches()
	_test_a_rest_and_a_fermata_tick_count_are_tells_not_cells()
	_test_writing_a_rest_tick_count_is_refused_at_the_encoder()
	_test_the_terminator_offers_the_extend_and_trim_rows()
	_test_a_track_with_no_outro_offers_extend_but_not_trim()
	_test_empty_space_past_the_end_resolves_to_the_outro_rows()
	_test_the_outro_undoes_by_snapshot()
	_test_structural_feds_verbs_undo_by_snapshot()
	_test_right_click_resolves_to_a_named_byte_boundary()
	_test_right_click_in_empty_space_names_what_it_resolved_to()
	_test_context_actions_name_the_anchor_and_carry_the_corpus()
	_test_a_click_on_no_bytes_names_the_place_it_landed()
	_test_the_add_submenu_says_why_there_is_no_add_note_row()
	_test_delete_on_a_span_names_the_silence_it_leaves()
	_test_cut_offers_only_what_can_be_pasted_back()
	_test_paste_addresses_both_sides_of_the_anchor()
	_test_a_cut_and_paste_re_orders_without_resetting_the_params()
	_test_the_top_panel_height_is_latched_per_root()
	_test_the_editor_band_still_shares_the_budget()
	_test_a_span_label_never_draws_wider_than_its_own_bar()
	_test_the_label_ladder_drops_whole_tokens_pitch_before_ordinal()
	_test_every_span_boundary_gets_exactly_one_separator()
	_test_the_projection_keeps_the_fraction_of_a_frame()
	_test_the_octave_tint_is_a_global_ordered_ramp()
	_test_the_roll_puts_every_note_on_its_own_key_row()
	_test_the_roll_has_thirteen_rows_that_never_move()
	_test_a_vertical_drag_of_n_rows_moves_the_key_by_n()
	_test_the_roll_ladder_prints_the_octave_the_row_cannot()
	_test_every_span_boundary_gets_one_separator_per_ROLL_row()
	_test_the_roll_fits_the_band_on_a_full_height_window()
	_test_the_roll_toggle_is_opt_in_and_routes_from_the_header()
	_test_a_fermata_span_offers_both_of_its_boundaries()
	_test_the_boundary_past_the_fermata_is_writable()
	_test_end_bar_rides_the_phantom_boundary_context()
	_test_a_borrowed_items_owner_track_is_pair_local()

	print("\n=== FedsPairEditorTest: %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		print("[FAIL] FedsPairEditorTest")
		get_tree().quit(1)
	else:
		print("[PASS] FedsPairEditorTest")
		get_tree().quit(0)


# --- Read model: the runtime decoder annotates byte offsets ----------------
# Stream hand-assembled from the opcode table (independent of the decoder):
#   AC 05     Instrument(5)            @0, 2 bytes
#   60 0C     Note vel 0x60, C dur 12  @2, 2 bytes (table-form: 0x0C%19=12)
#   B4 3F     Noise_EnableAndClock(3F) @4, 2 bytes
#   60 00 2A  Note vel 0x60, C dur 42  @6, 3 bytes (explicit-byte form: idx 0)
#   90        EndBar                   @9, 1 byte
func _test_decode_annotates_offsets_and_sizes() -> void:
	var bytes := PackedByteArray([0xAC, 0x05, 0x60, 0x0C, 0xB4, 0x3F, 0x60, 0x00, 0x2A, 0x90])
	var events: Array = SMD.decode_track(bytes)
	_assert_eq(events.size(), 5, "decode yields 5 events")
	if events.size() != 5:
		return
	var offsets: Array = []
	var sizes: Array = []
	for e in events:
		offsets.append(e.offset)
		sizes.append(e.size)
	_assert_eq(offsets, [0, 2, 4, 6, 9], "per-event byte offsets")
	_assert_eq(sizes, [2, 2, 2, 3, 1], "per-event byte sizes")
	# The explicit-byte-form note carries its duration from the 3rd byte.
	_assert_eq(events[3].delta_time, 42, "explicit-form note duration")
	_assert_eq(events[1].delta_time, 12, "table-form note duration")


# --- View model: FedsPairModel.pair_view ------------------------------------
# Synthetic 1-pair bank, every expected value hand-computed from the byte layout
# (offsets are FEDS-blob-absolute so the slice-2 writer can patch in place):
#   header 0x18 + 2*2 offset table = tracks at 28 and 42
#   track A (28, 14 bytes): AC 05 | 94 04 | E0 40 | 60 0C | 98 03 | 81 06 | 99 | 90
#     Instrument(5) Octave(4) Dynamics(64) Note(C dur12 vel96) Repeat(3) Fermata(6) Coda EndBar
#     folded ticks: note @0 dur 12 → clock 12; fermata extends note +6 → clock 18
#   track B (42, 2 bytes): D2 08 — PitchBendRel(8), NO EndBar → stub flow-through
func _make_bank():
	var blob := PackedByteArray()
	blob.append_array("feds".to_ascii_buffer())        # 0x00 magic
	blob.append_array([44, 0, 0, 0])                   # 0x04 data_size u32
	blob.append_array([2, 0])                          # 0x08 pair_count_plus1 (1 pair)
	blob.append_array([7, 0])                          # 0x0A resource_id
	blob.append_array([28, 0, 0, 0])                   # 0x0C data_offset
	blob.append_array([0, 0, 0, 0, 0, 0, 0, 0])        # 0x10 pad to 0x18
	blob.append_array([28, 0, 42, 0])                  # 0x18 track offset table
	blob.append_array([0xAC, 0x05, 0x94, 0x04, 0xE0, 0x40, 0x60, 0x0C,
			0x98, 0x03, 0x81, 0x06, 0x99, 0x90])       # track A @28
	blob.append_array([0xD2, 0x08])                    # track B @42 (stub)
	return FedsBankScript.parse(blob)


func _test_pair_view_projects_lanes_ticks_and_offsets() -> void:
	var view: Dictionary = PairModel.pair_view(_make_bank(), 0, {}, null)
	_assert_eq(bool(view.get("valid")), true, "pair 0 is valid")
	var tracks: Array = view.get("tracks", [])
	_assert_eq(tracks.size(), 2, "pair projects 2 track lanes")
	if tracks.size() != 2:
		return
	var a: Dictionary = tracks[0]
	# Notes: one C4 bar, vel 96, dur 12, fermata-extended by 6.
	var notes: Array = a.get("notes", [])
	_assert_eq(notes.size(), 1, "track A has 1 note bar")
	if notes.size() == 1:
		var n: Dictionary = notes[0]
		_assert_eq(int(n.get("start_tick")), 0, "note starts at tick 0")
		_assert_eq(int(n.get("duration_ticks")), 12, "note duration ticks")
		_assert_eq(int(n.get("relative_key")), 0, "note key C")
		_assert_eq(int(n.get("octave")), 4, "note octave from Octave opcode")
		_assert_eq(int(n.get("velocity")), 0x60, "note velocity")
		_assert_eq(bool(n.get("has_fermata")), true, "fermata attaches to note")
		_assert_eq(int(n.get("fermata_extension_ticks")), 6, "fermata extension")
		_assert_eq(int(n.get("offset")), 34, "note offset blob-absolute (28+6)")
		_assert_eq(int(n.get("size")), 2, "note size")
		# Frame-axis amendment §3: the fermata extension carries integrated seconds
		# too (6 ticks at 120 BPM = 0.0625 s) so the panel can project it.
		_assert_true(absf(float(n.get("fermata_extension_seconds", -1.0)) - 0.0625) < 0.0001,
				"fermata extension integrates to seconds")
	# Opcode chips at their folded ticks, offsets blob-absolute.
	var cmds: Array = a.get("commands", [])
	var chip_summary: Array = []
	for c in cmds:
		chip_summary.append([str(c.get("label")), int(c.get("tick")), int(c.get("offset"))])
	_assert_eq(chip_summary, [
		["Instrument", 0, 28], ["Octave", 0, 30], ["Dynamics", 0, 32],
		["Repeat", 12, 36], ["Fermata", 12, 38], ["Coda", 18, 40], ["EndBar", 18, 41],
	], "track A opcode chips (label, folded tick, abs offset)")
	# The folded loop bracket: Repeat(3) @12 .. Coda @18, body plays 3 times —
	# annotated with integrated seconds (frame-axis §3: one tempo integrator).
	var a_loops: Array = a.get("loops", [])
	_assert_eq(a_loops.size(), 1, "one folded loop bracket")
	if a_loops.size() == 1:
		var lp: Dictionary = a_loops[0]
		_assert_eq([int(lp.get("start_tick")), int(lp.get("end_tick")), int(lp.get("count"))],
				[12, 18, 3], "folded loop bracket with count badge")
		_assert_true(absf(float(lp.get("start_seconds", -1.0)) - 0.125) < 0.0001,
				"loop start integrates to seconds")
		_assert_true(absf(float(lp.get("end_seconds", -1.0)) - 0.1875) < 0.0001,
				"loop end integrates to seconds")
	_assert_eq(int(a.get("end_tick")), 18, "track A folded end tick")
	_assert_eq(bool(a.get("stub")), false, "track A ends with EndBar")
	# tick→seconds tell: 120 BPM fallback, PPQ 48 → tick 12 = 0.125 s.
	_assert_true(absf(float(a.get("end_seconds")) - 0.1875) < 0.0001,
			"tick→seconds tell integrates 120 BPM fallback (18 ticks = 0.1875 s)")
	_assert_eq(int(view.get("total_ticks")), 18, "pair total folded ticks")


func _test_pair_view_stub_track_carries_flow_through_tell() -> void:
	var view: Dictionary = PairModel.pair_view(_make_bank(), 0, {}, null)
	var tracks: Array = view.get("tracks", [])
	if tracks.size() != 2:
		_assert_true(false, "expected 2 tracks")
		return
	var b: Dictionary = tracks[1]
	_assert_eq(bool(b.get("stub")), true, "track B has no EndBar → stub tell")
	_assert_eq(int(b.get("size_bytes")), 2, "track B is a 2-byte stub")
	var cmds: Array = b.get("commands", [])
	_assert_eq(cmds.size(), 1, "stub still renders its own events")
	if cmds.size() == 1:
		_assert_eq(str(cmds[0].get("label")), "PitchBendRel", "runtime-table label")
		_assert_eq(int(cmds[0].get("offset")), 42, "stub event offset blob-absolute")


# --- Flow-through span (ADR-0085 2026-08-14 amendment) ----------------------
# E317 pair 0, the canonical case: track A is a stub that flows into track B.
#   header 0x18 + 2*2 offset table = tracks at 28 and 30
#   track A (28, 2 bytes):  D2 02 — PitchBendRel(+2), NO EndBar → stub
#   track B (30, 15 bytes): AC 0A 94 03 D4 0E 17 60 0B D4 90 D7 81 90 90
#     Instrument(10) Octave(3) Portamento(0E,17) Note(C dur16 vel96)
#     Portamento(90,D7)  ← the byte 0x90 @40 is a PORTAMENTO PARAM, not EndBar
#     Fermata(90=144)    ← the byte 0x90 @43 is a FERMATA PARAM, not EndBar
#     EndBar @44         ← the FIRST DECODED 0x90 opcode; where the flow stops
func _make_e317_bank():
	var blob := PackedByteArray()
	blob.append_array("feds".to_ascii_buffer())        # 0x00 magic
	blob.append_array([45, 0, 0, 0])                   # 0x04 data_size
	blob.append_array([2, 0])                          # 0x08 pair_count_plus1 (1 pair)
	blob.append_array([7, 0])                          # 0x0A resource_id
	blob.append_array([28, 0, 0, 0])                   # 0x0C data_offset
	blob.append_array([0, 0, 0, 0, 0, 0, 0, 0])        # 0x10 pad to 0x18
	blob.append_array([28, 0, 30, 0])                  # 0x18 track offset table
	blob.append_array([0xD2, 0x02])                    # track A @28 (stub)
	blob.append_array([0xAC, 0x0A, 0x94, 0x03, 0xD4, 0x0E, 0x17, 0x60, 0x0B,
			0xD4, 0x90, 0xD7, 0x81, 0x90, 0x90])       # track B @30 (sounding)
	return FedsBankScript.parse(blob)


# A synthetic 2-pair bank whose pair-0 track B is a stub → its flow crosses the
# PAIR boundary into pair 1 (the safety-rail case; zero such cases in the corpus).
#   header 0x18 + 4*2 offset table = tracks at 32,35,37,40
#   t0 (32,3): 60 0C 90  note+EndBar   t1 (35,2): D2 02  STUB (no EndBar)
#   t2 (37,3): 60 0C 90  note+EndBar   t3 (40,3): 60 0C 90
func _make_cross_pair_bank():
	var blob := PackedByteArray()
	blob.append_array("feds".to_ascii_buffer())
	blob.append_array([43, 0, 0, 0])                   # data_size
	blob.append_array([3, 0])                          # pair_count_plus1 (2 pairs)
	blob.append_array([7, 0])
	blob.append_array([32, 0, 0, 0])                   # data_offset
	blob.append_array([0, 0, 0, 0, 0, 0, 0, 0])
	blob.append_array([32, 0, 35, 0, 37, 0, 40, 0])    # 0x18 offset table (4 tracks)
	blob.append_array([0x60, 0x0C, 0x90])              # t0 @32
	blob.append_array([0xD2, 0x02])                    # t1 @35 (stub)
	blob.append_array([0x60, 0x0C, 0x90])              # t2 @37
	blob.append_array([0x60, 0x0C, 0x90])              # t3 @40
	return FedsBankScript.parse(blob)


func _test_flow_through_span_decodes_stub_into_next_track() -> void:
	var bank = _make_e317_bank()
	var span: Dictionary = PairModel.flow_through_span(bank, 0)
	_assert_eq(span.is_empty(), false, "track A is a stub → flow-through span present")
	if span.is_empty():
		return
	# Own-vs-flowed boundary is the next track's offset (30). Only the D2 is own.
	_assert_eq(int(span.get("own_boundary_offset")), 30, "own bytes end at track B's offset")
	_assert_eq(int(span.get("into_track")), 1, "stub A flows into track B (idx 1)")
	_assert_eq(bool(span.get("crosses_pair")), false, "the flow stays inside pair 0")
	var cmds: Array = span.get("commands", [])
	var own: Array = []
	var flowed_labels: Array = []
	for c in cmds:
		if bool(c.get("flowed")):
			flowed_labels.append(str(c.get("label")))
		else:
			own.append([str(c.get("label")), int(c.get("offset"))])
	_assert_eq(own, [["PitchBendRel", 28]], "the only OWN command is the D2 at @28")
	# The flow decoded PAST both decoy 0x90 param bytes to the real EndBar @44.
	_assert_eq(int(span.get("end_bar_offset")), 44, "flow stops at the FIRST DECODED EndBar (@44), not a 0x90 param")
	_assert_true(flowed_labels.has("Fermata"),
			"the Fermata AFTER the first decoy 0x90 decoded → the decoy was not a terminator")
	# The borrowed note carries the state the voice accumulated walking B's bytes.
	var notes: Array = span.get("notes", [])
	_assert_eq(notes.size(), 1, "one borrowed note (track B's C3)")
	if notes.size() == 1:
		var n: Dictionary = notes[0]
		_assert_eq(bool(n.get("flowed")), true, "the C3 is borrowed, not authored on A")
		_assert_eq(str(n.get("label")), "C3", "borrowed note is C at B's octave 3")
		_assert_eq(int(n.get("active_instrument")), 10, "borrowed note carries B's instrument #10")
		_assert_eq(int(n.get("offset")), 37, "borrowed note offset blob-absolute (30+7)")
	# The '+2 detune' the source tell reports comes from the stub's own PitchBendRel.
	_assert_eq(int(span.get("own_pitch_bend_total")), 2, "own PitchBendRel totals +2 (the detune tell)")


func _test_flow_through_absent_for_sounding_track() -> void:
	# Track B ends in an EndBar → not a stub → no flow-through, empty span.
	var span: Dictionary = PairModel.flow_through_span(_make_e317_bank(), 1)
	_assert_eq(span.is_empty(), true, "a track with an EndBar borrows nothing")


func _test_flow_through_field_rides_the_stub_track_view() -> void:
	var view: Dictionary = PairModel.pair_view(_make_e317_bank(), 0, {}, null)
	var tracks: Array = view.get("tracks", [])
	if tracks.size() != 2:
		_assert_true(false, "expected 2 tracks")
		return
	_assert_eq((tracks[0] as Dictionary).get("flow_through", {}).is_empty(), false,
			"the stub track view carries its flow_through span")
	_assert_eq((tracks[1] as Dictionary).get("flow_through", {}).is_empty(), true,
			"the sounding track view has no flow_through span")
	# The authored (bounded) track view is UNCHANGED — track A still shows only its D2.
	var a_cmds: Array = (tracks[0] as Dictionary).get("commands", [])
	_assert_eq(a_cmds.size(), 1, "authored track A still decodes only its own 1 command (no regression)")


func _test_flow_through_crosses_pair_is_flagged() -> void:
	# pair-0 track B (idx 1) is a stub; its flow walks into pair 1 → crosses_pair.
	var span: Dictionary = PairModel.flow_through_span(_make_cross_pair_bank(), 1)
	_assert_eq(span.is_empty(), false, "the pair-0 track-B stub has a flow-through span")
	if span.is_empty():
		return
	_assert_eq(bool(span.get("crosses_pair")), true, "the flow walks past pair 0 into pair 1")
	_assert_eq(int(span.get("into_track")), 2, "it flows into pair 1's track A (idx 2)")


## A NULL SLOT: a pair whose track B offset is 0. The feds header + offset table
## occupy the blob's first bytes, so offset 0 can never be bytecode — the slot is
## an UNUSED track, not music. Ten corpus effects carry one (always a pair's track
## B: E097/E185/E332/E336/E376/E382 pair 1, E343 pair 2, E248/E249 pair 3, E089
## pair 5 — that last one mid-table, so it is not trailing padding).
func _make_null_slot_bank():
	var blob := PackedByteArray()
	blob.append_array("feds".to_ascii_buffer())
	blob.append_array([31, 0, 0, 0])                   # data_size (28 + 3)
	blob.append_array([2, 0])                          # pair_count_plus1 (1 pair)
	blob.append_array([7, 0])
	blob.append_array([28, 0, 0, 0])                   # data_offset
	blob.append_array([0, 0, 0, 0, 0, 0, 0, 0])
	blob.append_array([28, 0, 0, 0])                   # offset table: t0 @28, t1 @0 (NULL)
	blob.append_array([0x60, 0x0C, 0x90])              # track A @28 — Note C (dur12), EndBar
	return FedsBankScript.parse(blob)


func _test_null_slot_is_not_a_stub() -> void:
	var view: Dictionary = PairModel.pair_view(_make_null_slot_bank(), 0, {}, null)
	var b: Dictionary = (view.get("tracks", []) as Array)[1]
	_assert_true(bool(b.get("null_track", false)), "an offset-0 slot is marked null_track")
	_assert_false(bool(b.get("stub", false)),
			"a null slot is NOT a stub — it has no bytes, not a missing EndBar")
	_assert_false(b.has("flow_through"),
			"a null slot borrows nothing (no flow_through field)")
	_assert_eq((b.get("notes", []) as Array).size(), 0,
			"a null slot decodes no notes (the header is never bytecode)")
	_assert_false(bool(((view.get("tracks", []) as Array)[0] as Dictionary) \
			.get("null_track", false)), "a real track is not null")


func _test_flow_through_span_refuses_a_null_slot() -> void:
	_assert_eq(PairModel.flow_through_span(_make_null_slot_bank(), 1), {},
			"flow_through_span refuses a null slot rather than decoding the header")


func _test_pair_pips_ignore_a_null_slot() -> void:
	var GP = load("res://src/effects/studio/SoundGhostProjector.gd")
	_assert_eq(GP.pair_pips(_make_null_slot_bank(), 0), [0],
			"only track A's onset — the null slot contributes no pips")


## A stub track's borrowed span reads as a PHANTOM `NoEnd` — a derived span with no
## byte behind it — on the FLOW lane, folded by default, unrolling in place exactly
## like a loop (ADR-0085 2026-08-18). `structure` stays authored bytes only.
func _test_stub_lane_carries_a_folded_noend_phantom() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var view: Dictionary = PairModel.pair_view(_make_leading_rest_stub_bank(), 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 700.0, {})
	# Track A authors ONE Rest — no loops, no structure byte. The phantom is what
	# pulls a Flow lane into existence.
	var kinds: Array = []
	for lane in lay.get("lanes", []):
		if int(lane.get("track")) == 0:
			kinds.append(str(lane.get("kind")))
	_assert_true("flow" in kinds, "the NoEnd phantom forces a Flow lane onto the stub")
	_assert_false("structure" in kinds,
			"…and never onto the structure lane — that lane is authored bytes only")
	var ph: Dictionary = {}
	for br in lay.get("brackets", []):
		if bool(br.get("phantom", false)):
			ph = br
	_assert_false(ph.is_empty(), "the stub draws a NoEnd phantom bracket")
	if ph.is_empty():
		return
	_assert_eq(int(ph.get("track", -1)), 0, "…on the stub's own track")
	_assert_eq(int(ph.get("loop_index", 0)), -1,
			"…keyed -1, so it shares the loop's fold verb and hit-test route")
	_assert_false(bool(ph.get("unwound", true)), "folded by default, like a loop")
	_assert_true("▸" in str(ph.get("badge", "")), "the badge reads folded")
	_assert_true("B" in str(ph.get("badge", "")), "…and names where the voice runs on")
	_assert_true(float(ph.get("x1", 0.0)) > float(ph.get("x0", 0.0)),
			"the COLLAPSED bracket already spans the real borrowed envelope")
	var borrowed := 0
	for bar in lay.get("span_bars", []):
		if bool(bar.get("flowed", false)):
			borrowed += 1
	_assert_eq(borrowed, 0, "folded, the borrowed notes stay hidden (content, not time)")


## Unfolding reveals the borrowed notes ON THE STUB'S OWN LANES, flagged `flowed` —
## a second, independent axis from `ghost` (an unrolled copy). Track B's C3 is
## borrowed by voice A 12 ticks later, so it lands to the RIGHT of B's own bar.
func _test_unfolding_the_noend_reveals_borrowed_notes() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var view: Dictionary = PairModel.pair_view(_make_leading_rest_stub_bank(), 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 700.0, {"unwound": {"0:noend": true}})
	var ph: Dictionary = {}
	for br in lay.get("brackets", []):
		if bool(br.get("phantom", false)):
			ph = br
	_assert_true("▾" in str(ph.get("badge", "")), "the unfolded badge flips its glyph")
	var borrowed: Array = []
	var own: Array = []
	for bar in lay.get("span_bars", []):
		if bool(bar.get("flowed", false)):
			borrowed.append(bar)
		else:
			own.append(bar)
	_assert_eq(borrowed.size(), 1, "the one borrowed note appears")
	# Track A's own authored byte is a `0x80 Rest 12`, which under ADR-0085
	# 2026-08-18c is a REST SPAN drawn grey on its time lane — not an empty lane and
	# not a chip. So the pair's own spans are that rest plus track B's note.
	_assert_eq(own.size(), 2, "the stub's own leading Rest is a span, alongside track B's note")
	var own_rests: Array = []
	for b in own:
		if bool(b.get("rest", false)):
			own_rests.append(b)
	_assert_eq(own_rests.size(), 1, "…and exactly one of them is that rest")
	if own_rests.size() == 1:
		_assert_eq(int(own_rests[0].get("track", -1)), 0, "the rest span is the STUB's")
		_assert_eq(str(own_rests[0].get("label", "")), "Rest", "a rest span says so")
		_assert_false(own_rests[0].has("fermata_rect"), "silence has no interior to split")
	own = own.filter(func(b): return not bool(b.get("rest", false)))
	if borrowed.size() != 1 or own.size() != 1:
		return
	_assert_eq(int(borrowed[0].get("track", -1)), 0, "…drawn on the STUB's lane")
	_assert_false(bool(borrowed[0].get("ghost", true)),
			"borrowed is not the same claim as ghost (a loop copy) — flags are independent")
	_assert_eq(int(borrowed[0].get("owner_track", -1)), 1,
			"…and it knows its bytes live in track B")
	_assert_eq(int(borrowed[0].get("owner_event_index", -1)), 0,
			"…at track B's OWN event index (identity is the blob offset, not the walk)")
	_assert_true((borrowed[0].get("rect") as Rect2).position.x \
			> (own[0].get("rect") as Rect2).position.x,
			"the borrowed copy sounds LATER — the stub's 12-tick lead-in shifts it right")
	# Lane taxonomy follows the content: the borrowed note lands on the time lane the
	# track's own Rest already pulled in.
	var kinds: Array = []
	for lane in lay.get("lanes", []):
		if int(lane.get("track")) == 0:
			kinds.append(str(lane.get("kind")))
	_assert_true("time" in kinds, "borrowed notes pull in the Time lane they need")


## Click a borrowed note and the selection lands on its OWNER's event — you edit a
## byte where it LIVES, never where it is heard. Same law the panel already applies
## to an unrolled loop copy, extended across tracks.
func _test_borrowed_note_click_selects_its_owner() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var view: Dictionary = PairModel.pair_view(_make_leading_rest_stub_bank(), 0, {}, null)
	var panel = Panel.new()
	panel.size = Vector2(700.0, 400.0)
	panel.set_view(view)
	_assert_true(panel.is_loop_unwound(0, -1),
			"the pair OPENS with the NoEnd phantom unfolded (2026-08-19d)")
	var lay: Dictionary = Panel.layout(view, 700.0, {"unwound": {"0:noend": true}})
	var rect := Rect2()
	for bar in lay.get("span_bars", []):
		if bool(bar.get("flowed", false)):
			rect = bar.get("rect")
	_assert_eq(panel.hit_test(rect.get_center()),
			{"kind": "select", "track": 1, "event_index": 0},
			"a borrowed note routes the click to track B's authored event")
	panel.free()


## The header's unwind-all means "show me everything this pair actually does" — after
## this work the borrowed span IS the part the bytes do not show, so it joins.
func _test_noend_phantom_joins_unwind_all() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var view: Dictionary = PairModel.pair_view(_make_leading_rest_stub_bank(), 0, {}, null)
	var panel = Panel.new()
	panel.size = Vector2(700.0, 400.0)
	panel.set_view(view)
	panel.set_all_unwound(true)
	_assert_true(panel.is_loop_unwound(0, -1), "unwind-all unfolds the NoEnd phantom too")
	_assert_true(bool((Panel.layout(view, 700.0, {"unwound": {"0:noend": true}}) \
			.get("header", {}) as Dictionary).get("all_unwound", false)),
			"…and the header badge reads fully unwound with only the phantom open")
	panel.set_all_unwound(false)
	_assert_false(panel.is_loop_unwound(0, -1), "…and folds it back")
	panel.free()


## A stub with its own PitchBendRel: the source tell names WHERE the voice runs on
## and WHAT its own bytes do to the borrowed notes. Always visible on the section
## header — the condition is never hidden behind the fold.
func _make_detuned_stub_bank():
	var blob := PackedByteArray()
	blob.append_array("feds".to_ascii_buffer())
	blob.append_array([35, 0, 0, 0])                   # data_size (28 + 4 + 3)
	blob.append_array([2, 0])                          # pair_count_plus1 (1 pair)
	blob.append_array([7, 0])
	blob.append_array([28, 0, 0, 0])                   # data_offset
	blob.append_array([0, 0, 0, 0, 0, 0, 0, 0])
	blob.append_array([28, 0, 32, 0])                  # offset table
	blob.append_array([0xD2, 0x02, 0x80, 0x0C])        # track A @28 — PitchBendRel +2, Rest, STUB
	blob.append_array([0x60, 0x0C, 0x90])              # track B @32 — Note C, EndBar
	return FedsBankScript.parse(blob)


func _test_stub_section_tell_names_what_it_borrows() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var view: Dictionary = PairModel.pair_view(_make_detuned_stub_bank(), 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 700.0, {})
	var label := str((lay.get("sections", []) as Array)[0].get("label", ""))
	_assert_true("borrows Track B" in label, "the tell names the track it runs on into")
	_assert_true("PitchBendRel +2 detunes" in label,
			"…and what the stub's own bytes do to the borrowed notes")
	var sounding := str((lay.get("sections", []) as Array)[1].get("label", ""))
	_assert_false("borrows" in sounding, "a sounding track borrows nothing and says nothing")


func _test_pair_view_provenance_names_referencing_containers() -> void:
	# Container 0 (mode 0 → always id_a=1 → pair 0) referenced by one firing trigger.
	var containers := {"containers": [
		{"index": 0, "mode": 0, "id_a": 1, "id_b": 0, "id_c": 0}]}
	var effect_sound := {"phase1": [
		{"channel_index": 0, "max_keyframe": 1,
			"keyframes": [{"sound_id": 2, "duration_frames": 10}]}]}
	var view: Dictionary = PairModel.pair_view(_make_bank(), 0, containers, effect_sound)
	var used: Array = view.get("used_by_containers", [])
	_assert_eq(used.size(), 1, "pair 0 is used by 1 container")
	if used.size() == 1:
		_assert_eq(int(used[0].get("index")), 0, "referencing container index")
		_assert_eq(int(used[0].get("used_by")), 1, "container's firing trigger count")
	# An unreferenced pair reports no users (honesty, not an error).
	var lone: Dictionary = PairModel.pair_view(_make_bank(), 0, {"containers": [
		{"index": 0, "mode": 0, "id_a": 9, "id_b": 0, "id_c": 0}]}, effect_sound)
	_assert_eq((lone.get("used_by_containers", []) as Array).size(), 0,
			"container pointing elsewhere is not provenance")


func _test_pair_view_out_of_range_is_inert() -> void:
	var view: Dictionary = PairModel.pair_view(_make_bank(), 5, {}, null)
	_assert_eq(bool(view.get("valid")), false, "out-of-range pair is invalid, not a crash")
	_assert_eq((view.get("tracks", []) as Array).size(), 0, "no lanes for an invalid pair")
	var null_view: Dictionary = PairModel.pair_view(null, 0, {}, null)
	_assert_eq(bool(null_view.get("valid")), false, "null bank is inert")


# --- Target kind + registry (ADR-0073: reached by following the reference) --

func _test_pair_target_kind_is_registered() -> void:
	var t := Target.pair(3)
	_assert_eq(t, {"kind": "pair", "ref": {"pair_idx": 3}}, "pair target shape")
	_assert_eq(Target.title(t), "FEDS pair 3", "pair inspector title")
	_assert_eq(Target.label(t), "pair 3", "pair breadcrumb label")
	_assert_true(Registry.has_kind("pair"), "registry knows the pair kind")
	_assert_true(Registry.is_built("pair"), "pair kind is built, not a seam")
	_assert_true(Registry.projector_for("pair") != null, "pair projector resolves")


## The container's Sound slots resolve into FEDS pairs; the drill-in is a `link`
## cell whose target is the pair (following the reference, like trigger→container).
func _test_container_sections_link_to_referenced_pairs() -> void:
	var containers := {"containers": [
		{"index": 0, "mode": 0, "id_a": 1, "id_b": 0, "id_c": 0}]}
	var view := ContainerModel.container_view(containers, _make_bank(), null, 0)
	var score := {"sound_containers": [view]}
	var secs: Array = ContainerProjector.sections(Target.container(0), null, score)
	var pair_links: Array = []
	for sec in secs:
		for f in sec.get("fields", []):
			if str(f.get("shape", "")) == "link" and str(f.get("target", {}).get("kind", "")) == "pair":
				pair_links.append(f.get("target"))
	_assert_eq(pair_links, [Target.pair(0)], "container links to its referenced pair")


# --- Pair projector: THIN reader over score["feds_pairs"] -------------------

func _pair_score() -> Dictionary:
	var containers := {"containers": [
		{"index": 0, "mode": 0, "id_a": 1, "id_b": 0, "id_c": 0}]}
	var effect_sound := {"phase1": [
		{"channel_index": 0, "max_keyframe": 1,
			"keyframes": [{"sound_id": 2, "duration_frames": 10}]}]}
	var view := PairModel.pair_view(_make_bank(), 0, containers, effect_sound)
	return {"feds_pairs": [view]}


func _test_pair_projector_header_leads_with_provenance() -> void:
	var rows: Array = PairProjector.header(Target.pair(0), null, _pair_score())
	_assert_true(rows.size() >= 2, "header has identity + provenance rows")
	if rows.size() < 2:
		return
	_assert_eq(str(rows[0].get("label")), "Pair", "header leads with pair identity")
	# Provenance: a link row back to the referencing container (the blast radius).
	var container_links: Array = []
	for r in rows:
		var link: Dictionary = r.get("link", {})
		if str(link.get("target", {}).get("kind", "")) == "container":
			container_links.append(link["target"])
	_assert_eq(container_links, [Target.container(0)],
			"provenance links back to the referencing container")
	# Out-of-range target is inert.
	_assert_eq(PairProjector.header(Target.pair(9), null, _pair_score()), [],
			"missing pair view renders empty, not a crash")


## Event-scoped inspector (the panel IS the listing): with no selection the pair
## renders ONLY the overview; a `selected` annotation on the view scopes a single
## Event section to that event's cells — no per-track event dump, so the grid's
## 2-up wrap can never garble the byte order again.
func _test_pair_projector_sections_render_track_lanes() -> void:
	var score := _pair_score()
	var secs: Array = PairProjector.sections(Target.pair(0), null, score)
	_assert_eq(secs.size(), 1, "no selection → overview only (the panel is the listing)")
	if secs.size() >= 1:
		_assert_eq(str(secs[0].get("title")), "Pair", "overview section first")

	# Selecting the note (event_index 3 in the fixture stream) scopes an Event section.
	var view: Dictionary = score["feds_pairs"][0]
	view["selected"] = {"track": 0, "event_index": 3}
	var sel_secs: Array = PairProjector.sections(Target.pair(0), null, score)
	_assert_eq(sel_secs.size(), 2, "selection → event section + overview")
	if sel_secs.size() == 2:
		_assert_true(str(sel_secs[0].get("title", "")).begins_with("Event"),
				"the Event section LEADS (the clicked event's cells are visible " +
				"even when the inspector band is short)")
		_assert_true("Track A" in str(sel_secs[0].get("title", "")),
				"event title names its track")
		var names: Array = []
		for f in sel_secs[0].get("fields", []):
			names.append(str(f.get("name", "")))
		_assert_true(names.has("Note velocity") and names.has("Note key"),
				"the note's edit cells render in the Event section")

	# A structure chip stays const (placement is the deferred compile path).
	view["selected"] = {"track": 0, "event_index": 7}   # EndBar
	var end_secs: Array = PairProjector.sections(Target.pair(0), null, score)
	_assert_eq(end_secs.size(), 2, "structure selection still scopes an Event section")
	if end_secs.size() == 2:
		var f0: Dictionary = (end_secs[0].get("fields", []) as Array)[0]
		_assert_eq(str(f0.get("shape", "")), "const", "EndBar placement stays read-only")

	# A stale selection (event gone after a reshape) degrades to overview-only.
	view["selected"] = {"track": 0, "event_index": 99}
	_assert_eq(PairProjector.sections(Target.pair(0), null, score).size(), 1,
			"stale selection is inert (overview only)")
	view.erase("selected")


## Collect [name → field] for one section.
func _fields_by_name(sec: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for f in sec.get("fields", []):
		out[str(f.get("name", ""))] = f
	return out


## Annotate `score`'s pair view with a selection and return the Event section's
## fields by name ({} when no event section renders). The Event section leads.
func _select_event(score: Dictionary, track: int, event_index: int) -> Dictionary:
	var view: Dictionary = score["feds_pairs"][0]
	view["selected"] = {"track": track, "event_index": event_index}
	var secs: Array = PairProjector.sections(Target.pair(0), null, score)
	if secs.size() < 2 or not str(secs[0].get("title", "")).begins_with("Event"):
		return {}
	return _fields_by_name(secs[0])


## Ring 1: every parameterized opcode's param bytes are `int` edit cells with the
## blob-absolute byte address (Instrument @29, Repeat count @37 in the synthetic
## bank), reached by SELECTING the event (the panel is the listing).
func _test_ring1_opcode_params_are_int_cells() -> void:
	var score := _pair_score()
	var by_name := _select_event(score, 0, 0)   # Instrument
	var instr: Dictionary = by_name.get("Instrument", {})
	_assert_eq(str(instr.get("shape", "")), "edit", "Instrument param is editable")
	_assert_eq(int(instr.get("value", -1)), 5, "seeded to the raw param")
	_assert_eq(instr.get("field_ref"), {"channel": "sound_def", "kind": "byte",
			"offset": 29, "pair_idx": 0}, "field_ref addresses the param byte")
	var rep: Dictionary = _select_event(score, 0, 4).get("Play count", {})   # Repeat(3)
	_assert_eq(str(rep.get("shape", "")), "edit", "Repeat COUNT is ring-1 editable")
	_assert_eq(int(rep.get("value", -1)), 3, "Repeat count seeded")
	_assert_eq(int(rep.get("field_ref", {}).get("offset", -1)), 37, "Repeat count byte address")


# Track A at 28 = D3 FF FE 90 (PitchBend_Add_16bit −2, EndBar); track B at 32 = D2 08.
func _make_d3_bank():
	var blob := PackedByteArray()
	blob.append_array("feds".to_ascii_buffer())
	blob.append_array([34, 0, 0, 0])
	blob.append_array([2, 0])
	blob.append_array([7, 0])
	blob.append_array([28, 0, 0, 0])
	blob.append_array([0, 0, 0, 0, 0, 0, 0, 0])
	blob.append_array([28, 0, 32, 0])
	blob.append_array([0xD3, 0xFF, 0xFE, 0x90])
	blob.append_array([0xD2, 0x08])
	return FedsBankScript.parse(blob)


func _pitchbend16_score() -> Dictionary:
	return {"feds_pairs": [PairModel.pair_view(_make_d3_bank(), 0, {}, null)]}


## 0xD3 PitchBend_Add_16bit is a genuine 16-bit value (high<<8|low) — the purest case
## of the byte-thinking the author objects to. It projects as ONE signed s16 word cell
## (not two byte cells), fanning the whole word through the atomic "s16" write
## addressing the high byte (ADR-0085 §3).
func _test_pitchbend16_is_a_single_signed_word_cell() -> void:
	var by_name := _select_event(_pitchbend16_score(), 0, 0)
	_assert_eq(by_name.size(), 1, "0xD3 projects a single cell, not two 'p' bytes")
	if by_name.is_empty():
		return
	var w: Dictionary = by_name.values()[0]
	_assert_eq(str(w.get("editor", "")), "int", "the word is an int cell")
	_assert_eq(str(w.get("type", "")), "s16", "typed as a signed 16-bit word")
	_assert_eq(int(w.get("value", 0)), -2, "0xFF 0xFE seeds as −2 (high<<8|low, signed)")
	_assert_eq(w.get("field_ref"), {"channel": "sound_def", "kind": "s16",
			"offset": 29, "pair_idx": 0}, "one atomic s16 write addressing the high byte")


## Ring 2 (table-form note): velocity is its own byte (capped at 127 — 0x80+ would
## BECOME an opcode); key and duration share the data byte via the note_key /
## note_delta_idx sub-field kinds; duration is an enum over the 18 storable values.
func _test_ring2_note_cells_share_the_data_byte() -> void:
	var by_name := _select_event(_pair_score(), 0, 3)   # the note event
	var vel: Dictionary = by_name.get("Note velocity", {})
	_assert_eq(str(vel.get("editor", "")), "int", "velocity int cell")
	_assert_eq(int(vel.get("value", -1)), 0x60, "velocity seeded")
	_assert_eq(int(vel.get("max", -1)), 127, "velocity capped at 127 (same-size guarantee)")
	_assert_eq(vel.get("field_ref"), {"channel": "sound_def", "kind": "byte",
			"offset": 34, "pair_idx": 0}, "velocity addresses the note's first byte")
	var key: Dictionary = by_name.get("Note key", {})
	_assert_eq(str(key.get("editor", "")), "enum", "key enum cell")
	_assert_eq(int(key.get("value", -1)), 0, "key seeded (C)")
	_assert_eq((key.get("choices", []) as Array).size(), 12,
			"the twelve keys C..B and nothing else — the tie and the note-form rest are "
			+ "forms FFT writes zero of, so the studio READS them and never offers them")
	_assert_eq(key.get("field_ref"), {"channel": "sound_def", "kind": "note_key",
			"offset": 35, "pair_idx": 0}, "key addresses the shared data byte")
	# Duration is a TELL, not a cell (2026-08-19 §6): changing a span's length is the one
	# verb that moves the track's clock, and 18c §7 parks its encoding. It shipped as a
	# bounded enum, which made the parked verb reachable through a costume.
	var dur: Dictionary = by_name.get("Note duration", {})
	_assert_eq(str(dur.get("shape", "")), "const", "duration is read-only until the length verb exists")
	_assert_true(str(dur.get("value", "")).contains("12 ticks"),
			"…and still SHOWS what it is: %s" % str(dur.get("value", "")))
	_assert_false(dur.has("field_ref"), "a tell addresses nothing — there is no byte to write")


# Second fixture: track A = BA (ReverbOn) | 60 00 2A (explicit-form note, dur 42) | 90,
# track B = D2 08 stub. Offsets: table at 0x18, track A at 28, track B at 33.
func _make_toggle_bank():
	var blob := PackedByteArray()
	blob.append_array("feds".to_ascii_buffer())
	blob.append_array([35, 0, 0, 0])
	blob.append_array([2, 0])
	blob.append_array([7, 0])
	blob.append_array([28, 0, 0, 0])
	blob.append_array([0, 0, 0, 0, 0, 0, 0, 0])
	blob.append_array([28, 0, 33, 0])
	blob.append_array([0xBA, 0x60, 0x00, 0x2A, 0x90])
	blob.append_array([0xD2, 0x08])
	return FedsBankScript.parse(blob)


func _toggle_score() -> Dictionary:
	return {"feds_pairs": [PairModel.pair_view(_make_toggle_bank(), 0, {}, null)]}


## Ring 2 (explicit-byte form): the duration is its OWN byte — and closed for the same
## reason the table form is (2026-08-19 §6). This form was the WIDER back door: a free
## 0-255 int with no snap at all, re-timing the track by any amount.
func _test_ring2_explicit_form_note_shows_its_own_byte_read_only() -> void:
	var by_name := _select_event(_toggle_score(), 0, 1)   # the explicit-form note
	var dur: Dictionary = by_name.get("Note duration", {})
	_assert_eq(str(dur.get("shape", "")), "const", "the explicit form is a tell too")
	_assert_true(str(dur.get("value", "")).contains("42 ticks"),
			"…seeded from its own third byte: %s" % str(dur.get("value", "")))
	_assert_false(dur.has("field_ref"), "and it addresses nothing")


## Ring 3: a 0-param paired toggle is an enum over the two same-shape opcodes —
## the VALUE is the opcode byte itself, written at the opcode's offset.
func _test_ring3_toggle_pairs_are_enum_substitutions() -> void:
	var by_name := _select_event(_toggle_score(), 0, 0)   # ReverbOn
	var rev: Dictionary = by_name.get("Reverb", {})
	_assert_eq(str(rev.get("editor", "")), "enum", "toggle renders as an enum")
	_assert_eq(int(rev.get("value", -1)), 0xBA, "seeded to the current opcode byte")
	var vals: Array = []
	for c in rev.get("choices", []):
		vals.append(int(c.get("value", -1)))
	_assert_eq(vals, [0xBA, 0xBB], "choices are exactly the On/Off pair")
	_assert_eq(rev.get("field_ref"), {"channel": "sound_def", "kind": "byte",
			"offset": 28, "pair_idx": 0}, "substitution writes the opcode byte in place")


# --- Ghost pips (ADR-0085): note onsets projected into ghost bars ------------

# Loop fixture: track A = 98 03 (Repeat 3) | 60 05 (note C, 64 ticks) | 99 | 90,
# track B = D2 08 stub (no notes). Unrolled: notes at ticks 0/64/128 → at 120 BPM
# (64 ticks = 2/3 s) and 30 fps → frames 0/20/40.
func _make_loop_bank():
	var blob := PackedByteArray()
	blob.append_array("feds".to_ascii_buffer())
	blob.append_array([36, 0, 0, 0])
	blob.append_array([2, 0])
	blob.append_array([7, 0])
	blob.append_array([28, 0, 0, 0])
	blob.append_array([0, 0, 0, 0, 0, 0, 0, 0])
	blob.append_array([28, 0, 34, 0])
	blob.append_array([0x98, 0x03, 0x60, 0x05, 0x99, 0x90])
	blob.append_array([0xD2, 0x08])
	return FedsBankScript.parse(blob)


func _test_pair_pips_unroll_loops() -> void:
	var GP = load("res://src/effects/studio/SoundGhostProjector.gd")
	var pips: Array = GP.pair_pips(_make_loop_bank(), 0)
	_assert_eq(pips, [0, 20, 40],
			"pips unroll the folded Repeat ×3 (onsets at ticks 0/64/128 → frames 0/20/40)")
	_assert_eq(GP.pair_pips(_make_loop_bank(), 5), [], "out-of-range pair → no pips")
	_assert_eq(GP.pair_pips(null, 0), [], "null bank is inert")


func _test_pair_pips_are_capped() -> void:
	var GP = load("res://src/effects/studio/SoundGhostProjector.gd")
	# Repeat 200: the unroll must not run away — bounded by the pip cap / the
	# 30 s render ceiling, whichever bites first.
	var blob := PackedByteArray()
	blob.append_array("feds".to_ascii_buffer())
	blob.append_array([36, 0, 0, 0])
	blob.append_array([2, 0])
	blob.append_array([7, 0])
	blob.append_array([28, 0, 0, 0])
	blob.append_array([0, 0, 0, 0, 0, 0, 0, 0])
	blob.append_array([28, 0, 34, 0])
	blob.append_array([0x98, 200, 0x60, 0x05, 0x99, 0x90])
	blob.append_array([0xD2, 0x08])
	var pips: Array = GP.pair_pips(FedsBankScript.parse(blob), 0)
	_assert_true(pips.size() > 3 and pips.size() <= 96, "runaway loop unroll is capped")
	for i in range(1, pips.size()):
		_assert_true(int(pips[i]) > int(pips[i - 1]), "pips stay strictly increasing")


# A stub track's pips come from its FLOW-THROUGH span (ADR-0085 2026-08-14), so a
# borrowed onset is a pip too. Track A = `80 0C` (Rest 12), NO EndBar → stub; it flows
# into track B's C3, which — after the stub's 12-tick lead — onsets at tick 12 (= frame
# 4 @120BPM/30fps), DISTINCT from track B's own onset at tick 0 (frame 0). The bounded
# reader would miss it (track A has no note of its own); the flow-through reader lands it.
func _make_leading_rest_stub_bank():
	var blob := PackedByteArray()
	blob.append_array("feds".to_ascii_buffer())
	blob.append_array([33, 0, 0, 0])                   # data_size (28 + 2 + 3)
	blob.append_array([2, 0])                          # pair_count_plus1 (1 pair)
	blob.append_array([7, 0])
	blob.append_array([28, 0, 0, 0])                   # data_offset
	blob.append_array([0, 0, 0, 0, 0, 0, 0, 0])
	blob.append_array([28, 0, 30, 0])                  # offset table
	blob.append_array([0x80, 0x0C])                    # track A @28 — Rest 12, STUB
	blob.append_array([0x60, 0x0C, 0x90])              # track B @30 — Note C (dur12), EndBar
	return FedsBankScript.parse(blob)


func _test_pair_pips_source_stub_from_flow_through() -> void:
	var GP = load("res://src/effects/studio/SoundGhostProjector.gd")
	var pips: Array = GP.pair_pips(_make_leading_rest_stub_bank(), 0)
	# Frame 0 = track B's own C3; frame 4 = the SAME C3 borrowed by voice A, shifted by
	# the stub's 12-tick lead. A bounded-only reader would yield only [0].
	_assert_eq(pips, [0, 4],
			"the stub's borrowed onset (frame 4) joins track B's own onset (frame 0)")


func _test_model_threads_pips_onto_firing_spans() -> void:
	var ed = EffectDataClass.new()
	ed.sound = {"for_each": [{"channel_index": 0, "max_keyframe": 2, "keyframes": [
		{"duration_frames": 10, "sound_id": 2},
		{"duration_frames": 5, "sound_id": 0},
		{"duration_frames": 0, "sound_id": 0}]}]}
	var score: Dictionary = Model.build(ed, {2: 44}, {}, [], [], {2: [0, 20, 40]})
	var spans := _sound_lane_spans(score)
	_assert_true(spans.size() >= 3, "event+event+terminator spans present")
	if spans.size() < 3:
		return
	_assert_eq(spans[0].get("pips"), [0, 20, 40], "firing span carries its pair's pips")
	_assert_eq(spans[1].get("pips", []), [], "silent event carries no pips")
	_assert_eq(spans[2].get("pips", []), [], "terminator carries no pips")


func _sound_lane_spans(score: Dictionary) -> Array:
	for lane in score.get("lanes", []):
		if str(lane.get("kind", "")) == "sound" and not (lane.get("spans", []) as Array).is_empty():
			return lane.get("spans", [])
	return []


## Scope (ADR): pips light up for the pair OPEN in TIER-3 (every ghost resolving
## to it) or for the SELECTED sound trigger's ghost; otherwise none. One-way
## editor→timeline emphasis — the page computes the map from the nav target.
func _test_page_scopes_pips_to_open_pair_or_selected_trigger() -> void:
	var ed = EffectDataClass.new()
	ed.sound_containers = {"containers": [
		{"index": 0, "mode": 0, "id_a": 1, "id_b": 0, "id_c": 0}]}
	ed.sound = {"phase1": [
		{"channel_index": 0, "max_keyframe": 1,
			"keyframes": [{"sound_id": 2, "duration_frames": 10}]}]}
	var page = Page.new()
	page._effect_data = ed
	page._sound_env = {"feds_bank": _make_loop_bank(), "sound_containers": ed.sound_containers}
	page._nav = [Target.pair(0)]
	var by_pair: Dictionary = page._compute_pips()
	_assert_eq(by_pair.get(2), [0, 20, 40], "open pair lights every resolving trigger")
	page._nav = [Target.span("sound:phase1:0#0")]
	var by_span: Dictionary = page._compute_pips()
	_assert_eq(by_span.get(2), [0, 20, 40], "selected sound trigger lights its own ghost")
	page._nav = [Target.container(0)]
	_assert_eq(page._compute_pips(), {}, "no open pair / trigger → no pips")
	page._nav = []
	_assert_eq(page._compute_pips(), {}, "empty nav → no pips")
	page.free()


func _test_timeline_ghost_rects_carry_pips() -> void:
	var Timeline = load("res://src/effects/studio/EffectScoreTimeline.gd")
	var TimelineDataClass = ExMateriaEffects.TimelineData
	var ed = EffectDataClass.new()
	ed.timeline = TimelineDataClass.from_json({
		"header": {"phase1_duration": 8, "phase2_delay": 64}, "particle_channels": []})
	ed.sound = {"for_each": [{"channel_index": 0, "max_keyframe": 1, "keyframes": [
		{"duration_frames": 10, "sound_id": 2}]}]}
	var tl = Timeline.new()
	tl.size = Vector2(900.0, 400.0)
	tl.load_score(Model.build(ed, {2: 44}, {}, [], [], {2: [0, 20, 40]}))
	var found: Array = []
	for g in tl._ghost_rects:
		found = g.get("pips", [])
	_assert_eq(found, [0, 20, 40], "the ghost rect carries its pips for the draw pass")
	tl.free()


## End-to-end wiring: an inspector int widget change lowers the sound_def field_ref
## through the mutate callback with the raw value (the F1 kit stays generic).
func _test_inspector_widget_edit_lowers_sound_def_ref() -> void:
	var score := _pair_score()
	# Dynamics (event 2, param byte @33) — Instrument is a named enum now, so the
	# int-widget lowering is driven through a genuinely-int cell.
	(score["feds_pairs"][0] as Dictionary)["selected"] = {"track": 0, "event_index": 2}
	var secs: Array = PairProjector.sections(Target.pair(0), null, score)
	var Inspector = load("res://src/effects/studio/EffectKeyframeInspector.gd")
	var insp = Inspector.new()
	add_child(insp)
	var mutations: Array = []
	insp.show_target(Target.pair(0), [], secs,
		func(_i): return [], func(_a, _b): pass, func(_t): pass,
		func(_p, _e): return false, func(_p, _e, _s): pass,
		func(ref, raw): mutations.append([ref, raw]),
		func(_refs, _col): return Color.BLACK)
	var ints: Array = insp.int_widgets()
	_assert_true(ints.size() >= 1, "the selected event's int cell renders as a SpinBox")
	if ints.is_empty():
		insp.free()
		return
	ints[0].value = 9   # the Dynamics (Channel volume) param cell
	_assert_eq(mutations.size(), 1, "one widget change → one lowering")
	if mutations.size() == 1:
		_assert_eq(mutations[0][0], {"channel": "sound_def", "kind": "byte",
				"offset": 33, "pair_idx": 0}, "the lowering carries the sound_def address")
		_assert_eq(int(mutations[0][1]), 9, "the raw value rides along")
	insp.free()


## A signed opcode param (the `sb` bytes — PitchBendRel/Detune/AddPitchBend/…) is a
## CELL-LOCAL display transform (ADR-0085 2026-08-12 §2). The decoder hands raw 0-255
## and SoundDefChannel's "byte" kind rejects anything outside 0-255, so a small negative
## bend would read as 254 — a lie. A `type:"s8"` cell SIGN-EXTENDS the seed (254 → −2)
## and MASKS the fanned write (−100 → 156) so the byte writer's 0-255 contract is
## unchanged. Round-trip mirrors the ring-2 velocity round-trip.
func _test_signed_byte_cell_round_trips_display_and_write() -> void:
	var Inspector = load("res://src/effects/studio/EffectKeyframeInspector.gd")
	var insp = Inspector.new()
	add_child(insp)
	var ref := {"channel": "sound_def", "kind": "byte", "offset": 30, "pair_idx": 0}
	var cell := {"name": "Glide amount", "shape": "edit", "editor": "int",
			"type": "s8", "value": 254, "field_ref": ref}
	var mutations: Array = []
	insp.show_target(Target.pair(0), [], [{"title": "Event", "fields": [cell]}],
		func(_i): return [], func(_a, _b): pass, func(_t): pass,
		func(_p, _e): return false, func(_p, _e, _s): pass,
		func(r, raw): mutations.append([r, raw]),
		func(_refs, _col): return Color.BLACK)
	var ints: Array = insp.int_widgets()
	_assert_true(ints.size() == 1, "the signed cell renders one int widget")
	if ints.is_empty():
		insp.free()
		return
	# SEED: raw 254 shows the signed value −2, not the 254 lie; the box spans −128…127.
	_assert_eq(int(ints[0].value), -2, "raw 254 seeds the box as −2")
	_assert_eq(int(ints[0].min_value), -128, "signed byte spans −128")
	_assert_eq(int(ints[0].max_value), 127, "…to +127")
	# FAN: a negative edit MASKS back to a storable byte (−100 → 156), address unchanged.
	ints[0].value = -100
	_assert_eq(mutations.size(), 1, "one edit → one lowering")
	if mutations.size() == 1:
		_assert_eq(mutations[0][0], ref, "the lowering keeps the raw-byte address")
		_assert_eq(int(mutations[0][1]), 156, "−100 masks to byte 156 (0-255 contract intact)")
	# A positive signed value writes itself unchanged.
	ints[0].value = 5
	_assert_eq(int(mutations[1][1]), 5, "a positive signed value writes itself")
	insp.free()


## The empirical usage range (ADR-0085 §4) surfaces on a range-bound int cell as a dim
## inline hint of what shipped effects do — and an out-of-corpus TELL when the value
## leaves that envelope (the honest answer to "is this a lot?"). The tell is live and
## not sticky: it fires when you leave the range and clears when you return.
func _test_range_hint_shows_typical_and_out_of_corpus_tell() -> void:
	var Inspector = load("res://src/effects/studio/EffectKeyframeInspector.gd")
	var insp = Inspector.new()
	add_child(insp)
	var ref := {"channel": "sound_def", "kind": "byte", "offset": 30, "pair_idx": 0}
	var cell := {"name": "Glide rate", "shape": "edit", "editor": "int", "type": "u8",
			"value": 20, "range": {"min": 0, "max": 40, "median": 18, "n": 47}, "field_ref": ref}
	insp.show_target(Target.pair(0), [], [{"title": "Event", "fields": [cell]}],
		func(_i): return [], func(_a, _b): pass, func(_t): pass,
		func(_p, _e): return false, func(_p, _e, _s): pass,
		func(_r, _raw): pass,
		func(_refs, _col): return Color.BLACK)
	var hints: Array = insp.range_hints()
	_assert_eq(hints.size(), 1, "a range-bound cell renders one empirical-range hint")
	if hints.is_empty():
		insp.free()
		return
	var t: String = str(hints[0].text)
	_assert_true("typical" in t and "0" in t and "40" in t, "the hint shows the corpus min…max")
	_assert_true("median 18" in t and "n=47" in t, "…with median and sample count")
	# Typing OUTSIDE the observed envelope fires the out-of-corpus tell.
	var ints: Array = insp.int_widgets()
	ints[0].value = 99
	_assert_true("outside corpus" in str(hints[0].text).to_lower(),
			"leaving the corpus envelope warns")
	# Coming back inside restores the plain typical hint (the tell is not sticky).
	ints[0].value = 10
	_assert_true(not ("outside" in str(hints[0].text).to_lower()), "back in range clears the tell")
	insp.free()
	# A STORED value already beyond the corpus warns on first paint (the seed, not typing).
	var insp2 = Inspector.new()
	add_child(insp2)
	var cell2 := {"name": "Glide rate", "shape": "edit", "editor": "int", "type": "u8",
			"value": 250, "range": {"min": 0, "max": 40, "median": 18, "n": 47}, "field_ref": ref}
	insp2.show_target(Target.pair(0), [], [{"title": "Event", "fields": [cell2]}],
		func(_i): return [], func(_a, _b): pass, func(_t): pass,
		func(_p, _e): return false, func(_p, _e, _s): pass,
		func(_r, _raw): pass,
		func(_refs, _col): return Color.BLACK)
	_assert_true("outside corpus" in str(insp2.range_hints()[0].text).to_lower(),
			"an out-of-corpus stored value warns on first paint")
	insp2.free()


func _test_score_build_threads_pair_views() -> void:
	var data = EffectDataClass.new()
	var views := [{"pair_idx": 0, "valid": true}]
	var score: Dictionary = Model.build(data, {}, {}, [], views)
	_assert_eq(score.get("feds_pairs"), views, "score carries the pre-projected pair views")
	var bare: Dictionary = Model.build(data)
	_assert_eq(bare.get("feds_pairs"), [], "pair views default empty")


## Audition rides the existing on_action seam: ONE pair = one resolved sound id
## (pair_idx + 1), so the button reuses the container's ▶ "audition_sound" action —
## no new host method, and the ghost-queue holdoff comes for free.
func _test_pair_overview_carries_audition_action() -> void:
	var secs: Array = PairProjector.sections(Target.pair(0), null, _pair_score())
	if secs.is_empty():
		_assert_true(false, "sections empty")
		return
	var actions: Array = []
	for f in secs[0].get("fields", []):
		if str(f.get("shape", "")) == "action":
			actions.append(f.get("action"))
	_assert_eq(actions, [
			{"kind": "audition_sound", "id": 1},
			{"kind": "audition_pruned", "pair_idx": 0},
			{"kind": "prune_noops_commit", "pair_idx": 0}],
			"overview carries Audition pair, its no-ops-pruned sibling, AND the real delete")


func _test_page_computes_and_threads_pair_views() -> void:
	var ed = EffectDataClass.new()
	ed.sound_containers = {"containers": [
		{"index": 0, "mode": 0, "id_a": 1, "id_b": 0, "id_c": 0}]}
	ed.sound = {"phase1": [
		{"channel_index": 0, "max_keyframe": 1,
			"keyframes": [{"sound_id": 2, "duration_frames": 10}]}]}
	var page = Page.new()
	page._effect_data = ed
	page._sound_env = {"feds_bank": _make_bank(), "sound_containers": ed.sound_containers}
	var views: Array = page._compute_pair_views()
	_assert_eq(views.size(), 1, "one view per bank pair")
	if views.size() == 1:
		_assert_eq(int(views[0].get("pair_idx")), 0, "view is pair 0")
		_assert_eq((views[0].get("used_by_containers", []) as Array).size(), 1,
				"page-computed view reads the LIVE containers doc for provenance")
	page._pair_views = views
	var score: Dictionary = page._build_score()
	_assert_eq(score.get("feds_pairs"), views, "page threads pair views into the score")
	# No FEDS env → no views (soundless effects stay inert).
	page._sound_env = {}
	_assert_eq(page._compute_pair_views(), [], "no sound env → no pair views")
	page.free()


# --- The page-level lane panel (ADR-0085 2026-08-11 amendment): pure layout ----

## Decision 1 (EffectScoreTimeline idiom: 24px lanes, ~124px gutter, real ruler,
## collapsible per-track sections) + decision 2 (data-driven one-lane-per-kind:
## a note lane per track plus one opcode lane per kind PRESENT — no empty grid)
## + decision 6 (note bar = fixed height, key+velocity as text, width=duration)
## + the retained honesty furniture (provenance header, stub-track badge).
func _test_panel_layout_places_ruler_sections_and_lanes() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var containers := {"containers": [
		{"index": 0, "mode": 0, "id_a": 1, "id_b": 0, "id_c": 0}]}
	var effect_sound := {"phase1": [
		{"channel_index": 0, "max_keyframe": 1,
			"keyframes": [{"sound_id": 2, "duration_frames": 10}]}]}
	var view: Dictionary = PairModel.pair_view(_make_bank(), 0, containers, effect_sound)
	var lay: Dictionary = Panel.layout(view, 700.0, {})

	# Provenance leads (retained honesty furniture).
	_assert_true("container 0 → 1 trigger" in str(lay.get("header", {}).get("text", "")),
			"panel header leads with provenance")

	# Per-track collapsible sections; the stub tell rides track B's section title.
	var sections: Array = lay.get("sections", [])
	_assert_eq(sections.size(), 2, "one collapsible section per track")
	if sections.size() == 2:
		_assert_true(str(sections[0].get("label", "")).begins_with("Track A"),
				"track A section title")
		_assert_true("flows into" in str(sections[1].get("label", "")),
				"track B section title carries the stub flow-through tell")

	# Data-driven lane taxonomy: track A = notes + the kinds present (opcode,
	# structure, loops); track B (stub, one PitchBendRel) = a single opcode lane.
	var kinds_by_track := [[], []]
	for lane in lay.get("lanes", []):
		kinds_by_track[int(lane.get("track"))].append(str(lane.get("kind")))
		_assert_true((lane.get("rect") as Rect2).size.y >= Panel.LANE_H,
				"lane rows are at least the timeline's lane height (rows may grow one)")
	# ADR-0085 2026-08-18c §5: the notes / holds / rests trio is ONE time lane of
	# spans, so Fermata has no lane of its own to sit on — it is the amber half of
	# the bar whose ticks it adds to.
	_assert_eq(kinds_by_track, [["time", "opcode", "structure", "flow"], ["opcode"]],
			"one lane per kind PRESENT, per track — absent kinds draw no lane")

	# The span bar: fixed height, labeled key+velocity, width = the WHOLE span.
	var bars: Array = lay.get("span_bars", [])
	_assert_eq(bars.size(), 1, "one span bar — the note and its Fermata are one span")
	if bars.size() == 1:
		var r: Rect2 = bars[0].get("rect")
		_assert_eq(r.size.y, Panel.NOTE_BAR_H, "span bar height is FIXED (no pitch axis)")
		_assert_true(absf(r.position.x - (Panel.GUTTER_W + Panel.PAD_X)) < 0.01,
				"tick 0 sits at the anchor frame's x (frame 0 under the unbound axis)")
		# Frame axis, now FRACTIONAL (2026-08-21c): the span is 12 + 6 = 18 ticks at
		# 120 BPM = 0.1875 s = 5.625 frames. This assertion used to demand 6.0 and call it
		# "tempo-true" — round() inflated the span 6.7% here, and elsewhere collapsed 314
		# of the corpus's 6439 notes to zero width. 18b drew this bar 4 frames wide and
		# put the missing 2 on another lane.
		_assert_true(absf(r.size.x - 5.625 * Axis.DEFAULT_PPF) < 0.01,
				"the bar spans the note AND its Fermata — its tempo-true frame span")
		# Three fills: blue for the note's own 12 ticks (3.75 frames), amber for the
		# Fermata's 6 (1.875) — neither of which is a whole frame, which is the point.
		var blue: Rect2 = bars[0].get("note_rect")
		var amber: Rect2 = bars[0].get("fermata_rect")
		_assert_true(absf(blue.size.x - 3.75 * Axis.DEFAULT_PPF) < 0.01,
				"the blue fill is the note's own delta_time")
		_assert_true(absf(amber.position.x - blue.end.x) < 0.01,
				"the amber fill is BUTTED against it, not floating on another lane")
		_assert_true(absf(amber.size.x - 1.875 * Axis.DEFAULT_PPF) < 0.01,
				"…and it is exactly the Fermata's sounding time")
		_assert_false(bool(bars[0].get("rest", false)), "a sounding span is not a rest")
		# The label drops the corpus-universal velocity (2026-08-21c): 6262 of 6439 notes
		# are v96, so printing it says nothing while costing ~5 characters on a bar that
		# is often 40 px wide. The KEY always prints; velocity prints only when it is
		# NOT 96 — see _test_span_label_ladder for that half.
		_assert_eq(str(bars[0].get("label", "")), "C4",
				"a v96 note labels its key alone — the constant is not printed")
		_assert_eq(str(bars[0].get("octave", -1)), "4",
				"the bar carries the octave it sounds at, for the fill tint")
		# The bar lands inside track A's TIME lane row.
		var note_lane_rect := Rect2()
		for lane in lay.get("lanes", []):
			if int(lane.get("track")) == 0 and str(lane.get("kind")) == "time":
				note_lane_rect = lane.get("rect")
		_assert_true(note_lane_rect.encloses(r), "span bar rides its time lane row")

	# A real detached ruler band with the tick→seconds tell.
	var ruler: Array = lay.get("ruler", [])
	_assert_true(ruler.size() >= 2, "ruler band has marks")
	if ruler.size() >= 2:
		var last: Dictionary = ruler[ruler.size() - 1]
		# Frame-axis §4: the ×3 loop (body 6 ticks) reserves its 2 extra passes
		# even folded → the axis runs to 18 + 12 = 30 ticks = 0.3125 s.
		_assert_eq(int(last.get("tick")), 30,
				"ruler runs to the pair end tick incl. reserved loop passes")
		_assert_true(absf(float(last.get("seconds")) - 0.3125) < 0.0001,
				"ruler marks carry the seconds tell")

	# Collapsing a track keeps its header but drops its lanes (timeline idiom).
	var collapsed: Dictionary = Panel.layout(view, 700.0, {"collapsed": {0: true}})
	var col_kinds := [[], []]
	for lane in collapsed.get("lanes", []):
		col_kinds[int(lane.get("track"))].append(str(lane.get("kind")))
	_assert_eq(col_kinds, [[], ["opcode"]], "collapsed section drops its lanes")
	_assert_eq((collapsed.get("sections", []) as Array).size(), 2,
			"collapsed section keeps its clickable header")


## Decision 4: the typed chip — a SHORT FIXED-WIDTH code in-lane (every chip the
## same width, killing the tick-0 auto-width overdraw), full name + params on the
## `full` hover payload.
func _test_panel_chips_are_typed_fixed_width() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var view: Dictionary = PairModel.pair_view(_make_bank(), 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 700.0, {})
	var chips: Array = lay.get("chips", [])
	# Seven, not eight: track A's Fermata is folded into its note's span (§5) and
	# draws as the amber half of that bar, so it is no longer a chip of its own.
	_assert_eq(chips.size(), 7, "every command that is not time renders as a chip (A: 6, B: 1)")
	var instr_full := ""
	for chip in chips:
		_assert_eq((chip.get("rect") as Rect2).size.x, Panel.CHIP_W,
				"chip %s is fixed-width" % str(chip.get("code")))
		if (chip.get("rect") as Rect2).size.x != Panel.CHIP_W:
			return
		_assert_true(str(chip.get("code", "")).length() <= 6, "chip code stays short")
		if str(chip.get("full", "")).begins_with("Instrument"):
			instr_full = str(chip.get("full"))
	_assert_true("Instrument(5)" in instr_full and "tick 0" in instr_full,
			"chip carries its full opcode name + params for the hover detail")


# Two-loop fixture: track A = 98 02 | 60 05 | 99 | 98 03 | 60 05 | 99 | 90
#   → L0 = [0,64)×2 (body: note C dur 64), L1 = [64,128)×3 (body: note C dur 64).
# track B = D2 08 stub. Track offsets: A at 28 (10 bytes), B at 38.
func _make_two_loop_bank():
	# Track A is ELEVEN bytes (28..38 inclusive), so track B starts at 39 — with B at
	# 38 the bank truncated A's trailing 0x90 and A silently read as a STUB, which
	# only became visible once a stub started drawing a NoEnd phantom.
	var blob := PackedByteArray()
	blob.append_array("feds".to_ascii_buffer())
	blob.append_array([41, 0, 0, 0])
	blob.append_array([2, 0])
	blob.append_array([7, 0])
	blob.append_array([28, 0, 0, 0])
	blob.append_array([0, 0, 0, 0, 0, 0, 0, 0])
	blob.append_array([28, 0, 39, 0])
	blob.append_array([0x98, 0x02, 0x60, 0x05, 0x99, 0x98, 0x03, 0x60, 0x05, 0x99, 0x90])
	blob.append_array([0xD2, 0x08])
	return FedsBankScript.parse(blob)


## Decision 3, fold half — REFRAMED by the frame-axis amendment §4: folding
## collapses DRAWING, never TIME. A folded ×3 loop still RESERVES its full
## 3-pass extent (the pips are unrolled on the shared axis, so the bracket must
## span its own pips' envelope); only the repeated bodies stay hidden.
func _test_panel_folded_state_hides_bodies_but_keeps_time() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var view: Dictionary = PairModel.pair_view(_make_loop_bank(), 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 700.0, {})
	_assert_eq(int(lay.get("total_ticks")), 192,
			"folded axis still reserves the full N-pass time (64 × 3)")
	_assert_eq((lay.get("span_bars", []) as Array).size(), 1,
			"folded loop draws ONE authored note bar (bodies hidden, time kept)")
	var brackets: Array = lay.get("brackets", [])
	_assert_eq(brackets.size(), 1, "one folded loop bracket")
	if brackets.size() != 1:
		return
	var br: Dictionary = brackets[0]
	_assert_true("×3" in str(br.get("badge", "")), "badge carries the play count")
	_assert_eq(bool(br.get("unwound")), false,
			"an empty fold state draws folded — the PANEL's open state is a separate "
			+ "decision (2026-08-19d), the pure layout still honours whatever it is given")
	_assert_true((br.get("toggle_rect") as Rect2).has_area(),
			"the wind/unwind toggle is a visible click target")
	# The folded bracket spans the pip envelope: 192 ticks = 2 s = 60 frames.
	_assert_true(absf(float(br.get("x1")) - (Panel.GUTTER_W + Panel.PAD_X \
			+ 60.0 * Axis.DEFAULT_PPF)) < 0.01,
			"folded bracket spans its full N-pass frame width (the pip envelope)")
	# Unwinding is a DRAWING change only: the extent does not move.
	var un: Dictionary = Panel.layout(view, 700.0, {"unwound": {"0:0": true}})
	_assert_eq(int(un.get("total_ticks")), int(lay.get("total_ticks")),
			"unwinding never moves the axis extent (drawing-collapse, not time)")
	_assert_eq(int(un.get("end_frame")), int(lay.get("end_frame")),
			"folded and unwound agree on the end frame")


## Decision 3 unwind half + frame-axis §4: BOTH loops always reserve their full
## pass time (L0 ×2 → [0,128) ticks, L1 ×3 → [128,320)); unwinding ONE loop only
## FILLS its reserved span with ghost copies — the sibling stays folded and
## NOTHING moves (drawing-collapse, not time).
func _test_panel_unwind_expands_in_place_per_loop() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var view: Dictionary = PairModel.pair_view(_make_two_loop_bank(), 0, {}, null)
	# Sanity: the fixture decodes to two loops on track A.
	_assert_eq((view.get("tracks", [])[0].get("loops", []) as Array).size(), 2,
			"fixture has two sibling loops")
	# Unwind ONLY the second loop (L1 ×3).
	var lay: Dictionary = Panel.layout(view, 700.0, {"unwound": {"0:1": true}})
	_assert_eq(int(lay.get("total_ticks")), 320,
			"the axis reserves every pass: 128 authored + 64 (L0 ×2) + 128 (L1 ×3)")
	var bars: Array = lay.get("span_bars", [])
	_assert_eq(bars.size(), 4, "×3 fills its span with 3 bars; the folded sibling keeps 1")
	if bars.size() != 4:
		return
	bars.sort_custom(func(a, b): return (a.get("rect") as Rect2).position.x < (b.get("rect") as Rect2).position.x)
	var ghosts: Array = []
	for b in bars:
		ghosts.append(bool(b.get("ghost")))
	_assert_eq(ghosts, [false, false, true, true],
			"authored passes stay solid; the extra passes are ghost copies")
	# Frame axis: 64 ticks = 2/3 s = 20 frames. L0 reserves frames [0,40), so
	# L1's authored pass sits at 40 and its copies march 20-frame strides.
	var xs: Array = []
	for b in bars:
		xs.append(roundf(((b.get("rect") as Rect2).position.x - Panel.GUTTER_W - Panel.PAD_X) \
				/ Axis.DEFAULT_PPF))
	_assert_eq(xs, [0.0, 40.0, 60.0, 80.0], "copies march at body-length strides (frames)")
	# Brackets: L0 folded but still spanning its ×2 envelope; L1 unwound. Track B is a
	# stub (D2 08, no EndBar) but it is the LAST track in the blob, so it borrows
	# NOTHING — and a stub with nothing to borrow draws no NoEnd phantom. Silence
	# here is the honest answer, not a missing feature.
	var brackets: Array = []
	var phantoms: Array = []
	for b in lay.get("brackets", []):
		if bool(b.get("phantom", false)):
			phantoms.append(b)
		else:
			brackets.append(b)
	_assert_eq(phantoms.size(), 0,
			"a stub with no following bytecode borrows nothing → no phantom")
	if brackets.size() == 2:
		_assert_eq(bool(brackets[0].get("unwound")), false, "sibling loop stays folded")
		_assert_true("▾" in str(brackets[1].get("badge", "")), "unwound badge flips its glyph")
		_assert_true(absf(float(brackets[0].get("x1")) - (Panel.GUTTER_W + Panel.PAD_X \
				+ 40.0 * Axis.DEFAULT_PPF)) < 0.01,
				"the folded sibling's bracket still spans its ×2 envelope")
	else:
		_assert_true(false, "expected 2 brackets, got %d" % brackets.size())
	# The structure chips play after EVERY pass: Coda/EndBar at tick 320 = frame 100.
	var last_chip_frame := 0.0
	for chip in lay.get("chips", []):
		if str(chip.get("kind")) == "structure":
			last_chip_frame = maxf(last_chip_frame,
					roundf(((chip.get("rect") as Rect2).position.x - Panel.GUTTER_W - Panel.PAD_X) \
							/ Axis.DEFAULT_PPF))
	_assert_eq(last_chip_frame, 100.0, "downstream structure chips sit past every reserved pass")
	# Fold-invariance: the folded layout keeps every non-body event at the SAME x.
	var folded: Dictionary = Panel.layout(view, 700.0, {})
	_assert_eq(int(folded.get("total_ticks")), 320, "folded layout reserves the same axis")
	_assert_eq((folded.get("span_bars", []) as Array).size(), 2,
			"folded layout draws only the authored bars")
	var folded_last := 0.0
	for chip in folded.get("chips", []):
		if str(chip.get("kind")) == "structure":
			folded_last = maxf(folded_last,
					roundf(((chip.get("rect") as Rect2).position.x - Panel.GUTTER_W - Panel.PAD_X) \
							/ Axis.DEFAULT_PPF))
	_assert_eq(folded_last, last_chip_frame,
			"folding hides bodies but never moves downstream events")


## The unroll REUSES the ghost-pip bounds (MAX_PIPS / the 30 s ceiling): a ×200
## runaway truncates with a visible tell instead of flooding the lane.
func _test_panel_unroll_is_bounded_with_a_tell() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var blob := PackedByteArray()
	blob.append_array("feds".to_ascii_buffer())
	blob.append_array([36, 0, 0, 0])
	blob.append_array([2, 0])
	blob.append_array([7, 0])
	blob.append_array([28, 0, 0, 0])
	blob.append_array([0, 0, 0, 0, 0, 0, 0, 0])
	blob.append_array([28, 0, 34, 0])
	blob.append_array([0x98, 200, 0x60, 0x05, 0x99, 0x90])
	blob.append_array([0xD2, 0x08])
	var view: Dictionary = PairModel.pair_view(FedsBankScript.parse(blob), 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 700.0, {"unwound": {"0:0": true}})
	var bars: Array = lay.get("span_bars", [])
	_assert_true(bars.size() > 3, "the unroll really expands")
	_assert_true(bars.size() <= Panel.MAX_UNROLL_COPIES + 1,
			"runaway unroll is capped by the shared pip budget")
	var br: Dictionary = (lay.get("brackets", []) as Array)[0]
	_assert_eq(bool(br.get("truncated")), true, "the cap is flagged, not silent")
	_assert_true("…" in str(br.get("badge", "")), "the badge carries the truncation tell")


## The tick-0 overdraw cure, frame-axis amendment §5: coincident chips keep their
## TRUE axis-derived x (a pushed chip lies about its tick) and WRAP TO ROWS —
## greedy first-fit in tick/byte order — while the kind-lane grows by
## rows × (CHIP_H + gap) to hold them. Note bars stay single-row.
func _test_panel_coincident_chips_never_overlap() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var view: Dictionary = PairModel.pair_view(_make_bank(), 0, {}, null)
	# Deep zoom (40 px/frame) so only TRUE coincidences share a column — at a
	# coarse zoom near-neighbours wrap too (that's the point of rows).
	var axis = Axis.new()
	axis.configure(Panel.GUTTER_W + Panel.PAD_X, 40.0)
	var lay: Dictionary = Panel.layout(view, 700.0, {}, axis)

	# TRUE x: Instrument/Octave/Dynamics (event_index 0/1/2) all sit at tick 0 —
	# every one keeps the ruler's tick-0 x, none is pushed right off its tick.
	var tick0_x := -1.0
	for m in lay.get("ruler", []):
		if int(m.get("tick", -1)) == 0:
			tick0_x = float(m.get("x"))
	var tick0_chips: Array = []
	for chip in lay.get("chips", []):
		if int(chip.get("track")) == 0 and str(chip.get("kind")) == "opcode" \
				and int(chip.get("event_index")) in [0, 1, 2]:
			tick0_chips.append(chip)
	_assert_eq(tick0_chips.size(), 3, "fixture has 3 coincident tick-0 opcode chips")
	if tick0_chips.size() != 3:
		return
	for chip in tick0_chips:
		_assert_true(absf((chip.get("rect") as Rect2).position.x - tick0_x) < 0.01,
				"chip %s keeps its TRUE tick-0 x (no push-right)" % str(chip.get("code")))

	# Rows: byte order drops them to rows 0/1/2, spaced CHIP_H + gap.
	var ys: Array = []
	for chip in tick0_chips:
		ys.append((chip.get("rect") as Rect2).position.y)
	_assert_true(absf(ys[1] - ys[0] - (Panel.CHIP_H + 2.0)) < 0.01 \
			and absf(ys[2] - ys[1] - (Panel.CHIP_H + 2.0)) < 0.01,
			"coincident chips drop to successive rows (CHIP_H + gap apart)")

	# No two same-lane chips ever intersect — rows, not overdraw.
	var by_lane: Dictionary = {}
	for chip in lay.get("chips", []):
		var key := "%d:%s" % [int(chip.get("track")), str(chip.get("kind"))]
		if not by_lane.has(key):
			by_lane[key] = []
		by_lane[key].append(chip.get("rect"))
	var overlaps := 0
	for key in by_lane:
		var rects: Array = by_lane[key]
		for i in range(rects.size()):
			for j in range(i + 1, rects.size()):
				if (rects[i] as Rect2).intersects(rects[j] as Rect2):
					overlaps += 1
	_assert_eq(overlaps, 0, "same-lane chips never intersect (rows keep them clear)")

	# The kind-lane grows by rows × (CHIP_H+gap); single-row lanes keep LANE_H,
	# and every chip stays inside its own (grown) lane row.
	var lane_h: Dictionary = {}
	var lane_rects: Dictionary = {}
	for lane in lay.get("lanes", []):
		var key := "%d:%s" % [int(lane.get("track")), str(lane.get("kind"))]
		lane_h[key] = (lane.get("rect") as Rect2).size.y
		lane_rects[key] = lane.get("rect")
	_assert_eq(lane_h.get("0:opcode"), Panel.LANE_H + 2.0 * (Panel.CHIP_H + 2.0),
			"3-row opcode lane grows by rows × (CHIP_H+gap)")
	_assert_eq(lane_h.get("0:structure"), Panel.LANE_H + (Panel.CHIP_H + 2.0),
			"Coda+EndBar coincide → the structure lane grows one row")
	_assert_eq(lane_h.get("0:time"), Panel.LANE_H, "single-row lanes keep the lane height")
	for chip in lay.get("chips", []):
		var key := "%d:%s" % [int(chip.get("track")), str(chip.get("kind"))]
		var lr: Rect2 = lane_rects[key]
		var cr: Rect2 = chip.get("rect")
		# Vertical containment only — a chip at the axis's right edge may clip
		# horizontally (the panel scrolls/clips x), but rows never leave the lane.
		_assert_true(cr.position.y >= lr.position.y and cr.end.y <= lr.end.y,
				"chip %s rides inside its lane row" % str(chip.get("code")))

	# Lanes stack without overlapping each other (layout y follows the growth).
	var lanes: Array = lay.get("lanes", [])
	for i in range(1, lanes.size()):
		_assert_true((lanes[i].get("rect") as Rect2).position.y >= \
				(lanes[i - 1].get("rect") as Rect2).end.y,
				"grown lanes push the next lane down, never under")

	# hit_test reads the same layout: a row-1 chip (Octave, event 1) still selects.
	# (The unbound panel lays out on its own default axis — mirror that here.)
	var panel = Panel.new()
	panel.size = Vector2(700.0, 400.0)
	panel.set_view(view)
	var hit_lay: Dictionary = Panel.layout(view, 700.0, {})
	var oct_rect := Rect2()
	for chip in hit_lay.get("chips", []):
		if int(chip.get("event_index")) == 1 and str(chip.get("kind")) == "opcode":
			oct_rect = chip.get("rect")
	_assert_eq(panel.hit_test(oct_rect.get_center()),
			{"kind": "select", "track": 0, "event_index": 1},
			"a wrapped row-1 chip is still its event's click target")
	panel.free()


## ADR-0085 frame-axis amendment §1/§3: the panel PROJECTS onto the timeline's
## shared TimelineAxis — placement is axis.frame_to_x(fire + round(seconds × 30)),
## seconds integrated by the same tempo math the ghost pips use, so panel events
## land ON their pips. Hand numbers (the pip fixture's): 120 BPM, PPQ 48, 30 fps
## → 64 ticks = 2/3 s = 20 frames; axis base 132, 10 px/frame, fire frame 40.
func _test_panel_projects_onto_shared_frame_axis() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var axis = Axis.new()
	axis.configure(Panel.GUTTER_W + Panel.PAD_X, 10.0)
	var view: Dictionary = PairModel.pair_view(_make_loop_bank(), 0, {}, null)
	var state := {"unwound": {"0:0": true}}
	var lay: Dictionary = Panel.layout(view, 700.0, state, axis, {"frame": 40, "source": "first"})

	# Unrolled ×3 note onsets land on the pip frames: fire 40 + 0/20/40.
	var bars: Array = lay.get("span_bars", [])
	_assert_eq(bars.size(), 3, "×3 unroll draws 3 bars")
	if bars.size() == 3:
		bars.sort_custom(func(a, b): return (a.get("rect") as Rect2).position.x < (b.get("rect") as Rect2).position.x)
		var xs: Array = []
		for b in bars:
			xs.append((b.get("rect") as Rect2).position.x)
		_assert_eq(xs, [532.0, 732.0, 932.0], "bars sit at axis.frame_to_x(fire + pip frame)")
		_assert_true(absf((bars[0].get("rect") as Rect2).size.x - 200.0) < 0.01,
				"a 64-tick note spans its 20-frame width at 10 px/frame")

	# The ruler keeps its tick·seconds labels but projects them at axis-derived x:
	# tick 0 sits at the ANCHOR frame's x, not the gutter edge.
	var t0x := -1.0
	for m in lay.get("ruler", []):
		if int(m.get("tick", -1)) == 0:
			t0x = float(m.get("x"))
	_assert_true(absf(t0x - 532.0) < 0.01, "ruler tick 0 projects to the anchor frame's x")

	# Downstream structure chips shift in tempo-true frames: EndBar folded tick 64
	# → unrolled tick 192 = 2 s = frame 60 → x 132 + (40+60)×10.
	var end_x := -1.0
	for chip in lay.get("chips", []):
		if str(chip.get("kind")) == "structure" and str(chip.get("code")) == "End":
			end_x = (chip.get("rect") as Rect2).position.x
	_assert_true(absf(end_x - 1132.0) < 0.01, "downstream chips shift in tempo-true frames")

	# The axis is SHARED state, re-read each layout: panning it re-derives every x.
	axis.scroll_x = 100.0
	var panned: Dictionary = Panel.layout(view, 700.0, state, axis, {"frame": 40, "source": "first"})
	var pxs: Array = []
	for b in panned.get("span_bars", []):
		pxs.append((b.get("rect") as Rect2).position.x)
	pxs.sort()
	_assert_true(not pxs.is_empty() and absf(float(pxs[0]) - 432.0) < 0.01,
			"the panel re-reads the shared axis each layout (pan reflected)")

	# Instance side: binding shares the axis OBJECT, and a zoom gesture on the
	# panel retargets the timeline (the panel is an extension, not a viewport).
	var Timeline = load("res://src/effects/studio/EffectScoreTimeline.gd")
	var tl = Timeline.new()
	var panel = Panel.new()
	panel.size = Vector2(700.0, 300.0)
	panel.set_view(view)
	panel.bind_timeline(tl)
	_assert_true(panel._axis_obj() == tl.axis, "the bound panel reads the timeline's axis object")
	var before_ppf: float = tl.axis.pixels_per_frame
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.ctrl_pressed = true
	wheel.position = Vector2(300.0, 50.0)
	panel._gui_input(wheel)
	_assert_true(tl.axis.pixels_per_frame > before_ppf,
			"ctrl+wheel on the panel zooms the SHARED axis (timeline follows)")
	panel.free()
	tl.free()


## ADR-0085 amendment (2026-08-12): a per-frame orientation GRID on the shared
## axis so a chip can be pegged in time. Lines sit at round frames from frame 0
## (NOT from `fire`) by the same `_ruler_step` spacing FramesBar/the score use, so
## they coincide pixel-for-pixel with EffectScoreTimeline._draw_grid below. Hand
## numbers: ppf 10 → _ruler_step lands on 5 (5×10=50 ≥ 48 px) → a line every 50 px
## from the axis base (GUTTER_W+PAD_X = 132), clipped to [GUTTER_W, width].
func _test_panel_draws_per_frame_orientation_grid() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var axis = Axis.new()
	axis.configure(Panel.GUTTER_W + Panel.PAD_X, 10.0)
	var view: Dictionary = PairModel.pair_view(_make_bank(), 0, {}, null)
	var width := 700.0
	# A non-zero fire frame proves the grid ignores the anchor (absolute frames).
	var lay: Dictionary = Panel.layout(view, width, {}, axis, {"frame": 40, "source": "first"})

	var grid: Array = lay.get("grid", [])
	_assert_true(not grid.is_empty(), "layout returns a per-frame grid")

	# Independent expectation: absolute frames 0,5,10,… whose x ∈ [GUTTER_W, width].
	var expected_x: Array = []
	var f := 0
	while true:
		var x := 132.0 + float(f) * 10.0   # base_x (132) - scroll(0) + frame*ppf
		if x > width:
			break
		if x >= Panel.GUTTER_W:
			expected_x.append(x)
		f += 5
	var got_x: Array = []
	for g in grid:
		got_x.append(float(g.get("x")))
	got_x.sort()
	_assert_eq(got_x, expected_x,
			"grid lines sit at axis.frame_to_x(stepped absolute frame), clipped to the band")

	# Each line's x is the axis projection of its own frame — panel and score both
	# start at frame 0, so the lines coincide.
	for g in grid:
		_assert_true(absf(float(g.get("x")) - axis.frame_to_x(float(g.get("frame")))) < 0.01,
				"grid line x == axis.frame_to_x(frame)")
		_assert_true(float(g.get("x")) >= Panel.GUTTER_W, "no grid line intrudes on the gutter")

	# The tick-quarter ruler marks (the seconds labels) survive — the grid is additive.
	_assert_true((lay.get("ruler", []) as Array).size() >= 2,
			"tick-quarter ruler marks are retained alongside the grid")


## Frame-axis §6: the panel draws the MAIN playhead at axis.frame_to_x(playhead)
## and redraws when it moves. Draw-only at v1 — the panel exposes no seek.
func _test_panel_draws_playhead_from_shared_axis() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var Timeline = load("res://src/effects/studio/EffectScoreTimeline.gd")
	var tl = Timeline.new()
	var panel = Panel.new()
	panel.size = Vector2(700.0, 300.0)
	panel.set_view(PairModel.pair_view(_make_loop_bank(), 0, {}, null))
	panel.bind_timeline(tl)
	tl.set_playhead(20)
	_assert_true(absf(panel._playhead_x() - tl.axis.frame_to_x(20.0)) < 0.01,
			"panel playhead x = the shared axis's frame_to_x(playhead)")
	_assert_true(tl.playhead_changed.is_connected(panel.queue_redraw),
			"playhead moves redraw the panel")
	_assert_true(tl.axis_changed.is_connected(panel._refit),
			"axis changes refit the panel (row-wrap depends on zoom)")
	_assert_true(not panel.has_signal("seek_requested"),
			"no seek surface at v1 (VIEW-only scope)")
	panel.free()
	tl.free()
	# Unbound: no playhead to draw — a sentinel, never a crash.
	var lone = Panel.new()
	_assert_true(lone._playhead_x() < 0.0, "unbound panel has no playhead")
	lone.free()


## Decision 6 routing (the timeline hit-test guard at panel scale): badge →
## wind toggle, section header → collapse, gutter → inert, event → select
## (and a click on a ghost copy selects the AUTHORED event).
func _test_panel_hit_test_routes_toggles_selects_and_inert_gutter() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var panel = Panel.new()
	panel.size = Vector2(700.0, 400.0)
	panel.set_view(PairModel.pair_view(_make_loop_bank(), 0, {}, null))
	var lay: Dictionary = Panel.layout(panel._view, 700.0, panel._state())

	# Badge → toggle_loop; applying it unwinds THAT loop.
	var badge: Rect2 = (lay.get("brackets", []) as Array)[0].get("toggle_rect")
	var hit: Dictionary = panel.hit_test(badge.get_center())
	_assert_eq(hit, {"kind": "toggle_loop", "track": 0, "loop_index": 0},
			"the ×N badge routes to the wind/unwind toggle")
	_assert_eq(panel.is_loop_unwound(0, 0), true, "the pair OPENS unwound (2026-08-19d)")
	panel.toggle_loop(0, 0)
	_assert_eq(panel.is_loop_unwound(0, 0), false, "the badge FOLDS an open loop")
	panel.toggle_loop(0, 0)
	_assert_eq(panel.is_loop_unwound(0, 0), true, "…and unwinds it again — reversible either way")
	# A ghost copy's bar selects the AUTHORED event (same event_index).
	var un_lay: Dictionary = Panel.layout(panel._view, 700.0, panel._state())
	var ghost_bar: Dictionary = {}
	for b in un_lay.get("span_bars", []):
		if bool(b.get("ghost")):
			ghost_bar = b
	_assert_true(not ghost_bar.is_empty(), "unwound layout carries ghost bars")
	if not ghost_bar.is_empty():
		var ghit: Dictionary = panel.hit_test((ghost_bar.get("rect") as Rect2).get_center())
		_assert_eq(ghit, {"kind": "select", "track": 0,
				"event_index": int(ghost_bar.get("event_index"))},
				"a ghost copy selects the authored event")

	# Section header → collapse toggle; gutter lane-label area → inert.
	var sec_rect: Rect2 = (lay.get("sections", []) as Array)[0].get("rect")
	_assert_eq(panel.hit_test(Vector2(10.0, sec_rect.get_center().y)),
			{"kind": "toggle_section", "track": 0}, "section header routes to collapse")
	var lane_rect: Rect2 = (lay.get("lanes", []) as Array)[0].get("rect")
	_assert_eq(panel.hit_test(Vector2(10.0, lane_rect.get_center().y)),
			{"kind": "none"}, "the label gutter is inert (no S/M — decision 7)")

	# A note-bar click SELECTS and emits the route-to-inspector signal.
	var bar_rect: Rect2 = ((lay.get("span_bars", []) as Array)[0].get("rect") as Rect2)
	var selections: Array = []
	panel.event_selected.connect(func(t, ei): selections.append([t, ei]))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = bar_rect.get_center()
	panel._gui_input(press)
	_assert_eq(selections, [[0, 1]], "note-bar click emits event_selected(track, event_index)")
	_assert_eq(panel.selected_event(), {"track": 0, "event_index": 1},
			"the panel highlights the selection")
	panel.free()


## Decision 3 hover-peek + decision 4 hover detail, through the tooltip seam.
func _test_panel_hover_peeks_fold_and_chip_detail() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var panel = Panel.new()
	panel.size = Vector2(700.0, 400.0)
	panel.set_view(PairModel.pair_view(_make_bank(), 0, {}, null))
	var lay: Dictionary = Panel.layout(panel._view, 700.0, panel._state())
	# The folded badge peeks the loop body without committing.
	var badge: Rect2 = (lay.get("brackets", []) as Array)[0].get("toggle_rect")
	var peek: String = panel._get_tooltip(badge.get_center())
	_assert_true("×3" in peek, "hover-peek names the play count")
	_assert_true("Fermata" in peek, "hover-peek lists the folded body's content")
	# A typed chip reveals its full opcode name + params.
	var instr_center := Vector2.ZERO
	for chip in lay.get("chips", []):
		if str(chip.get("full", "")).begins_with("Instrument"):
			instr_center = (chip.get("rect") as Rect2).get_center()
	var tip: String = panel._get_tooltip(instr_center)
	_assert_true("Instrument(5)" in tip, "chip hover reveals the full opcode + params")
	panel.free()


## ADR-0085 2026-08-11 amendment root-cause fix: the pair surface is a PAGE-LEVEL
## panel, so the projector overview must NOT ship a strip field into the reflowing
## inspector grid (the width-unstable cell the rejected micro-strip lived in).
func _test_overview_drops_the_inspector_hosted_strip() -> void:
	var secs: Array = PairProjector.sections(Target.pair(0), null, _pair_score())
	if secs.is_empty():
		_assert_true(false, "sections empty")
		return
	var strip_fields := 0
	for sec in secs:
		for f in sec.get("fields", []):
			if str(f.get("shape", "")) == "strip":
				strip_fields += 1
	_assert_eq(strip_fields, 0, "no inspector-cell strip field survives (page-level panel instead)")


# --- Param semantics: author units, not raw technobabble ---------------------

## The shared corpus table (feds_param_stats.json) is loaded by FedsParamStats and
## is the single source for BOTH the empirical usage range AND per-param signedness
## (ADR-0085 2026-08-12). Literals are the hand-verified corpus truth.
func _test_param_stats_load_the_shared_corpus_table() -> void:
	var Stats = load("res://src/effects/studio/FedsParamStats.gd")
	var d3: Dictionary = Stats.of(0xD3, 0)
	_assert_eq(bool(d3.get("signed", false)), true, "0xD3 word is signed")
	_assert_eq(int(d3.get("bits", 0)), 16, "…16-bit")
	_assert_eq(int(d3.get("n", 0)), 15, "corpus occurrence count for 0xD3")
	_assert_eq(int(d3.get("min", 0)), -759, "signed-space min")
	_assert_eq(int(d3.get("max", 0)), 1536, "signed-space max")
	var d2: Dictionary = Stats.of(0xD2, 0)
	_assert_eq(bool(d2.get("signed", false)), true, "0xD2 PitchBendRel is a signed byte")
	_assert_eq(int(d2.get("bits", 0)), 8, "…8-bit")
	_assert_true(int(d2.get("min", 0)) < 0, "signed byte reports negatives (signed space)")
	var rate: Dictionary = Stats.of(0xD4, 1)   # Portamento_Init rate — unsigned
	_assert_eq(bool(rate.get("signed", true)), false, "an uncurated scalar is unsigned")
	_assert_true(int(rate.get("n", 0)) > 0, "…and still carries a corpus range")
	_assert_eq(Stats.of(0x94, 5), {}, "an absent (opcode, param) is empty")



## The shared unit seam grows a LOOKUP-MAP branch (nonlinear raw↔human, e.g. SPU
## ADSR rate → milliseconds): display = map[raw], typing snaps to the NEAREST
## storable raw, quantize reports the achieved value honestly.
func _test_camera_units_support_lookup_maps() -> void:
	var CU = load("res://src/effects/studio/CameraUnits.gd")
	var unit := {"map": PackedFloat32Array([0.0, 10.0, 100.0]), "suffix": " ms", "decimals": 1}
	_assert_eq(CU.to_display(1, unit), 10.0, "map unit displays the table value")
	_assert_eq(CU.to_display(9, unit), 100.0, "out-of-range raw clamps to the table")
	_assert_eq(CU.to_raw(9.0, unit), 1, "typing snaps to the nearest storable raw")
	_assert_eq(CU.to_raw(500.0, unit), 2, "past the table end clamps to the last raw")
	var q: Dictionary = CU.quantize(60.0, unit)
	_assert_eq(int(q.get("raw", -1)), 2, "quantize picks the nearest raw (100 beats 10)")
	_assert_eq(bool(q.get("ok", true)), false, "the snap is reported, not silent")
	_assert_true("100" in str(q.get("reason", "")), "the tell names the achieved value")
	for r in range(3):
		_assert_eq(CU.to_raw(CU.to_display(r, unit), unit), r, "map round-trips raw %d" % r)


## The curated per-opcode descriptors: ADSR times in MILLISECONDS (snapped to the
## nearest hardware rate — the SPU stores rates, not times), Instrument as a NAMED
## enum, tick params labeled as ticks, Dynamics as channel volume. Expected ms
## values hand-computed from the PCSX-Redux envelope tables, independent of the
## implementation.
func _test_param_semantics_translate_the_common_opcodes() -> void:
	var Sem = load("res://src/effects/studio/FedsParamSemantics.gd")
	# ADSR_Attack (0xC2): rate 0-127 → time-to-full ms (linear mode).
	var atk: Dictionary = Sem.descriptor(0xC2, 0)
	_assert_eq(str(atk.get("label", "")), "Attack time", "attack gets an author label")
	_assert_eq(int(atk.get("max", -1)), 127, "attack rate field is 7-bit")
	var amap: PackedFloat32Array = atk.get("unit", {}).get("map", PackedFloat32Array())
	_assert_eq(amap.size(), 128, "one ms entry per storable attack rate")
	if amap.size() == 128:
		_assert_true(absf(amap[0] - 0.068) < 0.01, "attack rate 0 ≈ 0.068 ms")
		_assert_true(absf(amap[58] - 1188.9) < 1.0, "attack rate 58 ≈ 1189 ms")
		var mono := true
		for i in range(1, 128):
			if amap[i] < amap[i - 1]:
				mono = false
		_assert_true(mono, "attack ms map is monotonic (nearest-snap is well-defined)")
	# ADSR_Release (0xC5): 5-bit rate → exponential fall-to-silence ms.
	var rmap: PackedFloat32Array = Sem.descriptor(0xC5, 0).get("unit", {}).get("map", PackedFloat32Array())
	_assert_eq(rmap.size(), 32, "one ms entry per storable release rate")
	if rmap.size() == 32:
		_assert_true(absf(rmap[12] - 855.4) < 1.0, "release rate 12 ≈ 855 ms")
	# ADSR_Decay (0xC9): 4-bit rate.
	var dmap: PackedFloat32Array = Sem.descriptor(0xC9, 0).get("unit", {}).get("map", PackedFloat32Array())
	_assert_eq(dmap.size(), 16, "one ms entry per storable decay rate")
	if dmap.size() == 16:
		_assert_true(absf(dmap[8] - 53.4) < 0.5, "decay rate 8 ≈ 53 ms")
	# Instrument (0xAC): a NAMED enum over the waveset ids (DAW picker names).
	var inst: Dictionary = Sem.descriptor(0xAC, 0)
	_assert_eq(str(inst.get("editor", "")), "enum", "instrument edits as a named enum")
	var timpani := ""
	for c in inst.get("choices", []):
		if int(c.get("value", -1)) == 64:
			timpani = str(c.get("label", ""))
	_assert_true("Timpani" in timpani, "instrument 64 shows its DAW name")
	# Tick params + volume get honest labels.
	_assert_true("tick" in str(Sem.descriptor(0x81, 0).get("label", "")).to_lower(),
			"Fermata's param is labeled as ticks")
	_assert_eq(str(Sem.descriptor(0xE0, 0).get("label", "")), "Channel volume",
			"Dynamics is channel volume 0-127")
	_assert_eq(int(Sem.descriptor(0xE0, 0).get("max", -1)), 127, "volume capped 0-127")
	# Uncurated opcodes stay undescribed (the caller falls back to an honest-generic
	# label + the empirical range). 0xD8 PitchLFO_Init has no confident semantics.
	_assert_eq(Sem.descriptor(0xD8, 1), {}, "uncurated opcode → raw fallback")


# Semantics fixture: track A@28 = D4 20 17 (Portamento target=32 rate=23) | D8 01 02 03
# (PitchLFO_Init, uncurated 3-param) | 90; track B@36 = D2 FE (PitchBendRel −2) | 90.
func _make_semantics_bank():
	var blob := PackedByteArray()
	blob.append_array("feds".to_ascii_buffer())
	blob.append_array([39, 0, 0, 0])
	blob.append_array([2, 0])
	blob.append_array([7, 0])
	blob.append_array([28, 0, 0, 0])
	blob.append_array([0, 0, 0, 0, 0, 0, 0, 0])
	blob.append_array([28, 0, 36, 0])
	blob.append_array([0xD4, 0x20, 0x17, 0xD8, 0x01, 0x02, 0x03, 0x90])
	blob.append_array([0xD2, 0xFE, 0x90])
	return FedsBankScript.parse(blob)


func _semantics_score() -> Dictionary:
	return {"feds_pairs": [PairModel.pair_view(_make_semantics_bank(), 0, {}, null)]}


## ADR-0085 2026-08-12 §1/§2/§4: uncurated params get an author label (confident-else
## honest-generic — never the opaque "p2"), signed params are typed s8 (a display-only
## transform), and a scalar without a unit/enum carries the empirical corpus range.
func _test_uncurated_params_get_labels_signedness_and_range() -> void:
	var score := _semantics_score()
	# Portamento_Init: curated labels; the rate carries the corpus range, NO fake unit
	# (it is a per-tick delta, provably not ms). The design's rate=23 example.
	var porta := _select_event(score, 0, 0)
	_assert_true(porta.has("Glide target"), "Portamento p0 is 'Glide target', not a bare 'p1'")
	var rate: Dictionary = porta.get("Glide rate", {})
	_assert_eq(str(rate.get("editor", "")), "int", "glide rate is a plain int (no invented unit)")
	_assert_true(not rate.has("unit"), "rate has NO fabricated ms/cents unit")
	_assert_true(int(rate.get("range", {}).get("n", 0)) > 0, "rate carries an empirical corpus range")
	_assert_eq(int(rate.get("value", -1)), 23, "the design's Portamento rate=23 example")
	# An uncurated multi-param opcode: the honest-generic label names the OPCODE the byte
	# touches — never the opaque "p2"/"p3".
	var lfo := _select_event(score, 0, 1)
	var has_generic := false
	for n in lfo.keys():
		if "PitchLFO_Init param 2" in str(n):
			has_generic = true
		_assert_true(not str(n).ends_with(" p2") and not str(n).ends_with(" p3"),
				"no opaque pN label survives")
	_assert_true(has_generic, "an uncurated param names what the byte touches (the opcode)")
	# A signed byte is typed s8 (display-only; _int_cell sign-extends the raw seed).
	var rel := _select_event(score, 1, 0)
	var pb: Dictionary = rel.get("Pitch bend (relative)", {})
	_assert_eq(str(pb.get("type", "")), "s8", "PitchBendRel cell is typed signed")
	_assert_eq(int(pb.get("value", -1)), 254, "cell seeds the RAW byte; _int_cell signs it to −2")
	_assert_true(pb.has("range"), "the signed scalar also carries its corpus range")
	# A unit-grounded cell (ADSR ms) does NOT also show the corpus range (redundant noise).
	var atk: Dictionary = _select_event(_adsr_score(), 0, 0).get("Attack time", {})
	_assert_true(atk.has("unit") and not atk.has("range"),
			"a unit-grounded cell suppresses the empirical range")
	# An enum cell (Instrument) likewise suppresses the range.
	var inst: Dictionary = _select_event(_pair_score(), 0, 0).get("Instrument", {})
	_assert_true(not inst.has("range"), "a named-enum cell suppresses the empirical range")


# ADSR fixture: track A = C2 3A (ADSR_Attack 58) | 90, track B = D2 08 stub.
func _adsr_score() -> Dictionary:
	var blob := PackedByteArray()
	blob.append_array("feds".to_ascii_buffer())
	blob.append_array([33, 0, 0, 0])
	blob.append_array([2, 0])
	blob.append_array([7, 0])
	blob.append_array([28, 0, 0, 0])
	blob.append_array([0, 0, 0, 0, 0, 0, 0, 0])
	blob.append_array([28, 0, 31, 0])
	blob.append_array([0xC2, 0x3A, 0x90])
	blob.append_array([0xD2, 0x08])
	return {"feds_pairs": [PairModel.pair_view(FedsBankScript.parse(blob), 0, {}, null)]}


## The Event section consumes the descriptors: the ADSR cell edits in ms (unit
## map + raw byte address unchanged), the Instrument cell is a named enum.
func _test_event_section_applies_semantics() -> void:
	var score := _adsr_score()
	var atk: Dictionary = _select_event(score, 0, 0).get("Attack time", {})
	_assert_eq(str(atk.get("shape", "")), "edit", "ADSR attack stays an edit cell")
	_assert_eq(int(atk.get("value", -1)), 58, "seeded to the raw rate byte")
	_assert_eq(atk.get("field_ref"), {"channel": "sound_def", "kind": "byte",
			"offset": 29, "pair_idx": 0}, "ms editing still lowers the SAME raw byte")
	var map: PackedFloat32Array = atk.get("unit", {}).get("map", PackedFloat32Array())
	_assert_eq(map.size(), 128, "the cell carries the ms map for the kit")
	_assert_true(" ms" in str(atk.get("unit", {}).get("suffix", "")), "the box shows ms")
	# Instrument in the ring-1 fixture becomes the named enum.
	var inst: Dictionary = _select_event(_pair_score(), 0, 0).get("Instrument", {})
	_assert_eq(str(inst.get("editor", "")), "enum", "Instrument edits as a named enum")
	_assert_eq(int(inst.get("value", -1)), 5, "seeded to the raw id")
	var five := ""
	for c in inst.get("choices", []):
		if int(c.get("value", -1)) == 5:
			five = str(c.get("label", ""))
	_assert_true("Saw Wave" in five, "the choice shows the DAW name for id 5")


## The panel's chip hover speaks the same language: an Instrument chip names the
## instrument; an ADSR chip reports the ≈ milliseconds.
func _test_panel_chip_hover_carries_semantics() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var panel = Panel.new()
	panel.size = Vector2(700.0, 400.0)
	panel.set_view(_pair_score()["feds_pairs"][0])
	var lay: Dictionary = Panel.layout(panel._view, 700.0, panel._state())
	var tip := ""
	for chip in lay.get("chips", []):
		if str(chip.get("full", "")).begins_with("Instrument"):
			tip = panel._get_tooltip((chip.get("rect") as Rect2).get_center())
	_assert_true("Saw Wave" in tip, "Instrument chip hover names the instrument")
	panel.free()
	var panel2 = Panel.new()
	panel2.size = Vector2(700.0, 400.0)
	panel2.set_view(_adsr_score()["feds_pairs"][0])
	var lay2: Dictionary = Panel.layout(panel2._view, 700.0, panel2._state())
	var tip2 := ""
	for chip in lay2.get("chips", []):
		if str(chip.get("full", "")).begins_with("ADSR_Attack"):
			tip2 = panel2._get_tooltip((chip.get("rect") as Rect2).get_center())
	_assert_true("ms" in tip2 and "1189" in tip2, "ADSR chip hover reports ≈ milliseconds")
	panel2.free()


## Chip-hover PARITY (ADR-0085 §E): param_summary speaks the SAME author labels as the
## inspector cells (a labeled-but-unitless opcode names its label + its signed-aware
## value), while the fuller corpus-range detail stays in the inspector — NOT the one-line
## hover. Expected labels/values are hand-derived from the opcode table.
func _test_chip_hover_speaks_the_cell_labels() -> void:
	var Sem = load("res://src/effects/studio/FedsParamSemantics.gd")
	# PitchBendRel (signed byte): the hover names the cell label and the SIGNED value…
	var rel: String = Sem.param_summary(0xD2, [0xFE])
	_assert_true("Pitch bend (relative)" in rel, "the chip speaks the cell's author label")
	_assert_true("-2" in rel, "…and the signed value (0xFE → −2), like the cell")
	# …but NOT the corpus-range detail, which is inspector-only (avoid a noisy hover).
	_assert_true(not ("typical" in rel) and not ("n=" in rel),
			"the one-line hover leaves the corpus range to the inspector")
	# The 16-bit word speaks its signed word value.
	var pb16: String = Sem.param_summary(0xD3, [0xFF, 0xFE])
	_assert_true("Pitch bend add (16-bit)" in pb16 and "-2" in pb16,
			"the s16 chip names its label + signed word value")
	# A truly uncurated opcode adds nothing beyond the chip's own opcode name.
	_assert_eq(Sem.param_summary(0xD8, [1, 2, 3]), "",
			"an uncurated opcode's hover stays silent (the chip already names it)")


## Decision 1 hosting + decision 6 nav discipline: the page owns ONE lane panel
## above the timeline; a pair target shows it (loaded with that pair's view), any
## other target hides it, and a panel event click routes to the inspector WITHOUT
## growing the _nav back-stack on same-pair re-selection.
func _test_page_hosts_the_pair_lane_panel() -> void:
	var page = Page.new()
	add_child(page)
	await get_tree().process_frame   # _ready builds the UI
	var ed = EffectDataClass.new()
	ed.sound_containers = {"containers": [
		{"index": 0, "mode": 0, "id_a": 1, "id_b": 0, "id_c": 0}]}
	ed.sound = {"phase1": [
		{"channel_index": 0, "max_keyframe": 1,
			"keyframes": [{"sound_id": 2, "duration_frames": 10}]}]}
	page._effect_data = ed
	page._sound_env = {"feds_bank": _make_loop_bank(), "sound_containers": ed.sound_containers}
	page._pair_views = page._compute_pair_views()
	page._timeline.load_score(page._build_score())

	_assert_true(page._pair_panel != null, "the page owns a pair lane panel")
	_assert_true(page._pair_panel._tl == page._timeline,
			"the page binds its timeline into the panel (one shared axis object)")
	_assert_eq(page._pair_panel.visible, false, "no pair open → panel hidden")

	page._set_root(Target.pair(0))
	_assert_eq(page._pair_panel.visible, true, "opening a pair shows the panel")
	_assert_eq(int(page._pair_panel._view.get("pair_idx", -1)), 0,
			"the panel carries the open pair's view")

	# Same-pair re-selection from the panel: inspector re-routes, nav does NOT grow.
	page._pair_panel.event_selected.emit(0, 1)
	page._pair_panel.event_selected.emit(0, 1)
	_assert_eq(page._nav.size(), 1, "same-pair re-selection never grows the nav stack")
	_assert_eq(str(page._nav.back().get("kind", "")), "pair", "the pair stays the root")

	# The panel's selection scopes the inspector: the page annotates the live view,
	# and a view re-derive (an edit's invalidates_feds recompute) re-applies it —
	# the Event section survives the recompute instead of dropping to overview.
	page._pair_panel._selected = {"track": 0, "event_index": 1}
	page._render_current()
	_assert_eq((page._pair_panel._view as Dictionary).get("selected"),
			{"track": 0, "event_index": 1}, "page annotates the view with the selection")
	page._pair_views = page._compute_pair_views()   # fresh dicts — annotation gone
	page._render_current()
	_assert_eq((page._pair_panel._view as Dictionary).get("selected"),
			{"track": 0, "event_index": 1},
			"selection survives a view re-derive (re-annotated from the panel)")

	page._set_root(Target.container(0))
	_assert_eq(page._pair_panel.visible, false, "leaving the pair hides the panel")
	page.queue_free()
	await get_tree().process_frame


## Frame-axis §2: the pair's tick-0 anchors to a REPRESENTATIVE firing trigger's
## fire frame — drilled-from origin span → selected resolving trigger (live
## re-anchor) → first-firing trigger → orphan at frame 0 with a header tell.
func _test_page_anchors_pair_tick0_to_representative_trigger() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var page = Page.new()
	add_child(page)
	await get_tree().process_frame
	var ed = EffectDataClass.new()
	ed.sound_containers = {"containers": [
		{"index": 0, "mode": 0, "id_a": 1, "id_b": 0, "id_c": 0}]}
	# Two channels; each opens with a silent gap event so the fires are NOT at 0:
	# channel 0 fires sound 2 at frame 10, channel 1 fires sound 2 at frame 20.
	ed.sound = {"phase1": [
		{"channel_index": 0, "max_keyframe": 2,
			"keyframes": [{"sound_id": 0, "duration_frames": 10},
				{"sound_id": 2, "duration_frames": 5}]},
		{"channel_index": 1, "max_keyframe": 2,
			"keyframes": [{"sound_id": 0, "duration_frames": 20},
				{"sound_id": 2, "duration_frames": 5}]}]}
	page._effect_data = ed
	page._sound_env = {"feds_bank": _make_loop_bank(), "sound_containers": ed.sound_containers}
	page._pair_views = page._compute_pair_views()
	page._timeline.load_score(page._build_score())

	# No origin span, no selection → the FIRST firing trigger anchors (frame 10).
	page._set_root(Target.pair(0))
	_assert_eq(page._pair_panel._anchor, {"frame": 10, "source": "first"},
			"first-firing trigger anchors the pair (fire frame 10)")

	# A selected resolving trigger re-anchors LIVE (channel 1's fire at 20).
	page._timeline.select_span("sound:phase1:1#1")
	page._render_current()
	_assert_eq(page._pair_panel._anchor, {"frame": 20, "source": "selected"},
			"selecting a resolving trigger re-anchors the panel")

	# The drilled-from origin span WINS over the selection (channel 0's fire at 10).
	page._nav = [Target.span("sound:phase1:0#1"), Target.pair(0)]
	page._render_current()
	_assert_eq(page._pair_panel._anchor, {"frame": 10, "source": "origin"},
			"the drill origin span is the anchor of record")

	# Orphan: no trigger resolves into the pair → frame 0 + a visible header tell.
	ed.sound_containers = {"containers": [
		{"index": 0, "mode": 0, "id_a": 9, "id_b": 0, "id_c": 0}]}
	page._sound_env = {"feds_bank": _make_loop_bank(), "sound_containers": ed.sound_containers}
	page._pair_views = page._compute_pair_views()
	page._timeline.load_score(page._build_score())
	page._set_root(Target.pair(0))
	_assert_eq(page._pair_panel._anchor, {"frame": 0, "source": "orphan"},
			"no resolving trigger → the pair anchors at frame 0")
	var lay: Dictionary = Panel.layout(page._pair_panel._view, 700.0,
			page._pair_panel._state(), null, page._pair_panel._anchor)
	_assert_true("anchored at frame 0" in str(lay.get("header", {}).get("text", "")),
			"the orphan anchor is a visible header tell, not silent")

	page.queue_free()
	await get_tree().process_frame


func _maxf_of(a: PackedFloat32Array) -> float:
	var m := 0.0
	for v in a:
		m = maxf(m, float(v))
	return m


func _band_for(bands: Array, track: int) -> Dictionary:
	for b in bands:
		if int(b.get("track", -1)) == track:
			return b
	return {}


## Slice 3 (ADR-0085 2026-08-12 §3): the two per-track energy bands share ONE
## normalization — scaled by the PAIR's peak, not each track's own — so a silent
## stub reads FLAT and the carrying track reads TALL, answering "which track makes
## the sound?" at a glance. The pure oracle; expected values hand-computed.
func _test_shared_peak_normalize_keeps_the_stub_flat() -> void:
	var GP = load("res://src/effects/studio/SoundGhostProjector.gd")
	var carrier := PackedFloat32Array([0.0, 0.4, 0.8, 0.5, 0.1])   # raw peak 0.8
	var stub := PackedFloat32Array([0.02, 0.03, 0.02])             # raw peak 0.03
	var res: Array = GP.normalize_pair_shared(carrier, stub)
	var na: PackedFloat32Array = res[0]
	var nb: PackedFloat32Array = res[1]
	_assert_true(absf(_maxf_of(na) - 1.0) < 0.0001, "the carrier normalizes to a full-height peak")
	_assert_true(_maxf_of(nb) < 0.05, "the stub reads FLAT under the SHARED peak (not its own)")
	_assert_eq(na.size(), 5, "carrier length preserved")
	_assert_eq(nb.size(), 3, "stub length preserved")
	_assert_true(absf(na[2] - 1.0) < 0.0001 and absf(na[1] - 0.5) < 0.0001,
			"the carrier's internal shape is preserved (shared divisor cancels ratios)")
	# The stub scaled by the shared 0.8: 0.03/0.8 ≈ 0.0375 — flat, but its own shape kept.
	_assert_true(absf(nb[1] - 0.0375) < 0.0002, "the stub keeps its (tiny) shape under the shared peak")
	# An all-silent pair returns unchanged — never a divide-by-zero.
	var sil: Array = GP.normalize_pair_shared(PackedFloat32Array([0.0, 0.0]), PackedFloat32Array([0.0]))
	_assert_eq(sil[0], PackedFloat32Array([0.0, 0.0]), "a silent pair is returned unchanged")
	_assert_eq(sil[1], PackedFloat32Array([0.0]), "…both tracks")


# A stub SPU engine for the per-track energy render: records the single_track passed
# to play_pair and emits a short audible burst per render — LOUD for track 0, QUIET
# for track 1 — then silence, so the render loop terminates and shared-normalization
# has a real carrier/stub contrast to resolve.
class _MockEnergyEngine:
	var capture_mode := false
	var ready_ok := true
	var play_calls: Array = []
	var _cur := -1
	var _f := 0
	func panic() -> void: pass
	func begin_effect() -> int: return 1
	func end_effect(_token: int) -> void: pass
	func play_pair(_token: int, _bank, _pair_idx: int, _sound_id: int,
			single_track: int = -1) -> bool:
		play_calls.append(single_track)
		_cur = single_track
		_f = 0
		return true
	func render_subs(_n: int) -> PackedInt32Array:
		var amp := 0
		if _f < 5:
			amp = 20000 if _cur == 0 else 800   # track 0 loud, track 1 quiet
		_f += 1
		return PackedInt32Array([amp, amp])


## Slice 3: render_track_energies renders each track ALONE (single_track 0 then 1 —
## NOT an L/R split) and shares ONE normalization, so the loud track reads tall and
## the quiet track flat. Driven through a stub SPU engine (no real render).
func _test_render_track_energies_isolates_each_track() -> void:
	var GP = load("res://src/effects/studio/SoundGhostProjector.gd")
	var eng = _MockEnergyEngine.new()
	var res: Dictionary = GP.render_track_energies(eng, _make_bank(), 0, 2)
	_assert_eq(eng.play_calls, [0, 1], "each track renders ALONE (single_track 0 then 1)")
	var a: PackedFloat32Array = res.get("a")
	var b: PackedFloat32Array = res.get("b")
	_assert_true(_maxf_of(a) > 0.9, "the loud track's energy reads TALL")
	_assert_true(_maxf_of(b) < 0.2, "the quiet track's energy reads FLAT under the shared peak")


## Slice 3: each track gets its OWN energy band inline under its lane, on the shared
## frame axis, so the swell sits directly beneath the opcodes that cause it (and
## doubles as §2's ground truth). Shared-normalized data → the carrier band is tall,
## the stub band flat. A collapsed track draws no band.
func _test_panel_draws_per_track_energy_band() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var axis = Axis.new()
	axis.configure(Panel.GUTTER_W + Panel.PAD_X, 10.0)
	var view: Dictionary = PairModel.pair_view(_make_bank(), 0, {}, null)
	# Inject shared-normalized per-track energy (carrier tall, stub flat).
	(view.get("tracks", [])[0] as Dictionary)["energy"] = PackedFloat32Array([0.0, 0.5, 1.0, 0.6, 0.1])
	(view.get("tracks", [])[1] as Dictionary)["energy"] = PackedFloat32Array([0.05, 0.04, 0.05])
	var fire := 40
	var lay: Dictionary = Panel.layout(view, 900.0, {}, axis, {"frame": fire, "source": "first"})
	var bands: Array = lay.get("energy_bands", [])
	_assert_eq(bands.size(), 2, "one energy band per track")
	var bandA: Dictionary = _band_for(bands, 0)
	var bandB: Dictionary = _band_for(bands, 1)
	_assert_true(not bandA.is_empty() and not bandB.is_empty(), "both tracks have a band")
	if bandA.is_empty() or bandB.is_empty():
		return
	# The band rides the SHARED frame axis: sample i sits at axis.frame_to_x(fire + i).
	var pts: PackedVector2Array = bandA.get("points")
	_assert_true(pts.size() >= 1 and absf(pts[0].x - axis.frame_to_x(float(fire))) < 0.01,
			"the band's first sample sits at the fire frame on the shared axis")
	# Shared-normalize shows which track sounds: carrier tall, stub flat.
	_assert_true(float(bandA.get("peak")) > 0.9, "the carrier track's band is TALL")
	_assert_true(float(bandB.get("peak")) < 0.1, "the silent-stub track's band is FLAT")
	# The band sits UNDER its track's lanes (inline, on the shared axis).
	var lastA_bottom := 0.0
	for lane in lay.get("lanes", []):
		if int(lane.get("track")) == 0:
			lastA_bottom = maxf(lastA_bottom, (lane.get("rect") as Rect2).end.y)
	_assert_true((bandA.get("rect") as Rect2).position.y >= lastA_bottom,
			"the energy band sits beneath the track's opcode lanes")
	# A collapsed track draws no band (nothing to sit under).
	var col: Dictionary = Panel.layout(view, 900.0, {"collapsed": {0: true}}, axis,
			{"frame": fire, "source": "first"})
	_assert_true(_band_for(col.get("energy_bands", []), 0).is_empty(),
			"a collapsed track draws no energy band")
	_assert_true(not _band_for(col.get("energy_bands", []), 1).is_empty(),
			"…but the expanded sibling still shows its band")


# Verdict fixture: track A@28 (11 bytes) exercises every verdict —
#   AC 05  Instrument   @ei0  (before the first note → Pre-arm)
#   60 0C  Note         @ei1  (the sounding note → Live)
#   AC 06  Instrument   @ei2  (at/after the first note → Live)
#   82     NOP          @ei3  (true no-op → Inert)
#   98 03  Repeat       @ei4  (flow → Structural)
#   99     Coda         @ei5  (flow → Structural)
#   90     EndBar       @ei6  (flow → Structural; track A is Sounding)
# track B@39 (2 bytes): D2 08 PitchBendRel, no EndBar → a Stub, its voice-write
# pre-arms the track it flows into.
func _make_verdict_bank():
	var blob := PackedByteArray()
	blob.append_array("feds".to_ascii_buffer())
	blob.append_array([41, 0, 0, 0])                   # data_size = 41
	blob.append_array([2, 0])
	blob.append_array([7, 0])
	blob.append_array([28, 0, 0, 0])
	blob.append_array([0, 0, 0, 0, 0, 0, 0, 0])
	blob.append_array([28, 0, 39, 0])                  # track A @28, track B @39
	blob.append_array([0xAC, 0x05, 0x60, 0x0C, 0xAC, 0x06, 0x82,
			0x98, 0x03, 0x99, 0x90])                   # track A @28 (11 bytes)
	blob.append_array([0xD2, 0x08])                    # track B @39 (stub)
	return FedsBankScript.parse(blob)


## Slice 2 (ADR-0085 2026-08-12 §2): the pure classifier tags each opcode with an
## honest verdict off the decoded stream — a NOP is Inert, flow is Structural, a
## voice-write is Pre-arm before the first note and Live at/after it, and a note is
## Live. Track-level: a missing EndBar is a Stub whose writes pre-arm the
## next track. Expected verdicts hand-derived from the opcode table.
func _test_opcode_verdicts_classify_each_kind() -> void:
	var V = load("res://src/effects/studio/FedsOpcodeVerdicts.gd")
	var view: Dictionary = PairModel.pair_view(_make_verdict_bank(), 0, {}, null)
	var a: Dictionary = view.get("tracks", [])[0]
	var va: Dictionary = V.verdicts(a)
	var pe: Dictionary = va.get("per_event", {})
	_assert_eq(str(pe.get(0)), V.PREARM, "Instrument before the first note pre-arms the voice")
	_assert_eq(str(pe.get(1)), V.LIVE, "a Note is heard (Live)")
	_assert_eq(str(pe.get(2)), V.LIVE, "a voice-write at/after the first note is Live")
	_assert_eq(str(pe.get(3)), V.INERT, "a true NOP (0x82) is Inert")
	_assert_eq(str(pe.get(4)), V.STRUCTURAL, "Repeat is Structural (flow)")
	_assert_eq(str(pe.get(5)), V.STRUCTURAL, "Coda is Structural (flow)")
	_assert_eq(str(pe.get(6)), V.STRUCTURAL, "EndBar is Structural (flow)")
	_assert_eq(str(va.get("track")), V.SOUNDING, "track A ends with EndBar → Sounding")
	var reasons: Dictionary = va.get("reasons", {})
	_assert_true("pre-arm" in str(reasons.get(0)).to_lower(), "the pre-arm reason explains the staging")
	_assert_true("tick 0" in str(reasons.get(0)), "…and names the note it stages")
	# Track B: a stub's voice-write pre-arms the track it flows into (no note of its own).
	var b: Dictionary = view.get("tracks", [])[1]
	var vb: Dictionary = V.verdicts(b)
	_assert_eq(str(vb.get("track")), V.STUB, "track B has no EndBar → a Stub")
	_assert_eq(str((vb.get("per_event", {}) as Dictionary).get(0)), V.PREARM,
			"a stub's voice-write pre-arms the track it flows into")
	_assert_true("flows into" in str((vb.get("reasons", {}) as Dictionary).get(0)),
			"the stub's pre-arm reason names the flow-through")


## Slice 2: the panel paints the verdicts — every chip and note bar carries its
## verdict (→ tint/glyph) and the track section label speaks the Sounding/Stub tell.
func _test_panel_chips_carry_opcode_verdicts() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var V = load("res://src/effects/studio/FedsOpcodeVerdicts.gd")
	var view: Dictionary = PairModel.pair_view(_make_verdict_bank(), 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 700.0, {})
	var by_ei: Dictionary = {}
	for chip in lay.get("chips", []):
		if int(chip.get("track")) == 0:
			by_ei[int(chip.get("event_index"))] = chip
	_assert_eq(str(by_ei.get(0, {}).get("verdict")), V.PREARM, "the pre-arm chip is tagged Pre-arm")
	_assert_eq(str(by_ei.get(2, {}).get("verdict")), V.LIVE, "the post-note chip is tagged Live")
	_assert_eq(str(by_ei.get(3, {}).get("verdict")), V.INERT, "the NOP chip is tagged Inert")
	_assert_eq(str(by_ei.get(4, {}).get("verdict")), V.STRUCTURAL, "the Repeat chip is Structural")
	# A note bar carries Live.
	var note_verdict := ""
	for bar in lay.get("span_bars", []):
		if int(bar.get("event_index")) == 1:
			note_verdict = str(bar.get("verdict"))
	_assert_eq(note_verdict, V.LIVE, "the note bar is tagged Live")
	# The track section labels speak the Sounding / Stub tell.
	var sections: Array = lay.get("sections", [])
	_assert_true("Sounding" in str(sections[0].get("label", "")), "track A section reads Sounding")
	_assert_true("flows into" in str(sections[1].get("label", "")),
			"track B section keeps the Silent-stub flow-through tell")


## Slice 2: the reason rides the EXISTING chip-hover label (not the F1 inspector) —
## a Pre-arm chip's hover explains it pre-arms the voice for the note at tick X.
func _test_panel_chip_hover_speaks_the_verdict_reason() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var panel = Panel.new()
	panel.size = Vector2(700.0, 400.0)
	panel.set_view(PairModel.pair_view(_make_verdict_bank(), 0, {}, null))
	var lay: Dictionary = Panel.layout(panel._view, 700.0, panel._state())
	# The first Instrument chip (ei0) pre-arms — its hover carries the reason.
	var prearm_center := Vector2.ZERO
	for chip in lay.get("chips", []):
		if int(chip.get("track")) == 0 and int(chip.get("event_index")) == 0:
			prearm_center = (chip.get("rect") as Rect2).get_center()
	var tip: String = panel._get_tooltip(prearm_center)
	_assert_true("pre-arm" in tip.to_lower(), "the pre-arm chip's hover speaks its verdict reason")
	_assert_true("tick 0" in tip, "…and names the note it stages")
	panel.free()


# --- Two-axis static "Muted" verdict + hatch (ADR-0085 2026-08-12 amendment) ---

## Slice A: the instrument table splits the `· Silence` category into a TRUSTED-EMPTY
## tier (provably zero output — "Empty"/"Empty/Silent") and a GRAY-ZONE CLIP tier
## (faint but nonzero — "Inaudible Clip"/"Nearly Inaudible Clip"). The Muted verdict
## may only hatch trusted-empty; the clip tier gets the softer faint tell. Ids are
## hand-picked from the generated NAMES table (independent source of truth).
func _test_instrument_names_split_empty_from_gray_zone_clip() -> void:
	var N = load("res://src/effects/studio/FedsInstrumentNames.gd")
	# Trusted-empty: id 1 "Empty/Silent · Silence", id 45 "Empty · Silence".
	_assert_true(N.is_trusted_empty(1), "id 1 (Empty/Silent) is trusted-empty")
	_assert_true(N.is_trusted_empty(45), "id 45 (Empty) is trusted-empty")
	_assert_false(N.is_gray_zone_clip(1), "a trusted-empty id is not a gray-zone clip")
	# Gray-zone clips: id 178 "Inaudible Clip", id 179 "Nearly Inaudible Clip".
	_assert_true(N.is_gray_zone_clip(178), "id 178 (Inaudible Clip) is a gray-zone clip")
	_assert_true(N.is_gray_zone_clip(179), "id 179 (Nearly Inaudible Clip) is a gray-zone clip")
	_assert_false(N.is_trusted_empty(178), "a gray-zone clip is not trusted-empty")
	# An audible instrument (id 5 "Fat Saw Wave-Asp · Synth") is neither.
	_assert_false(N.is_trusted_empty(5), "an audible synth is not trusted-empty")
	_assert_false(N.is_gray_zone_clip(5), "an audible synth is not a gray-zone clip")
	# The flavour parse normalizes "Empty/Silent" → "Empty" and preserves the clip name.
	_assert_eq(N.silence_flavour(1), "Empty", "Empty/Silent normalizes to the Empty flavour")
	_assert_eq(N.silence_flavour(178), "Inaudible Clip", "the clip flavour is preserved")
	_assert_eq(N.silence_flavour(5), "", "a non-silence id has no silence flavour")


## A 1-pair FEDS bank from raw track-A / track-B opcode bytes (the Muted-verdict
## fixtures). Mirrors _make_verdict_bank's header layout, computing offsets so any
## byte stream drops in: magic, data_size, pair_count_plus1=2 (→1 pair), resource
## id, data_offset=28, then the two u16 track offsets at 0x18.
func _make_feds_bank(a: PackedByteArray, b: PackedByteArray):
	var off_a := 28
	var off_b := off_a + a.size()
	var total := off_b + b.size()
	var blob := PackedByteArray()
	blob.append_array("feds".to_ascii_buffer())
	blob.append_array([total & 0xFF, (total >> 8) & 0xFF, 0, 0])   # 0x04 data_size
	blob.append_array([2, 0])                                       # 0x08 pair_count_plus1
	blob.append_array([7, 0])                                       # 0x0A resource_id
	blob.append_array([off_a & 0xFF, (off_a >> 8) & 0xFF, 0, 0])   # 0x0C data_offset
	blob.append_array([0, 0, 0, 0, 0, 0, 0, 0])                     # 0x10 padding → 0x18
	blob.append_array([off_a & 0xFF, (off_a >> 8) & 0xFF])          # 0x18 track A offset
	blob.append_array([off_b & 0xFF, (off_b >> 8) & 0xFF])          # 0x1A track B offset
	blob.append_array(a)
	blob.append_array(b)
	return FedsBankScript.parse(blob)


## Slice B: the read model carries per-voice running state — the active instrument
## (last 0xAC, mirroring the octave walk) and whether noise is armed (0xB4/0xB6 arm,
## 0xB7 clears) — and stamps each note with the state in force when it plays.
func _test_model_threads_active_instrument_and_noise_armed() -> void:
	# AC 05 | note | B6 (arm) | note | B7 (disarm) | note | AC 01 | note | EndBar
	var a := PackedByteArray([0xAC, 0x05, 0x60, 0x0C, 0xB6, 0x60, 0x0C, 0xB7,
			0x60, 0x0C, 0xAC, 0x01, 0x60, 0x0C, 0x90])
	var view: Dictionary = PairModel.pair_view(
			_make_feds_bank(a, PackedByteArray([0x90])), 0, {}, null)
	var notes: Array = (view.get("tracks", [])[0] as Dictionary).get("notes", [])
	var by_ei := {}
	for n in notes:
		by_ei[int(n.get("event_index"))] = n
	_assert_eq(int(by_ei[1].get("active_instrument")), 5, "the first note runs under instrument 5")
	_assert_false(bool(by_ei[1].get("noise_armed")), "…on a voice that is not yet noise-armed")
	_assert_true(bool(by_ei[3].get("noise_armed")), "a note after 0xB6 is noise-armed")
	_assert_false(bool(by_ei[5].get("noise_armed")), "…and 0xB7 clears the noise-arm")
	_assert_eq(int(by_ei[7].get("active_instrument")), 1, "a later 0xAC updates the running instrument")


## Slice C: inside a SOUNDING track (one that has at least one audible note), a note
## whose running instrument is a trusted-empty sample is Muted; an audible note stays
## Live; voice-writes keep their Pre-arm/Live verdict (muteness downgrades notes only).
func _test_muted_note_under_trusted_empty_instrument() -> void:
	var V = load("res://src/effects/studio/FedsOpcodeVerdicts.gd")
	# AC 05 (audible) | note | AC 01 (Empty/Silent) | note | EndBar
	var a := PackedByteArray([0xAC, 0x05, 0x60, 0x0C, 0xAC, 0x01, 0x60, 0x0C, 0x90])
	var view: Dictionary = PairModel.pair_view(
			_make_feds_bank(a, PackedByteArray([0x90])), 0, {}, null)
	var vd: Dictionary = V.verdicts(view.get("tracks", [])[0])
	var pe: Dictionary = vd.get("per_event", {})
	_assert_eq(str(pe.get(1)), V.LIVE, "a note under an audible instrument is Live")
	_assert_eq(str(pe.get(3)), V.MUTED, "a note under a trusted-empty instrument is Muted")
	_assert_eq(str(pe.get(0)), V.PREARM, "a voice-write keeps Pre-arm in a sounding track")
	_assert_eq(str(pe.get(2)), V.LIVE, "a voice-write after the first note stays Live")
	_assert_eq(str(vd.get("track")), V.SOUNDING, "a track with an audible note is Sounding")
	_assert_true("empty" in str(vd.get("reasons", {}).get(3)).to_lower(),
			"the Muted reason names the trusted-empty instrument")


## Slice D: a track where no note ever resolves to an audible instrument is WHOLLY
## Muted — the deterministic E001 fix. Every event (voice-writes and structural
## alike) reads Muted so the whole track hatches; the return flags it wholly_muted.
func _test_wholly_muted_track_hatches_every_event() -> void:
	var V = load("res://src/effects/studio/FedsOpcodeVerdicts.gd")
	# AC 01 (Empty/Silent) | note | note | EndBar — no audible note anywhere.
	var a := PackedByteArray([0xAC, 0x01, 0x60, 0x0C, 0x60, 0x0C, 0x90])
	var view: Dictionary = PairModel.pair_view(
			_make_feds_bank(a, PackedByteArray([0x90])), 0, {}, null)
	var vd: Dictionary = V.verdicts(view.get("tracks", [])[0])
	var pe: Dictionary = vd.get("per_event", {})
	_assert_true(bool(vd.get("wholly_muted")), "a track with no audible note is wholly Muted")
	_assert_eq(str(pe.get(0)), V.MUTED, "the Instrument voice-write hatches in a wholly-Muted track")
	_assert_eq(str(pe.get(1)), V.MUTED, "the first note hatches")
	_assert_eq(str(pe.get(2)), V.MUTED, "the second note hatches")
	_assert_eq(str(pe.get(3)), V.MUTED, "even the EndBar hatches — the whole track is silent")
	# A track WITH an audible note is not wholly Muted (contrast — the C fixture).
	var b := PackedByteArray([0xAC, 0x05, 0x60, 0x0C, 0x90])
	var view2: Dictionary = PairModel.pair_view(
			_make_feds_bank(b, PackedByteArray([0x90])), 0, {}, null)
	_assert_false(bool(V.verdicts(view2.get("tracks", [])[0]).get("wholly_muted")),
			"a track with an audible note is not wholly Muted")


## Slice E: the confirmed noise-clock allowlist (0xB4/0xB5 write the single shared
## SPU noise register) reads Live-by-proxy — never hatched, even inside a wholly-
## Muted track. And the noise-armed gate: a note on a noise-armed voice (0xB4/0xB6)
## is audible even under a trusted-empty instrument, so it is NOT Muted.
func _test_live_by_proxy_noise_clock_and_noise_armed_gate() -> void:
	var V = load("res://src/effects/studio/FedsOpcodeVerdicts.gd")
	# Noise-armed gate: AC 01 (empty) | B6 (arm the voice) | note | EndBar.
	var g := PackedByteArray([0xAC, 0x01, 0xB6, 0x60, 0x0C, 0x90])
	var vg: Dictionary = V.verdicts(PairModel.pair_view(
			_make_feds_bank(g, PackedByteArray([0x90])), 0, {}, null).get("tracks", [])[0])
	_assert_eq(str(vg.get("per_event", {}).get(2)), V.LIVE,
			"a note on a noise-armed voice is audible (not Muted) even under an empty instrument")
	_assert_false(bool(vg.get("wholly_muted")), "…so the track is not wholly Muted")
	# Live-by-proxy inside a wholly-Muted track: AC 01 | note | B5 (clock, no arm) |
	# note | EndBar. Every note is empty+un-armed → wholly Muted, but B5 stays un-hatched.
	var w := PackedByteArray([0xAC, 0x01, 0x60, 0x0C, 0xB5, 0x20, 0x60, 0x0C, 0x90])
	var vw: Dictionary = V.verdicts(PairModel.pair_view(
			_make_feds_bank(w, PackedByteArray([0x90])), 0, {}, null).get("tracks", [])[0])
	var pw: Dictionary = vw.get("per_event", {})
	_assert_true(bool(vw.get("wholly_muted")), "0xB5 does not arm the voice, so the track is still wholly Muted")
	_assert_eq(str(pw.get(2)), V.LIVE_BY_PROXY, "the noise clock reads Live-by-proxy inside a wholly-Muted track")
	_assert_eq(str(pw.get(0)), V.MUTED, "…while the Instrument voice-write still hatches")
	_assert_eq(str(pw.get(1)), V.MUTED, "…and the notes hatch")
	_assert_true("proxy" in str(vw.get("reasons", {}).get(2)).to_lower(),
			"the Live-by-proxy reason explains it colours another voice")
	# Live-by-proxy in a SOUNDING track too: AC 05 (audible) | note | B4 3F | EndBar.
	var s := PackedByteArray([0xAC, 0x05, 0x60, 0x0C, 0xB4, 0x3F, 0x90])
	var vs: Dictionary = V.verdicts(PairModel.pair_view(
			_make_feds_bank(s, PackedByteArray([0x90])), 0, {}, null).get("tracks", [])[0])
	_assert_eq(str(vs.get("per_event", {}).get(2)), V.LIVE_BY_PROXY,
			"0xB4 reads Live-by-proxy in a sounding track (not plain Live)")


## Slice F: a note under a GRAY-ZONE clip (faint but nonzero) is NOT provably silent —
## it stays Live and is NOT hatched; it is flagged in the `faint` set for the softer ≈
## tell. Only trusted-empty earns the Muted hatch; we never over-claim silence.
func _test_gray_zone_clip_note_is_faint_not_muted() -> void:
	var V = load("res://src/effects/studio/FedsOpcodeVerdicts.gd")
	# AC B2 (178 "Inaudible Clip") | note | EndBar.
	var a := PackedByteArray([0xAC, 0xB2, 0x60, 0x0C, 0x90])
	var vd: Dictionary = V.verdicts(PairModel.pair_view(
			_make_feds_bank(a, PackedByteArray([0x90])), 0, {}, null).get("tracks", [])[0])
	var pe: Dictionary = vd.get("per_event", {})
	var faint: Dictionary = vd.get("faint", {})
	_assert_eq(str(pe.get(1)), V.LIVE, "a gray-zone clip note stays Live (not Muted)")
	_assert_true(bool(faint.get(1, false)), "…but it is flagged faint for the ≈ tell")
	_assert_false(bool(vd.get("wholly_muted")), "a clip note keeps the track sounding (not wholly Muted)")
	_assert_true("faint" in str(vd.get("reasons", {}).get(1)).to_lower(),
			"the faint reason explains it is nearly-inaudible, not proven silent")
	# A trusted-empty note is Muted, never merely faint (contrast).
	var b := PackedByteArray([0xAC, 0x01, 0x60, 0x0C, 0xAC, 0x05, 0x60, 0x0C, 0x90])
	var vb: Dictionary = V.verdicts(PairModel.pair_view(
			_make_feds_bank(b, PackedByteArray([0x90])), 0, {}, null).get("tracks", [])[0])
	_assert_eq(str(vb.get("per_event", {}).get(1)), V.MUTED, "a trusted-empty note is Muted")
	_assert_false(bool(vb.get("faint", {}).get(1, false)), "…and not in the faint set")
	_assert_false(bool(vb.get("faint", {}).get(3, false)), "an audible note is not faint")


## Slice G: the panel threads the Muted / Live-by-proxy verdict and the faint flag
## onto placed note bars and chips (→ the hatch, the ≈ tell, the Live-by-proxy tint),
## and the section label speaks the wholly-Muted tell. Layout-level (no pixels).
func _test_panel_carries_muted_faint_and_live_by_proxy() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var V = load("res://src/effects/studio/FedsOpcodeVerdicts.gd")
	# Track A wholly-muted with a noise-clock (Live-by-proxy); track B: clip + audible.
	var a := PackedByteArray([0xAC, 0x01, 0x60, 0x0C, 0xB5, 0x20, 0x60, 0x0C, 0x90])
	var b := PackedByteArray([0xAC, 0xB2, 0x60, 0x0C, 0xAC, 0x05, 0x60, 0x0C, 0x90])
	var view: Dictionary = PairModel.pair_view(_make_feds_bank(a, b), 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 900.0, {})
	var a_chip := {}
	for chip in lay.get("chips", []):
		if int(chip.get("track")) == 0:
			a_chip[int(chip.get("event_index"))] = chip
	_assert_eq(str(a_chip.get(0, {}).get("verdict")), V.MUTED,
			"the wholly-muted Instrument chip carries the Muted verdict (→ hatch)")
	_assert_eq(str(a_chip.get(2, {}).get("verdict")), V.LIVE_BY_PROXY,
			"the noise-clock chip carries Live-by-proxy (→ never hatched)")
	for bar in lay.get("span_bars", []):
		if int(bar.get("track")) == 0:
			_assert_eq(str(bar.get("verdict")), V.MUTED, "a wholly-muted track A note bar is Muted")
	var b_notes := {}
	for bar in lay.get("span_bars", []):
		if int(bar.get("track")) == 1:
			b_notes[int(bar.get("event_index"))] = bar
	_assert_true(bool(b_notes.get(1, {}).get("faint")), "the gray-zone clip note bar carries the faint flag")
	_assert_false(bool(b_notes.get(3, {}).get("faint")), "the audible note bar is not faint")
	_assert_true("Muted" in str((lay.get("sections", [])[0] as Dictionary).get("label", "")),
			"track A's section label speaks the wholly-Muted tell")


## Slice H: render_track_energies also reports each track's ABSOLUTE (un-normalized)
## raw peak, alongside the shared-normalized envelope, so a genuinely-silent track that
## the shared-normalize dresses UP to a full-height swell can still be told apart. This
## is a display-only honesty fix — it never feeds the opcode verdict.
func _test_render_track_energies_reports_absolute_raw_peak() -> void:
	var GP = load("res://src/effects/studio/SoundGhostProjector.gd")
	var eng = _MockEnergyEngine.new()
	var res: Dictionary = GP.render_track_energies(eng, _make_bank(), 0, 2)
	# Raw peaks: track 0 amp 20000 → 0.610, track 1 amp 800 → 0.024 (over full-scale).
	_assert_true(absf(float(res.get("a_peak")) - 20000.0 / 32767.0) < 0.001,
			"track 0 reports its absolute (un-normalized) raw peak")
	_assert_true(absf(float(res.get("b_peak")) - 800.0 / 32767.0) < 0.001,
			"track 1 reports its absolute (un-normalized) raw peak")
	# The quiet track reads silent-in-isolation; the loud one does not — the picture
	# stops lying about a shared-normalized floor swell.
	_assert_false(GP.is_silent_in_isolation(float(res.get("a_peak"))),
			"the loud track is not silent in isolation")
	_assert_true(GP.is_silent_in_isolation(float(res.get("b_peak"))),
			"the quiet track is silent in isolation")
	# The E001 track A exemplar (raw peak 0.0117) reads silent; a real swell (0.25) does not.
	_assert_true(GP.is_silent_in_isolation(0.0117),
			"E001 track A's raw peak 0.0117 reads silent in isolation (the display fix)")
	_assert_false(GP.is_silent_in_isolation(0.25), "a genuine swell (0.25) is not silent in isolation")


## Slice H (display): the panel's per-track energy band carries the ABSOLUTE raw peak
## and the "silent in isolation" flag, so a track whose shared-normalized swell fills the
## band but whose raw peak is a floor can still be read as silent. Display-only — the
## band never feeds the verdict.
func _test_energy_band_shows_absolute_silent_in_isolation_marker() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var axis = Axis.new()
	axis.configure(Panel.GUTTER_W + Panel.PAD_X, 10.0)
	var view: Dictionary = PairModel.pair_view(_make_bank(), 0, {}, null)
	# Track 0: a full-height NORMALIZED swell, but a floor RAW peak (the lie to catch).
	(view.get("tracks", [])[0] as Dictionary)["energy"] = PackedFloat32Array([0.0, 0.5, 1.0, 0.6])
	(view.get("tracks", [])[0] as Dictionary)["energy_raw_peak"] = 0.0117
	(view.get("tracks", [])[1] as Dictionary)["energy"] = PackedFloat32Array([0.0, 0.5, 1.0])
	(view.get("tracks", [])[1] as Dictionary)["energy_raw_peak"] = 0.6
	var lay: Dictionary = Panel.layout(view, 900.0, {}, axis, {"frame": 0, "source": "first"})
	var b0: Dictionary = _band_for(lay.get("energy_bands", []), 0)
	var b1: Dictionary = _band_for(lay.get("energy_bands", []), 1)
	_assert_true(bool(b0.get("silent_in_isolation")),
			"a full-height normalized swell over a floor raw peak is flagged silent in isolation")
	_assert_false(bool(b1.get("silent_in_isolation")),
			"a track with a real raw peak is not flagged")
	_assert_true(absf(float(b0.get("raw_peak")) - 0.0117) < 1e-4,
			"the band carries the absolute raw peak for the display tell")


# Empty-track-A fixture: track A (offset 30) is a zero-byte track (its offset sits at
# end-of-data), track B (offset 28) = D2 08. Decoding track A yields no events.
func _make_empty_track_a_bank():
	var blob := PackedByteArray()
	blob.append_array("feds".to_ascii_buffer())
	blob.append_array([30, 0, 0, 0])                   # data_size = 30
	blob.append_array([2, 0])
	blob.append_array([7, 0])
	blob.append_array([28, 0, 0, 0])
	blob.append_array([0, 0, 0, 0, 0, 0, 0, 0])
	blob.append_array([30, 0, 28, 0])                  # track A @30 (empty), track B @28
	blob.append_array([0xD2, 0x08])                    # track B @28 (2 bytes → data ends @30)
	return FedsBankScript.parse(blob)


## Slice 1 (ADR-0085 2026-08-12 §1): opening a pair LANDS ON THE CODE — the panel
## auto-selects track A's first event so the inspector/panel open on it, never on an
## empty overview the author must click again to leave. Always track A, no stub
## fallthrough; a same-pair re-derive keeps the live selection; a genuinely empty
## track A falls back to the overview.
func _test_panel_auto_selects_track_a_first_event() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var panel = Panel.new()
	panel.set_view(PairModel.pair_view(_make_bank(), 0, {}, null))
	_assert_eq(panel.selected_event(), {"track": 0, "event_index": 0},
			"opening a pair auto-selects track A's first event (event_index 0)")
	# A same-pair re-derive keeps the author's live selection — never re-seeds to 0.
	panel._selected = {"track": 0, "event_index": 3}
	panel.set_view(PairModel.pair_view(_make_bank(), 0, {}, null))
	_assert_eq(panel.selected_event(), {"track": 0, "event_index": 3},
			"a same-pair re-derive keeps the live selection")
	panel.free()
	# A genuinely empty track A → overview (fresh panel so the bank is a new pair).
	var panel2 = Panel.new()
	panel2.set_view(PairModel.pair_view(_make_empty_track_a_bank(), 0, {}, null))
	_assert_eq(panel2.selected_event(), {},
			"empty track A falls back to the overview (no event auto-selected)")
	panel2.free()


## Slice 1 (§1): a sound-trigger click LANDS DEEP on its pair — the nav seeds the full
## [span → container → pair] trail (container + trigger stay breadcrumb crumbs, one
## click to step back) and the panel opens on track A's first event, replacing the
## 4-click step-in drill onto an empty overview. A non-resolving span stays a plain root.
func _test_page_trigger_click_lands_on_pair_code() -> void:
	var ed = EffectDataClass.new()
	ed.sound_containers = {"containers": [
		{"index": 0, "mode": 0, "id_a": 1, "id_b": 0, "id_c": 0}]}
	ed.sound = {"phase1": [
		{"channel_index": 0, "max_keyframe": 1,
			"keyframes": [{"sound_id": 2, "duration_frames": 10}]}]}
	var page = Page.new()
	add_child(page)
	await get_tree().process_frame
	page._effect_data = ed
	page._sound_env = {"feds_bank": _make_loop_bank(), "sound_containers": ed.sound_containers}
	page._pair_views = page._compute_pair_views()
	page._timeline.load_score(page._build_score())

	page._on_span_selected("sound:phase1:0#0")
	_assert_eq(page._nav.size(), 3, "trigger click seeds span → container → pair")
	if page._nav.size() == 3:
		_assert_eq(Target.kind(page._nav[0]), "span", "the trigger span leads the trail")
		_assert_eq(page._nav[1], Target.container(0), "the resolving container is the middle crumb")
		_assert_eq(page._nav[2], Target.pair(0), "the pair is the landing target")
	_assert_eq(page._pair_panel.selected_event(), {"track": 0, "event_index": 0},
			"the pair opens auto-selected on track A's first event (land on the code)")
	_assert_eq(page._pair_panel.visible, true, "the pair lane panel is shown")

	# A non-sound span never deep-seeds — it stays a single-entry span root.
	page._on_span_selected("particle:phase1:0#0")
	_assert_eq(page._nav.size(), 1, "a non-sound span stays a plain span root (no deep seed)")
	_assert_eq(Target.kind(page._nav[0]), "span", "…the span itself")

	page.queue_free()
	await get_tree().process_frame


# === Per-instrument empirical usage range (ADR-0085 2026-08-12 amendment) =====
# The empirical range is ALSO bucketed by the ACTIVE INSTRUMENT (the last 0xAC
# earlier in the SAME track). The reader/semantics gain a conditional lookup, the
# projector resolves the active instrument and attaches BOTH ranges, and the cell
# renders a second line with n-adaptive wording + a gated, distinct tell. All
# corpus literals are the hand-verified truth from test_feds_param_stats_drift.py.

## Slice 2 — reader: the shared table's per-instrument bucket is readable by id.
func _test_param_stats_bucket_by_instrument() -> void:
	var Stats = load("res://src/effects/studio/FedsParamStats.gd")
	# 0xD3 under instrument 119 — the hand-verified conditional bucket ([-2,1,1,1]).
	var b: Dictionary = Stats.of_instrument(0xD3, 0, 119)
	_assert_eq(int(b.get("n", 0)), 4, "0xD3 under instrument 119 has 4 samples")
	_assert_eq(int(b.get("min", 99)), -2, "conditional signed-space min")
	_assert_eq(int(b.get("max", 99)), 1, "conditional max")
	_assert_eq(int(b.get("median", 99)), 1, "conditional median")
	# An instrument that never used this param → empty (state b is decided upstream).
	_assert_eq(Stats.of_instrument(0xD3, 0, 999), {}, "an unused instrument bucket is empty")
	# No active instrument (id < 0) → empty (the global line stands alone).
	_assert_eq(Stats.of_instrument(0xD3, 0, -1), {}, "no active instrument → empty bucket")


## Slice 2 — semantics: usage_range grows an optional instrument_id; the global
## call is unchanged, an instrument returns the conditional range (or {} when the
## bucket is empty, so the caller can render the honest "none with X" state).
func _test_usage_range_conditions_on_instrument() -> void:
	var Sem = load("res://src/effects/studio/FedsParamSemantics.gd")
	var g: Dictionary = Sem.usage_range(0xD3, 0)
	_assert_eq(int(g.get("n", 0)), 15, "the global range still spans the whole corpus")
	var c: Dictionary = Sem.usage_range(0xD3, 0, 119)
	_assert_eq(int(c.get("n", 0)), 4, "an instrument-conditional range narrows to its bucket")
	_assert_eq(int(c.get("min", 99)), -2, "conditional min")
	_assert_eq(int(c.get("median", 99)), 1, "conditional median")
	_assert_eq(Sem.usage_range(0xD3, 0, 999), {},
			"an unused instrument → empty conditional range (state b upstream)")


# Per-instrument fixture: track A = AC <inst> | D3 FF FE (PitchBend16 −2) | 90;
# track B = D3 FF FE | 90 (NO instrument → state a). The active instrument for the
# track-A D3 is the preceding 0xAC's value; track-B's D3 has none. Offsets are
# blob-absolute (header 0x18 + 2×2 table = tracks at 28, 34).
func _make_instrument_ctx_bank(inst_byte: int):
	var blob := PackedByteArray()
	blob.append_array("feds".to_ascii_buffer())
	blob.append_array([38, 0, 0, 0])
	blob.append_array([2, 0])
	blob.append_array([7, 0])
	blob.append_array([28, 0, 0, 0])
	blob.append_array([0, 0, 0, 0, 0, 0, 0, 0])
	blob.append_array([28, 0, 34, 0])
	blob.append_array([0xAC, inst_byte, 0xD3, 0xFF, 0xFE, 0x90])   # track A @28
	blob.append_array([0xD3, 0xFF, 0xFE, 0x90])                    # track B @34
	return FedsBankScript.parse(blob)


func _instrument_ctx_score(inst_byte: int) -> Dictionary:
	return {"feds_pairs": [PairModel.pair_view(_make_instrument_ctx_bank(inst_byte), 0, {}, null)]}


## Slice 3 — projector STATE (c): with an instrument active (the last in-track 0xAC),
## the range-bearing cell attaches BOTH the global range and an instrument-conditional
## one, named by its DAW id. Instrument 119 used 0xD3 four times ([-2,1,1,1]).
func _test_projector_attaches_instrument_range_when_active() -> void:
	var by_name := _select_event(_instrument_ctx_score(119), 0, 1)   # the D3 word cell
	var w: Dictionary = by_name.values()[0] if not by_name.is_empty() else {}
	# The global range is unchanged (the whole corpus).
	_assert_eq(int(w.get("range", {}).get("n", 0)), 15, "the global range still spans the corpus")
	# The instrument-conditional range narrows to instrument 119's bucket.
	var ri: Dictionary = w.get("range_instrument", {})
	_assert_eq(int(ri.get("id", -1)), 119, "the conditional range is tagged with the active instrument id")
	_assert_eq(int(ri.get("n", 0)), 4, "instrument 119 used 0xD3 four times")
	_assert_eq(int(ri.get("min", 99)), -2, "conditional signed-space min")
	_assert_eq(int(ri.get("max", 99)), 1, "conditional max")
	_assert_true(not bool(ri.get("empty", false)), "a populated bucket is not the empty state")
	_assert_true(str(ri.get("name", "")).length() > 0, "the conditional range names the instrument")


## Slice 3 — projector STATES (a) and (b): with NO 0xAC preceding, the cell shows the
## global range ALONE (no range_instrument). With an instrument active whose corpus has
## ZERO samples of this param (instrument 5 never used 0xD3), a DISTINCT empty-bucket
## marker rides the cell — the honest "none with X" counterpart, not silence.
func _test_projector_marks_empty_bucket_and_no_instrument_states() -> void:
	# State (a): track B's D3 has no preceding instrument.
	var a := _select_event(_instrument_ctx_score(119), 1, 0)
	var wa: Dictionary = a.values()[0] if not a.is_empty() else {}
	_assert_true(wa.has("range"), "the no-instrument cell still shows the global range")
	_assert_true(not wa.has("range_instrument"), "…but carries NO per-instrument line (state a)")
	# State (b): instrument 5 is active but never used 0xD3 → explicit empty bucket.
	var b := _select_event(_instrument_ctx_score(5), 0, 1)
	var wb: Dictionary = b.values()[0] if not b.is_empty() else {}
	var ri: Dictionary = wb.get("range_instrument", {})
	_assert_eq(int(ri.get("id", -1)), 5, "the empty-bucket marker still names the active instrument")
	_assert_true(bool(ri.get("empty", false)), "instrument 5 never used 0xD3 → the empty-bucket state")
	_assert_true(str(ri.get("name", "")).length() > 0, "the empty state still names the instrument")


# Build an inspector showing ONE int cell and return it (the caller frees it).
func _single_cell_inspector(cell: Dictionary):
	var Inspector = load("res://src/effects/studio/EffectKeyframeInspector.gd")
	var insp = Inspector.new()
	add_child(insp)
	insp.show_target(Target.pair(0), [], [{"title": "Event", "fields": [cell]}],
		func(_i): return [], func(_a, _b): pass, func(_t): pass,
		func(_p, _e): return false, func(_p, _e, _s): pass,
		func(_r, _raw): pass,
		func(_refs, _col): return Color.BLACK)
	return insp


## Slice 4 — the cell renders a SECOND (instrument-conditional) line beside the global
## one, with n-adaptive wording (n≥2 → a range; n=1 → "seen once at X", never a dressed-up
## range) and an explicit "none with X" line for the empty-bucket state. Corpus values here
## are synthetic (the cell UI is under test, not the corpus).
func _test_cell_renders_instrument_line_n_adaptive_and_empty_bucket() -> void:
	var ref := {"channel": "sound_def", "kind": "byte", "offset": 30, "pair_idx": 0}
	# n≥2 populated bucket: the global baseline AND a narrower instrument line.
	var cell := {"name": "Glide rate", "shape": "edit", "editor": "int", "type": "u8",
			"value": 8, "range": {"min": 0, "max": 255, "median": 200, "n": 3000},
			"range_instrument": {"id": 64, "name": "Timpani (64)",
					"min": 2, "max": 40, "median": 8, "n": 47}, "field_ref": ref}
	var insp = _single_cell_inspector(cell)
	var g: Array = insp.range_hints()
	var inst: Array = insp.range_instrument_hints()
	_assert_eq(g.size(), 1, "the global baseline line still renders")
	_assert_eq(inst.size(), 1, "a populated instrument bucket adds a second line")
	if not g.is_empty():
		_assert_true("all" in str(g[0].text), "the global line is marked as the (all) baseline")
	if not inst.is_empty():
		var t: String = str(inst[0].text)
		_assert_true("Timpani (64)" in t, "the instrument line names the active instrument")
		_assert_true("2…40" in t and "median 8" in t and "n=47" in t,
				"…and shows its conditional range, median, and sample count")
	insp.free()
	# n=1: a single sample is worded "seen once at X", never as a range.
	var one := {"name": "Glide rate", "shape": "edit", "editor": "int", "type": "u8",
			"value": 8, "range": {"min": 0, "max": 255, "median": 200, "n": 3000},
			"range_instrument": {"id": 64, "name": "Timpani (64)",
					"min": 8, "max": 8, "median": 8, "n": 1}, "field_ref": ref}
	var insp1 = _single_cell_inspector(one)
	var t1: String = str(insp1.range_instrument_hints()[0].text)
	_assert_true("seen once at 8" in t1, "n=1 is worded 'seen once at X', not a range")
	_assert_true(not ("…" in t1), "a single sample is never dressed as a min…max range")
	insp1.free()
	# Empty bucket (state b): a distinct 'none with X' line, NOT silence.
	var empty := {"name": "Glide rate", "shape": "edit", "editor": "int", "type": "u8",
			"value": 8, "range": {"min": 0, "max": 255, "median": 200, "n": 3000},
			"range_instrument": {"id": 64, "name": "Timpani (64)", "empty": true},
			"field_ref": ref}
	var inspE = _single_cell_inspector(empty)
	var tE: String = str(inspE.range_instrument_hints()[0].text)
	_assert_true("none with Timpani (64)" in tE, "the empty-bucket state says 'none with X'")
	inspE.free()


## Slice 4 — the out-of-corpus tell distinguishes WHICH envelope was left, and the
## instrument tell is GATED at n≥8. Leaving global fires the loud "outside corpus";
## leaving only the instrument envelope (bucket n≥8) fires a distinct, milder "unusual
## for X"; a small (n<8) bucket never drives the alarm; and outside-global takes
## precedence over an instrument-only miss.
func _test_cell_instrument_tell_is_gated_and_distinct() -> void:
	var ref := {"channel": "sound_def", "kind": "byte", "offset": 30, "pair_idx": 0}
	# A confident bucket (n≥8) inside a wide global range.
	var cell := {"name": "Glide rate", "shape": "edit", "editor": "int", "type": "u8",
			"value": 8, "range": {"min": 0, "max": 255, "median": 200, "n": 3000},
			"range_instrument": {"id": 64, "name": "Timpani (64)",
					"min": 2, "max": 40, "median": 8, "n": 47}, "field_ref": ref}
	var insp = _single_cell_inspector(cell)
	var g: Label = insp.range_hints()[0]
	var inst: Label = insp.range_instrument_hints()[0]
	var sb = insp.int_widgets()[0]
	# Inside both envelopes: no tell anywhere.
	_assert_true(not ("unusual" in str(inst.text)) and not ("outside" in str(g.text).to_lower()),
			"a value inside both envelopes fires no tell")
	# Inside global, OUTSIDE the instrument envelope → milder distinct 'unusual for X'.
	sb.value = 100
	_assert_true("unusual for Timpani (64)" in str(inst.text),
			"leaving only the instrument envelope fires the milder tell")
	_assert_true("2…40" in str(inst.text), "…and states the instrument's own envelope")
	_assert_true(not ("outside corpus" in str(inst.text).to_lower()),
			"the milder tell does NOT claim 'outside corpus' (the value IS precedented)")
	_assert_true(not ("outside" in str(g.text).to_lower()),
			"…and the global line stays its plain baseline (100 is inside 0…255)")
	insp.free()
	# OUTSIDE global too → the loud tell wins; the instrument line does not also blare.
	# A wider s16 case so the value can truly exceed the global envelope.
	var wide := {"name": "Pitch bend add (16-bit)", "shape": "edit", "editor": "int", "type": "s16",
			"value": 0, "range": {"min": -50, "max": 50, "median": 0, "n": 3000},
			"range_instrument": {"id": 64, "name": "Timpani (64)",
					"min": -5, "max": 5, "median": 0, "n": 47}, "field_ref": ref}
	var insp2 = _single_cell_inspector(wide)
	var g2: Label = insp2.range_hints()[0]
	var inst2: Label = insp2.range_instrument_hints()[0]
	insp2.int_widgets()[0].value = 200   # outside BOTH envelopes
	_assert_true("outside corpus" in str(g2.text).to_lower(), "leaving global fires the loud tell")
	_assert_true(not ("unusual" in str(inst2.text)),
			"outside-global takes precedence — no second amber blare on the instrument line")
	insp2.free()
	# Gating: a SMALL bucket (n<8) never drives the tell (a single-sample bucket would
	# flag every value). Leaving its envelope shows NO 'unusual' alarm.
	var small := {"name": "Glide rate", "shape": "edit", "editor": "int", "type": "u8",
			"value": 8, "range": {"min": 0, "max": 255, "median": 200, "n": 3000},
			"range_instrument": {"id": 64, "name": "Timpani (64)",
					"min": 2, "max": 40, "median": 8, "n": 4}, "field_ref": ref}
	var insp3 = _single_cell_inspector(small)
	insp3.int_widgets()[0].value = 100   # outside the flimsy bucket, inside global
	_assert_true(not ("unusual" in str(insp3.range_instrument_hints()[0].text)),
			"an n<8 bucket is too flimsy to drive the amber tell")
	insp3.free()


# --- No-op prune A/B (ADR-0085 2026-08-12 amendment) ------------------------

## Slice 1 (pure transform): a `Muted` note becomes an equal-duration `0x80 Rest`, an
## `Inert` NOP is DELETED, and every other byte is re-emitted identically. Verdicts drive
## the prune — a note is one muted OPCODE, not a hardcoded special case.
##
## ADR-0085 2026-08-18c §1: the substitute is `0x80`, the form FFT actually writes
## (87,793 times), NOT the note-form rest the prune used to invent — which appears
## nowhere in the corpus, music or effects. So the studio has exactly ONE rest.
func _test_prune_substitutes_muted_note_deletes_inert_keeps_the_rest() -> void:
	var V = load("res://src/effects/studio/FedsOpcodeVerdicts.gd")
	# AC 05 (audible) | 60 0C (Live note) | AC 01 (Empty) | 60 0C (Muted note) | 82 (Inert) | 90
	var a := PackedByteArray([0xAC, 0x05, 0x60, 0x0C, 0xAC, 0x01, 0x60, 0x0C, 0x82, 0x90])
	var bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var tv: Dictionary = PairModel.pair_view(bank, 0, {}, null).get("tracks", [])[0]
	var vd: Dictionary = V.verdicts(tv)
	# Fixture sanity: the verdicts really are Muted (ei3) and Inert (ei4).
	_assert_eq(str(vd.get("per_event", {}).get(3)), V.MUTED, "fixture: the empty-instrument note is Muted")
	_assert_eq(str(vd.get("per_event", {}).get(4)), V.INERT, "fixture: the NOP is Inert")
	var pruned: PackedByteArray = NoOpPrune.prune_track(bank.get_track_bytes(0), vd)
	# The muted note → `80 0C`; the Inert 0x82 gone; everything else identical. The
	# 2-byte table-form note substitutes at the SAME size — a note is `vv dd`, a rest
	# is `80 pp`, so delete essentially never relocates (§4).
	_assert_eq(pruned, PackedByteArray([0xAC, 0x05, 0x60, 0x0C, 0xAC, 0x01, 0x80, 0x0C, 0x90]),
			"muted note → equal-duration 0x80 Rest, Inert NOP deleted, all other bytes identical")
	_assert_true(pruned.find(0x82) == -1, "the Inert NOP is pruned out")
	_assert_eq(pruned.size(), a.size() - 1, "a table-form note substitutes same-size; only the NOP shrinks the blob")
	# It decodes as `0x80 Rest` carrying the note's delta_time (the clock is preserved).
	var pe: Array = SMD.decode_track(pruned)
	_assert_true(not (pe[3] is SMD.NoteEvent) and int(pe[3].opcode) == 0x80,
			"the muted slot decodes as the corpus's rest — 0x80, never relative_key 13")
	_assert_eq(int(pe[3].params[0]), 12, "the rest carries the note's delta_time")
	# The form the prune used to invent appears NOWHERE in the output.
	for ev in pe:
		_assert_false(ev is SMD.NoteEvent and ev.is_rest(),
				"the prune never emits a note-form rest — FFT writes zero of them")
	# The audible (Live) note at ei1 is byte-identical — un-pruned events never change.
	_assert_true(pe[1] is SMD.NoteEvent and pe[1].is_note() and int(pe[1].delta_time) == 12,
			"the audible Live note is left untouched")


## Slice 1: the prune preserves the folded tick clock, and the HARD exclusions
## (instrument 0xAC, structural/flow, and `Pre-arm`) are byte-identical regardless of
## verdict — only the no-ops move.
func _test_prune_keeps_total_ticks_and_hard_exclusions() -> void:
	var V = load("res://src/effects/studio/FedsOpcodeVerdicts.gd")
	# E0 40 (Dynamics, before first note → Pre-arm) | AC 05 (audible) | 60 0C (Live) |
	# AC 01 (Empty) | 60 0C (Muted) | 82 (Inert) | 98 02 (Repeat) | 99 (Coda) | 90
	var a := PackedByteArray([0xE0, 0x40, 0xAC, 0x05, 0x60, 0x0C, 0xAC, 0x01,
			0x60, 0x0C, 0x82, 0x98, 0x02, 0x99, 0x90])
	var bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var tv: Dictionary = PairModel.pair_view(bank, 0, {}, null).get("tracks", [])[0]
	var vd: Dictionary = V.verdicts(tv)
	_assert_eq(str(vd.get("per_event", {}).get(0)), V.PREARM, "fixture: the Dynamics write is Pre-arm")
	var pruned: PackedByteArray = NoOpPrune.prune_track(bank.get_track_bytes(0), vd)
	_assert_eq(pruned, PackedByteArray([0xE0, 0x40, 0xAC, 0x05, 0x60, 0x0C, 0xAC, 0x01,
			0x80, 0x0C, 0x98, 0x02, 0x99, 0x90]),
			"Pre-arm + instrument + structural stay byte-identical; only the no-ops move")
	_assert_true(pruned.find(0x82) == -1, "the Inert NOP is pruned")
	# The folded tick clock is unchanged (the rest replaces the muted note tick-for-tick).
	var orig_end: int = int(PairModel.pair_view(bank, 0, {}, null).get("tracks", [])[0].get("end_tick"))
	var pruned_end: int = int(PairModel.pair_view(_make_feds_bank(pruned, PackedByteArray([0x90])),
			0, {}, null).get("tracks", [])[0].get("end_tick"))
	_assert_eq(pruned_end, orig_end, "the prune preserves the folded tick clock")


## Slice 1: because the byte STREAM is edited (never a flattened event list), a pruned
## note inside a Repeat…Coda loop becomes a rest ONCE and the loop replays that rest
## every iteration — the loop bracket and its ×N count survive intact.
func _test_prune_loop_interior_muted_note_rests_every_iteration() -> void:
	var V = load("res://src/effects/studio/FedsOpcodeVerdicts.gd")
	# AC 01 (Empty) | 98 03 (Repeat ×3) | 60 0C (Muted note INSIDE the loop) | 99 | 90
	var a := PackedByteArray([0xAC, 0x01, 0x98, 0x03, 0x60, 0x0C, 0x99, 0x90])
	var bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var tv: Dictionary = PairModel.pair_view(bank, 0, {}, null).get("tracks", [])[0]
	var vd: Dictionary = V.verdicts(tv)
	var pruned: PackedByteArray = NoOpPrune.prune_track(bank.get_track_bytes(0), vd)
	var pe: Array = SMD.decode_track(pruned)
	_assert_eq(int(pe[1].opcode), 0x98, "the Repeat opcode survives the prune")
	_assert_eq(int(pe[1].params[0]), 3, "…with its ×3 count intact (the rest replays every iteration)")
	_assert_true(not (pe[2] is SMD.NoteEvent) and int(pe[2].opcode) == 0x80,
			"the loop-interior muted note is now a 0x80 Rest")
	_assert_eq(int(pe[3].opcode), 0x99, "…still bracketed by the Coda (it sits inside the loop body)")
	# The loop clock is unchanged (folded end tick identical before/after).
	var orig_end: int = int(PairModel.pair_view(bank, 0, {}, null).get("tracks", [])[0].get("end_tick"))
	var pruned_end: int = int(PairModel.pair_view(_make_feds_bank(pruned, PackedByteArray([0x90])),
			0, {}, null).get("tracks", [])[0].get("end_tick"))
	_assert_eq(pruned_end, orig_end, "the loop clock is preserved (a rest every iteration)")


## Slice 2 (projector): energy_diff reports max per-frame |Δ| and the change-in-loudness
## peak Δ, on a COMMON untrimmed length (the shorter render zero-extended, so the tail
## where the baseline still sounds is not silently dropped).
func _test_energy_diff_max_abs_and_peak_on_common_untrimmed_length() -> void:
	var GP = load("res://src/effects/studio/SoundGhostProjector.gd")
	var base := PackedFloat32Array([0.10, 0.20, 0.30, 0.05])
	var pruned := PackedFloat32Array([0.10, 0.18, 0.30])
	var d: Dictionary = GP.energy_diff(base, pruned)
	_assert_true(absf(float(d.get("max_abs")) - 0.05) < 1e-6,
			"max per-frame |Δ| catches the untrimmed tail (base 0.05 vs pruned 0)")
	_assert_true(absf(float(d.get("peak_delta"))) < 1e-6,
			"peak Δ is the change in overall loudness (0.30 vs 0.30 → 0)")
	_assert_eq(int(d.get("length")), 4, "the diff runs to the common (max) untrimmed length")
	# A bit-identical prune → Δ = 0 exactly (the deterministic-render guarantee).
	var same: Dictionary = GP.energy_diff(base, base)
	_assert_true(absf(float(same.get("max_abs"))) < 1e-9, "identical envelopes → Δ = 0 exactly")


## Slice 2: the three tiers come straight off the a-priori SoundGhostProjector constants
## (chosen before any result), never fitted — Δ < SILENCE_RMS inert, < ABSOLUTE_QUIET
## faint, else changed. E001's 0.0117 floor lands amber "faint" — the honest read.
func _test_noop_verdict_tiers_off_the_a_priori_constants() -> void:
	var GP = load("res://src/effects/studio/SoundGhostProjector.gd")
	_assert_eq(GP.noop_verdict_tier(0.0), GP.NOOP_INERT, "Δ 0 → inert ✓")
	_assert_eq(GP.noop_verdict_tier(GP.SILENCE_RMS - 0.0001), GP.NOOP_INERT, "just below SILENCE_RMS → inert")
	_assert_eq(GP.noop_verdict_tier(GP.SILENCE_RMS), GP.NOOP_FAINT, "at SILENCE_RMS → faint ≈")
	_assert_eq(GP.noop_verdict_tier(0.0117), GP.NOOP_FAINT, "E001's 0.0117 floor → faint ≈ (the honest answer)")
	_assert_eq(GP.noop_verdict_tier(GP.ABSOLUTE_QUIET), GP.NOOP_CHANGED, "at ABSOLUTE_QUIET → changed ✗")
	_assert_eq(GP.noop_verdict_tier(0.2), GP.NOOP_CHANGED, "a loud Δ → changed ✗ (classifier over-claimed)")


## Slice 2: render_pair_pruning_noops builds a TRANSIENT bank whose target track has its
## no-ops pruned, renders the MIXED pair (single_track -1), and never mutates the original
## bank — the un-pruned sibling track is byte-identical so it cancels in the Δ.
func _test_render_pair_pruning_noops_builds_a_transient_pruned_bank() -> void:
	var GP = load("res://src/effects/studio/SoundGhostProjector.gd")
	var eng = _RecordingPruneEngine.new()
	var bank = _make_verdict_bank()   # track A carries a 0x82 Inert NOP @ ei3
	var res: Dictionary = GP.render_pair_pruning_noops(eng, bank, 0, 2, 0)
	_assert_eq(eng.last_single_track, -1,
			"the no-op A/B renders the MIXED pair (single_track -1), never an isolated voice")
	_assert_true(eng.last_bank != null and eng.last_bank != bank,
			"it renders a TRANSIENT bank, not the original")
	_assert_true(eng.last_bank.get_track_bytes(0).find(0x82) == -1,
			"the transient bank's track A dropped the Inert NOP")
	_assert_true(bank.get_track_bytes(0).find(0x82) != -1,
			"the ORIGINAL bank is unmodified (proof-only, never mutated)")
	_assert_eq(eng.last_bank.get_track_bytes(1), bank.get_track_bytes(1),
			"the un-pruned track B is byte-identical (it cancels in the Δ)")
	_assert_true((res.get("energy") as PackedFloat32Array).size() >= 1,
			"the render returns a raw envelope to diff against the baseline")


## Orchestration: one press = the baseline rendered ONCE and reused for 4 MIXED renders
## total (baseline + track-A-pruned + track-B-pruned + both-pruned), each track's Δ read off
## the full mix and tiered off the a-priori constants. Driven by a SCRIPTED engine so the
## envelopes are controlled and the attribution + tiers are asserted, not the SPU.
func _test_noop_ab_runs_four_mixed_renders_and_attributes_per_track() -> void:
	var GP = load("res://src/effects/studio/SoundGhostProjector.gd")
	var eng = _ScriptedEngine.new()
	eng._queue = [
		PackedFloat32Array([0.10, 0.10, 0.10]),   # baseline (mixed) — rendered ONCE
		PackedFloat32Array([0.10, 0.08, 0.10]),   # track-A pruned → faint Δ ≈ 0.02
		PackedFloat32Array([0.10, 0.10, 0.10]),   # track-B pruned → identical → inert Δ 0
		PackedFloat32Array([0.10, 0.08, 0.10]),   # both-pruned → the joint overlay
	]
	var res: Dictionary = GP.noop_ab(eng, _make_verdict_bank(), 0, 2)
	_assert_eq(eng.calls, [-1, -1, -1, -1],
			"baseline reused → 4 MIXED renders (baseline + A + B + both), never 5, never isolated")
	var ta: Dictionary = res.get(0, {})
	var tb: Dictionary = res.get(1, {})
	_assert_eq(str(ta.get("tier")), GP.NOOP_FAINT, "track A's no-ops leak a faint Δ")
	_assert_true(absf(float(ta.get("max_abs")) - 0.02) < 1e-3, "…the measured Δ ≈ 0.02, not fitted")
	_assert_eq(str(tb.get("tier")), GP.NOOP_INERT, "track B's no-ops are inert (its pruned mix is bit-identical)")
	_assert_true(absf(float(tb.get("max_abs"))) < 1e-9, "…Δ = 0 exactly (attribution: only A moved)")
	_assert_true(res.has("joint"), "the same call carries the joint overlay (no extra baseline render)")


## Slice 3 (panel): once a track has an A/B result, the layout carries a per-track verdict
## row reading the tier glyph + the raw Δ. (The trigger is the inspector's '▶ Audition
## (no-ops pruned)' action, beside '▶ Audition pair' — see the projector test.)
func _test_panel_layout_places_per_track_tell() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var view: Dictionary = PairModel.pair_view(_make_bank(), 0, {}, null)
	(view.get("tracks", [])[0] as Dictionary)["noop_ab"] = {"tier": "faint", "max_abs": 0.0123}
	var lay: Dictionary = Panel.layout(view, 900.0, {})
	var tells: Array = lay.get("noop_tells", [])
	_assert_eq(tells.size(), 1, "one per-track tell for the track that ran the A/B")
	if tells.size() == 1:
		_assert_eq(int(tells[0].get("track")), 0, "the tell is attributed to its track")
		_assert_eq(str((tells[0].get("tell", {}) as Dictionary).get("tier")), "faint",
				"…carrying its measured tier")
		var txt: String = Panel._noop_tell_text(tells[0].get("tell", {}))
		_assert_true("faint" in txt and "≈" in txt and "Δ0.0123" in txt,
				"the tell reads the tier, its glyph, and the RAW Δ number")
	# A track with no A/B result draws no tell row (present only after the audition runs).
	var bare: Dictionary = Panel.layout(PairModel.pair_view(_make_bank(), 0, {}, null), 900.0, {})
	_assert_eq((bare.get("noop_tells", []) as Array).size(), 0, "no tell until the author runs the A/B")


## Slice 3 (page): the cached A/B tells inject onto the open pair view's two tracks, and a
## FEDS byte edit invalidates the cached proof (its bytes changed → the old Δ is stale).
func _test_page_injects_and_invalidates_noop_ab_tells() -> void:
	var page = Page.new()
	var v := {"pair_idx": 0, "valid": true,
			"tracks": [{"notes": []}, {"notes": []}]}
	page._pair_views = [v]
	page._pair_noop_ab_cache = {0: {
		0: {"tier": "faint", "max_abs": 0.012},
		1: {"tier": "inert", "max_abs": 0.0}}}
	page._inject_noop_ab(0, v)
	_assert_eq(str(((v.get("tracks", [])[0] as Dictionary).get("noop_ab", {}) as Dictionary).get("tier")),
			"faint", "the A/B tell rides track A's view")
	_assert_eq(str(((v.get("tracks", [])[1] as Dictionary).get("noop_ab", {}) as Dictionary).get("tier")),
			"inert", "…and track B's")
	page._invalidate_noop_ab(0)
	_assert_false(page._pair_noop_ab_cache.has(0), "a FEDS edit invalidates the pair's cached A/B proof")
	page.free()


## Slice 1 (audible audition support): build_pruned_bank prunes ONLY the named local tracks,
## composing the per-track splices, and never mutates the original.
func _test_build_pruned_bank_prunes_the_named_tracks_only() -> void:
	var GP = load("res://src/effects/studio/SoundGhostProjector.gd")
	var bank = _make_verdict_bank()   # track A has a 0x82 Inert; track B stub, no no-ops
	var both = GP.build_pruned_bank(bank, 0, [0, 1])
	_assert_true(both != null and both != bank, "builds a transient both-tracks-pruned bank")
	if both == null:
		return
	_assert_true(both.get_track_bytes(0).find(0x82) == -1, "both-prune drops track A's Inert NOP")
	_assert_eq(both.get_track_bytes(1), bank.get_track_bytes(1), "track B (no no-ops) is byte-identical")
	_assert_true(bank.get_track_bytes(0).find(0x82) != -1, "the original bank is never mutated")
	var only_a = GP.build_pruned_bank(bank, 0, [0])
	_assert_true(only_a != null and only_a.get_track_bytes(0).find(0x82) == -1, "[0] prunes only track A")


## Slice 2 support (joint waveform): render_pair_mixed_energy renders BOTH voices together
## (single_track -1) and peak-normalizes to fill the band, carrying the raw mix peak.
func _test_render_pair_mixed_energy_is_the_joint_normalized_envelope() -> void:
	var GP = load("res://src/effects/studio/SoundGhostProjector.gd")
	var eng = _ScriptedEngine.new()
	eng._queue = [PackedFloat32Array([0.2, 0.4, 0.2])]
	var j: Dictionary = GP.render_pair_mixed_energy(eng, _make_bank(), 0, 1)
	_assert_eq(eng.calls, [-1], "the joint energy is the MIXED render (single_track -1)")
	var s: PackedFloat32Array = j.get("samples")
	_assert_true(_maxf_of(s) > 0.99 and _maxf_of(s) <= 1.001, "the joint waveform fills its band (peak-normalized)")
	_assert_true(absf(float(j.get("raw_peak")) - 0.4) < 1e-3, "…and carries the raw mix peak")


## The joint A/B overlay (from noop_ab's "joint") normalizes baseline AND both-pruned by the
## SAME (baseline) peak, so the visible gap between the curves IS the Δ.
func _test_noop_ab_joint_overlays_baseline_and_pruned_on_a_shared_scale() -> void:
	var GP = load("res://src/effects/studio/SoundGhostProjector.gd")
	var eng = _ScriptedEngine.new()
	eng._queue = [
		PackedFloat32Array([0.4, 0.4, 0.4]),   # baseline mix
		PackedFloat32Array([0.4, 0.4, 0.4]),   # track-A pruned (attribution, unused here)
		PackedFloat32Array([0.4, 0.4, 0.4]),   # track-B pruned
		PackedFloat32Array([0.4, 0.2, 0.4]),   # both-pruned mix (Δ 0.2 at frame 1) → joint
	]
	var j: Dictionary = GP.noop_ab(eng, _make_verdict_bank(), 0, 2).get("joint", {})
	var base: PackedFloat32Array = j.get("baseline")
	var pruned: PackedFloat32Array = j.get("pruned")
	_assert_true(absf(_maxf_of(base) - 1.0) < 1e-3, "baseline fills the band (normalized by its own peak)")
	_assert_true(base[1] - pruned[1] > 0.4, "the pruned curve drops below baseline where the no-ops sounded (visible gap)")
	_assert_true(absf(float(j.get("max_abs")) - 0.2) < 1e-3, "the joint Δ is the both-tracks no-op contribution")
	_assert_eq(str(j.get("tier")), GP.NOOP_CHANGED, "a 0.2 Δ tiers changed")


## Slice 3 (panel): the pair view carries a JOINT (mixed) energy band, and once the A/B has
## run it overlays the pruned curve on the same band.
func _test_panel_draws_joint_energy_band_and_overlay() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var view: Dictionary = PairModel.pair_view(_make_bank(), 0, {}, null)
	# Baseline-only joint (as injected on pair-open).
	view["joint"] = {"baseline": PackedFloat32Array([0.0, 0.5, 1.0, 0.5]),
			"pruned": PackedFloat32Array(), "raw_peak": 0.42}
	var lay: Dictionary = Panel.layout(view, 900.0, {})
	var jb: Dictionary = lay.get("joint_band", {})
	_assert_true(not jb.is_empty(), "the panel draws a joint (mixed) energy band")
	_assert_true((jb.get("baseline_points") as PackedVector2Array).size() >= 2,
			"the joint band plots the baseline mix waveform")
	_assert_eq((jb.get("pruned_points") as PackedVector2Array).size(), 0,
			"…with no pruned overlay until the A/B runs")
	# After the A/B: baseline + pruned overlay share the band.
	view["joint"] = {"baseline": PackedFloat32Array([0.0, 0.5, 1.0, 0.5]),
			"pruned": PackedFloat32Array([0.0, 0.2, 0.4, 0.2]), "raw_peak": 0.42,
			"tier": "changed", "max_abs": 0.06}
	var lay2: Dictionary = Panel.layout(view, 900.0, {})
	var jb2: Dictionary = lay2.get("joint_band", {})
	_assert_true((jb2.get("pruned_points") as PackedVector2Array).size() >= 2,
			"once the A/B runs the pruned curve overlays the joint band")


# A scripted SPU stub: each play_pair call pops the next envelope off `_queue` and
# render_subs walks it (one Int32 sample-pair per frame == that frame's target RMS), so a
# test controls exactly what baseline / A-pruned / B-pruned each render, and records the
# single_track handed in to prove every render is the MIXED pair.
class _ScriptedEngine:
	var capture_mode := false
	var ready_ok := true
	var _queue: Array = []
	var _cur: PackedFloat32Array = PackedFloat32Array()
	var _f := 0
	var calls: Array = []
	func panic() -> void: pass
	func begin_effect() -> int: return 1
	func end_effect(_token: int) -> void: pass
	func play_pair(_token: int, _bank, _pair_idx: int, _sound_id: int,
			single_track: int = -1) -> bool:
		calls.append(single_track)
		_cur = _queue.pop_front() if not _queue.is_empty() else PackedFloat32Array()
		_f = 0
		return true
	func render_subs(_n: int) -> PackedInt32Array:
		var v: float = _cur[_f] if _f < _cur.size() else 0.0
		_f += 1
		var s := int(round(v * 32767.0))
		return PackedInt32Array([s, s])


# Records the bank + single_track handed to play_pair and emits a short burst so the
# render loop terminates — the no-op A/B mixed-render probe.
class _RecordingPruneEngine:
	var capture_mode := false
	var ready_ok := true
	var last_bank = null
	var last_single_track := -99
	var _f := 0
	func panic() -> void: pass
	func begin_effect() -> int: return 1
	func end_effect(_token: int) -> void: pass
	func play_pair(_token: int, bank, _pair_idx: int, _sound_id: int,
			single_track: int = -1) -> bool:
		last_bank = bank
		last_single_track = single_track
		_f = 0
		return true
	func render_subs(_n: int) -> PackedInt32Array:
		var amp := 6000 if _f < 3 else 0
		_f += 1
		return PackedInt32Array([amp, amp])


# --- Prune-for-real: the commit seam + snapshot undo (ADR-0085 2026-08-13) -----------
const EditSession = preload("res://src/effects/studio/EffectEditSession.gd")


## prune_feds_noops SWAPS EffectData.feds_bank to the pruned (smaller) blob — the exact bytes
## build_pruned_bank produces — and records a snapshot-undo entry that restores the ORIGINAL
## bank object byte-for-byte. The pair-scoped delete is size-changing, so it cannot ride the
## same-size sound_def patcher; it goes through its own structural verb.
func _test_prune_feds_noops_swaps_the_bank_and_undo_restores() -> void:
	var GP = load("res://src/effects/studio/SoundGhostProjector.gd")
	# Track A: audible instrument, Live note, an Inert 0x82 NOP (prunable), EndBar. Track B: EndBar
	# only (nothing to prune). So the pair delete shrinks A by exactly the 0x82 byte.
	var a := PackedByteArray([0xAC, 0x05, 0x60, 0x0C, 0x82, 0x90])
	var b := PackedByteArray([0x90])
	var ed = EffectDataClass.new()
	ed.feds_bank = _make_feds_bank(a, b)
	var orig_bank = ed.feds_bank
	var orig_raw: PackedByteArray = ed.feds_bank.raw.duplicate()
	var expected = GP.build_pruned_bank(orig_bank, 0, [0, 1])

	var session = EditSession.new(ed)
	var res: Dictionary = session.prune_feds_noops(0)
	_assert_true(bool(res.get("invalidates_feds", false)), "prune result flags invalidates_feds")
	_assert_eq(int(res.get("pair_idx", -1)), 0, "…and names the pruned pair")
	_assert_true(int(res.get("after_bytes", 0)) < int(res.get("before_bytes", 0)),
			"…and the blob shrank (an opcode was deleted)")
	_assert_true(ed.feds_bank != orig_bank, "the bank OBJECT was swapped, not mutated in place")
	_assert_eq(ed.feds_bank.raw, expected.raw, "the swapped bank is the byte-exact pruned blob")

	var undone: bool = session.undo()
	_assert_true(undone, "undo reports it unwound the delete")
	_assert_true(ed.feds_bank == orig_bank, "undo restores the ORIGINAL bank object")
	_assert_eq(ed.feds_bank.raw, orig_raw, "…byte-for-byte")


## When a pair has no prunable no-ops, prune_feds_noops is a true no-op: no swap, no undo entry
## (the button does nothing rather than pushing an empty edit onto the stack).
func _test_prune_feds_noops_is_a_noop_when_nothing_to_prune() -> void:
	# Both tracks are audible-only — a Live note + EndBar, nothing the classifier calls a no-op.
	var a := PackedByteArray([0xAC, 0x05, 0x60, 0x0C, 0x90])
	var b := PackedByteArray([0xAC, 0x05, 0x60, 0x0C, 0x90])
	var ed = EffectDataClass.new()
	ed.feds_bank = _make_feds_bank(a, b)
	var orig_bank = ed.feds_bank
	var session = EditSession.new(ed)
	var res: Dictionary = session.prune_feds_noops(0)
	_assert_true(res.is_empty(), "no prunable no-ops → empty result (no-op)")
	_assert_true(ed.feds_bank == orig_bank, "…the bank is untouched")
	_assert_false(session.undo(), "…and nothing was pushed onto the undo stack")


## The pair overview offers the destructive 'delete no-ops' commit action beside the proof-only
## '▶ Audition (no-ops pruned)' — same pair_idx, a distinct kind.
func _test_pair_overview_carries_prune_commit_action() -> void:
	var secs: Array = PairProjector.sections(Target.pair(0), null, _pair_score())
	if secs.is_empty():
		_assert_true(false, "sections empty")
		return
	var commit = null
	for f in secs[0].get("fields", []):
		if str(f.get("shape", "")) == "action" and str(f.get("action", {}).get("kind", "")) == "prune_noops_commit":
			commit = f.get("action")
	_assert_true(commit != null, "overview carries the prune-for-real commit action")
	if commit != null:
		_assert_eq(int(commit.get("pair_idx", -1)), 0, "…scoped to the open pair")


func _assert_eq(actual, expected, label: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected %s, got %s" % [label, str(expected), str(actual)])


func _assert_true(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected true" % label)


func _assert_false(cond: bool, label: String) -> void:
	if not cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] %s — expected false" % label)


## ADR-0085 §5: lanes group by "DOES THIS ADVANCE THE CLOCK?", not by encoding form.
## 18b established the RULE and got the LIST wrong — it split one concept across a
## "Holds" lane and a "Rests" lane, on the strength of two forms (tie, note-form rest)
## that FFT writes ZERO times. 18c keeps the rule and collapses the list: `0x80 Rest`
## and `0x81 Fermata` are two ways of adding time to the SAME lane — silent time and
## sounding time (§2) — so both carry kind "time", as do the note path's tie and
## note-form rest. What is left on "opcode" is voice settings ONLY.
func _test_time_carrying_events_all_share_the_one_time_kind() -> void:
	# note C(dur12) | tie(48) | note-form rest(48) | 0x80 Rest(8) | 0x81 Fermata(6)
	# | Octave(4) | Instrument(5) | Dynamics(64) | Tempo(120) | EndBar
	var a := PackedByteArray([0x60, 0x0C, 0x60, 234, 0x60, 253, 0x80, 0x08,
			0x81, 0x06, 0x94, 0x04, 0xAC, 0x05, 0xE0, 0x40, 0xA0, 0x78, 0x90])
	var view: Dictionary = PairModel.pair_view(
			_make_feds_bank(a, PackedByteArray([0x90])), 0, {}, null)
	var track: Dictionary = (view.get("tracks", [])[0] as Dictionary)
	var kind_by_label := {}
	for c in track.get("commands", []):
		kind_by_label[str(c.get("label", ""))] = str(c.get("kind", ""))
	_assert_eq(kind_by_label.get("Rest"), "time",
			"0x80 Rest carries time — one time lane, whichever form wrote it")
	_assert_eq(kind_by_label.get("Hold"), "time", "a tie carries time")
	_assert_eq(kind_by_label.get("Fermata"), "time",
			"Fermata adds exactly its param to the clock like every other time event (§2)")
	_assert_eq(kind_by_label.get("Tempo"), "tempo", "Tempo keeps its own lane (zero-tick, but it bends the wall clock)")
	_assert_eq(kind_by_label.get("EndBar"), "structure", "flow stays flow")
	_assert_eq(kind_by_label.get("Octave"), "opcode", "Octave is a voice setting")
	_assert_eq(kind_by_label.get("Instrument"), "opcode", "…and so is Instrument")
	_assert_eq(kind_by_label.get("Dynamics"), "opcode", "…and Dynamics")

	# The whole point, unchanged from 18b: the Opcodes lane is voice settings ONLY, so
	# "does deleting this move everything after it?" is answered by which lane the
	# event sits on. Under 18c the answer is also "no, ever" — spans tile the time
	# lane, so a delete there leaves no hole to close (§3).
	for c in track.get("commands", []):
		var advances: bool = int(c.get("opcode", -1)) in [0x80, 0x81] \
				or str(c.get("kind", "")) == "time"
		if str(c.get("kind", "")) == "opcode":
			_assert_false(advances, "no event on the Opcodes lane advances the clock (%s)"
					% str(c.get("label", "")))


## §4: the SPAN is the unit of time — a run of ticks that is one note or one rest, and
## spans TILE the track with no empty space between them. The fold layers over the
## event list rather than replacing it, so `spans` holds references to the very note /
## command dicts `notes` and `commands` carry: every byte stays projected and stays
## keyed by decode-order `event_index`.
func _test_spans_tile_the_track_as_notes_and_rests() -> void:
	# note C(12) | 0x81 Fermata(6) | 0x80 Rest(8) | note D(24) | EndBar
	var a := PackedByteArray([0x60, 0x0C, 0x81, 0x06, 0x80, 0x08, 0x60, 0x2F, 0x90])
	var view: Dictionary = PairModel.pair_view(
			_make_feds_bank(a, PackedByteArray([0x90])), 0, {}, null)
	var track: Dictionary = (view.get("tracks", [])[0] as Dictionary)
	var spans: Array = track.get("spans", [])
	var shape: Array = []
	for sp in spans:
		shape.append([str(sp.get("span_kind")), int(sp.get("span_start_tick")),
				int(sp.get("span_note_ticks")), int(sp.get("span_extension_ticks")),
				int(sp.get("span_total_ticks"))])
	_assert_eq(shape, [["note", 0, 12, 6, 18], ["rest", 18, 0, 0, 8],
			["note", 26, 24, 0, 24]],
			"note+fermata is ONE 18-tick span; the rest is its own; then the next note")
	# Tiling: each span starts where the previous ended, and the last reaches end_tick.
	var cursor := 0
	for sp in spans:
		_assert_eq(int(sp.get("span_start_tick")), cursor, "spans tile — no gap, no overlap")
		cursor += int(sp.get("span_total_ticks"))
	_assert_eq(cursor, int(track.get("end_tick")), "…and they tile the WHOLE track")
	# The span layer is references, not copies: the note span IS the note dict.
	_assert_true(spans[0] == (track.get("notes", [])[0] as Dictionary),
			"a note span is the note dict itself — one representation, not two")
	_assert_eq(int(spans[0].get("event_index")), 0, "…so it keeps its decode-order event_index")
	_assert_eq(spans[0].get("span_segments"), [0, 1],
			"the span keeps its SEGMENTS (note byte + fermata byte), never a bare total")


## §2, the rule the lane draws by: a Fermata's ticks are SOUNDING when a note is
## playing and SILENT otherwise. The fold reads no opcode names — it asks one question
## per event, *is a note sounding?*, which is what the sequencer answers, so the
## picture cannot drift from the sound. 24 corpus Fermatas sound with nothing playing.
func _test_a_fermata_with_no_note_playing_is_a_rest_span() -> void:
	# 0x81 Fermata(48) with nothing sounding | note C(12) | 0x81 Fermata(6) | EndBar
	var a := PackedByteArray([0x81, 0x30, 0x60, 0x0C, 0x81, 0x06, 0x90])
	var view: Dictionary = PairModel.pair_view(
			_make_feds_bank(a, PackedByteArray([0x90])), 0, {}, null)
	var track: Dictionary = (view.get("tracks", [])[0] as Dictionary)
	var spans: Array = track.get("spans", [])
	_assert_eq(spans.size(), 2, "a leading Fermata is a span of its own, then the note's")
	_assert_eq(str(spans[0].get("span_kind")), "rest",
			"a Fermata with no note playing is SILENT time — a rest span")
	_assert_eq(int(spans[0].get("span_total_ticks")), 48, "…carrying its full param in ticks")
	_assert_eq(str(spans[1].get("span_kind")), "note", "the second Fermata extends the note")
	_assert_eq(int(spans[1].get("span_total_ticks")), 18, "…so that span is 12 + 6")
	# Both opcodes add exactly `param` ticks either way — they differ in whose ticks
	# they are, never in how many.
	_assert_eq(int(track.get("end_tick")), 66, "the clock is 48 + 12 + 6 regardless of sounding")


## The regroup is a MODEL change — `_opcode_kind` is shared by the verdict system and
## read next to the prune — so it must move lanes without moving behaviour. 0x80/0x81
## are already in `FedsOpcodeVerdicts.STRUCTURAL_OPCODES` (which the prune consults as
## an OPCODE list, never through the kind), so both stay Structural and both stay
## hard-excluded from pruning.
##
## That opcode arm is why this guard can pass for the WRONG reason, so the note path's
## tie and note-form rest — which carry opcode -1 and are reachable ONLY through the
## kind — are asserted alongside: they are the events that silently re-classify as
## voice-writes if `_classify`'s kind clause does not move with the lane collapse.
func _test_time_regroup_leaves_verdicts_and_pruning_alone() -> void:
	var Verdicts = load("res://src/effects/studio/FedsOpcodeVerdicts.gd")
	var Prune = load("res://src/effects/studio/FedsNoOpPrune.gd")
	# Instrument | note | 0x80 Rest | 0x81 Fermata | a real no-op (0x82) | EndBar
	var a := PackedByteArray([0xAC, 0x05, 0x60, 0x0C, 0x80, 0x08, 0x81, 0x06, 0x82, 0x90])
	var bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var view: Dictionary = PairModel.pair_view(bank, 0, {}, null)
	var track: Dictionary = (view.get("tracks", [])[0] as Dictionary)
	var vd: Dictionary = Verdicts.verdicts(track)
	var per_event: Dictionary = vd.get("per_event", {})
	for c in track.get("commands", []):
		if int(c.get("opcode", -1)) in [0x80, 0x81]:
			_assert_eq(str(per_event.get(int(c.get("event_index", -1)), "")),
					Verdicts.STRUCTURAL,
					"%s stays Structural after the regroup" % str(c.get("label", "")))
	# The prune still takes the 0x82 no-op and nothing else: it consults
	# STRUCTURAL_OPCODES as an opcode LIST, so a lane regroup cannot reach it.
	var pruned: PackedByteArray = Prune.prune_track(bank.get_track_bytes(0), vd)
	_assert_eq(pruned.size(), a.size() - 1, "the prune drops exactly the one 0x82 no-op")
	_assert_true(0x80 in pruned, "0x80 Rest survives the prune")
	_assert_true(0x81 in pruned, "…and so does Fermata")
	_assert_false(0x82 in pruned, "…while the real no-op goes")

	# The kind arm, which no opcode list can backstop: a tie and a note-form rest carry
	# opcode -1, so `kind == "time"` is the ONLY thing that keeps them Structural.
	# note C(12) | tie(48) | note-form rest(48) | EndBar
	var b := PackedByteArray([0x60, 0x0C, 0x60, 234, 0x60, 253, 0x90])
	var bview: Dictionary = PairModel.pair_view(
			_make_feds_bank(b, PackedByteArray([0x90])), 0, {}, null)
	var btrack: Dictionary = (bview.get("tracks", [])[0] as Dictionary)
	var bvd: Dictionary = Verdicts.verdicts(btrack)
	for c in btrack.get("commands", []):
		if int(c.get("opcode", -1)) < 0:
			_assert_eq(str(bvd.get("per_event", {}).get(int(c.get("event_index", -1)), "")),
					Verdicts.STRUCTURAL,
					"the note-form %s stays Structural — it is reachable only through its kind"
							% str(c.get("label", "")))


## ADR-0085 §6 (2026-08-18b): the panel already stacks same-tick events top-to-bottom
## in stream order, but only WITHIN one lane — so two simultaneous events on different
## lanes carried no ordering cue at all. Every note bar and chip now draws its ordinal
## (its decode-order `event_index`), which makes the pair read as ONE ordered list
## across lanes — what "pick a slot in the list" requires. Gappy runs are informative:
## `0, 1, 2, … 4` on the Opcodes lane says a note sits at 3.
func _test_every_event_carries_its_ordinal_in_the_stream() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	# Instrument(0) Octave(1) Dynamics(2) note(3) Instrument(4) EndBar(5)
	var a := PackedByteArray([0xAC, 0x05, 0x94, 0x04, 0xE0, 0x40, 0x60, 0x0C,
			0xAC, 0x06, 0x90])
	var view: Dictionary = PairModel.pair_view(
			_make_feds_bank(a, PackedByteArray([0x90])), 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 700.0, {})
	var ord_by_ei := {}
	for chip in lay.get("chips", []):
		if int(chip.get("track", -1)) == 0:
			ord_by_ei[int(chip.get("event_index", -1))] = int(chip.get("ordinal", -1))
	for bar in lay.get("span_bars", []):
		if int(bar.get("track", -1)) == 0:
			ord_by_ei[int(bar.get("event_index", -1))] = int(bar.get("ordinal", -1))
	_assert_eq(ord_by_ei, {0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 5: 5},
			"every event carries its position in the ONE stream, notes and chips alike")
	# The Opcodes lane reads 0,1,2,·,4 — the gap at 3 IS the note.
	var opcode_ords: Array = []
	for chip in lay.get("chips", []):
		if int(chip.get("track", -1)) == 0 and str(chip.get("kind", "")) == "opcode":
			opcode_ords.append(int(chip.get("ordinal", -1)))
	opcode_ords.sort()
	_assert_eq(opcode_ords, [0, 1, 2, 4], "a gappy opcode run is the tell that a note sits between")
	# The ordinal is DRAWN, and the chip is wide enough for a two-digit prefix.
	_assert_true(Panel.CHIP_W >= Panel.BADGE_W,
			"chips widened to carry the ordinal prefix (ADR-0085 §6: ~44 px)")
	for chip in lay.get("chips", []):
		_assert_true(Panel.chip_text(chip).begins_with("%d " % int(chip.get("ordinal", -1))),
				"the drawn chip text leads with its ordinal")


## §6, second half: a borrowed or ghost copy shows its OWNER's number, not a fresh
## one. A borrowed `Ins10` is track B's item 0 heard on A's voice, and clicking it
## already routes to (owner_track, owner_event_index) — any other number would
## contradict the click.
func _test_borrowed_and_ghost_copies_show_their_owners_ordinal() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	# Track A is a STUB (no EndBar) and flows into track B, borrowing B's bytes.
	var a := PackedByteArray([0xD2, 0x08])
	var b := PackedByteArray([0xAC, 0x0A, 0x94, 0x03, 0x90])
	var view: Dictionary = PairModel.pair_view(_make_feds_bank(a, b), 0, {}, null)
	# The borrowed span is a NoEnd phantom: unfold it to draw what A actually hears.
	var lay: Dictionary = Panel.layout(view, 700.0, {"unwound": {"0:noend": true}})
	var borrowed := 0
	for chip in lay.get("chips", []):
		if int(chip.get("track", -1)) != 0 or not bool(chip.get("flowed", false)):
			continue
		borrowed += 1
		_assert_eq(int(chip.get("ordinal", -1)), int(chip.get("owner_event_index", -2)),
				"a borrowed chip wears its OWNER's number, not a fresh one")
	_assert_true(borrowed >= 2, "the stub borrows track B's opcodes (%d)" % borrowed)


# --- Structural authoring: the verbs (ADR-0085 amendment 2026-08-18b §3/§4/§7) ---

## §7: the menu is the 57 opcodes the corpus contains, ordered by track coverage,
## minus the time-carrying pair (§3's slice boundary) and the flow opcodes.
func _test_insert_menu_is_the_corpus_ordered_by_coverage() -> void:
	var Catalog = load("res://src/effects/studio/FedsOpcodeCatalog.gd")
	var cov: Array = Catalog.coverage()
	_assert_eq(cov.size(), 57, "the corpus carries 57 distinct opcodes")
	var menu: Array = Catalog.insert_menu()
	var ops: Array = []
	var covers: Array = []
	for e in menu:
		ops.append(int(e["opcode"]))
		covers.append(int(e["tracks"]))
	_assert_true(_is_desc(covers), "the menu is ordered by track coverage, most-covered first")
	_assert_eq(int(ops[0]), 0xAC,
			"Instrument leads once EndBar is held back for the phantom boundary")
	for op in [0x80, 0x81]:
		_assert_false(op in ops, "the time-carrying pair is not offered in slice 1 (0x%02X)" % op)
	for op in [0x90, 0x91, 0x98, 0x99, 0x9A]:
		_assert_false(op in ops, "flow opcodes are not offered away from their place (0x%02X)" % op)
	# 0x91 (the loop-return) is on the exclusion list but never occurs in the corpus,
	# so the menu is 57 minus the two time-carrying and the four flow opcodes present.
	_assert_eq(menu.size(), 57 - 2 - 4, "…and everything else the corpus writes IS offered")
	# Every entry carries bytes that decode back to exactly the event asked for.
	for e in menu:
		var bytes: PackedByteArray = e["bytes"]
		var back: Array = SMD.decode_track(bytes, bytes.size())
		_assert_eq(back.size(), 1, "%s encodes to ONE event" % str(e["label"]))
		if back.size() == 1:
			_assert_eq(int(back[0].opcode), int(e["opcode"]),
					"%s round-trips through the decoder" % str(e["label"]))


func _is_desc(a: Array) -> bool:
	for i in range(1, a.size()):
		if int(a[i]) > int(a[i - 1]):
			return false
	return true


## §7: a new opcode starts at the CORPUS MODE for its parameter — the value FFT
## itself most often writes — so an inserted Instrument is a real instrument and an
## inserted ADSR_Attack does something, without a hand-authored default table to rot.
func _test_insert_menu_defaults_to_the_corpus_mode() -> void:
	var Catalog = load("res://src/effects/studio/FedsOpcodeCatalog.gd")
	var Stats = load("res://src/effects/studio/FedsParamStats.gd")
	for op in [0xAC, 0x94, 0xE0, 0xC2]:
		var mode: int = int(Stats.of(op, 0).get("mode", -1))
		_assert_true(mode >= 0, "the corpus has a mode for 0x%02X param 0" % op)
		var params: PackedByteArray = Catalog.default_params(op)
		_assert_eq(params.size(), 1, "0x%02X takes one param" % op)
		if params.size() == 1:
			_assert_eq(int(params[0]), mode & 0xFF,
					"0x%02X seeds from the corpus mode, not zero" % op)
	# A zero-param opcode has nothing to seed.
	_assert_eq(Catalog.default_params(0xBA).size(), 0, "ReverbOn takes no params")


## §3: EndBar inserted anywhere else makes the rest of the track unreachable. At a
## stub's phantom boundary it is the natural verb the NoEnd phantom has been
## advertising — one byte, no earlier offset moves, and the borrowing visibly stops.
func _test_end_bar_is_offered_only_at_the_phantom_boundary() -> void:
	var Catalog = load("res://src/effects/studio/FedsOpcodeCatalog.gd")
	_assert_false(Catalog.can_insert(Catalog.END_BAR, false),
			"EndBar is not on the menu in open stream space")
	_assert_true(Catalog.can_insert(Catalog.END_BAR, true),
			"…and IS at the phantom boundary")
	var ops: Array = []
	for e in Catalog.insert_menu(true):
		ops.append(int(e["opcode"]))
	_assert_true(Catalog.END_BAR in ops, "the boundary menu offers EndBar")
	for op in [0x98, 0x99, 0x9A]:
		_assert_false(op in ops, "the other flow opcodes stay off even there (0x%02X)" % op)


## §4: an insert is anchored to an EVENT, not to a time — the address is a byte
## boundary, "add after this event". A tick cannot say which of four stacked
## zero-tick events is meant; a byte boundary can.
func _test_insert_event_splices_an_opcode_after_its_anchor() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	# Instrument(0) | note(1) | EndBar(2)
	var a := PackedByteArray([0xAC, 0x05, 0x60, 0x0C, 0x90])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	# "after the Instrument" = the byte boundary at base+2.
	var res: Dictionary = Channel.insert_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0,
		"at": base + 2, "opcode": 0x94, "params": PackedByteArray([3])})
	_assert_true(bool(res.get("structural", false)), "the insert is structural")
	_assert_true(bool(res.get("invalidates_feds", false)), "…and re-derives the FEDS views")
	_assert_eq(int(res.get("event_index", -1)), 1, "selection lands on the NEW opcode (§8)")
	var got: PackedByteArray = data.feds_bank.get_track_bytes(0)
	_assert_eq(Array(got), [0xAC, 0x05, 0x94, 0x03, 0x60, 0x0C, 0x90],
			"the opcode lands after its anchor, every other byte verbatim")
	_assert_eq(int(res.get("after_bytes", 0)) - int(res.get("before_bytes", 0)), 2,
			"the bank grew by exactly the opcode's bytes")
	# The neighbour track's bytes still read correctly through the shifted table.
	_assert_eq(Array(data.feds_bank.get_track_bytes(1)), [0x90],
			"the offset table absorbed the growth — track B is where it was")


## §4: the address is a boundary, and the boundary BEFORE the first event is a real
## one — an Instrument ahead of every note is exactly the edit this needs to allow.
func _test_insert_at_the_track_start_is_addressable() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	var a := PackedByteArray([0x60, 0x0C, 0x90])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	var res: Dictionary = Channel.insert_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0,
		"at": base, "opcode": 0xAC, "params": PackedByteArray([7])})
	_assert_eq(int(res.get("event_index", -1)), 0, "the new opcode IS event 0 now")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)), [0xAC, 0x07, 0x60, 0x0C, 0x90],
			"it lands before the note it pre-arms")


## A byte boundary INSIDE an event is not an address — writing there would split a
## param off its opcode. Refused, not clamped: a silent clamp would write somewhere
## the author did not point.
func _test_insert_refuses_a_boundary_that_is_not_an_event_edge() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	var a := PackedByteArray([0xAC, 0x05, 0x90])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	var before: PackedByteArray = data.feds_bank.raw.duplicate()
	# base+1 is the Instrument's PARAM byte, not a boundary.
	var res: Dictionary = Channel.insert_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0,
		"at": base + 1, "opcode": 0x94, "params": PackedByteArray([3])})
	_assert_true(res.is_empty(), "a mid-event address is refused")
	_assert_eq(Array(data.feds_bank.raw), Array(before), "…and nothing was written")
	# So is a time-carrying opcode, in slice 1.
	_assert_true(Channel.insert_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0,
		"at": base, "opcode": 0x81, "params": PackedByteArray([6])}).is_empty(),
		"Fermata is not insertable in the zero-tick slice")


## Delete removes the addressed event's bytes and nothing else. §4: opcodes are
## POSITIONED after things, never OWNED by them, so the neighbours neither move nor
## vanish — they simply now follow whatever preceded the deleted event.
func _test_delete_event_removes_the_addressed_bytes_only() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	# Instrument(0) | Octave(1) | note(2) | Dynamics(3) | EndBar(4)
	var a := PackedByteArray([0xAC, 0x05, 0x94, 0x03, 0x60, 0x0C, 0xE0, 0x40, 0x90])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	var res: Dictionary = Channel.delete_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base + 2})
	_assert_true(bool(res.get("structural", false)), "the delete is structural")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)),
			[0xAC, 0x05, 0x60, 0x0C, 0xE0, 0x40, 0x90],
			"only the Octave's two bytes go")
	_assert_eq(int(res.get("event_index", -1)), 0,
			"selection lands on the ANCHOR — the event the deleted one followed (§8)")


## ADR-0085 2026-08-18c §4: deleting something that consumes time means putting a REST
## there. `_advances_the_clock` stops being a refusal and becomes the ROUTER — each of
## the span's time-carrying bytes is substituted in place by a `0x80 Rest` of identical
## tick count, so the ticks stay and only the sound goes.
func _test_deleting_a_note_span_rests_it_byte_for_byte() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	# Instrument | note C(12) | Octave (INTERIOR) | 0x81 Fermata(6) | note D(24) | EndBar
	var a := PackedByteArray([0xAC, 0x05, 0x60, 0x0C, 0x94, 0x03, 0x81, 0x06,
			0x60, 0x2F, 0x90])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	var before_view: Dictionary = PairModel.pair_view(data.feds_bank, 0, {}, null)
	var before_track: Dictionary = before_view.get("tracks", [])[0]
	var before_ticks: int = int(before_track.get("end_tick"))
	var before_events: int = (before_track.get("commands", []) as Array).size() \
			+ (before_track.get("notes", []) as Array).size()
	var res: Dictionary = Channel.delete_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base + 2})
	_assert_true(bool(res.get("structural", false)), "resting a span is a structural edit")
	# The note AND its Fermata segment both become 0x80 Rests of the same duration —
	# the Fermata too, or it would extend whatever sounded before instead.
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)),
			[0xAC, 0x05, 0x80, 0x0C, 0x94, 0x03, 0x80, 0x06, 0x60, 0x2F, 0x90],
			"every time-carrying byte of the span becomes an equal-duration 0x80 Rest")
	_assert_eq(int(res.get("after_bytes", -1)), int(res.get("before_bytes", -2)),
			"a table-form note substitutes at the SAME size — a delete never relocates")
	# The interior Octave keeps its exact firing tick — the split point IS its timing,
	# which is why the span is re-timed by substitution and never re-spelled.
	var after: Dictionary = PairModel.pair_view(data.feds_bank, 0, {}, null).get("tracks", [])[0]
	var oct_tick := -1
	for c in after.get("commands", []):
		if int(c.get("opcode", -1)) == 0x94:
			oct_tick = int(c.get("tick", -1))
	_assert_eq(oct_tick, 12, "the interior opcode fires at the same tick as before")
	_assert_eq(int(after.get("end_tick")), before_ticks,
			"the clock does not move — a delete leaves no hole to close (§3)")
	_assert_eq(int(res.get("event_index", -1)), 1,
			"the event COUNT is unchanged, so the selection stays on the same event")
	_assert_eq((after.get("commands", []) as Array).size()
			+ (after.get("notes", []) as Array).size(), before_events,
			"…because the event count is stable: a delete is not a resize in the addressing sense")


## §4, the explicit-duration case — the only one that changes size, and it SHRINKS by
## one byte (356 of the corpus's 6234 notes). The byte-level splice + offset fixup
## handles it exactly as the prune's does.
func _test_deleting_an_explicit_duration_note_shrinks_by_one_byte() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	# note C with delta_index 0 → an explicit 3rd duration byte (200 ticks) | EndBar
	var a := PackedByteArray([0x60, 0x00, 200, 0x90])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	var res: Dictionary = Channel.delete_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base})
	_assert_false(res.is_empty(), "an explicit-duration note rests like any other")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)), [0x80, 200, 0x90],
			"`vv kk tt` becomes `80 tt` — one byte smaller, same ticks")
	var rested: Dictionary = PairModel.pair_view(data.feds_bank, 0, {}, null).get("tracks", [])[0]
	_assert_eq(int(rested.get("end_tick")), 200,
			"…and 200 ticks is still 200 ticks (one param byte holds 0-255)")


## §6: delete and "make it a rest" are the same act, so deleting a REST is a literal
## no-op and is refused — the only way to remove silence is to make it not silence.
## A segment addressed instead of its head is refused too: a Fermata inside a note is
## not a span of its own, and a tie is refused by DESIGN rather than by accident.
func _test_delete_refuses_a_rest_a_segment_and_a_tie() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	# Instrument | note C(12) | 0x81 Fermata(6) | 0x80 Rest(8) | EndBar
	var a := PackedByteArray([0xAC, 0x05, 0x60, 0x0C, 0x81, 0x06, 0x80, 0x08, 0x90])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	var before: PackedByteArray = data.feds_bank.raw.duplicate()
	_assert_true(Channel.delete_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base + 6}).is_empty(),
		"deleting a rest is a no-op, so it is refused rather than silently done")
	_assert_true(Channel.delete_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base + 4}).is_empty(),
		"a Fermata is a SEGMENT of the note's span, not a span of its own")
	_assert_eq(Array(data.feds_bank.raw), Array(before), "…and neither refusal wrote a byte")
	# A tie: zero corpus occurrences, so its semantics are stated-not-designed.
	var t := PackedByteArray([0x60, 0x0C, 0x60, 234, 0x90])   # note C(12) | tie(48) | EndBar
	var tdata = EffectDataClass.new()
	tdata.feds_bank = _make_feds_bank(t, PackedByteArray([0x90]))
	var tbase: int = tdata.feds_bank.track_offsets[0]
	var tbefore: PackedByteArray = tdata.feds_bank.raw.duplicate()
	_assert_true(Channel.delete_event(tdata, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": tbase}).is_empty(),
		"a span containing a tie is refused — no FFT sound has one to test against")
	_assert_eq(Array(tdata.feds_bank.raw), Array(tbefore), "…without writing a byte")
	# The zero-tick EndBar beside them is still a plain byte delete.
	_assert_false(Channel.delete_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base + 8}).is_empty(),
		"a zero-tick event still deletes by splicing its bytes out")


## §4: a pruned note inside a Repeat…Coda rests EVERY iteration for free, because the
## substitution is at the BYTE level and the loop bytes replay it each pass. 2842 of
## the corpus's 9776 time-carrying events (29%) sit inside a loop body.
func _test_resting_a_span_inside_a_loop_replays_every_iteration() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	# Repeat ×3 | note C(12) | Coda | EndBar
	var a := PackedByteArray([0x98, 0x03, 0x60, 0x0C, 0x99, 0x90])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	var before: Dictionary = PairModel.pair_view(data.feds_bank, 0, {}, null).get("tracks", [])[0]
	_assert_false(Channel.delete_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base + 2}).is_empty(),
		"a span inside a loop body rests like any other")
	var after: Dictionary = PairModel.pair_view(data.feds_bank, 0, {}, null).get("tracks", [])[0]
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)), [0x98, 0x03, 0x80, 0x0C, 0x99, 0x90],
			"…once in the bytes, which the loop replays each pass")
	_assert_eq((after.get("loops", []) as Array), (before.get("loops", []) as Array),
			"the bracket and its ×3 count survive intact — same ticks per iteration")


## ADR-0087 dec. 29, applied to a NEW byte-writing path (18c build notes):
## every path that writes bytes must RE-DERIVE the opcode verdicts, and it is a silent
## wrong answer if it does not. Resting a span moves the classifier's first-note
## anchor, so a voice-write that was Live (at/after the first note) becomes Pre-arm
## (before it) — nothing about that is designed for delete, it just has to be fresh.
func _test_resting_a_span_re_derives_the_opcode_verdicts() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	var Verdicts = load("res://src/effects/studio/FedsOpcodeVerdicts.gd")
	# Dynamics(0) | note C(1) | Octave(2) | note D(3) | EndBar(4) — all on an audible
	# instrument, so nothing is Muted and the anchor is the only thing moving.
	var a := PackedByteArray([0xE0, 0x40, 0x60, 0x0C, 0x94, 0x03, 0x60, 0x2F, 0x90])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	var before: Dictionary = Verdicts.verdicts(
			PairModel.pair_view(data.feds_bank, 0, {}, null).get("tracks", [])[0])
	_assert_eq(str(before.get("per_event", {}).get(0, "")), Verdicts.PREARM,
			"fixture: the Dynamics before the first note is Pre-arm")
	_assert_eq(str(before.get("per_event", {}).get(2, "")), Verdicts.LIVE,
			"fixture: the Octave after the first note is Live")
	_assert_false(Channel.delete_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base + 2}).is_empty(),
		"the first note rests")
	var after: Dictionary = Verdicts.verdicts(
			PairModel.pair_view(data.feds_bank, 0, {}, null).get("tracks", [])[0])
	_assert_eq(str(after.get("per_event", {}).get(1, "")), Verdicts.STRUCTURAL,
			"the rested slot is now a rest — flow / timing, not a sounding note")
	_assert_eq(str(after.get("per_event", {}).get(2, "")), Verdicts.PREARM,
			"…and the Octave re-reads as Pre-arm, because the first note it stages for moved")


## §6: a note span's context menu offers Delete; a REST span's does not. The verb keeps
## its name and its plumbing, and the surface simply never offers the no-op.
func _test_a_rest_span_has_no_delete_row() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var Page = load("res://src/effects/studio/EffectStudioPage.gd")
	# note C(12) | 0x80 Rest(8) | Octave | EndBar
	var a := PackedByteArray([0x60, 0x0C, 0x80, 0x08, 0x94, 0x03, 0x90])
	var view: Dictionary = PairModel.pair_view(
			_make_feds_bank(a, PackedByteArray([0x90])), 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 700.0, {})
	var by_kind := {}
	for bar in lay.get("span_bars", []):
		by_kind["rest" if bool(bar.get("rest", false)) else "note"] = bar
	_assert_eq(by_kind.size(), 2, "the fixture draws one note span and one rest span")
	if by_kind.size() != 2:
		return
	var note_ctx: Dictionary = Panel.resolve_context(view, lay,
			(by_kind["note"]["rect"] as Rect2).get_center())
	var rest_ctx: Dictionary = Panel.resolve_context(view, lay,
			(by_kind["rest"]["rect"] as Rect2).get_center())
	_assert_false((note_ctx.get("delete", {}) as Dictionary).is_empty(),
			"a note span offers Delete — which means putting a rest there")
	_assert_true((rest_ctx.get("delete", {}) as Dictionary).is_empty(),
			"a rest span does not — deleting silence is a literal no-op")
	# And the menu the page builds from that context says the same thing.
	var note_verbs: Array = []
	for act in Page._pair_context_actions(note_ctx):
		note_verbs.append(str(act.get("verb", "")))
	var rest_verbs: Array = []
	for act in Page._pair_context_actions(rest_ctx):
		rest_verbs.append(str(act.get("verb", "")))
	_assert_true("delete" in note_verbs, "the note's menu carries a Delete row")
	_assert_false("delete" in rest_verbs, "the grey bar's menu has no Delete row")
	_assert_true("insert" in rest_verbs,
			"…but a rest is still a real address — Add opcode stays offered there")


## The back door closed at the encoder as well as at the surface (2026-08-19 §6): a
## `note_delta_idx` write re-times the span whatever built the address, so the kind
## refuses rather than trusting the projector to stop offering it.
func _test_note_duration_writes_are_refused_at_the_encoder() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	var a := PackedByteArray([0x60, 0x0C, 0x90])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var off: int = data.feds_bank.track_offsets[0] + 1
	var ref := {"channel": "sound_def", "kind": "note_delta_idx", "offset": off, "pair_idx": 0}
	_assert_true(Channel.apply_raw(data, ref, 4).is_empty(),
			"re-timing a span is the parked length verb (18c §7), not a bounded param")
	_assert_eq(int(data.feds_bank.raw[off]), 0x0C, "…and the byte is untouched")
	# The key half of the SAME byte still writes: only the duration field is closed.
	var kref := {"channel": "sound_def", "kind": "note_key", "offset": off, "pair_idx": 0}
	_assert_false(Channel.apply_raw(data, kref, 2).is_empty(), "the key is still editable")
	_assert_eq(int(data.feds_bank.raw[off]), 2 * 19 + 12, "key written, duration index kept")


## ADR-0085 2026-08-19 (the un-rest): delete's inverse. 18c §6 said "the only way to
## remove silence is to make it not silence" and left that verb unbuilt, so a delete had
## no inverse but Ctrl+Z. The span's ticks are re-spelled as a NOTE of identical length,
## at the corpus's one velocity (96, all 6234 notes) and its most common key (C, 3143).
func _test_un_resting_a_span_sounds_it_at_the_corpus_velocity() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	# Instrument | 0x80 Rest(12) | Octave | EndBar
	var a := PackedByteArray([0xAC, 0x05, 0x80, 0x0C, 0x94, 0x03, 0x90])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	var before: Dictionary = PairModel.pair_view(data.feds_bank, 0, {}, null).get("tracks", [])[0]
	var before_events: int = (before.get("commands", []) as Array).size() \
			+ (before.get("notes", []) as Array).size()
	var res: Dictionary = Channel.unrest_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base + 2})
	_assert_true(bool(res.get("structural", false)), "un-resting a span is a structural edit")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)),
			[0xAC, 0x05, 0x60, 0x0C, 0x94, 0x03, 0x90],
			"`80 pp` becomes `60 dd` — velocity 96, key C, the same 12 ticks")
	_assert_eq(int(res.get("after_bytes", -1)), int(res.get("before_bytes", -2)),
			"a table-value duration substitutes at the SAME size, like the delete it inverts")
	var after: Dictionary = PairModel.pair_view(data.feds_bank, 0, {}, null).get("tracks", [])[0]
	_assert_eq(int(after.get("end_tick")), int(before.get("end_tick")),
			"the clock does not move — the span keeps its ticks, it only starts sounding")
	_assert_eq((after.get("commands", []) as Array).size()
			+ (after.get("notes", []) as Array).size(), before_events,
			"one span in, one span out: the event count is stable")
	_assert_eq(int(res.get("event_index", -1)), 1,
			"…so the selection stays on the same event, now a note")
	var n: Dictionary = (after.get("notes", []) as Array)[0]
	_assert_eq(int(n.get("velocity", -1)), 96, "the corpus writes ONE velocity, 96")
	_assert_eq(int(n.get("relative_key", -1)), 0, "and C is its most common key — 3143 of 6234")
	_assert_eq(int(n.get("duration_ticks", -1)), 12, "the note is exactly as long as the rest was")
	_assert_eq(str(n.get("span_kind", "")), "note", "the grey bar is a blue one now")


## The 66 of 779 corpus rests whose duration is NOT one of the 18 `DELTA_TIME_TABLE`
## values need the explicit third byte — the one case the un-rest GROWS, mirroring the
## one case delete shrinks. Refused-never-clamped would be wrong here: the tick count is
## the one thing the verb must preserve.
func _test_un_resting_a_non_table_duration_takes_the_explicit_form() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	var a := PackedByteArray([0x80, 0x0D, 0x90])          # 13 ticks — not in the table
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	var res: Dictionary = Channel.unrest_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base})
	_assert_false(res.is_empty(), "a non-table duration is still un-restable")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)), [0x60, 0x00, 0x0D, 0x90],
			"`80 0D` becomes `60 00 0D` — key C, delta index 0, an explicit duration byte")
	_assert_eq(int(res.get("after_bytes", -1)), int(res.get("before_bytes", 0)) + 1,
			"…one byte larger, and the offset table is fixed up for it")
	var after: Dictionary = PairModel.pair_view(data.feds_bank, 0, {}, null).get("tracks", [])[0]
	_assert_eq(int(after.get("end_tick")), 13, "13 ticks in, 13 ticks out")


## The forms 18c §1 said we would only ever READ: an effect pruned and saved before the
## `0x80` retrofit still carries note-form rests (relative_key 13). They fold as rest
## spans like any other, so the un-rest sounds them — and never writes the form back.
func _test_un_resting_a_legacy_note_form_rest_writes_the_corpus_note() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	# `vv F7 tt`: key 13 (rest), delta index 0, explicit 200 ticks | EndBar
	var a := PackedByteArray([0x60, 0xF7, 200, 0x90])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	_assert_false(Channel.unrest_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base}).is_empty(),
		"a note-form rest is a rest span, so it un-rests")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)), [0x60, 0x00, 200, 0x90],
			"only the key field moves: 13 (rest) → 0 (C), same three bytes")
	# The table-form note rest (`60 FF` = key 13, delta index 8) shrinks its key the same way.
	var t := PackedByteArray([0x60, 0xFF, 0x90])
	var tdata = EffectDataClass.new()
	tdata.feds_bank = _make_feds_bank(t, PackedByteArray([0x90]))
	_assert_false(Channel.unrest_event(tdata, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0,
		"at": tdata.feds_bank.track_offsets[0]}).is_empty(), "…as does the table form")
	_assert_eq(Array(tdata.feds_bank.get_track_bytes(0)), [0x60, 0x08, 0x90],
			"32 ticks re-spelled as key C at the same delta index")


## The mirror of delete's refusals. A NOTE span is already sounding, so un-resting it is
## the no-op this time; a Fermata inside a note is a segment, not a span; a tie is
## undesigned in both directions; and a zero-tick span has no length to sound.
func _test_un_rest_refuses_a_note_a_segment_a_tie_and_a_zero_tick_span() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	# Instrument | note C(12) | 0x81 Fermata(6) | 0x80 Rest(8) | EndBar
	var a := PackedByteArray([0xAC, 0x05, 0x60, 0x0C, 0x81, 0x06, 0x80, 0x08, 0x90])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	var before: PackedByteArray = data.feds_bank.raw.duplicate()
	_assert_true(Channel.unrest_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base + 2}).is_empty(),
		"a note span already sounds — un-resting it is the no-op in this direction")
	_assert_true(Channel.unrest_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base + 4}).is_empty(),
		"a Fermata is a SEGMENT of the note's span, not a span of its own")
	_assert_eq(Array(data.feds_bank.raw), Array(before), "…and neither refusal wrote a byte")
	_assert_false(Channel.unrest_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base + 6}).is_empty(),
		"the rest beside them un-rests")
	# A tie heading a span: zero corpus occurrences, undesigned in both directions.
	var t := PackedByteArray([0x60, 234, 0x90])           # tie, delta index 6 → 48 ticks
	var tdata = EffectDataClass.new()
	tdata.feds_bank = _make_feds_bank(t, PackedByteArray([0x90]))
	var traw: PackedByteArray = tdata.feds_bank.raw.duplicate()
	_assert_true(Channel.unrest_event(tdata, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0,
		"at": tdata.feds_bank.track_offsets[0]}).is_empty(),
		"a span headed by a tie is refused — no FFT sound has one to test against")
	_assert_eq(Array(tdata.feds_bank.raw), Array(traw), "…without writing a byte")
	# A zero-tick rest (no corpus occurrences either, but a 0-tick Fermata delete makes one).
	var z := PackedByteArray([0x80, 0x00, 0x90])
	var zdata = EffectDataClass.new()
	zdata.feds_bank = _make_feds_bank(z, PackedByteArray([0x90]))
	_assert_true(Channel.unrest_event(zdata, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0,
		"at": zdata.feds_bank.track_offsets[0]}).is_empty(),
		"a span of zero ticks has no length to sound")


## Delete then un-rest is the identity on the corpus's own note — velocity 96, key C, a
## table duration. It is NOT the identity on any other key: the rest kept no key to
## restore, which is the honest limit of the pair (and the note-key edit is one click).
func _test_delete_then_un_rest_round_trips_the_corpus_note() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	var a := PackedByteArray([0xAC, 0x05, 0x60, 0x0C, 0x90])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	var ref := {"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base + 2}
	_assert_false(Channel.delete_event(data, ref).is_empty(), "the note rests")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)), [0xAC, 0x05, 0x80, 0x0C, 0x90],
			"…to `80 0C`")
	_assert_false(Channel.unrest_event(data, ref).is_empty(), "and un-rests back")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)), Array(a),
			"byte-for-byte the note it started as — delete finally has an inverse")
	# A D would come back as a C: the rest holds ticks, never a key.
	var d := PackedByteArray([0x60, 0x2F, 0x90])          # key 2 (D), delta index 9 → 24 ticks
	var ddata = EffectDataClass.new()
	ddata.feds_bank = _make_feds_bank(d, PackedByteArray([0x90]))
	var dref := {"channel": "sound_def", "pair_idx": 0, "track_idx": 0,
			"at": ddata.feds_bank.track_offsets[0]}
	_assert_false(Channel.delete_event(ddata, dref).is_empty(), "a D rests")
	_assert_false(Channel.unrest_event(ddata, dref).is_empty(), "…and sounds again")
	_assert_eq(Array(ddata.feds_bank.get_track_bytes(0)), [0x60, 0x09, 0x90],
			"as a C of the same 24 ticks — the key is lost at the delete, not at the un-rest")


## ADR-0087 dec. 29 on the un-rest's new byte-writing path: re-derive the
## verdicts or be silently wrong. Un-resting moves the classifier's first-note anchor
## EARLIER (the exact inverse of what resting does), so a Pre-arm write becomes Live.
func _test_un_resting_a_span_re_derives_the_opcode_verdicts() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	var Verdicts = load("res://src/effects/studio/FedsOpcodeVerdicts.gd")
	# Dynamics(0) | 0x80 Rest(12)(1) | Octave(2) | note D(3) | EndBar(4)
	var a := PackedByteArray([0xE0, 0x40, 0x80, 0x0C, 0x94, 0x03, 0x60, 0x2F, 0x90])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	var before: Dictionary = Verdicts.verdicts(
			PairModel.pair_view(data.feds_bank, 0, {}, null).get("tracks", [])[0])
	_assert_eq(str(before.get("per_event", {}).get(2, "")), Verdicts.PREARM,
			"fixture: the Octave stages for the only note there is, so it reads Pre-arm")
	_assert_false(Channel.unrest_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base + 2}).is_empty(),
		"the rest sounds")
	var after: Dictionary = Verdicts.verdicts(
			PairModel.pair_view(data.feds_bank, 0, {}, null).get("tracks", [])[0])
	_assert_eq(str(after.get("per_event", {}).get(2, "")), Verdicts.LIVE,
			"…and the Octave re-reads as Live, because the first note it follows moved earlier")


## §6's surface, completed: a rest span's menu offers the un-rest where a note span's
## offers Delete. Every bar now carries exactly one time verb, and both name what the
## click resolved to.
func _test_a_rest_span_offers_the_un_rest_row() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var Page = load("res://src/effects/studio/EffectStudioPage.gd")
	# note C(12) | 0x80 Rest(8) | Octave | EndBar
	var a := PackedByteArray([0x60, 0x0C, 0x80, 0x08, 0x94, 0x03, 0x90])
	var view: Dictionary = PairModel.pair_view(
			_make_feds_bank(a, PackedByteArray([0x90])), 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 700.0, {})
	var by_kind := {}
	for bar in lay.get("span_bars", []):
		by_kind["rest" if bool(bar.get("rest", false)) else "note"] = bar
	_assert_eq(by_kind.size(), 2, "the fixture draws one note span and one rest span")
	if by_kind.size() != 2:
		return
	var note_ctx: Dictionary = Panel.resolve_context(view, lay,
			(by_kind["note"]["rect"] as Rect2).get_center())
	var rest_ctx: Dictionary = Panel.resolve_context(view, lay,
			(by_kind["rest"]["rect"] as Rect2).get_center())
	_assert_false((rest_ctx.get("unrest", {}) as Dictionary).is_empty(),
			"a rest span offers the un-rest — the only way to remove silence")
	_assert_true((note_ctx.get("unrest", {}) as Dictionary).is_empty(),
			"a note span does not: it already sounds")
	var rest_verbs: Array = []
	for act in Page._pair_context_actions(rest_ctx):
		rest_verbs.append(str(act.get("verb", "")))
	var note_verbs: Array = []
	for act in Page._pair_context_actions(note_ctx):
		note_verbs.append(str(act.get("verb", "")))
	_assert_true("unrest" in rest_verbs, "the grey bar's menu carries the un-rest row")
	_assert_false("unrest" in note_verbs, "…and the blue bar's does not")
	# The row NAMES what it will write, the way the Add row names its anchor (§2).
	var label := ""
	for act in Page._pair_context_actions(rest_ctx):
		if str(act.get("verb", "")) == "unrest":
			label = str(act.get("label", ""))
	_assert_true(label.contains("8"), "the label says how long the note will be: %s" % label)


## The un-rest rides the same snapshot-undo contract as insert and delete: the verb
## SWAPS the bank, so the pre-edit object IS the exact restore.
func _test_un_rest_undoes_by_snapshot() -> void:
	var Session = load("res://src/effects/studio/EffectEditSession.gd")
	var a := PackedByteArray([0x80, 0x0C, 0x90])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var before = data.feds_bank
	var before_raw: PackedByteArray = before.raw.duplicate()
	var session = Session.new(data)
	var res: Dictionary = session.unrest_event({
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": before.track_offsets[0]})
	_assert_false(res.is_empty(), "the session routes the un-rest to the FEDS verb")
	_assert_true(data.feds_bank != before, "the bank was SWAPPED, never mutated")
	_assert_eq(Array(before.raw), Array(before_raw), "…so the snapshot is still pristine")
	session.undo()
	_assert_true(data.feds_bank == before, "undo puts the pre-edit bank back")


## ADR-0085 2026-08-19b §2 — the PAINT: a note inside a rest, splitting it.
## `rest(N)` becomes `rest(a) · note(d) · rest(N-a-d)`, so this is the one time-lane
## verb that raises the event count. The clock still does not move: a + d + (N-a-d) = N.
func _test_painting_into_a_rest_splits_it_in_three() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	# Instrument | 0x80 Rest(48) | Octave | EndBar
	var a := PackedByteArray([0xAC, 0x05, 0x80, 0x30, 0x94, 0x03, 0x90])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	var before: Dictionary = PairModel.pair_view(data.feds_bank, 0, {}, null).get("tracks", [])[0]
	var res: Dictionary = Channel.paint_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base + 2,
		"offset_ticks": 16, "duration_ticks": 24})
	_assert_true(bool(res.get("structural", false)), "painting a note is a structural edit")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)),
			[0xAC, 0x05, 0x80, 0x10, 0x60, 0x09, 0x80, 0x08, 0x94, 0x03, 0x90],
			"`80 30` becomes `80 10` · `60 09` · `80 08` — 16 silent, 24 sounding, 8 silent")
	var after: Dictionary = PairModel.pair_view(data.feds_bank, 0, {}, null).get("tracks", [])[0]
	_assert_eq(int(after.get("end_tick")), int(before.get("end_tick")),
			"the clock does not move — a + d + (N-a-d) = N")
	_assert_eq((after.get("commands", []) as Array).size()
			+ (after.get("notes", []) as Array).size(),
			(before.get("commands", []) as Array).size()
			+ (before.get("notes", []) as Array).size() + 2,
			"one event in, THREE out — the only time-lane verb that grows the count")
	_assert_eq(int(res.get("event_index", -1)), 2,
			"the selection lands on the NOTE the author just made, not on the rest it split")
	var n: Dictionary = (after.get("notes", []) as Array)[0]
	_assert_eq(int(n.get("velocity", -1)), 96, "the corpus's one velocity, as the un-rest writes")
	_assert_eq(int(n.get("relative_key", -1)), 0, "…and its most common key")
	_assert_eq(int(n.get("duration_ticks", -1)), 24, "the note is exactly as long as asked")
	_assert_eq(int(n.get("start_tick", -1)), 16, "and starts exactly where asked")


## A piece of zero length is NOT written as `80 00`: a zero-tick span is a thing the
## un-rest already refuses to sound, so the paint must not manufacture one. Painting
## flush against either end of the rest emits two events, not three.
func _test_painting_at_either_end_omits_the_empty_piece() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	var head = EffectDataClass.new()
	head.feds_bank = _make_feds_bank(PackedByteArray([0x80, 0x30, 0x90]), PackedByteArray([0x90]))
	var hres: Dictionary = Channel.paint_event(head, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0,
		"at": head.feds_bank.track_offsets[0], "offset_ticks": 0, "duration_ticks": 24})
	_assert_eq(Array(head.feds_bank.get_track_bytes(0)), [0x60, 0x09, 0x80, 0x18, 0x90],
			"flush at the head: no leading rest, just note · rest")
	_assert_eq(int(hres.get("event_index", -1)), 0, "the note IS the first event now")
	var tail = EffectDataClass.new()
	tail.feds_bank = _make_feds_bank(PackedByteArray([0x80, 0x30, 0x90]), PackedByteArray([0x90]))
	var tres: Dictionary = Channel.paint_event(tail, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0,
		"at": tail.feds_bank.track_offsets[0], "offset_ticks": 24, "duration_ticks": 24})
	_assert_eq(Array(tail.feds_bank.get_track_bytes(0)), [0x80, 0x18, 0x60, 0x09, 0x90],
			"flush at the tail: rest · note, no trailing rest")
	_assert_eq(int(tres.get("event_index", -1)), 1, "…and the selection follows the note")


## The un-rest is the paint's degenerate case — offset 0 for the whole length — and the
## two must agree byte for byte, because they share one encoder.
func _test_painting_the_whole_rest_is_the_un_rest_byte_for_byte() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	var a := PackedByteArray([0xAC, 0x05, 0x80, 0x0C, 0x90])
	var painted = EffectDataClass.new()
	painted.feds_bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var unrested = EffectDataClass.new()
	unrested.feds_bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var base: int = painted.feds_bank.track_offsets[0]
	_assert_false(Channel.paint_event(painted, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base + 2,
		"offset_ticks": 0, "duration_ticks": 12}).is_empty(), "the whole rest paints")
	_assert_false(Channel.unrest_event(unrested, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base + 2}).is_empty(),
		"…and un-rests")
	_assert_eq(Array(painted.feds_bank.get_track_bytes(0)),
			Array(unrested.feds_bank.get_track_bytes(0)),
			"the un-rest IS paint(0, N) — one encoder, so the bytes cannot disagree")


## The note encoder is the un-rest's, lifted rather than re-derived: a duration that is
## not one of `DELTA_TIME_TABLE`'s 18 values takes the 3-byte explicit form. The rests
## around it never do — `0x80` carries a raw byte, so any 1-255 count spells exactly.
func _test_painting_a_non_table_duration_takes_the_explicit_form() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(PackedByteArray([0x80, 0x30, 0x90]), PackedByteArray([0x90]))
	var res: Dictionary = Channel.paint_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0,
		"at": data.feds_bank.track_offsets[0], "offset_ticks": 5, "duration_ticks": 13})
	_assert_false(res.is_empty(), "13 ticks is not a table value, and paints anyway")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)),
			[0x80, 0x05, 0x60, 0x00, 0x0D, 0x80, 0x1E, 0x90],
			"`60 00 0D` — key C, delta index 0, an explicit 13; the rests spell 5 and 30 exactly")
	var after: Dictionary = PairModel.pair_view(data.feds_bank, 0, {}, null).get("tracks", [])[0]
	_assert_eq(int(after.get("end_tick")), 48, "48 ticks in, 48 ticks out")


## The un-rest's refusals, plus the two the tick offset adds. Refused, never clamped: a
## clamp would sound somewhere the author did not point.
func _test_paint_refuses_a_note_a_segment_a_tie_and_an_out_of_range_placement() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	# Instrument | note C(12) | 0x81 Fermata(6) | 0x80 Rest(48) | EndBar
	var a := PackedByteArray([0xAC, 0x05, 0x60, 0x0C, 0x81, 0x06, 0x80, 0x30, 0x90])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	var before: PackedByteArray = data.feds_bank.raw.duplicate()
	var ok := {"channel": "sound_def", "pair_idx": 0, "track_idx": 0,
			"offset_ticks": 8, "duration_ticks": 8}
	var note_ref := ok.duplicate(); note_ref["at"] = base + 2
	_assert_true(Channel.paint_event(data, note_ref).is_empty(),
			"a note span already sounds — there is no silence in it to paint into")
	var seg_ref := ok.duplicate(); seg_ref["at"] = base + 4
	_assert_true(Channel.paint_event(data, seg_ref).is_empty(),
			"a Fermata is a SEGMENT of the note's span, not a span of its own")
	var past_ref := ok.duplicate(); past_ref["at"] = base + 6
	past_ref["offset_ticks"] = 40; past_ref["duration_ticks"] = 16
	_assert_true(Channel.paint_event(data, past_ref).is_empty(),
			"40 + 16 runs past the rest's 48 ticks — refused, never clamped to fit")
	var zero_ref := ok.duplicate(); zero_ref["at"] = base + 6; zero_ref["duration_ticks"] = 0
	_assert_true(Channel.paint_event(data, zero_ref).is_empty(),
			"a zero-tick note would sound nothing — the un-rest refuses one too")
	var neg_ref := ok.duplicate(); neg_ref["at"] = base + 6; neg_ref["offset_ticks"] = -1
	_assert_true(Channel.paint_event(data, neg_ref).is_empty(),
			"and an offset before the span's own start names no tick in it")
	_assert_eq(Array(data.feds_bank.raw), Array(before), "…and not one refusal wrote a byte")
	var good := ok.duplicate(); good["at"] = base + 6
	_assert_false(Channel.paint_event(data, good).is_empty(), "the rest itself paints")
	# A tie heading a span: zero corpus occurrences, undesigned in every direction.
	var tdata = EffectDataClass.new()
	tdata.feds_bank = _make_feds_bank(PackedByteArray([0x60, 234, 0x90]), PackedByteArray([0x90]))
	var traw: PackedByteArray = tdata.feds_bank.raw.duplicate()
	var tref := ok.duplicate(); tref["at"] = tdata.feds_bank.track_offsets[0]
	_assert_true(Channel.paint_event(tdata, tref).is_empty(),
			"a span headed by a tie is refused — no FFT sound has one to test against")
	_assert_eq(Array(tdata.feds_bank.raw), Array(traw), "…without writing a byte")


## ADR-0087 dec. 29 on the paint's byte-writing path. A painted note moves the
## classifier's first-note anchor exactly as the un-rest does — and the paint can move it
## to a LATER tick than the un-rest would, since the note need not start at the span head.
func _test_painting_re_derives_the_opcode_verdicts() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	var Verdicts = load("res://src/effects/studio/FedsOpcodeVerdicts.gd")
	# Dynamics(0) | 0x80 Rest(48)(1) | Octave(2) | note D(3) | EndBar(4)
	var a := PackedByteArray([0xE0, 0x40, 0x80, 0x30, 0x94, 0x03, 0x60, 0x2F, 0x90])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	var before: Dictionary = Verdicts.verdicts(
			PairModel.pair_view(data.feds_bank, 0, {}, null).get("tracks", [])[0])
	_assert_eq(str(before.get("per_event", {}).get(2, "")), Verdicts.PREARM,
			"fixture: the Octave stages for the only note there is, so it reads Pre-arm")
	_assert_false(Channel.paint_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base + 2,
		"offset_ticks": 16, "duration_ticks": 24}).is_empty(), "a note lands inside the rest")
	var after: Dictionary = Verdicts.verdicts(
			PairModel.pair_view(data.feds_bank, 0, {}, null).get("tracks", [])[0])
	_assert_eq(str(after.get("per_event", {}).get(4, "")), Verdicts.LIVE,
			"…and the Octave, now event 4, re-reads as Live behind the note the paint made")


## The paint rides the same snapshot-undo contract as the other three structural verbs,
## which matters more here: it is the one that changes the event COUNT, so a replay-style
## undo would have to re-derive every later ordinal. Swapping the bank back does not.
func _test_paint_undoes_by_snapshot() -> void:
	var Session = load("res://src/effects/studio/EffectEditSession.gd")
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(PackedByteArray([0x80, 0x30, 0x90]), PackedByteArray([0x90]))
	var before = data.feds_bank
	var before_raw: PackedByteArray = before.raw.duplicate()
	var session = Session.new(data)
	var res: Dictionary = session.paint_event({
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0,
		"at": before.track_offsets[0], "offset_ticks": 16, "duration_ticks": 24})
	_assert_false(res.is_empty(), "the session routes the paint to the FEDS verb")
	_assert_true(data.feds_bank != before, "the bank was SWAPPED, never mutated")
	_assert_eq(Array(before.raw), Array(before_raw), "…so the snapshot is still pristine")
	session.undo()
	_assert_true(data.feds_bank == before, "undo puts the pre-edit bank back")



## ADR-0085 2026-08-19b §5/§6: the paint's SURFACE before the drag exists. A right-click
## inside a grey bar reads its tick from the BAR — one linear rect per span, so the tick is
## by construction the one the author is pointing at — and offers a row that runs to the
## end of the rest. The un-rest row stays: it is the precise, zoom-independent "all of it".
func _test_a_rest_bar_offers_the_paint_row_at_the_grabbed_tick() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var Page = load("res://src/effects/studio/EffectStudioPage.gd")
	# 0x80 Rest(48) | note C(12) | EndBar
	var a := PackedByteArray([0x80, 0x30, 0x60, 0x0C, 0x90])
	var bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var view: Dictionary = PairModel.pair_view(bank, 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 900.0, {}, null, {})
	var bar: Dictionary = {}
	for b in lay["span_bars"]:
		if int(b["track"]) == 0 and bool(b.get("rest", false)):
			bar = b
	_assert_false(bar.is_empty(), "fixture: the grey bar is drawn")
	var rect: Rect2 = bar["rect"]
	# A third of the way into the bar: 48 ticks * 1/3 = 16.
	var pos := Vector2(rect.position.x + rect.size.x / 3.0, rect.position.y + rect.size.y * 0.5)
	var ctx: Dictionary = Panel.resolve_context(view, lay, pos)
	var paint: Dictionary = ctx.get("paint", {})
	_assert_false(paint.is_empty(), "a grey bar carries a paint context")
	_assert_eq(int(paint.get("offset_ticks", -1)), 16,
			"the tick is read from the BAR's own rect — a third of 48 ticks is 16")
	_assert_eq(int(paint.get("duration_ticks", -1)), 32,
			"…and the row runs to the end of the rest, which is the remainder")
	# The blue bar beside it offers no paint: there is no silence in it to paint into.
	var note_bar: Dictionary = {}
	for b in lay["span_bars"]:
		if int(b["track"]) == 0 and not bool(b.get("rest", false)):
			note_bar = b
	var nrect: Rect2 = note_bar["rect"]
	var nctx: Dictionary = Panel.resolve_context(view, lay,
			Vector2(nrect.position.x + nrect.size.x / 3.0, nrect.position.y + nrect.size.y * 0.5))
	_assert_true((nctx.get("paint", {}) as Dictionary).is_empty(),
			"a note span already sounds — no paint row on a blue bar")
	# Grabbed flush at the head the paint IS the un-rest, so only the un-rest row shows.
	# No deadzone is needed to reach it: the un-rest row sits on every grey bar whatever
	# the grab, so "all of it" never depends on pixel-perfect aim — which is why a grab one
	# tick in is left alone as the real, distinct edit it is rather than snapped away.
	var head_ctx: Dictionary = Panel.resolve_context(view, lay,
			Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5))
	_assert_true((head_ctx.get("paint", {}) as Dictionary).is_empty(),
			"flush at the head the paint would BE the un-rest — one row, not two that agree")
	_assert_false((head_ctx.get("unrest", {}) as Dictionary).is_empty(),
			"…and the un-rest row is there regardless of where in the bar the grab landed")
	# The rows themselves.
	var verbs: Array = []
	var labels: Array = []
	for act in Page._pair_context_actions(ctx):
		verbs.append(str(act.get("verb", "")))
		labels.append(str(act.get("label", "")))
	_assert_true("paint" in verbs, "the grey bar's menu carries the paint row")
	_assert_true("unrest" in verbs, "…beside the un-rest, which is still the way to say ALL of it")
	for i in range(verbs.size()):
		if verbs[i] == "paint":
			_assert_true(labels[i].contains("+16") and labels[i].contains("32 ticks"),
					"the row NAMES what it will write — where it starts and how long it is")
			var fr: Dictionary = Page._pair_context_actions(ctx)[i].get("field_ref", {})
			_assert_eq(int(fr.get("offset_ticks", -1)), 16, "and carries the offset it named")
			_assert_eq(int(fr.get("duration_ticks", -1)), 32, "…and the duration")


## Undo is the prune's snapshot contract verbatim: a verb REPLACES the whole
## FedsBank, never mutates it, so stashing the pre-edit object IS an exact snapshot.
func _test_structural_feds_verbs_undo_by_snapshot() -> void:
	var Session = load("res://src/effects/studio/EffectEditSession.gd")
	var a := PackedByteArray([0xAC, 0x05, 0x60, 0x0C, 0x90])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var before = data.feds_bank
	var before_raw: PackedByteArray = before.raw.duplicate()
	var base: int = before.track_offsets[0]
	var session = Session.new(data)
	var ref := {"channel": "sound_def", "pair_idx": 0, "track_idx": 0,
			"at": base + 2, "opcode": 0x94, "params": PackedByteArray([3])}
	var res: Dictionary = session.insert_event(ref)
	_assert_false(res.is_empty(), "the session routes sound_def to the FEDS verbs")
	_assert_true(data.feds_bank != before, "the bank was SWAPPED, never mutated")
	_assert_eq(Array(before.raw), Array(before_raw), "…so the snapshot is still pristine")
	session.undo()
	_assert_true(data.feds_bank == before, "undo puts the pre-edit bank back")
	# And the delete verb rides the same path.
	var del: Dictionary = session.delete_event({
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base})
	_assert_false(del.is_empty(), "delete lowers through the session too")
	session.undo()
	_assert_eq(Array(data.feds_bank.raw), Array(before_raw), "…and undoes the same way")


# --- Structural authoring: the gesture (ADR-0085 amendment 2026-08-18b §2/§4/§8) ---

## §4: a right-click ON an event resolves to the byte boundary AFTER it and names it.
## The address is a boundary, not a tick — four zero-tick events can share a tick, and
## an Instrument after the note does not affect that note.
func _test_right_click_resolves_to_a_named_byte_boundary() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	# Instrument(0) | Octave(1) | note(2) | EndBar(3) — all four at tick 0 but the note.
	var a := PackedByteArray([0xAC, 0x05, 0x94, 0x03, 0x60, 0x0C, 0x90])
	var view: Dictionary = PairModel.pair_view(
			_make_feds_bank(a, PackedByteArray([0x90])), 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 700.0, {})
	var base: int = int((view["tracks"][0] as Dictionary).get("offset", 0))
	# Click the Octave chip (event 1, bytes [base+2, base+4)).
	var target := Rect2()
	for chip in lay["chips"]:
		if int(chip.get("track", -1)) == 0 and int(chip.get("event_index", -1)) == 1:
			target = chip["rect"]
	_assert_true(target.size.x > 0.0, "the Octave chip is drawn")
	var ctx: Dictionary = Panel.resolve_context(view, lay, target.get_center())
	_assert_eq(int(ctx.get("at", -1)), base + 4, "the address is the boundary AFTER the anchor")
	_assert_eq(int((ctx.get("anchor", {}) as Dictionary).get("event_index", -1)), 1,
			"…and the anchor is the event that was clicked")
	_assert_eq(str((ctx.get("anchor", {}) as Dictionary).get("label", "")), "Oct3",
			"the menu can NAME it with the code the chip wears")
	_assert_eq(int(ctx.get("track_idx", -1)), 0, "the verb's address is the GLOBAL bank track")
	_assert_eq(int((ctx.get("delete", {}) as Dictionary).get("at", -1)), base + 2,
			"a direct hit on a zero-tick opcode also offers Delete, at ITS bytes")
	# The gutter offers no verbs — but it NAMES itself rather than resolving to silence
	# (2026-08-19e §1); the silent {} was the whole of "right-click didn't do anything".
	var gutter: Dictionary = Panel.resolve_context(view, lay, Vector2(4.0, target.get_center().y))
	_assert_eq(int(gutter.get("track_idx", -1)), -1, "the label gutter offers no verbs")
	_assert_true(str(gutter.get("refused", "")).contains("label strip"),
			"…and says which place it landed on instead: %s" % str(gutter.get("refused", "")))


## §4: "a right-click in empty lane space may still work, but the menu must NAME what
## it resolved to rather than silently picking one of four." It resolves to the
## track's own last item at or before the cursor — and to the track START before them
## all, which is a real address (an Instrument ahead of every note).
func _test_right_click_in_empty_space_names_what_it_resolved_to() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var a := PackedByteArray([0xAC, 0x05, 0x94, 0x03, 0x60, 0x0C, 0x90])
	var view: Dictionary = PairModel.pair_view(
			_make_feds_bank(a, PackedByteArray([0x90])), 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 700.0, {})
	var base: int = int((view["tracks"][0] as Dictionary).get("offset", 0))
	var opcode_lane := Rect2()
	for lane in lay["lanes"]:
		if int(lane.get("track", -1)) == 0 and str(lane.get("kind", "")) == "opcode":
			opcode_lane = lane["rect"]
	_assert_true(opcode_lane.size.y > 0.0, "track A has an Opcodes lane")
	# Far to the right of every chip: resolves to the LAST of the track's own events.
	var far := Vector2(opcode_lane.end.x - 4.0, opcode_lane.get_center().y)
	var ctx: Dictionary = Panel.resolve_context(view, lay, far)
	_assert_eq(int((ctx.get("anchor", {}) as Dictionary).get("event_index", -1)), 3,
			"empty space past everything resolves to the track's last event")
	_assert_eq(int(ctx.get("at", -1)), base + 7, "…and to the boundary after it")
	_assert_true((ctx.get("delete", {}) as Dictionary).is_empty(),
			"nothing was under the cursor, so nothing is offered for deletion")
	# Left of the gutter edge + 1 px: before every chip → the track start, named as such.
	var start_ctx: Dictionary = Panel.resolve_context(
			view, lay, Vector2(Panel.GUTTER_W + 1.0, opcode_lane.get_center().y))
	_assert_true((start_ctx.get("anchor", {}) as Dictionary).is_empty(),
			"before every event, the anchor is the track START")
	_assert_eq(int(start_ctx.get("at", -1)), base, "…which is the track's own first byte")


## §2/§7: the two verbs, both NAMING what the click resolved to, and the Add row
## carrying the corpus menu the popup hangs off it.
func _test_context_actions_name_the_anchor_and_carry_the_corpus() -> void:
	var acts: Array = Page._pair_context_actions({
		"pair_idx": 0, "track": 0, "track_idx": 0, "at": 30,
		"anchor": {"event_index": 1, "label": "Oct3", "tick": 0},
		"direct": true, "delete": {"at": 28, "label": "Oct3"},
		"phantom_boundary": false})
	_assert_eq(acts.size(), 2, "a direct hit offers both verbs — one pair, one place to look")
	if acts.size() != 2:
		return
	_assert_eq(str(acts[0].get("label", "")), "Add opcode after `Oct3` @ tick 0",
			"the Add row names what it resolved to, never a silent pick")
	_assert_eq(str(acts[1].get("label", "")), "Delete `Oct3`", "…and so does Delete")
	var ref: Dictionary = acts[0]["field_ref"]
	_assert_eq(str(ref.get("channel", "")), "sound_def", "the verbs lower through the FEDS channel")
	_assert_eq(int(ref.get("at", -1)), 30, "Add writes at the resolved boundary")
	_assert_eq(int((acts[1]["field_ref"] as Dictionary).get("at", -1)), 28,
			"Delete addresses the event's OWN bytes, not the boundary after it")
	_assert_eq((acts[0].get("options", []) as Array).size(), 51,
			"the Add row carries the corpus menu")
	# Empty space (no direct hit) offers Add alone, named for the start.
	var start_acts: Array = Page._pair_context_actions({
		"pair_idx": 0, "track": 0, "track_idx": 0, "at": 28, "anchor": {},
		"direct": false, "delete": {}, "phantom_boundary": false})
	_assert_eq(start_acts.size(), 1, "with nothing under the cursor there is nothing to delete")
	_assert_eq(str(start_acts[0].get("label", "")), "Add opcode at the start of this track",
			"…and the Add row still says where")


## §3: EndBar is offered ONLY at the phantom's boundary — where the stub's own bytes
## stop and the borrowing starts. That context comes off the resolution, not a guess.
func _test_end_bar_rides_the_phantom_boundary_context() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var Catalog = load("res://src/effects/studio/FedsOpcodeCatalog.gd")
	# Track A is a stub (no EndBar): its own bytes are just the PitchBendRel.
	var view: Dictionary = PairModel.pair_view(
			_make_feds_bank(PackedByteArray([0xD2, 0x08]),
					PackedByteArray([0xAC, 0x0A, 0x90])), 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 700.0, {})
	var target := Rect2()
	for chip in lay["chips"]:
		if int(chip.get("track", -1)) == 0 and not bool(chip.get("flowed", false)):
			target = chip["rect"]
	var ctx: Dictionary = Panel.resolve_context(view, lay, target.get_center())
	_assert_true(bool(ctx.get("phantom_boundary", false)),
			"after the stub's last own event IS the phantom boundary")
	var ops: Array = []
	for o in (Page._pair_context_actions(ctx)[0] as Dictionary)["options"]:
		ops.append(int(o["opcode"]))
	_assert_true(Catalog.END_BAR in ops, "so the menu offers the EndBar that ends the borrowing")
	# The sounding track B ends itself — no phantom, no EndBar on offer.
	var b_ctx: Dictionary = Panel._context_for(view, 1, 0, true)
	_assert_false(bool(b_ctx.get("phantom_boundary", false)),
			"a track with its own EndBar has no phantom boundary")


## The model stamps a borrowed event's owner as a GLOBAL bank track index, but every
## panel coordinate — lanes, selection, the verbs' pair-local track — is 0/1. Before
## this was mapped, clicking a borrowed item in any pair but the first looked for a
## lane that does not exist.
func _test_a_borrowed_items_owner_track_is_pair_local() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	# Four tracks: pair 0 sounds, pair 1's track A is a stub borrowing pair 1's track B.
	var bank = _make_pairs_bank([
		PackedByteArray([0x90]), PackedByteArray([0x90]),
		PackedByteArray([0xD2, 0x08]), PackedByteArray([0xAC, 0x0A, 0x94, 0x03, 0x90])])
	var view: Dictionary = PairModel.pair_view(bank, 1, {}, null)
	_assert_eq(int((view["tracks"][0] as Dictionary).get("track_idx", -1)), 2,
			"pair 1's track A is global track 2")
	var lay: Dictionary = Panel.layout(view, 700.0, {"unwound": {"0:noend": true}})
	var borrowed := 0
	for chip in lay["chips"]:
		if int(chip.get("track", -1)) != 0 or not bool(chip.get("flowed", false)):
			continue
		borrowed += 1
		_assert_eq(int(chip.get("owner_track", -1)), 1,
				"a borrowed chip's owner is the PAIR-LOCAL lane 1, not global track 3")
	_assert_true(borrowed >= 2, "the stub borrows track B's opcodes (%d)" % borrowed)
	# …so the click routes to a lane that exists, and its context addresses global 3.
	var target := Rect2()
	for chip in lay["chips"]:
		if int(chip.get("track", -1)) == 0 and bool(chip.get("flowed", false)):
			target = chip["rect"]
	var ctx: Dictionary = Panel.resolve_context(view, lay, target.get_center())
	_assert_eq(int(ctx.get("track", -1)), 1, "the borrowed click lands on the OWNER's lane")
	_assert_eq(int(ctx.get("track_idx", -1)), 3,
			"…and the verb addresses that lane's global bank track")


## A FEDS bank of N tracks (N/2 pairs) from raw byte streams. Offsets are COMPUTED
## from the stream sizes — a fixture that hand-writes them is where an off-by-one
## truncates a track's trailing EndBar and makes it read as a stub.
func _make_pairs_bank(streams: Array):
	var table := 0x18 + streams.size() * 2
	var offsets: Array = []
	var at := table
	for st in streams:
		offsets.append(at)
		at += (st as PackedByteArray).size()
	var total := at
	var blob := PackedByteArray()
	blob.append_array("feds".to_ascii_buffer())
	blob.append_array([total & 0xFF, (total >> 8) & 0xFF, 0, 0])          # 0x04 data_size
	blob.append_array([(streams.size() / 2) + 1, 0])                      # 0x08 pair_count_plus1
	blob.append_array([7, 0])                                             # 0x0A resource_id
	blob.append_array([table & 0xFF, (table >> 8) & 0xFF, 0, 0])          # 0x0C data_offset
	blob.append_array([0, 0, 0, 0, 0, 0, 0, 0])                           # 0x10 padding → 0x18
	for o in offsets:
		blob.append_array([int(o) & 0xFF, (int(o) >> 8) & 0xFF])
	for st in streams:
		blob.append_array(st)
	return FedsBankScript.parse(blob)


# === The sound-lane DRAG planner (ADR-0085 2026-08-19b §7 stage 2) ============
#
# `SoundDragPlan` is the law of §3 as a pure function: spans in, new tiling out, no
# EffectData / bank / scene. Every case below is byte-fixtured through the REAL decoder and
# the REAL fold, so "what the planner thinks a run is" and "what the picture draws" cannot
# drift — that is the whole point of folding the cells off `fold_spans` rather than off a
# second walk of the stream.


## The cell row: spans and BARE opcodes in event order, and an opcode that fires INSIDE a
## span is not a cell at all — it is the flag that parks a move (§8).
func _test_cells_fold_spans_bare_opcodes_and_flag_an_interior_one() -> void:
	# Instrument | rest(8) | note C(16) | Octave | Fermata(24) | rest(12) | EndBar
	var cells := _drag_cells(PackedByteArray([
			0xAC, 0x05, 0x80, 0x08, 0x60, 0x0B, 0x94, 0x03, 0x81, 0x18, 0x80, 0x0C, 0x90]))
	_assert_eq(_cell_kinds(cells), ["opcode", "rest", "note", "rest", "opcode"],
			"a bare opcode is a CELL (a wall); an interior one is not")
	_assert_eq(int(cells[1]["ticks"]), 8, "the rest cell carries its tick count — the currency")
	_assert_eq(int(cells[2]["ticks"]), 40,
			"the note cell is the whole SPAN: 16 of its own plus the Fermata's 24 raw ticks")
	_assert_eq(int(cells[2]["last_index"]), 4,
			"…and reaches to its last segment, which is where a right-side deposit goes")
	_assert_true(bool(cells[2]["interior_opcode"]),
			"the Octave fires inside the note — the fact that parks a move on it")
	_assert_false(bool(cells[1]["interior_opcode"]), "a rest is always exactly one segment")


## The move, in one line: leading rest `a+k`, trailing rest `b-k`, and NOT ONE NOTE BYTE
## written (§2). The clock does not move — whatever one side spends the other absorbs.
func _test_a_move_spends_one_side_and_absorbs_on_the_other() -> void:
	# rest(8) | note C(16) | rest(12) | EndBar
	var cells := _drag_cells(PackedByteArray([0x80, 0x08, 0x60, 0x0B, 0x80, 0x0C, 0x90]))
	var p := DragPlan.plan(cells, 1, DragPlan.MOVE, 5)
	_assert_true(bool(p["ok"]), "a note with a rest on either side moves")
	_assert_eq(int(p["delta"]), 5, "5 ticks later, as asked")
	_assert_eq(int((p["rests"] as Dictionary).get(2, -1)), 7, "the trailing rest pays 5 of its 12")
	_assert_eq(int((p["rests"] as Dictionary).get(0, -1)), 13, "…and the leading rest absorbs them")
	_assert_eq(int(p["note_index"]), -1, "a move writes NO note byte — it is rest arithmetic")
	_assert_eq(int(p["insert_before"]), -1, "there was already a rest on both sides to re-time")


## §3's law at the wall: clamped, never refused, and the wall is never shortened to make
## room. A rest taken to zero is SPLICED OUT (0), which is how two notes are made adjacent —
## the thing ADR-0095's colour lanes cannot express because `ColorLowering` has no zero.
func _test_a_move_clamps_at_a_wall_and_never_shortens_it() -> void:
	var cells := _drag_cells(PackedByteArray([0x80, 0x08, 0x60, 0x0B, 0x80, 0x0C, 0x90]))
	var p := DragPlan.plan(cells, 1, DragPlan.MOVE, 50)
	_assert_eq(int(p["delta"]), 12, "50 asked, 12 of currency — clamped to what there was")
	_assert_eq(int((p["rests"] as Dictionary).get(2, -1)), 0,
			"the spent rest is spliced out, so the note ends up flush against the next thing")
	_assert_eq(int((p["rests"] as Dictionary).get(0, -1)), 20, "every spent tick lands on the other side")
	_assert_eq(int(p["note_ticks"]), -1, "the note itself is untouched at the wall, never shortened")


## 5932 of 6234 corpus notes have a rest on NEITHER side, so this is the answer a move gives
## 95.2% of the time. It is a clamp to zero, not a refusal: nothing is wrong, there is simply
## nothing to spend, and the drag keeps following the cursor.
func _test_a_move_with_no_rest_beside_it_spends_nothing() -> void:
	# note C(16) | note C(32) | EndBar
	var cells := _drag_cells(PackedByteArray([0x60, 0x0B, 0x60, 0x08, 0x90]))
	var p := DragPlan.plan(cells, 0, DragPlan.MOVE, 5)
	_assert_true(bool(p["ok"]), "packed wall to wall is not an error")
	_assert_eq(int(p["delta"]), 0, "…it is a move with no currency")
	_assert_true((p["rests"] as Dictionary).is_empty(), "and it writes nothing")


## The third wall, the one ADR-0095's colour lanes do not have: rewriting a rest's `pp` ahead
## of an Octave changes WHEN THAT OCTAVE FIRES. So a run is only ever measured through rests
## with no opcode between them.
func _test_the_run_stops_at_a_zero_tick_opcode() -> void:
	# note C(16) | rest(3) | Octave | rest(5) | EndBar
	var cells := _drag_cells(PackedByteArray([0x60, 0x0B, 0x80, 0x03, 0x94, 0x03, 0x80, 0x05, 0x90]))
	_assert_eq(DragPlan.currency(cells, 0, 1), 3,
			"the run stops at the Octave — the 5 ticks beyond it are not this drag's to spend")
	var p := DragPlan.plan(cells, 0, DragPlan.MOVE, 10)
	_assert_eq(int(p["delta"]), 3, "…so a 10-tick drag clamps at 3")
	_assert_eq(int((p["rests"] as Dictionary).get(1, -1)), 0, "the near rest is spent to zero")
	_assert_false((p["rests"] as Dictionary).has(3), "and the rest past the wall is untouched")


## The cascade — 90 of the corpus's rest runs are 2 or 3 long, so this is not a corner. It
## spends NEAREST FIRST: the minimum edit, and the author's spelling of the silence they did
## not reach survives.
func _test_the_cascade_crosses_a_run_of_rests_nearest_first() -> void:
	# note C(16) | rest(3) | rest(5) | EndBar
	var cells := _drag_cells(PackedByteArray([0x60, 0x0B, 0x80, 0x03, 0x80, 0x05, 0x90]))
	_assert_eq(DragPlan.currency(cells, 0, 1), 8, "two contiguous rests are one 8-tick run")
	var p := DragPlan.plan(cells, 0, DragPlan.MOVE, 6)
	_assert_eq(int(p["delta"]), 6, "the drag reaches through the first rest into the second")
	_assert_eq(int((p["rests"] as Dictionary).get(1, -1)), 0, "the near rest goes first, to zero")
	_assert_eq(int((p["rests"] as Dictionary).get(2, -1)), 2, "…then the next one pays the remaining 3")
	_assert_eq(int(p["insert_before"]), 0, "and with no rest to grow on the left, one is INSERTED")
	_assert_eq(int(p["insert_ticks"]), 6, "…carrying every spent tick, so the clock holds still")


## Where the deposit goes when there is no rest to grow: BYTE-ADJACENT to the note, ahead of
## whatever opcode is on that side. `Instrument note(16)` moved right becomes
## `Instrument rest(k) note(16)` — the Instrument still fires at its own tick, which is
## exactly what §3 forbids moving.
func _test_a_deposit_with_no_rest_to_grow_inserts_one_beside_the_note() -> void:
	# Instrument | note C(16) | rest(12) | EndBar
	var cells := _drag_cells(PackedByteArray([0xAC, 0x05, 0x60, 0x0B, 0x80, 0x0C, 0x90]))
	_assert_eq(DragPlan.currency(cells, 1, -1), 0,
			"an opcode on the left is a wall, so there is no currency that way")
	var p := DragPlan.plan(cells, 1, DragPlan.MOVE, 4)
	_assert_eq(int(p["delta"]), 4, "…but moving RIGHT spends the rest on the right")
	_assert_eq(int((p["rests"] as Dictionary).get(2, -1)), 8, "which pays 4 of its 12")
	_assert_eq(int(p["insert_before"]), 1,
			"and the new rest lands between the Instrument and the note, not before the Instrument")
	_assert_eq(int(p["insert_ticks"]), 4, "carrying the whole delta")


## The resize: one flanking rest and the duration byte (§2). Growing is the gesture that
## SPENDS, so it clamps at the wall like a move does.
func _test_a_resize_eats_the_rest_beside_it_and_clamps_at_the_wall() -> void:
	# note C(16) | rest(12) | EndBar
	var cells := _drag_cells(PackedByteArray([0x60, 0x0B, 0x80, 0x0C, 0x90]))
	var p := DragPlan.plan(cells, 0, DragPlan.RESIZE_RIGHT, 5)
	_assert_eq(int(p["delta"]), 5, "the end moves 5 later")
	_assert_eq(int(p["note_index"]), 0, "…which IS a note-byte write, unlike a move")
	_assert_eq(int(p["note_ticks"]), 21, "16 + 5")
	_assert_eq(int((p["rests"] as Dictionary).get(1, -1)), 7, "and the rest beside it pays them")
	var far := DragPlan.plan(cells, 0, DragPlan.RESIZE_RIGHT, 40)
	_assert_eq(int(far["delta"]), 12, "past the wall it clamps at the currency")
	_assert_eq(int(far["note_ticks"]), 28, "…eating the rest whole")
	_assert_eq(int((far["rests"] as Dictionary).get(1, -1)), 0, "which splices it out")


## Shrinking is free: it MAKES silence rather than spending it, so it works on the 4615
## single-segment notes that have no rest at all beside them — the 95% case a move cannot
## touch. The delta is absorbed by a rest that is grown, or inserted when there is none.
func _test_a_shrink_makes_silence_and_needs_no_currency() -> void:
	# note C(16) | note C(32) | EndBar — walled on both sides
	var packed := _drag_cells(PackedByteArray([0x60, 0x0B, 0x60, 0x08, 0x90]))
	var p := DragPlan.plan(packed, 0, DragPlan.RESIZE_RIGHT, -6)
	_assert_eq(int(p["delta"]), -6, "shrinking needs no currency — it creates it")
	_assert_eq(int(p["note_ticks"]), 10, "16 - 6")
	_assert_eq(int(p["insert_before"]), 1, "and a rest is inserted between the two notes")
	_assert_eq(int(p["insert_ticks"]), 6, "…so the SECOND note still fires at tick 16")
	# With a rest already there, it grows rather than a second one being written.
	var beside := _drag_cells(PackedByteArray([0x60, 0x0B, 0x80, 0x0C, 0x90]))
	var q := DragPlan.plan(beside, 0, DragPlan.RESIZE_RIGHT, -6)
	_assert_eq(int((q["rests"] as Dictionary).get(1, -1)), 18, "the existing rest absorbs it")
	_assert_eq(int(q["insert_before"]), -1, "no second rest is manufactured beside it")


## The LEFT grip (ADR-0095 §1 transferred by §6): the span's start moves and its end sits
## still, so nothing downstream is re-timed. Dragging left GROWS the note out of the silence
## in front of it — literally the capability ADR-0095 was opened for.
func _test_a_left_resize_moves_the_start_and_leaves_the_end_alone() -> void:
	# rest(24) | note C(16) | EndBar
	var cells := _drag_cells(PackedByteArray([0x80, 0x18, 0x60, 0x0B, 0x90]))
	var grow := DragPlan.plan(cells, 1, DragPlan.RESIZE_LEFT, -8)
	_assert_eq(int(grow["delta"]), -8, "the start moves 8 earlier")
	_assert_eq(int(grow["note_ticks"]), 24, "so the note is 8 longer")
	_assert_eq(int((grow["rests"] as Dictionary).get(0, -1)), 16, "and the rest in front pays them")
	var shrink := DragPlan.plan(cells, 1, DragPlan.RESIZE_LEFT, 5)
	_assert_eq(int(shrink["note_ticks"]), 11, "dragging the start later shortens the note")
	_assert_eq(int((shrink["rests"] as Dictionary).get(0, -1)), 29,
			"…and the rest in front absorbs the delta, so the END never moves")


## Refused, with a reason, never silently reshaped — the two §8 parks plus the kind error.
func _test_the_drag_refuses_a_rest_an_interior_opcode_and_a_multi_segment_resize() -> void:
	var cells := _drag_cells(PackedByteArray([0x80, 0x08, 0x60, 0x0B, 0x80, 0x0C, 0x90]))
	var on_rest := DragPlan.plan(cells, 0, DragPlan.MOVE, 4)
	_assert_false(bool(on_rest["ok"]), "a rest is the CURRENCY, not the cargo — it does not drag")
	_assert_true(str(on_rest["reason"]).contains("paint"),
			"…and the refusal names the verb that does put a note inside one")
	# note C(16) | Octave | Fermata(24) | rest(12) | EndBar — a multi-segment span with an
	# opcode firing inside it.
	var multi := _drag_cells(PackedByteArray([0x60, 0x0B, 0x94, 0x03, 0x81, 0x09, 0x80, 0x0C, 0x90]))
	_assert_false(bool(DragPlan.plan(multi, 0, DragPlan.MOVE, 4)["ok"]),
			"a move would carry the interior opcode with the note — parked, not guessed")
	_assert_false(bool(DragPlan.plan(multi, 0, DragPlan.RESIZE_RIGHT, 4)["ok"]),
			"and which segment absorbs a length delta is undesigned — refused EXPLICITLY")
	# The same span without the interior opcode still refuses the resize, and still moves.
	var clean := _drag_cells(PackedByteArray([0x60, 0x0B, 0x81, 0x09, 0x80, 0x0C, 0x90]))
	_assert_true(bool(DragPlan.plan(clean, 0, DragPlan.MOVE, 4)["ok"]),
			"a multi-segment span with nothing firing inside it moves — the whole span translates")
	_assert_false(bool(DragPlan.plan(clean, 0, DragPlan.RESIZE_RIGHT, 4)["ok"]),
			"…but the length question is about SEGMENTS, so the resize still refuses it")


## The note form's own bounds are a wall like any other: `vv 00 tt` carries one duration
## byte, and below one tick a note sounds nothing (the un-rest's own refusal).
func _test_a_resize_never_shortens_a_note_out_of_existence() -> void:
	# note C(4) | rest(12) | EndBar
	var small := _drag_cells(PackedByteArray([0x60, 0x10, 0x80, 0x0C, 0x90]))
	var p := DragPlan.plan(small, 0, DragPlan.RESIZE_RIGHT, -10)
	_assert_eq(int(p["delta"]), -3, "a 4-tick note gives up 3 ticks, not 10")
	_assert_eq(int(p["note_ticks"]), 1, "…and stops at one tick rather than vanishing")
	_assert_eq(int((p["rests"] as Dictionary).get(1, -1)), 15, "the rest absorbs exactly what it lost")
	# rest(200) | note C(192) | EndBar — plenty of currency, no room in the duration byte.
	var big := _drag_cells(PackedByteArray([0x80, 0xC8, 0x60, 0x01, 0x90]))
	var q := DragPlan.plan(big, 1, DragPlan.RESIZE_LEFT, -100)
	_assert_eq(int(q["delta"]), -63, "192 + 63 = 255, the largest tick count a note can say")
	_assert_eq(int(q["note_ticks"]), 255, "…so it clamps at the form's ceiling")
	_assert_eq(int((q["rests"] as Dictionary).get(0, -1)), 137, "and only the spent ticks leave the rest")


## The planner's fixture bridge: bytes → the REAL decoder → the REAL fold → cells. Fixturing
## from bytes rather than hand-written span dicts is what keeps "what the planner calls a run"
## and "what the lane draws" the same question.
func _drag_cells(stream: PackedByteArray) -> Array:
	var events: Array = SMD.decode_track(stream, stream.size())
	return DragPlan.build_cells(PairModel.fold_spans(events), events.size())


func _cell_kinds(cells: Array) -> Array:
	var out: Array = []
	for c in cells:
		out.append(str(c["kind"]))
	return out


# === The drag VERB (ADR-0085 2026-08-19b §7 stage 4) ==========================
#
# `SoundDragPlan` decides; `SoundDefChannel.drag_event` writes. These guard the writing:
# which bytes move, which are carried verbatim, and that the clock never moves.


## §2's headline: a move rewrites two `0x80 pp` params, both same-size, and touches NOT ONE
## note byte. It is the cheapest of the three verbs rather than the middle one.
func _test_a_move_rewrites_the_two_rests_and_no_note_byte() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	# rest(8) | note C(16) | rest(12) | EndBar
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(
			PackedByteArray([0x80, 0x08, 0x60, 0x0B, 0x80, 0x0C, 0x90]), PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	var before_tick: int = int(PairModel.pair_view(data.feds_bank, 0, {}, null)
			.get("tracks", [])[0].get("end_tick", -1))
	var res: Dictionary = Channel.drag_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base + 2,
		"gesture": "move", "delta_ticks": 5})
	_assert_true(bool(res.get("structural", false)), "a move is a structural edit")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)),
			[0x80, 0x0D, 0x60, 0x0B, 0x80, 0x07, 0x90],
			"8 → 13 and 12 → 7; the note's two bytes are byte-for-byte what they were")
	_assert_eq(int(res.get("after_bytes", -1)), int(res.get("before_bytes", -2)),
			"…so a move never relocates a byte and needs no encoder")
	_assert_eq(int(res.get("delta_ticks", 0)), 5, "the verb reports what it achieved")
	_assert_eq(int(PairModel.pair_view(data.feds_bank, 0, {}, null)
			.get("tracks", [])[0].get("end_tick", -1)), before_tick,
			"the clock does not move — whatever one side spends the other absorbs")


## A rest spent to zero is SPLICED OUT, which is how two notes are made adjacent. ADR-0095's
## colour lanes cannot express this: `ColorLowering` has no zero, so a merely-clamping drag
## always leaves a 1-frame spacer behind that no verb can remove.
func _test_a_move_at_a_wall_splices_the_rest_out_and_makes_two_notes_adjacent() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	# note C(16) | rest(12) | note C(32) | EndBar
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(
			PackedByteArray([0x60, 0x0B, 0x80, 0x0C, 0x60, 0x08, 0x90]), PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	var res: Dictionary = Channel.drag_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base,
		"gesture": "move", "delta_ticks": 40})
	_assert_eq(int(res.get("delta_ticks", 0)), 12, "clamped at the 12 ticks there were")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)),
			[0x80, 0x0C, 0x60, 0x0B, 0x60, 0x08, 0x90],
			"the rest moves to the far side whole — the two notes are now flush")
	_assert_eq(int(res.get("event_index", -1)), 1,
			"and the selection follows the note the author is holding, now event 1")


## §3's third wall on the DEPOSIT side. `Instrument note(16)` moved right must not grow a rest
## AHEAD of the Instrument — that would re-time when the instrument changes. The new rest goes
## between them, byte-adjacent to the note.
func _test_a_deposit_beside_an_opcode_keeps_that_opcodes_firing_tick() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	# rest(8) | Instrument | note C(16) | rest(12) | EndBar
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(
			PackedByteArray([0x80, 0x08, 0xAC, 0x05, 0x60, 0x0B, 0x80, 0x0C, 0x90]),
			PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	var before: Dictionary = PairModel.pair_view(data.feds_bank, 0, {}, null).get("tracks", [])[0]
	var inst_tick: int = int(_command_at(before, 1).get("tick", -1))
	_assert_eq(inst_tick, 8, "fixture: the Instrument fires at tick 8, behind the leading rest")
	var res: Dictionary = Channel.drag_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base + 4,
		"gesture": "move", "delta_ticks": 4})
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)),
			[0x80, 0x08, 0xAC, 0x05, 0x80, 0x04, 0x60, 0x0B, 0x80, 0x08, 0x90],
			"the new rest lands BETWEEN the Instrument and the note, never in front of it")
	var after: Dictionary = PairModel.pair_view(data.feds_bank, 0, {}, null).get("tracks", [])[0]
	_assert_eq(int(_command_at(after, 1).get("tick", -1)), inst_tick,
			"…so the Instrument still fires at 8: the drag re-timed silence, not authored work")
	_assert_eq(int(res.get("event_index", -1)), 3, "and the note is event 3 now, not 2")


## A resize re-TIMES a note; it does not re-author it. The un-rest writes the corpus velocity
## and key because it has no note to preserve — here there is one, so it survives the rewrite.
func _test_a_resize_keeps_the_notes_own_velocity_and_key() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	# note E(16) at velocity 0x50 | rest(12) | EndBar  (key 4 → data byte 4*19 + 11 = 87)
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(
			PackedByteArray([0x50, 87, 0x80, 0x0C, 0x90]), PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	_assert_false(Channel.drag_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base,
		"gesture": "resize_right", "delta_ticks": 8}).is_empty(), "the end grip grows the note")
	var n: Dictionary = (PairModel.pair_view(data.feds_bank, 0, {}, null)
			.get("tracks", [])[0].get("notes", []) as Array)[0]
	_assert_eq(int(n.get("duration_ticks", -1)), 24, "16 + 8, eaten out of the rest beside it")
	_assert_eq(int(n.get("velocity", -1)), 0x50, "its own velocity, not the corpus default")
	_assert_eq(int(n.get("relative_key", -1)), 4, "and its own key")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)), [0x50, 4 * 19 + 9, 0x80, 0x04, 0x90],
			"24 is a table value, so the note stays two bytes and the rest keeps the change")


## Shrinking MAKES silence rather than spending it, so it reaches the 95% of the corpus that
## is packed wall to wall. The inserted rest is what holds the next note's firing tick still.
func _test_a_shrink_between_two_notes_writes_the_rest_that_holds_the_clock() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	# note C(16) | note C(32) | EndBar — no currency anywhere
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(
			PackedByteArray([0x60, 0x0B, 0x60, 0x08, 0x90]), PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	var before: Dictionary = PairModel.pair_view(data.feds_bank, 0, {}, null).get("tracks", [])[0]
	var second_tick: int = int((before.get("notes", []) as Array)[1].get("start_tick", -1))
	_assert_true(Channel.drag_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base,
		"gesture": "move", "delta_ticks": 5}).is_empty() == false,
		"a move here is a legal no-op, not a refusal")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)), [0x60, 0x0B, 0x60, 0x08, 0x90],
			"…and with no currency it writes nothing")
	_assert_false(Channel.drag_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base,
		"gesture": "resize_right", "delta_ticks": -8}).is_empty(),
		"but the end grip still shortens it — that CREATES currency")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)), [0x60, 0x0E, 0x80, 0x08, 0x60, 0x08, 0x90],
			"16 → 8 and an 8-tick rest is inserted after it")
	var after: Dictionary = PairModel.pair_view(data.feds_bank, 0, {}, null).get("tracks", [])[0]
	_assert_eq(int((after.get("notes", []) as Array)[1].get("start_tick", -1)), second_tick,
			"so the SECOND note still fires at 16 — the whole point of the compensating rest")


## The minimum edit: bytes outside the affected event range are carried verbatim, interior
## opcodes and everything past the decoder's EndBar stop included — `_rest_span`'s contract.
func _test_the_drag_carries_untouched_bytes_verbatim() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	# rest(8) | note C(16) | Octave | Fermata(24) | rest(12) | Dynamics | EndBar | junk
	var stream := PackedByteArray([0x80, 0x08, 0x60, 0x0B, 0x94, 0x03, 0x81, 0x18,
			0x80, 0x0C, 0xE0, 0x40, 0x90, 0xAB, 0xCD])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(stream, PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	# The span carries an interior opcode, so a MOVE is parked — but a resize is refused for
	# a different reason, and neither may write a byte.
	_assert_true(Channel.drag_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base + 2,
		"gesture": "move", "delta_ticks": 4}).is_empty(), "an interior opcode parks the move")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)), Array(stream), "…without a byte moving")
	# The same track with the Octave taken out: the move runs, and the Fermata, the Dynamics,
	# the EndBar and the two junk bytes past it all survive untouched.
	var clean := PackedByteArray([0x80, 0x08, 0x60, 0x0B, 0x81, 0x18,
			0x80, 0x0C, 0xE0, 0x40, 0x90, 0xAB, 0xCD])
	var cdata = EffectDataClass.new()
	cdata.feds_bank = _make_feds_bank(clean, PackedByteArray([0x90]))
	var cbase: int = cdata.feds_bank.track_offsets[0]
	_assert_false(Channel.drag_event(cdata, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": cbase + 2,
		"gesture": "move", "delta_ticks": 4}).is_empty(),
		"a multi-segment span with nothing firing inside it moves — the whole span translates")
	_assert_eq(Array(cdata.feds_bank.get_track_bytes(0)),
			[0x80, 0x0C, 0x60, 0x0B, 0x81, 0x18, 0x80, 0x08, 0xE0, 0x40, 0x90, 0xAB, 0xCD],
			"only the two rests changed; the Fermata, Dynamics, EndBar and trailing junk stand")


## Refused, never clamped into something else — and every refusal leaves the blob pristine.
func _test_drag_refuses_a_segment_a_rest_and_the_parked_shapes() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	# rest(8) | note C(16) | Fermata(24) | rest(12) | EndBar
	var stream := PackedByteArray([0x80, 0x08, 0x60, 0x0B, 0x81, 0x18, 0x80, 0x0C, 0x90])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(stream, PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	var ref := {"channel": "sound_def", "pair_idx": 0, "track_idx": 0,
			"gesture": "move", "delta_ticks": 4}
	var seg := ref.duplicate(); seg["at"] = base + 4
	_assert_true(Channel.drag_event(data, seg).is_empty(),
			"a Fermata is a SEGMENT of the note's span, not a span of its own")
	var on_rest := ref.duplicate(); on_rest["at"] = base
	_assert_true(Channel.drag_event(data, on_rest).is_empty(),
			"a rest is the currency a drag spends, not the cargo it moves")
	var multi := ref.duplicate()
	multi["at"] = base + 2
	multi["gesture"] = "resize_right"
	_assert_true(Channel.drag_event(data, multi).is_empty(),
			"and a resize refuses a multi-segment span EXPLICITLY (ADR-0085 19b §8)")
	var nowhere := ref.duplicate(); nowhere["at"] = base + 3
	_assert_true(Channel.drag_event(data, nowhere).is_empty(), "a mid-event address names nothing")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)), Array(stream),
			"…and not one of the four wrote a byte")


## A drag pulled back to where it started must still SWAP, or the pair views keep drawing the
## previous motion's tiling — the pristine re-plan restores the bytes and the picture has to
## follow. So a zero-tick gesture is a structural result with identical bytes, not a {}.
func _test_a_clamped_drag_still_swaps_so_the_picture_is_never_stale() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	var stream := PackedByteArray([0x60, 0x0B, 0x60, 0x08, 0x90])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(stream, PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	var res: Dictionary = Channel.drag_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base,
		"gesture": "move", "delta_ticks": 9})
	_assert_true(bool(res.get("structural", false)), "clamped flat is still a structural result")
	_assert_eq(int(res.get("delta_ticks", -1)), 0, "…reporting the zero it achieved")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)), Array(stream), "with the bytes identical")


## ADR-0087 dec. 29: every byte-writing path re-derives the opcode verdicts. A moved
## note moves the classifier's first-note anchor, so skipping it is a silent wrong answer.
func _test_dragging_re_derives_the_opcode_verdicts() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	var Verdicts = load("res://src/effects/studio/FedsOpcodeVerdicts.gd")
	# note D(16)(0) | rest(12)(1) | Octave(2) | note D(32)(3) | EndBar(4)
	var a := PackedByteArray([0x60, 0x2F, 0x80, 0x0C, 0x94, 0x03, 0x60, 0x2C, 0x90])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	var before: Dictionary = Verdicts.verdicts(
			PairModel.pair_view(data.feds_bank, 0, {}, null).get("tracks", [])[0])
	_assert_eq(str(before.get("per_event", {}).get(2, "")), Verdicts.LIVE,
			"fixture: the Octave sits behind a note, so it reads Live")
	_assert_false(Channel.drag_event(data, {
		"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base,
		"gesture": "move", "delta_ticks": 12}).is_empty(), "the first note moves to the wall")
	var after: Dictionary = Verdicts.verdicts(
			PairModel.pair_view(data.feds_bank, 0, {}, null).get("tracks", [])[0])
	_assert_eq(str(after.get("per_event", {}).get(2, "")), Verdicts.LIVE,
			"…and the verdicts are re-read off the new tiling, not carried over stale")
	_assert_eq((after.get("per_event", {}) as Dictionary).size(),
			(before.get("per_event", {}) as Dictionary).size(),
			"the event count is the same: the rest moved sides, it did not disappear")


## ADR-0095 §4, generalized here: one gesture is ONE undo whose restore is the pre-DRAG bank,
## and every motion re-plans from that pristine state — so dragging past a rest and back
## brings the rest back, WITHOUT abandoning the gesture. Without the re-plan, motion 2 would
## compound on motion 1's splices and 12 + 12 would walk two rests instead of one.
func _test_one_drag_is_one_undo_and_every_motion_re_plans_from_pristine() -> void:
	var Session = load("res://src/effects/studio/EffectEditSession.gd")
	var stream := PackedByteArray([0x80, 0x08, 0x60, 0x0B, 0x80, 0x0C, 0x90])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(stream, PackedByteArray([0x90]))
	var pristine = data.feds_bank
	var base: int = pristine.track_offsets[0]
	var session = Session.new(data)
	var ref := {"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base + 2,
			"gesture": "move"}
	session.begin_coalesce(ref)
	var m1 := ref.duplicate(); m1["delta_ticks"] = 5
	_assert_false(session.drag_event(m1).is_empty(), "motion 1 moves the note 5 ticks later")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)),
			[0x80, 0x0D, 0x60, 0x0B, 0x80, 0x07, 0x90], "13 / 7")
	var m2 := ref.duplicate(); m2["delta_ticks"] = 9
	_assert_false(session.drag_event(m2).is_empty(), "motion 2 asks for 9 from the START")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)),
			[0x80, 0x11, 0x60, 0x0B, 0x80, 0x03, 0x90],
			"17 / 3 — planned against the PRE-DRAG 8 / 12, not compounded on 13 / 7")
	var m3 := ref.duplicate(); m3["delta_ticks"] = 0
	_assert_false(session.drag_event(m3).is_empty(), "dragging back to the start is a motion too")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)), Array(stream),
			"…and it restores the pristine tiling while the mouse is still held")
	session.end_coalesce()
	_assert_true(session.undo(), "the whole gesture undoes")
	_assert_true(data.feds_bank == pristine, "…back to the pre-drag bank, in ONE step")
	_assert_false(session.undo(), "and there was only ever one entry: one drag, one undo")


## The command chip a track's decoded event `ei` projects to, or {}.
func _command_at(track: Dictionary, ei: int) -> Dictionary:
	for c in track.get("commands", []):
		if int(c.get("event_index", -1)) == ei:
			return c
	return {}


# === The lane's DRAG gesture (ADR-0085 2026-08-19b §7 stage 3) ================
#
# The surface, guarded without pixels: `_place_grips`, `drag_target` and `drag_motion` are
# pure over an already-computed layout, the way `hit_in` and `resolve_context` are.


## A grip belongs only to a boundary a drag can actually spend across. 5932 of 6234 corpus
## notes are walled on both sides, so most bars draw none — that is the corpus, said out
## loud, rather than a phantom handle over a drag that cannot move.
func _test_a_grip_is_drawn_only_where_a_drag_can_spend() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	# note C(48) | rest(48) | note C(48) | note C(48) | EndBar
	var bank = _make_feds_bank(
			PackedByteArray([0x60, 0x06, 0x80, 0x30, 0x60, 0x06, 0x60, 0x06, 0x90]),
			PackedByteArray([0x90]))
	var view: Dictionary = PairModel.pair_view(bank, 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 900.0, {}, null, {})
	var sides: Dictionary = {}
	for g in lay["grips"]:
		sides[str(g["event_index"]) + str(g["side"])] = true
	_assert_true(sides.has("0right"), "the first note has a rest on its right — it owns a grip")
	_assert_false(sides.has("0left"), "…and nothing on its left, so no handle there")
	_assert_true(sides.has("2left"), "the note after the rest owns the same boundary from the other side")
	_assert_false(sides.has("2right"), "but it is walled by the next note")
	_assert_false(sides.has("3left"), "which in turn has no currency at all")
	_assert_false(sides.has("3right"), "…on either side, so it draws none — the 95% case")
	_assert_eq((lay["grips"] as Array).size(), 2, "one boundary, one grip per side, and no others")
	# A rest bar owns no grips of its own: it IS the currency, and its own gesture is the paint.
	for g in lay["grips"]:
		_assert_true(int(g["event_index"]) != 1, "the rest bar carries no grip of its own")


## ADR-0095 §1's band, transferred: CENTRED on the boundary, so grabbing either side of the
## line writes the same number. What is new here is the CAP — this lane's bars host two
## gestures where a colour tile hosts one, so a full-width band on a narrow bar would swallow
## the body drag whole.
func _test_a_grip_band_straddles_the_boundary_and_is_capped_on_a_narrow_bar() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var bank = _make_feds_bank(
			PackedByteArray([0x60, 0x06, 0x80, 0x30, 0x60, 0x06, 0x90]), PackedByteArray([0x90]))
	var view: Dictionary = PairModel.pair_view(bank, 0, {}, null)
	var wide: Dictionary = Panel.layout(view, 4000.0, {}, null, {})
	var note_bar := _bar_for(wide, 0, 0)
	var grip := _grip_for(wide, 0, "right")
	_assert_false(grip.is_empty(), "fixture: the boundary carries a grip")
	var gr: Rect2 = grip["rect"]
	_assert_eq(gr.get_center().x, (note_bar["rect"] as Rect2).end.x,
			"the band is centred ON the boundary, not inset inside either tile")
	_assert_eq(gr.size.x, Panel.GRIP_W, "at this zoom it is the full 9 px")
	_assert_true(gr.size.x < (note_bar["rect"] as Rect2).size.x * 0.75,
			"…and still leaves most of the bar as body — the move has somewhere to start")
	# Zoomed out far enough that a quarter of the narrower bar is under the floor, the grip
	# disappears rather than eating the whole bar. The menu row is the zoom-independent path.
	var zoomed = Axis.new()
	zoomed.configure(Panel.GUTTER_W + 8.0, 0.3)
	var tight: Dictionary = Panel.layout(view, 4000.0, {}, zoomed, {})
	_assert_true((_bar_for(tight, 0, 0)["rect"] as Rect2).size.x < 6.0,
			"fixture: zoomed out, a 48-tick span is a few pixels wide")
	_assert_true((tight["grips"] as Array).is_empty(),
			"below the floor a bar has no room for two gestures, so it offers one")


## Which gesture a press arms is decided by what is under the cursor: a grip, a rest bar, or
## a note bar's body. The grip wins over the bar it straddles — that is what "centred on the
## boundary" means.
func _test_a_press_arms_the_gesture_the_bar_under_it_owns() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var bank = _make_feds_bank(
			PackedByteArray([0x60, 0x06, 0x80, 0x30, 0x60, 0x06, 0x90]), PackedByteArray([0x90]))
	var view: Dictionary = PairModel.pair_view(bank, 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 4000.0, {}, null, {})
	var note_bar := _bar_for(lay, 0, 0)
	var rest_bar := _bar_for(lay, 0, 1)
	var nr: Rect2 = note_bar["rect"]
	var rr: Rect2 = rest_bar["rect"]
	var body: Dictionary = Panel.drag_target(view, lay, Vector2(nr.position.x + nr.size.x * 0.5, nr.get_center().y))
	_assert_eq(str(body.get("gesture", "")), "move", "a note bar's interior drags the note")
	_assert_eq(int(body.get("at", -1)), int(bank.track_offsets[0]),
			"…addressed by the span head's byte boundary, exactly as the un-rest is")
	_assert_eq(int(body.get("span_ticks", 0)), 48, "and carrying the bar's own tick count")
	var paint: Dictionary = Panel.drag_target(view, lay, Vector2(rr.position.x + rr.size.x * 0.5, rr.get_center().y))
	_assert_eq(str(paint.get("gesture", "")), "paint", "a rest bar drags out a note instead")
	_assert_eq(int(paint.get("grab_ticks", -1)), 24, "…starting at the tick the grab read off the bar")
	# One pixel INSIDE the rest bar, but inside the grip band, is still the note's resize:
	# either half of the band writes the same number (ADR-0095 §1).
	var on_grip: Dictionary = Panel.drag_target(view, lay, Vector2(nr.end.x + 2.0, nr.get_center().y))
	_assert_eq(str(on_grip.get("gesture", "")), "resize_right",
			"the band straddles the boundary — the rest's first pixels resize the note")
	_assert_eq(int(on_grip.get("event_index", -1)), 0, "…rooted on the note, whose end it moves")
	var left_grip: Dictionary = Panel.drag_target(view, lay, Vector2(rr.end.x - 2.0, rr.get_center().y))
	_assert_eq(str(left_grip.get("gesture", "")), "resize_left",
			"and the rest's LAST pixels move the following note's start")
	_assert_eq(int(left_grip.get("event_index", -1)), 2, "…rooted on that note")


## A press that would arm a gesture which cannot move arms NOTHING, so it stays a plain
## selection. The alternative — a live drag that writes zero every motion — would read as a
## broken handle rather than as an honest wall.
func _test_a_walled_note_and_a_parked_span_arm_nothing() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	# note C(48) | note C(48) | EndBar — packed wall to wall
	var packed = _make_feds_bank(
			PackedByteArray([0x60, 0x06, 0x60, 0x06, 0x90]), PackedByteArray([0x90]))
	var pview: Dictionary = PairModel.pair_view(packed, 0, {}, null)
	var play: Dictionary = Panel.layout(pview, 4000.0, {}, null, {})
	var pb := _bar_for(play, 0, 0)
	_assert_true(Panel.drag_target(pview, play,
			(pb["rect"] as Rect2).get_center()).is_empty(),
			"a note with no rest on either side has nothing to spend — no drag is armed")
	_assert_true((play["grips"] as Array).is_empty(), "…and no grips either")
	# note C(48) | Octave | Fermata(48) | rest(48) | EndBar — the §8 park.
	var parked = _make_feds_bank(
			PackedByteArray([0x60, 0x06, 0x94, 0x03, 0x81, 0x30, 0x80, 0x30, 0x90]),
			PackedByteArray([0x90]))
	var kview: Dictionary = PairModel.pair_view(parked, 0, {}, null)
	var klay: Dictionary = Panel.layout(kview, 4000.0, {}, null, {})
	var kb := _bar_for(klay, 0, 0)
	_assert_true(Panel.drag_target(kview, klay, (kb["rect"] as Rect2).get_center()).is_empty(),
			"an opcode firing INSIDE the span parks the move, so the body arms nothing")
	_assert_true((klay["grips"] as Array).is_empty(),
			"and a multi-segment span refuses the resize, so it draws no grip over the refusal")


## §5's law at the gesture: the pixel became ticks at GRAB time, and a motion only ever
## multiplies a distance. So the axis re-anchoring under a structural edit can never make a
## later motion address a different span.
func _test_a_motion_reports_ticks_from_the_grab_not_the_axis() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var bank = _make_feds_bank(
			PackedByteArray([0x60, 0x06, 0x80, 0x30, 0x60, 0x06, 0x90]), PackedByteArray([0x90]))
	var view: Dictionary = PairModel.pair_view(bank, 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 4000.0, {}, null, {})
	var bar := _bar_for(lay, 0, 0)
	var r: Rect2 = bar["rect"]
	var drag: Dictionary = Panel.drag_target(view, lay, Vector2(r.position.x + r.size.x * 0.5, r.get_center().y))
	var px_per_tick: float = r.size.x / 48.0
	var m: Dictionary = Panel.drag_motion(drag, float(drag["start_x"]) + px_per_tick * 12.0)
	_assert_eq(str(m.get("verb", "")), "drag", "a move lowers to the drag verb")
	_assert_eq(str(m.get("gesture", "")), "move", "…carrying which gesture it is")
	_assert_eq(int(m.get("delta_ticks", 0)), 12, "12 ticks' worth of pixels is 12 ticks")
	var back: Dictionary = Panel.drag_motion(drag, float(drag["start_x"]) - px_per_tick * 5.0)
	_assert_eq(int(back.get("delta_ticks", 0)), -5,
			"and the delta is measured from the GRAB, so dragging back is a smaller number, "
			+ "never a second edit compounded on the first")


## The paint drag: the range between the grab tick and the cursor tick, either way round. A
## zero-length range writes nothing rather than manufacturing the zero-tick note the un-rest
## refuses to sound.
func _test_a_paint_drag_reports_the_range_between_the_grab_and_the_cursor() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var bank = _make_feds_bank(PackedByteArray([0x80, 0x30, 0x60, 0x06, 0x90]),
			PackedByteArray([0x90]))
	var view: Dictionary = PairModel.pair_view(bank, 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 4000.0, {}, null, {})
	var bar := _bar_for(lay, 0, 0)
	var r: Rect2 = bar["rect"]
	var px_per_tick: float = r.size.x / 48.0
	var drag: Dictionary = Panel.drag_target(view, lay, Vector2(r.position.x + px_per_tick * 12.0, r.get_center().y))
	_assert_eq(int(drag.get("grab_ticks", -1)), 12, "the grab landed 12 ticks in")
	var fwd: Dictionary = Panel.drag_motion(drag, float(drag["start_x"]) + px_per_tick * 20.0)
	_assert_eq(str(fwd.get("verb", "")), "paint", "a rest bar's drag lowers to the paint")
	_assert_eq(int(fwd.get("offset_ticks", -1)), 12, "starting at the grab")
	_assert_eq(int(fwd.get("duration_ticks", -1)), 20, "and running to the cursor")
	var rev: Dictionary = Panel.drag_motion(drag, float(drag["start_x"]) - px_per_tick * 8.0)
	_assert_eq(int(rev.get("offset_ticks", -1)), 4, "dragging BACK paints the span behind the grab")
	_assert_eq(int(rev.get("duration_ticks", -1)), 8, "…which is the same range read the other way")
	_assert_true(Panel.drag_motion(drag, float(drag["start_x"])).is_empty(),
			"and a zero-length range writes nothing — no zero-tick note is manufactured")
	# Past the end of the rest it CLAMPS: the paint verb refuses rather than clamps, so the
	# surface must not hand it something the span cannot hold.
	var past: Dictionary = Panel.drag_motion(drag, float(drag["start_x"]) + px_per_tick * 400.0)
	_assert_eq(int(past.get("offset_ticks", -1)) + int(past.get("duration_ticks", -1)), 48,
			"a drag past the end stops at the last tick of the span it started in")


## What the page lowers each gesture to. The ADDRESS half is the grab's and is identical for
## every motion — which is what keeps it valid after a motion has spliced a rest out from in
## front of the span, because the session restores the pristine bytes before each dispatch.
func _test_the_page_lowers_each_gesture_to_its_own_field_ref() -> void:
	var Page = load("res://src/effects/studio/EffectStudioPage.gd")
	var grab := {"pair_idx": 1, "track": 0, "track_idx": 2, "at": 4096, "gesture": "resize_left"}
	var opened: Dictionary = Page._pair_drag_ref(grab)
	_assert_eq(str(opened.get("channel", "")), "sound_def", "the drag is a sound_def verb")
	_assert_eq(int(opened.get("at", -1)), 4096, "addressed by the grabbed span head's boundary")
	var moved := grab.duplicate()
	moved["verb"] = "drag"
	moved["delta_ticks"] = -7
	var mref: Dictionary = Page._pair_drag_ref(moved)
	_assert_eq(str(mref.get("gesture", "")), "resize_left", "a resize carries which edge it is")
	_assert_eq(int(mref.get("delta_ticks", 0)), -7, "…and one signed delta")
	_assert_false(mref.has("offset_ticks"), "and no paint numbers it does not use")
	var painted := grab.duplicate()
	painted["verb"] = "paint"
	painted["offset_ticks"] = 12
	painted["duration_ticks"] = 20
	var pref: Dictionary = Page._pair_drag_ref(painted)
	_assert_eq(int(pref.get("offset_ticks", -1)), 12, "a paint carries where the note starts")
	_assert_eq(int(pref.get("duration_ticks", -1)), 20, "…and how long it is")
	_assert_false(pref.has("delta_ticks"), "and no delta it does not use")
	_assert_eq(int(pref.get("at", -1)), int(opened.get("at", -1)),
			"both motions and the bracket that opened share ONE address, so they coalesce")


## This track's own (non-ghost, non-borrowed) span bar for a decoded event index.
func _bar_for(lay: Dictionary, t: int, event_index: int) -> Dictionary:
	for b in lay["span_bars"]:
		if int(b.get("track", -1)) == t and int(b.get("event_index", -1)) == event_index \
				and not bool(b.get("ghost", false)) and not bool(b.get("flowed", false)):
			return b
	return {}


func _grip_for(lay: Dictionary, event_index: int, side: String) -> Dictionary:
	for g in lay["grips"]:
		if int(g.get("event_index", -1)) == event_index and str(g.get("side", "")) == side:
			return g
	return {}


## --- The OUTRO (ADR-0085 amendment 2026-08-19c) --------------------------------
##
## The one verb on this lane that moves the clock. Everything before it is a
## substitution inside a fixed tick total; this rewrites the silence between a track's
## last authored event and its terminator, which is the one write that re-times nothing.


## The read: the outro is the RUN of `0x80` rests immediately before the `0x90 EndBar`,
## and it stops at the first non-rest. 1917 of the corpus's 1928 terminated tracks have
## none at all, so "absent" is the normal answer and has to be a real one.
func _test_outro_is_the_rest_run_before_the_terminator() -> void:
	# note(12) | rest(8) | rest(12) | EndBar
	var run := SMD.decode_track(PackedByteArray([0x60, 0x0C, 0x80, 0x08, 0x80, 0x0C, 0x90]), 7)
	var o: Dictionary = PairModel.outro_of(run)
	_assert_eq(int(o["ticks"]), 20, "the whole RUN counts, not just the last rest")
	_assert_eq(int(o["first_index"]), 1, "…and the rewrite starts at the run's first event")
	_assert_eq(int(o["end_bar_index"]), 3, "the terminator is where the carried-verbatim tail begins")
	# note(12) | EndBar — the corpus's overwhelming shape
	var none := SMD.decode_track(PackedByteArray([0x60, 0x0C, 0x90]), 3)
	var n: Dictionary = PairModel.outro_of(none)
	_assert_eq(int(n["ticks"]), 0, "no trailing rest = a zero-tick outro, not a missing one")
	_assert_eq(int(n["first_index"]), int(n["end_bar_index"]),
			"…and the rewrite point IS the terminator: there is nothing to replace")


## The run stops at a zero-tick opcode, exactly as the drag's cascade does (19b §3's third
## wall). 482 corpus tracks end on a `Coda`, and silence written in front of one would move
## when it fires.
func _test_an_opcode_between_the_rest_and_the_end_kills_the_outro() -> void:
	# note(12) | rest(8) | Coda | EndBar — the rest is NOT the outro
	var walled := SMD.decode_track(PackedByteArray([0x60, 0x0C, 0x80, 0x08, 0x99, 0x90]), 6)
	var w: Dictionary = PairModel.outro_of(walled)
	_assert_eq(int(w["ticks"]), 0, "a zero-tick opcode between the rest and the end is a wall")
	_assert_eq(int(w["first_index"]), 3, "…so the write goes AFTER it, in front of the EndBar")
	# note(12) | Coda | rest(120) | EndBar — E259 pair 0's real shape
	var open := SMD.decode_track(PackedByteArray([0x60, 0x0C, 0x99, 0x80, 0x78, 0x90]), 6)
	_assert_eq(int(PairModel.outro_of(open)["ticks"]), 120,
			"but a rest AFTER the Coda is the outro — E259 t0 authors exactly this")


## A STUB has no terminator, so it has no outro to speak of — the number is not 0, it is
## unanswerable, and the track view says so.
func _test_a_stub_has_no_outro_and_the_view_says_so() -> void:
	var stub := SMD.decode_track(PackedByteArray([0xD2, 0x08]), 2)
	_assert_eq(int(PairModel.outro_of(stub)["end_bar_index"]), -1,
			"no EndBar decoded = no outro; -1, never 0")
	var view: Dictionary = PairModel.pair_view(
			_make_feds_bank(PackedByteArray([0xD2, 0x08]), PackedByteArray([0x60, 0x0C, 0x90])),
			0, {}, null)
	var tracks: Array = view["tracks"]
	_assert_false(bool(tracks[0]["has_terminator"]), "the stub's lane knows it cannot be lengthened")
	_assert_true(bool(tracks[1]["has_terminator"]), "…and its neighbour knows it can")


## The verb, growing from nothing: `note(12) EndBar` set to 48 ticks. This is the FIRST
## edit in the studio whose tell is `end_tick` rather than the tiling.
func _test_setting_the_outro_grows_the_tracks_clock() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(PackedByteArray([0x60, 0x0C, 0x90]), PackedByteArray([0x90]))
	var before: Dictionary = PairModel.pair_view(data.feds_bank, 0, {}, null).get("tracks", [])[0]
	var res: Dictionary = Channel.set_outro(data, {
			"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "outro_ticks": 48})
	_assert_true(bool(res.get("structural", false)), "growing the clock is a structural edit")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)), [0x60, 0x0C, 0x80, 0x30, 0x90],
			"the silence goes immediately in front of the terminator")
	var after: Dictionary = PairModel.pair_view(data.feds_bank, 0, {}, null).get("tracks", [])[0]
	_assert_eq(int(before["end_tick"]), 12, "the track was 12 ticks long")
	_assert_eq(int(after["end_tick"]), 60, "…and is 60 now — the clock MOVED, which is the point")
	_assert_eq(int(after["outro_ticks"]), 48, "and the lane reads back exactly what was asked")
	_assert_eq(int(res.get("event_index", -1)), 1,
			"the selection lands on the silence the author just made")


## One number, not a delta: setting an outro that already exists REPLACES it, so repeated
## edits never stack up a run of rests where the author asked for one span of silence.
func _test_setting_an_existing_outro_replaces_it_rather_than_appending() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(
			PackedByteArray([0x60, 0x0C, 0x80, 0x08, 0x90]), PackedByteArray([0x90]))
	_assert_false(Channel.set_outro(data, {
			"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "outro_ticks": 20}).is_empty(),
			"the outro is set")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)), [0x60, 0x0C, 0x80, 0x14, 0x90],
			"`80 08` becomes `80 14` — ONE rest of 20, never `80 08 80 0C`")


## Trim is set-to-zero, and it splices the outro out entirely — the inverse of the grow,
## through the same call. The wall is the last authored event: an outro cannot eat into it,
## because a rest run stops there by construction.
func _test_trimming_the_outro_to_zero_splices_it_out() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(
			PackedByteArray([0x60, 0x0C, 0x80, 0x4B, 0x90]), PackedByteArray([0x90]))
	var res: Dictionary = Channel.set_outro(data, {
			"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "outro_ticks": 0})
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)), [0x60, 0x0C, 0x90],
			"E481 t3's authored 75-tick tail, removed — the only verb that can shorten a track")
	_assert_eq(int(PairModel.pair_view(data.feds_bank, 0, {}, null)["tracks"][0]["end_tick"]), 12,
			"…and the clock moved back to the last authored event")
	_assert_eq(int(res.get("event_index", -1)), 1,
			"with nothing to select, the selection lands on the terminator")


## `0x80` carries one param byte, so a long outro is spelled as a RUN — more silence,
## spelled differently, never a clamp of the number the author asked for.
func _test_a_long_outro_chunks_into_a_run_of_rests() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(PackedByteArray([0x60, 0x0C, 0x90]), PackedByteArray([0x90]))
	_assert_false(Channel.set_outro(data, {
			"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "outro_ticks": 300}).is_empty(),
			"300 ticks is expressible")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)),
			[0x60, 0x0C, 0x80, 0xFF, 0x80, 0x2D, 0x90], "255 + 45, exactly as `_encode_rests` chunks")
	_assert_eq(int(PairModel.pair_view(data.feds_bank, 0, {}, null)["tracks"][0]["outro_ticks"]),
			300, "and the run reads back as ONE outro — the run is the spelling, not the number")


## Everything from the terminator on is carried VERBATIM, including bytes past the decoder's
## EndBar stop: unreachable, but authored.
func _test_the_outro_carries_the_bytes_past_the_end_bar_verbatim() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(
			PackedByteArray([0x60, 0x0C, 0x90, 0xAC, 0x05]), PackedByteArray([0x90]))
	_assert_false(Channel.set_outro(data, {
			"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "outro_ticks": 12}).is_empty(),
			"the outro is set")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)), [0x60, 0x0C, 0x80, 0x0C, 0x90, 0xAC, 0x05],
			"the dead bytes after the EndBar survive the splice")


## Refused, never clamped. The stub refusal is the one this verb exists to make: appending
## to a stub pushes BORROWED bytes later in ticks, which is 19b §3's law broken facing the
## other way — and `insert_event` already offers the EndBar that fixes it.
func _test_the_outro_refuses_a_stub_a_negative_count_and_an_absurd_one() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	var stub = EffectDataClass.new()
	stub.feds_bank = _make_feds_bank(PackedByteArray([0xD2, 0x08]), PackedByteArray([0x60, 0x0C, 0x90]))
	var stub_bytes: Array = Array(stub.feds_bank.get_track_bytes(0))
	_assert_true(Channel.set_outro(stub, {
			"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "outro_ticks": 48}).is_empty(),
			"a stub has no end to write in front of")
	_assert_eq(Array(stub.feds_bank.get_track_bytes(0)), stub_bytes, "…and nothing was written")
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(PackedByteArray([0x60, 0x0C, 0x90]), PackedByteArray([0x90]))
	_assert_true(Channel.set_outro(data, {
			"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "outro_ticks": -1}).is_empty(),
			"a negative outro is refused, not clamped to zero")
	_assert_true(Channel.set_outro(data, {
			"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "outro_ticks": 999999}).is_empty(),
			"…and so is a fat-fingered one")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)), [0x60, 0x0C, 0x90],
			"a refusal writes nothing at all")


## The outro is not a special kind of silence: once it exists it is a REST SPAN, so the five
## verbs that retile a fixed clock all reach it. That composition is the whole reach argument
## — grow the clock once, then author inside it with what already shipped.
func _test_the_new_outro_is_a_rest_span_the_paint_reaches() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(PackedByteArray([0x60, 0x0C, 0x90]), PackedByteArray([0x90]))
	_assert_false(Channel.set_outro(data, {
			"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "outro_ticks": 48}).is_empty(),
			"grow the clock by 48")
	var base: int = data.feds_bank.track_offsets[0]
	_assert_false(Channel.paint_event(data, {
			"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "at": base + 2,
			"offset_ticks": 12, "duration_ticks": 24}).is_empty(),
			"…then paint a note into it, with the verb that already shipped")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)),
			[0x60, 0x0C, 0x80, 0x0C, 0x60, 0x09, 0x80, 0x0C, 0x90],
			"a note now sounds 24 ticks PAST where FFT's track used to end")


## The costume, closed (ADR-0085 2026-08-19 §6, extended by 19c). A rest's and a fermata's
## tick counts were live int cells in the inspector — same-size, so they read as parameters,
## but each retype slid every later event in the voice with no law and no tell.
func _test_a_rest_and_a_fermata_tick_count_are_tells_not_cells() -> void:
	# note(12) | 0x81 Fermata(6) | 0x80 Rest(8) | EndBar
	var view: Dictionary = PairModel.pair_view(
			_make_feds_bank(PackedByteArray([0x60, 0x0C, 0x81, 0x06, 0x80, 0x08, 0x90]),
					PackedByteArray([0x90])), 0, {}, null)
	var score := {"feds_pairs": [view]}
	for ei in [1, 2]:
		var fields: Array = _select_event(score, 0, ei).values()
		_assert_eq(fields.size(), 1, "one row for event %d" % ei)
		if fields.is_empty():
			continue
		var row: Dictionary = fields[0]
		_assert_eq(str(row.get("shape", "")), "const",
				"a tick count is a TELL, never an edit cell (event %d)" % ei)
		_assert_true(str(row.get("tooltip", "")).contains("outro"),
				"…and it names where new time comes from (event %d)" % ei)


## Refused at the encoder too, because a field_ref can be built by any tool — the same
## defence in depth `note_delta_idx` got.
func _test_writing_a_rest_tick_count_is_refused_at_the_encoder() -> void:
	var Channel = load("res://src/effects/studio/SoundDefChannel.gd")
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(
			PackedByteArray([0x60, 0x0C, 0x81, 0x06, 0x80, 0x08, 0x90]), PackedByteArray([0x90]))
	var base: int = data.feds_bank.track_offsets[0]
	_assert_true(Channel.apply_raw(data, {"channel": "sound_def", "kind": "byte",
			"offset": base + 5, "pair_idx": 0}, 40).is_empty(), "a rest's tick byte is refused")
	_assert_true(Channel.apply_raw(data, {"channel": "sound_def", "kind": "byte",
			"offset": base + 3, "pair_idx": 0}, 40).is_empty(), "…and a fermata's")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)),
			[0x60, 0x0C, 0x81, 0x06, 0x80, 0x08, 0x90], "neither wrote a byte")
	_assert_false(Channel.apply_raw(data, {"channel": "sound_def", "kind": "byte",
			"offset": base, "pair_idx": 0}, 0x50).is_empty(),
			"a velocity byte one position away still writes — the guard is exact, not a blanket")


## The surface (2026-08-19c §4): the track's END owns the two outro rows. A click on the
## terminator chip resolves them; a stub's terminator does not exist, so it offers none —
## the NoEnd phantom is already advertising the EndBar that would give it one.
func _test_the_terminator_offers_the_extend_and_trim_rows() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	# Track A: note(12) | rest(75) | EndBar — E481 t3's shape. Track B: a stub.
	var view: Dictionary = PairModel.pair_view(
			_make_feds_bank(PackedByteArray([0x60, 0x0C, 0x80, 0x4B, 0x90]),
					PackedByteArray([0xD2, 0x08])), 0, {}, null)
	var ctx: Dictionary = Panel._context_for(view, 0, 2, true)   # the EndBar
	var outro: Dictionary = ctx.get("outro", {})
	_assert_eq(int(outro.get("ticks", -1)), 75, "the end names the silence in front of it")
	var labels: Array = []
	var steps: Array = []
	for act in Page._pair_context_actions(ctx):
		if str(act.get("verb", "")) == "outro":
			labels.append(str(act["label"]))
			if act.has("outro_options"):
				steps = act["outro_options"]
	_assert_eq(labels.size(), 2, "extend and trim, and trim only because there IS silence")
	_assert_true(labels[1].contains("75"), "…and trim says the number it removes: %s" % labels[1])
	_assert_eq(steps.size(), 18, "extend hangs the corpus's 18 delta-time lengths off a submenu")
	_assert_eq(int((steps[0] as Dictionary)["outro_ticks"]), 77,
			"a row carries the ABSOLUTE result — 75 + the shortest step, so the verb takes one number")
	# A note in the middle of the track is not the end and offers neither row.
	_assert_true((Panel._context_for(view, 0, 0, true).get("outro", {}) as Dictionary).is_empty(),
			"only the terminator carries them — a note is not where a track ends")
	# The stub has no terminator at all.
	for ei in range(2):
		_assert_true((Panel._context_for(view, 1, ei, true).get("outro", {}) as Dictionary).is_empty(),
				"a stub offers no outro row: it has no end to lengthen")


## A track with NO trailing silence — 1917 of the corpus's 1928 terminated tracks — offers
## extend and no trim, because there is nothing to remove.
func _test_a_track_with_no_outro_offers_extend_but_not_trim() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var view: Dictionary = PairModel.pair_view(
			_make_feds_bank(PackedByteArray([0x60, 0x0C, 0x90]), PackedByteArray([0x90])), 0, {}, null)
	var acts: Array = []
	for act in Page._pair_context_actions(Panel._context_for(view, 0, 1, true)):
		if str(act.get("verb", "")) == "outro":
			acts.append(act)
	_assert_eq(acts.size(), 1, "one row: there is no silence to trim")
	_assert_true((acts[0] as Dictionary).has("outro_options"), "and it is the extend submenu")
	_assert_eq(int(((acts[0] as Dictionary)["outro_options"][6] as Dictionary)["outro_ticks"]), 12,
			"from nothing, a step IS the outro")


## Right-clicking the EMPTY lane past the end resolves to the same anchor the terminator
## chip does, so "extend" is reachable where an author actually reaches for it.
func _test_empty_space_past_the_end_resolves_to_the_outro_rows() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var view: Dictionary = PairModel.pair_view(
			_make_feds_bank(PackedByteArray([0x60, 0x0C, 0x90]),
					PackedByteArray([0x60, 0x0C, 0x80, 0x30, 0x90])), 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 700.0, {})
	var lane := Rect2()
	for l in lay["lanes"]:
		if int(l["track"]) == 0:
			lane = l["rect"]
	var ctx: Dictionary = Panel.resolve_context(view, lay,
			Vector2(lane.position.x + lane.size.x - 2.0, lane.get_center().y))
	_assert_false((ctx.get("outro", {}) as Dictionary).is_empty(),
			"a click in the empty lane past track A's end still names its end")


## The session routes the outro like every other structural FEDS verb: it swaps the bank,
## so the pre-edit object IS the exact restore — and undo puts the track's clock back.
func _test_the_outro_undoes_by_snapshot() -> void:
	var Session = load("res://src/effects/studio/EffectEditSession.gd")
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(PackedByteArray([0x60, 0x0C, 0x90]), PackedByteArray([0x90]))
	var before = data.feds_bank
	var session = Session.new(data)
	var res: Dictionary = session.set_outro({
			"channel": "sound_def", "pair_idx": 0, "track_idx": 0, "outro_ticks": 48})
	_assert_false(res.is_empty(), "the session routes the outro to the FEDS verb")
	_assert_true(data.feds_bank != before, "the bank was SWAPPED, never mutated")
	session.undo()
	_assert_true(data.feds_bank == before, "undo puts the pre-edit bank — and the clock — back")
	# No other channel has an end to lengthen: no other channel tiles its time.
	_assert_true(session.set_outro({"channel": "camera", "context": "phase1"}).is_empty(),
			"the outro is FEDS-only, like the other three time verbs")


## Opening a pair UNROLLS it (2026-08-19d): every `Rep` bracket unwound in place and every
## stub's `Flow` phantom revealed, rather than ADR-0085 decision 3's fold-default. The
## reversal is the panel's OPEN state only — the pure layout still draws whatever state it
## is handed, and both fold verbs stay reversible.
func _test_a_pair_opens_with_every_loop_and_flow_unrolled() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var panel = Panel.new()
	panel.size = Vector2(700.0, 400.0)
	# Track A: a ×3 loop. Track B: a stub, so the pair has a Flow phantom too.
	panel.set_view(PairModel.pair_view(_make_loop_bank(), 0, {}, null))
	_assert_true(panel.is_loop_unwound(0, 0), "the loop opens unwound, without a click")
	_assert_true(panel.is_loop_unwound(1, -1), "…and so does track B's Flow phantom")
	var lay: Dictionary = Panel.layout(panel._view, 700.0, panel._state())
	var ghosts := 0
	for b in lay.get("span_bars", []):
		if bool(b.get("ghost", false)):
			ghosts += 1
	_assert_true(ghosts > 0, "so the unrolled copies are on screen at open, not behind a toggle")
	# Re-deriving the SAME pair after an edit keeps whatever the author chose since.
	panel.toggle_loop(0, 0)
	panel.set_view(PairModel.pair_view(_make_loop_bank(), 0, {}, null))
	_assert_false(panel.is_loop_unwound(0, 0),
			"a same-pair re-derive keeps the author's fold, it does not re-unroll it")
	panel.free()



## §1: a right-click that resolves to NO byte boundary answers out loud. Three places on
## the panel own no bytes — the label gutter, the space below/between the lanes, and a null
## slot — and each used to return a silent `{}` that popped no menu at all. Now each names
## itself, and the page turns it into exactly one row that cannot be run.
func _test_a_click_on_no_bytes_names_the_place_it_landed() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var view: Dictionary = PairModel.pair_view(
			_make_feds_bank(PackedByteArray([0x60, 0x0C, 0x90]),
					PackedByteArray([0xD2, 0x08])), 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 700.0, {})
	# Below every lane: the energy band's row, which belongs to no track.
	var below := Vector2(Panel.GUTTER_W + 40.0, 4000.0)
	var cases: Array = [
		[Panel.resolve_context(view, lay, Vector2(4.0, 40.0)), "label strip"],
		[Panel.resolve_context(view, lay, below), "No lane here"],
		[Panel._context_for(PairModel.pair_view(_make_null_slot_bank(), 0, {}, null), 1, 0, true),
			"slot is empty"],
	]
	for c in cases:
		var ctx: Dictionary = c[0]
		var want: String = str(c[1])
		_assert_true(str(ctx.get("refused", "")).contains(want),
				"the refusal names the place: expected '%s', got '%s'"
						% [want, str(ctx.get("refused", ""))])
		var acts: Array = Page._pair_context_actions(ctx)
		_assert_eq(acts.size(), 1, "a refusal is exactly one row — the gesture is answered")
		if acts.size() != 1:
			continue
		_assert_true(bool((acts[0] as Dictionary).get("disabled", false)),
				"…and it is disabled: there is nothing here that could be run")
		_assert_eq(str((acts[0] as Dictionary).get("verb", "")), "",
				"a refusal carries no verb")


## §3: the corpus submenu is where an author goes looking for "add a note", so it is where
## the refusal is explained — and the explanation is the two COMPOSITIONS that are the real
## answer, neither of which the surface named before.
func _test_the_add_submenu_says_why_there_is_no_add_note_row() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var view: Dictionary = PairModel.pair_view(
			_make_feds_bank(PackedByteArray([0x60, 0x0C, 0x90]),
					PackedByteArray([0xD2, 0x08])), 0, {}, null)
	var add: Dictionary = Page._pair_context_actions(Panel._context_for(view, 0, 0, true))[0]
	var header: String = "\n".join(PackedStringArray(add.get("options_header", []) as Array))
	_assert_true(add.has("options"), "the first row is still the corpus Add row")
	_assert_true(header.contains("not an opcode"),
			"the header says why there is no add-a-note row: %s" % header)
	_assert_true(header.contains("Delete") and header.contains("sound the rest"),
			"…names delete → paint, the way to add a note INSIDE the track")
	_assert_true(header.contains("Extend") and header.contains("silence"),
			"…and outro → paint, the only way to add one past the end")


## §3: Delete on a SPAN leaves silence of exactly its length, and that silence is what the
## paint spends. The row says the number, so the composition is legible from the menu and
## not only from the ADR. A zero-tick opcode leaves nothing and keeps its bare row.
func _test_delete_on_a_span_names_the_silence_it_leaves() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	# AC 05 Instrument | 60 0C Note C dur 12 | 90 EndBar
	var view: Dictionary = PairModel.pair_view(
			_make_feds_bank(PackedByteArray([0xAC, 0x05, 0x60, 0x0C, 0x90]),
					PackedByteArray([0x90])), 0, {}, null)
	var note_label := ""
	for act in Page._pair_context_actions(Panel._context_for(view, 0, 1, true)):
		if str(act.get("verb", "")) == "delete":
			note_label = str(act.get("label", ""))
	_assert_true(note_label.contains("12 ticks"),
			"the note's Delete row says the silence it leaves: %s" % note_label)
	var op_label := ""
	for act in Page._pair_context_actions(Panel._context_for(view, 0, 0, true)):
		if str(act.get("verb", "")) == "delete":
			op_label = str(act.get("label", ""))
	_assert_eq(op_label, "Delete `Ins5`",
			"a zero-tick opcode leaves no silence, so its row stays bare: %s" % op_label)


## §2: Cut is offered only where the same bytes can be re-inserted. `can_insert` refuses the
## FLOW opcodes, and a cut with no lawful paste would be a trap rather than a verb — so an
## EndBar keeps its Delete row and grows no Cut row.
func _test_cut_offers_only_what_can_be_pasted_back() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	# AC 05 Instrument | 60 0C Note | D2 08 PitchBendRel | 90 EndBar
	var view: Dictionary = PairModel.pair_view(
			_make_feds_bank(PackedByteArray([0xAC, 0x05, 0x60, 0x0C, 0xD2, 0x08, 0x90]),
					PackedByteArray([0x90])), 0, {}, null)
	var bend: Dictionary = Panel._context_for(view, 0, 2, true)
	var clip: Dictionary = bend.get("cut", {})
	_assert_eq(int(clip.get("opcode", -1)), 0xD2, "the cut carries the opcode it removed")
	_assert_eq(Array(clip.get("params", PackedByteArray()) as PackedByteArray), [8],
			"…and its OWN params, which is the whole point: a re-order keeps the value")
	var verbs: Array = []
	for act in Page._pair_context_actions(bend):
		verbs.append(str(act.get("verb", "")))
	_assert_true("cut" in verbs and "delete" in verbs,
			"a re-insertable opcode offers both — cut is delete that remembers")
	# The EndBar: deletable, but `can_insert` takes it back only at a phantom boundary.
	var end_ctx: Dictionary = Panel._context_for(view, 0, 3, true)
	_assert_true((end_ctx.get("cut", {}) as Dictionary).is_empty(),
			"a flow opcode has no lawful paste, so it grows no Cut row")
	var end_verbs: Array = []
	for act in Page._pair_context_actions(end_ctx):
		end_verbs.append(str(act.get("verb", "")))
	_assert_false("cut" in end_verbs, "…and the menu agrees")
	# A SPAN is not an opcode: its time verb is Delete (→ a rest), never a cut.
	_assert_true((Panel._context_for(view, 0, 1, true).get("cut", {}) as Dictionary).is_empty(),
			"a note span offers no cut — it is a velocity byte, not a re-orderable opcode")


## §2: the paste addresses BOTH sides of the anchor, because neither side is derivable from
## the other where zero-tick opcodes stack — "before `Oct3`" is Oct3's own first byte, and
## "after `Oct3`" is the boundary past it (18b §4's two endpoints).
func _test_paste_addresses_both_sides_of_the_anchor() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var view: Dictionary = PairModel.pair_view(
			_make_feds_bank(PackedByteArray([0xAC, 0x05, 0x60, 0x0C, 0xD2, 0x08, 0x90]),
					PackedByteArray([0x90])), 0, {}, null)
	var base: int = int((view["tracks"][0] as Dictionary)["offset"])
	var note_ctx: Dictionary = Panel._context_for(view, 0, 1, true)
	_assert_eq(int(note_ctx.get("before_at", -1)), base + 2,
			"the anchor's own first byte is the BEFORE address")
	_assert_eq(int(note_ctx.get("at", -1)), base + 4, "…and the boundary past it is AFTER")
	# With nothing cut there is no paste row at all.
	var dry: Array = []
	for act in Page._pair_context_actions(note_ctx):
		dry.append(str(act.get("label", "")))
	for l in dry:
		_assert_false(str(l).begins_with("Paste"), "an empty clipboard offers no paste row")
	var clip := {"opcode": 0xD2, "params": PackedByteArray([8]), "label": "Bend"}
	var pastes: Array = []
	for act in Page._pair_context_actions(note_ctx, clip):
		if str(act.get("label", "")).begins_with("Paste"):
			pastes.append(act)
	_assert_eq(pastes.size(), 2, "both sides of the anchor, and both named")
	if pastes.size() != 2:
		return
	_assert_eq(str((pastes[0] as Dictionary)["label"]), "Paste `Bend` before `C4` @ tick 0",
			"the row names the side AND the anchor, never a silent pick")
	_assert_eq(int(((pastes[0] as Dictionary)["field_ref"] as Dictionary)["at"]), base + 2,
			"…and before writes at the anchor's own first byte")
	_assert_eq(int(((pastes[1] as Dictionary)["field_ref"] as Dictionary)["at"]), base + 4,
			"…after writes at the boundary past it")
	_assert_eq(int(((pastes[0] as Dictionary)["field_ref"] as Dictionary)["opcode"]), 0xD2,
			"the paste writes the bytes that were cut")
	# Before every event, there is no anchor to be before or after: one row, named for the start.
	var start_pastes: Array = []
	for act in Page._pair_context_actions(Panel._context_for(view, 0, -1, false), clip):
		if str(act.get("label", "")).begins_with("Paste"):
			start_pastes.append(str(act["label"]))
	_assert_eq(start_pastes, ["Paste `Bend` at the start of this track"],
			"at the track start there is one paste address, and it says so")


## §2 end to end: the re-order the author asked for. Cut lowers to the EXISTING delete verb
## and the paste to the EXISTING insert — no new dispatch case in either seam — and because
## the clipboard carries the opcode's own params, the moved opcode arrives with the value it
## had rather than the corpus mode the Add menu would have re-inserted.
func _test_a_cut_and_paste_re_orders_without_resetting_the_params() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var Session = load("res://src/effects/studio/EffectEditSession.gd")
	var Catalog = load("res://src/effects/studio/FedsOpcodeCatalog.gd")
	# AC 05 | 60 0C Note | D2 08 PitchBendRel | 90 EndBar — move the bend AHEAD of the note.
	var track_a := PackedByteArray([0xAC, 0x05, 0x60, 0x0C, 0xD2, 0x08, 0x90])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(track_a, PackedByteArray([0x90]))
	var before = data.feds_bank
	var session = Session.new(data)
	var view: Dictionary = PairModel.pair_view(data.feds_bank, 0, {}, null)
	var base: int = int((view["tracks"][0] as Dictionary)["offset"])
	var clip: Dictionary = (Panel._context_for(view, 0, 2, true).get("cut", {}) as Dictionary)
	# The corpus would have re-inserted a DIFFERENT value — which is the paper cut being fixed.
	_assert_false(Array(Catalog.default_params(0xD2)) == Array(clip["params"] as PackedByteArray),
			"the corpus mode differs from this opcode's own param, so the reset was visible")
	_assert_false(session.delete_event({"channel": "sound_def", "pair_idx": 0, "track_idx": 0,
			"at": int(clip["at"])}).is_empty(), "cut lowers to the delete verb that was there")
	# Re-resolve AFTER the edit: every later offset moved. The note is now event 1 again, and
	# its own first byte is the BEFORE address the paste wants.
	var mid: Dictionary = PairModel.pair_view(data.feds_bank, 0, {}, null)
	var before_at: int = int(Panel._context_for(mid, 0, 1, true).get("before_at", -1))
	_assert_false(session.insert_event({"channel": "sound_def", "pair_idx": 0, "track_idx": 0,
			"at": before_at, "opcode": int(clip["opcode"]), "params": clip["params"]}).is_empty(),
			"…and the paste lowers to the insert verb that was there")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)),
			[0xAC, 0x05, 0xD2, 0x08, 0x60, 0x0C, 0x90],
			"the opcode moved ahead of the note WITH its own param byte")
	session.undo()
	session.undo()
	_assert_true(data.feds_bank == before,
			"and both halves undo by snapshot, like every other structural FEDS verb")



## 19f: a multi-segment span owns TWO byte boundaries and the bar draws them as one picture
## — blue note, amber fermata tail, no chip for the `0x81` (18c §5). Only the first was
## addressable, and the row called it "after `C4`", which is where the author reading a
## 60-tick bar would NOT expect an insert at tick 12. Both are offered now, each named for
## the boundary it is and for the tick an opcode written there actually fires at.
func _test_a_fermata_span_offers_both_of_its_boundaries() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	# AC 05 Instrument | 60 0C Note C (12 ticks) | 81 30 Fermata(+48) | AC 07 | 90
	var a := PackedByteArray([0xAC, 0x05, 0x60, 0x0C, 0x81, 0x30, 0xAC, 0x07, 0x90])
	var view: Dictionary = PairModel.pair_view(
			_make_feds_bank(a, PackedByteArray([0x90])), 0, {}, null)
	var base: int = int((view["tracks"][0] as Dictionary)["offset"])
	var ctx: Dictionary = Panel._context_for(view, 0, 1, true)
	var se: Dictionary = ctx.get("span_end", {})
	_assert_eq(int(ctx.get("at", -1)), base + 4,
			"`at` is still the boundary after the head NOTE byte — inside the bar")
	_assert_eq(int(se.get("at", -1)), base + 6,
			"…and the span end is the boundary past the last segment")
	_assert_eq(int(se.get("tick", -1)), 60, "which is where the span's time runs out")
	_assert_eq(int(se.get("inside_tick", -1)), 12,
			"an opcode written INSIDE fires when the note's own ticks are up, not at tick 0")
	# The model agrees: FFT's own opcode after the fermata is stamped at the same tick.
	for c in (view["tracks"][0] as Dictionary).get("commands", []):
		if int((c as Dictionary).get("event_index", -1)) == 3:
			_assert_eq(int((c as Dictionary).get("tick", -1)), 60,
					"…the tick the corpus's own next opcode already sits at")
	var adds: Array = []
	for act in Page._pair_context_actions(ctx):
		if str(act.get("verb", "")) == "insert":
			adds.append(act)
	_assert_eq(adds.size(), 2, "two boundaries, two rows — not one row that means either")
	if adds.size() != 2:
		return
	_assert_eq(str((adds[0] as Dictionary)["label"]),
			"Add opcode inside `C4` — before its Fermata, @ tick 12",
			"the interior row says it is interior AND says the tick it writes at")
	_assert_eq(str((adds[1] as Dictionary)["label"]),
			"Add opcode after `C4`'s Fermata @ tick 60",
			"…and the other names the fermata it is past")
	_assert_eq(int(((adds[1] as Dictionary)["field_ref"] as Dictionary)["at"]), base + 6,
			"…and addresses the span end")
	_assert_eq((adds[1] as Dictionary).get("options", []).size(), 51,
			"both rows hang the same corpus submenu")
	# A SINGLE-segment note has one boundary and keeps the plain row it always had.
	var plain: Dictionary = Panel._context_for(PairModel.pair_view(
			_make_feds_bank(PackedByteArray([0x60, 0x0C, 0x90]),
					PackedByteArray([0x90])), 0, {}, null), 0, 0, true)
	_assert_true((plain.get("span_end", {}) as Dictionary).is_empty(),
			"one segment, one boundary — nothing to disambiguate")
	_assert_eq(str((Page._pair_context_actions(plain)[0] as Dictionary)["label"]),
			"Add opcode after `C4` @ tick 0", "…so its row is unchanged")
	# With a clipboard, the paste splits the same way the Add did.
	var sites: Array = []
	for act in Page._pair_context_actions(ctx,
			{"opcode": 0xD2, "params": PackedByteArray([8]), "label": "Bend"}):
		if str(act.get("label", "")).begins_with("Paste"):
			sites.append(int((act["field_ref"] as Dictionary)["at"]))
	_assert_eq(sites, [base + 2, base + 4, base + 6],
			"before the span, inside it, and past its fermata — the three real addresses")


## 19f, end to end: the span-end boundary is not just nameable, it is WRITABLE — it was
## always a legal `boundaries` entry in the channel, with nothing on the surface addressing
## it. The opcode lands between the fermata and what followed, and undoes by snapshot.
func _test_the_boundary_past_the_fermata_is_writable() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var Session = load("res://src/effects/studio/EffectEditSession.gd")
	var a := PackedByteArray([0xAC, 0x05, 0x60, 0x0C, 0x81, 0x30, 0xAC, 0x07, 0x90])
	var data = EffectDataClass.new()
	data.feds_bank = _make_feds_bank(a, PackedByteArray([0x90]))
	var before = data.feds_bank
	var session = Session.new(data)
	var view: Dictionary = PairModel.pair_view(data.feds_bank, 0, {}, null)
	var se: Dictionary = (Panel._context_for(view, 0, 1, true).get("span_end", {}) as Dictionary)
	_assert_false(session.insert_event({"channel": "sound_def", "pair_idx": 0, "track_idx": 0,
			"at": int(se["at"]), "opcode": 0xD2, "params": PackedByteArray([8])}).is_empty(),
			"the channel takes the span end — it was always one of its boundaries")
	_assert_eq(Array(data.feds_bank.get_track_bytes(0)),
			[0xAC, 0x05, 0x60, 0x0C, 0x81, 0x30, 0xD2, 0x08, 0xAC, 0x07, 0x90],
			"the opcode lands AFTER the fermata, ahead of what already followed it")
	# And the span is unchanged: the note still sounds 60 ticks over two segments.
	var after_view: Dictionary = PairModel.pair_view(data.feds_bank, 0, {}, null)
	for n in (after_view["tracks"][0] as Dictionary).get("notes", []):
		_assert_eq(int((n as Dictionary).get("span_total_ticks", -1)), 60,
				"…and the span it was written past is untouched — no tick moved")
	session.undo()
	_assert_true(data.feds_bank == before, "snapshot undo, like every structural FEDS verb")



## 2026-08-20: clicking an opcode re-navigates to the pair root and rebuilds the inspector,
## so the top panel's height — which on a roomy window IS its content height — was re-derived
## on every click and the whole band re-flowed under it. The height is now a HIGH-WATER mark
## per open root: it never shrinks while you click around one pair, and it starts over when a
## different root opens, so a tall target cannot leave a permanent gap behind it.
func _test_the_top_panel_height_is_latched_per_root() -> void:
	var latch: Dictionary = {}
	var pair0: String = Page._target_key(Target.pair(0))
	_assert_eq(Page._latched_editor_h(latch, pair0, 335.0), 335.0,
			"the first look at a root takes its content height as it is")
	_assert_eq(Page._latched_editor_h(latch, pair0, 327.0), 335.0,
			"a shorter sibling does NOT shrink the band — that was the flicker")
	_assert_eq(Page._latched_editor_h(latch, pair0, 0.0), 335.0,
			"…and neither does the empty moment a rebuild passes through")
	_assert_eq(Page._latched_editor_h(latch, pair0, 355.0), 355.0,
			"but a target that genuinely needs more still gets it")
	_assert_eq(Page._latched_editor_h(latch, pair0, 335.0), 355.0, "…and keeps it, within the root")
	# A different root starts over, so the mark is bounded by what ONE root needed.
	_assert_eq(Page._latched_editor_h(latch, Page._target_key(Target.pair(1)), 327.0), 327.0,
			"opening another pair does not inherit the last one's high-water mark")
	# Nothing open: the inspector is cleared, and the band must collapse rather than latch.
	_assert_eq(Page._latched_editor_h(latch, "", 0.0), 0.0,
			"a cleared inspector still collapses — an empty key tracks content exactly")
	# The key is the same identity Target.equals compares, so "same root" means the same thing.
	_assert_eq(Page._target_key(Target.pair(2)), Page._target_key(Target.pair(2)),
			"the same target keys the same")
	_assert_true(Page._target_key(Target.pair(2)) != Page._target_key(Target.pair(3)),
			"…and two pairs are two roots")
	_assert_true(Page._target_key(Target.pair(2)) != Page._target_key(Target.span("x")),
			"…as are two kinds")


## The band arithmetic was lifted out of `_relayout` verbatim so it could be guarded without
## a scene. These are the three regimes it has always had, pinned so the extraction cannot
## have changed one: roomy (both get what they want), contended (the panel keeps half), and
## panel closed (the inspector alone against the budget).
func _test_the_editor_band_still_shares_the_budget() -> void:
	var over: float = Page.MIN_CHANNELS_H + FramesBar.BAR_H
	# Roomy: budget comfortably holds both, so each lands on exactly what it wanted.
	var roomy: Dictionary = Page._editor_band(over + 1000.0, 335.0, 346.0, true)
	_assert_eq(float(roomy["editor_h"]), 335.0, "with room, the inspector gets its content height")
	_assert_eq(float(roomy["panel_h"]), 346.0, "…and the pair panel shows WHOLE")
	# Contended: 296 px of budget cannot hold 335 + 346, so the panel keeps at least half.
	var tight: Dictionary = Page._editor_band(over + 296.0, 335.0, 346.0, true)
	_assert_eq(float(tight["panel_h"]), 148.0, "the panel keeps half the budget rather than vanishing")
	_assert_eq(float(tight["editor_h"]), 148.0, "…and the inspector takes what is left")
	# The panel's floor is its OWN want when that is less than half — it never grows to fill.
	var small_panel: Dictionary = Page._editor_band(over + 296.0, 335.0, 60.0, true)
	_assert_eq(float(small_panel["panel_h"]), 60.0, "a short panel is not padded out to half")
	_assert_eq(float(small_panel["editor_h"]), 236.0, "…and the inspector takes the remainder")
	# Closed: the inspector alone, clamped to the budget.
	var closed: Dictionary = Page._editor_band(over + 200.0, 335.0, 346.0, false)
	_assert_eq(float(closed["panel_h"]), 0.0, "a closed panel takes no band")
	_assert_eq(float(closed["editor_h"]), 200.0, "…and the inspector is clamped to the budget")
	# A window with no room at all yields nothing rather than a negative band.
	var none: Dictionary = Page._editor_band(10.0, 335.0, 346.0, true)
	_assert_eq(float(none["editor_h"]), 0.0, "no budget, no inspector band")
	_assert_eq(float(none["panel_h"]), 0.0, "…and no panel band either")


# --- ADR-0085 amendment 2026-08-21c: the note bars run together ---------------
# "there are some cases where the notes are so compressed you can't even read them. and
# also you can't see where they start and end." Four mechanical causes, all guarded here
# as LAYOUT facts rather than as field contents — this class of complaint has now been
# missed twice by green assertions that read the data and never measured the picture
# (2026-08-11, and again this round).


func _test_a_span_label_never_draws_wider_than_its_own_bar() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	# The clip used to be maxf(rect.w - 2.0, 40.0). Any bar narrower than 42 px therefore
	# drew its label WIDER than itself, straight over its neighbour — which is literally
	# "you can\'t read them". 23.4% of the corpus projects to one frame or less, and one
	# frame is 40 px at TimelineAxis.MAX_PPF, the panel\'s hard ceiling.
	var font: Font = ThemeDB.fallback_font
	var fs := 9
	var rungs: Array = Panel.span_text_rungs({"ordinal": 8, "label": "C3", "key_label": "C3"})
	for avail in [200.0, 60.0, 40.0, 28.0, 18.0, 9.0, 4.0]:
		var text: String = Panel.fit_label(font, fs, rungs, avail)
		if text.is_empty():
			continue
		var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		_assert_true(w <= avail,
				"at %d px avail the label '%s' fits INSIDE its bar (%d px)" % [int(avail), text, int(w)])
	_assert_eq(Panel.fit_label(font, fs, rungs, 1.0), "",
			"a bar too narrow for one glyph draws NO label — never a 40 px floor over a neighbour")


func _test_the_label_ladder_drops_whole_tokens_pitch_before_ordinal() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	# 6262 of the corpus\'s 6439 notes (97.3%) carry velocity 96, so "· v96" spends ~5
	# characters saying what is almost always true. v0 (106 notes) is the informative case
	# and nothing else marks it — the MUTED / FAINT verdicts are instrument-derived and
	# never read velocity.
	_assert_eq(Panel._note_label("C3", 96), "C3",
			"the corpus-universal velocity is not printed")
	_assert_eq(Panel._note_label("C3", 0), "C3 · v0",
			"a velocity that is NOT 96 prints — that is the case carrying information")
	var rungs: Array = Panel.span_text_rungs(
			{"ordinal": 8, "label": "C3 · v0", "key_label": "C3"})
	_assert_eq(rungs.size(), 4, "four rungs: full, key, ordinal, silence")
	_assert_eq(str(rungs[0]), "8 C3 · v0", "widest rung is everything")
	_assert_eq(str(rungs[1]), "8 C3", "then the velocity token goes, whole")
	_assert_eq(str(rungs[2]), "8", "then the pitch token goes, whole")
	_assert_eq(str(rungs[3]), "", "the last rung is silence — a bar can be too small for ink")
	# Pitch goes BEFORE the ordinal because the Opcodes lane directly below reprints every
	# ordinal in a fixed-width chip at the same x (2026-08-18b §6): the ordinal is
	# recoverable by looking down one lane, the pitch is recoverable from nowhere.
	_assert_eq(str(rungs[rungs.size() - 2]), "8",
			"the last rung with ink is the ORDINAL, not the pitch")
	# Whole tokens only: "8 C" would read as the key C rather than as a truncation, which
	# is the "first one visibly clipped mid-token" in the complaint screenshot.
	for rung in rungs:
		_assert_false(str(rung).ends_with(" C") or str(rung).ends_with("·")
				or str(rung).ends_with(" v"), "no rung ends mid-token ('%s')" % str(rung))
	# A v96 note has no velocity token to drop, so its ladder is one rung shorter.
	var common: Array = Panel.span_text_rungs(
			{"ordinal": 8, "label": "C3", "key_label": "C3"})
	_assert_eq(common.size(), 3, "with no velocity token there is no velocity rung")


func _test_every_span_boundary_gets_exactly_one_separator() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	# "you can\'t see where they start and end": two ordinary neighbouring notes shared an
	# edge, a fill and no stroke, so they drew as one unbroken rectangle. Spans TILE
	# (CONTEXT.md "Span"), so a boundary is ONE thing shared by two bars — N spans own
	# N+1 boundaries, not 2N edges.
	var view: Dictionary = PairModel.pair_view(_make_bank(), 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 700.0, {})
	var seps: Array = lay.get("span_seps", [])
	_assert_true(not seps.is_empty(), "a pair with spans draws separators at all")
	# Every bar\'s BOTH edges are covered, in its own lane row.
	var have := {}
	for sep in seps:
		have["%.1f:%.1f" % [float(sep["y"]), float(sep["x"])]] = true
	for bar in lay.get("span_bars", []):
		var r: Rect2 = bar["rect"]
		_assert_true(have.has("%.1f:%.1f" % [r.position.y, snappedf(r.position.x, 0.5)]),
				"a span\'s START boundary is drawn")
		_assert_true(have.has("%.1f:%.1f" % [r.position.y, snappedf(r.end.x, 0.5)]),
				"a span\'s END boundary is drawn")
		_assert_eq(float(seps[0]["h"]), Panel.NOTE_BAR_H,
				"the hairline is the bar\'s height — a boundary, not a lane rule")
	# On track A\'s TIME lane the spans tile, so the count is exactly N+1. Counting rather
	# than merely covering is what proves the boundary is shared and not double-drawn.
	var time_rect := Rect2()
	for lane in lay.get("lanes", []):
		if int(lane.get("track")) == 0 and str(lane.get("kind")) == "time":
			time_rect = lane.get("rect")
	var n_bars := 0
	var n_seps := 0
	for bar in lay.get("span_bars", []):
		if time_rect.encloses(bar["rect"] as Rect2):
			n_bars += 1
	for sep in seps:
		var sy: float = float(sep["y"])
		if sy >= time_rect.position.y and sy < time_rect.end.y:
			n_seps += 1
	_assert_true(n_bars > 0, "track A\'s time lane holds spans")
	_assert_eq(n_seps, n_bars + 1,
			"N tiled spans share N+1 boundaries — one hairline each, not a border per bar")


func _test_the_projection_keeps_the_fraction_of_a_frame() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	# _sec_x used to round BOTH endpoints to whole effect frames. That collapsed 314 of the
	# corpus\'s 6439 notes (4.9%) to ZERO width — drawn as a 2 px sliver by maxf(2.0, …) at
	# every zoom, unclickable as well as unreadable — and pinned another 18.5% to a single
	# frame, which is 40 px at MAX_PPF and cannot be zoomed out of.
	var view: Dictionary = PairModel.pair_view(_make_bank(), 0, {}, null)
	var axis = Axis.new()
	axis.configure(Panel.GUTTER_W + Panel.PAD_X, Axis.MAX_PPF)
	var lay: Dictionary = Panel.layout(view, 4000.0, {}, axis)
	var bars: Array = lay.get("span_bars", [])
	_assert_true(not bars.is_empty(), "the fixture places span bars at max zoom")
	var r: Rect2 = bars[0].get("rect")
	# 12 + 6 = 18 ticks at 120 BPM = 0.1875 s = 5.625 frames. At MAX_PPF that is 225 px;
	# rounding to 6 frames gave it 240 — a 15 px lie at the zoom the complaint was taken at.
	_assert_true(absf(r.size.x - 5.625 * Axis.MAX_PPF) < 0.01,
			"at MAX_PPF the span is its fractional 225 px, not the 240 that rounding gave it")
	for bar in bars:
		_assert_true((bar["rect"] as Rect2).size.x > 2.0,
				"no span sits on the 2 px minimum-width clamp at maximum zoom")


func _test_the_octave_tint_is_a_global_ordered_ramp() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	# Octave is ORDERED data set by the Octave / RaiseOctave / LowerOctave opcodes, so it
	# gets a sequential lightness scale on the one note hue rather than ten categorical
	# hues that would fight the blue / amber / grey the lane already speaks.
	_assert_true(Panel.octave_tint(Panel.COL_BAR, Panel.OCT_MID) == Panel.COL_BAR,
			"octave 4 keeps the colour the bar has always had — 24.3% of the corpus")
	var prev := -1.0
	for o in range(Panel.OCT_LO, Panel.OCT_HI + 1):
		var c: Color = Panel.octave_tint(Panel.COL_BAR, o)
		var lum: float = c.r * 0.299 + c.g * 0.587 + c.b * 0.114
		_assert_true(lum > prev, "octave %d is lighter than %d — the ramp is ORDERED" % [o, o - 1])
		prev = lum
		_assert_true(absf(c.a - Panel.COL_BAR.a) < 0.001,
				"the tint spends LIGHTNESS, never alpha — alpha is the ghost-copy axis")
	# Clamped, not wrapped: an out-of-range octave takes an end of the ramp, never a hue
	# from the other end.
	_assert_true(Panel.octave_tint(Panel.COL_BAR, -3) == Panel.octave_tint(Panel.COL_BAR, Panel.OCT_LO),
			"an octave below the ramp clamps to its floor")
	_assert_true(Panel.octave_tint(Panel.COL_BAR, 40) == Panel.octave_tint(Panel.COL_BAR, Panel.OCT_HI),
			"an octave above the ramp clamps to its ceiling")
	# Ink follows the fill, because near-black was chosen for one bright blue and the low
	# octaves are now dark enough to swallow it.
	_assert_true(Panel.label_ink(Panel.octave_tint(Panel.COL_BAR, 0), false) == Panel.COL_TEXT,
			"a low-octave bar takes LIGHT ink")
	_assert_true(Panel.label_ink(Panel.octave_tint(Panel.COL_BAR, 9), false).v < 0.2,
			"a high-octave bar keeps the near-black ink")
	_assert_true(Panel.label_ink(Panel.COL_BAR_REST, true) == Panel.COL_TEXT,
			"a rest keeps light ink — near-black would sink into the grey")


## A bank whose track A actually USES the key axis: four distinct keys plus an authored
## rest, so the roll's row law has something to be wrong about. Built from BYTES through
## the real decoder and the real fold_spans, like every other fixture here — a hand-written
## span dict would guard the test's arithmetic instead of the panel's.
##
##   note = [velocity, key × 19 + delta_index]. 19 is the delta table's length, so a data
##   byte for key 7+ is ≥ 0x80 and still a NOTE byte, not an opcode: the decoder decides
##   that from the VELOCITY byte being < 0x80, one byte earlier.
func _make_roll_bank():
	var track_a := PackedByteArray([
		0xAC, 0x05,        # SetInstrument
		0x94, 0x04,        # Octave 4
		0x60, 0 * 19 + 12, # C, 12 ticks
		0x60, 4 * 19 + 12, # E
		0x80, 0x08,        # Rest 8 ticks
		0x60, 7 * 19 + 12, # G
		0x60, 11 * 19 + 12,# B
		0x90,              # EndBar
	])
	var track_b := PackedByteArray([0x60, 0 * 19 + 12, 0x90])
	var a_off := 28
	var b_off := a_off + track_a.size()
	var data_size := b_off + track_b.size()
	var blob := PackedByteArray()
	blob.append_array("feds".to_ascii_buffer())
	blob.append_array([data_size & 0xFF, (data_size >> 8) & 0xFF, 0, 0])
	blob.append_array([2, 0])
	blob.append_array([7, 0])
	blob.append_array([28, 0, 0, 0])
	blob.append_array([0, 0, 0, 0, 0, 0, 0, 0])
	blob.append_array([a_off & 0xFF, a_off >> 8, b_off & 0xFF, b_off >> 8])
	blob.append_array(track_a)
	blob.append_array(track_b)
	return FedsBankScript.parse(blob)


func _test_the_roll_puts_every_note_on_its_own_key_row() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	# THE ROW LAW (ADR-0085 amendment 2026-08-21d §4). Y is `relative_key` and nothing
	# else — not absolute pitch, because octave is an Octave/RaiseOctave/LowerOctave
	# opcode's effect and putting it on Y would encode an opcode into the note lane's
	# geometry, which is the "overlaying event types" decision 5 rejects.
	#
	# PITCH ASCENDS UPWARD, so the row is 11 − key, not key: the accidental striping only
	# reads as a keyboard that way round.
	for k in range(Panel.ROLL_KEYS):
		_assert_eq(Panel.roll_row(false, k), Panel.ROLL_KEYS - 1 - k,
				"key %d sits on row %d — high notes at the TOP" % [k, Panel.ROLL_KEYS - 1 - k])
		_assert_eq(Panel.roll_key(Panel.roll_row(false, k)), k,
				"row → key round-trips for key %d" % k)
	_assert_eq(Panel.roll_row(true, 0), Panel.ROLL_REST_ROW,
			"a REST takes the 13th row — authored silence is not one of the twelve pitches")
	_assert_eq(Panel.roll_key(Panel.ROLL_REST_ROW), -1,
			"the Rest row is not a key: a drag onto it must refuse, never write key 12 "
			+ "(the TIE form FFT never writes)")

	var view: Dictionary = PairModel.pair_view(_make_roll_bank(), 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 1200.0, {"roll": true})
	var time_y := -1.0
	for lane in lay.get("lanes", []):
		if int(lane.get("track")) == 0 and str(lane.get("kind")) == "time":
			time_y = (lane.get("rect") as Rect2).position.y
			_assert_true(absf((lane.get("rect") as Rect2).size.y
					- float(Panel.ROLL_ROWS) * Panel.ROLL_ROW_H) < 0.01,
					"the roll's time lane is exactly 13 rows tall")
	_assert_true(time_y >= 0.0, "track A's time lane is placed")
	var seen := {}
	for bar in lay.get("span_bars", []):
		if int(bar.get("track", -1)) != 0:
			continue
		var row := int(bar.get("row", -1))
		_assert_eq(row, Panel.roll_row(bool(bar.get("rest", false)),
				int(bar.get("relative_key", -1))),
				"bar %d's row IS its key" % int(bar.get("ordinal", -1)))
		var want_y: float = time_y + float(row) * Panel.ROLL_ROW_H \
				+ (Panel.ROLL_ROW_H - Panel.ROLL_BAR_H) * 0.5
		_assert_true(absf((bar["rect"] as Rect2).position.y - want_y) < 0.01,
				"bar %d is DRAWN on row %d, not merely labelled with it"
				% [int(bar.get("ordinal", -1)), row])
		seen[row] = true
	# The fixture spends four distinct keys and one rest, so the roll must spread over five
	# rows. One row would be the ribbon this whole amendment exists to break up.
	for k in [0, 4, 7, 11]:
		_assert_true(seen.has(Panel.roll_row(false, k)), "key %d got its own row" % k)
	_assert_true(seen.has(Panel.ROLL_REST_ROW), "the authored rest got the Rest row")

	# LANES mode is untouched: one shared centre line, and no row stamped on the bar.
	var lanes_lay: Dictionary = Panel.layout(view, 1200.0, {})
	var ys := {}
	for bar in lanes_lay.get("span_bars", []):
		if int(bar.get("track", -1)) == 0:
			ys[(bar["rect"] as Rect2).position.y] = true
			_assert_eq(int(bar.get("row", -2)), -1, "a lanes-mode bar has no row")
	_assert_eq(ys.size(), 1, "in LANES mode every bar still shares one y — the roll is opt-in")


func _test_the_roll_has_thirteen_rows_that_never_move() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	var view: Dictionary = PairModel.pair_view(_make_roll_bank(), 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 1200.0, {"roll": true})
	var per_track := {}
	for rw in lay.get("roll_rows", []):
		var t := int(rw["track"])
		if not per_track.has(t):
			per_track[t] = []
		(per_track[t] as Array).append(rw)
	_assert_eq(per_track.size(), 2, "each of the pair's two tracks gets its own roll")
	for t in per_track.keys():
		var rows: Array = per_track[t]
		_assert_eq(rows.size(), Panel.ROLL_ROWS,
				"track %d has exactly 13 rows — 12 keys + Rest, and they never scroll" % t)
		for i in range(rows.size()):
			var rw: Dictionary = rows[i]
			_assert_eq(int(rw["row"]), i, "rows come out in order")
			if i == Panel.ROLL_REST_ROW:
				_assert_true(bool(rw["rest"]), "the LAST row is the Rest row")
				_assert_eq(str(rw["label"]), "Rest", "and it says so")
				_assert_false(bool(rw["accidental"]), "Rest is not an accidental")
			else:
				var key: int = Panel.roll_key(i)
				_assert_eq(str(rw["label"]), str(Panel.ROLL_KEY_NAMES[key]),
						"row %d is labelled %s" % [i, str(Panel.ROLL_KEY_NAMES[key])])
				# The five black keys, striped darker so the twelve rows read as a keyboard
				# rather than as an arbitrary 12-way split.
				_assert_eq(bool(rw["accidental"]), str(rw["label"]).ends_with("#"),
						"row %d's stripe matches whether %s is a black key"
						% [i, str(rw["label"])])
			if i > 0:
				var prev: Rect2 = (rows[i - 1] as Dictionary)["rect"]
				_assert_true(absf((rw["rect"] as Rect2).position.y - prev.end.y) < 0.01,
						"rows tile with no gap")
	var accidentals := 0
	for rw in per_track[0]:
		if bool(rw["accidental"]):
			accidentals += 1
	_assert_eq(accidentals, 5, "five black keys — C# D# F# G# A#")
	_assert_true((Panel.layout(view, 1200.0, {}).get("roll_rows", []) as Array).is_empty(),
			"LANES mode emits no roll rows at all — the roll is a second reading, not a cost")


func _test_a_vertical_drag_of_n_rows_moves_the_key_by_n() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	# THE ONE GENUINELY NEW VERB (amendment 2026-08-21d §7). It reports an ABSOLUTE key,
	# not a delta: the write is a same-size patch of one byte's upper field, so every motion
	# re-states the whole answer and none of them compound — drag away, drag back, and the
	# note is on the key it started on while the button is still down.
	var drag := {"gesture": "key", "roll": true, "start_y": 100.0, "start_key": 5,
			"start_x": 0.0, "ticks_per_px": 1.0, "span_ticks": 12, "grab_ticks": 0}
	for rows in range(-5, 6):
		var m: Dictionary = Panel.drag_motion(drag, 0.0, 100.0 + float(rows) * Panel.ROLL_ROW_H)
		_assert_eq(str(m.get("verb", "")), "key", "a vertical drag reports the key verb")
		# UP is a HIGHER key, because pitch ascends upward. A drag of Δrows moves the key
		# by −Δrows and by NOTHING ELSE — no tick, no offset, no duration.
		_assert_eq(int(m.get("relative_key", -99)), clampi(5 - rows, 0, 11),
				"%+d rows → key %d" % [rows, clampi(5 - rows, 0, 11)])
		_assert_false(m.has("delta_ticks") or m.has("offset_ticks") or m.has("duration_ticks"),
				"a key drag writes a KEY and nothing that moves the clock")
	# Clamped at both ends, never wrapped: dragging past B must not come back at C, and it
	# must never reach 12 (tie) or 13 (note-form rest) — forms FFT writes zero of.
	_assert_eq(int(Panel.drag_motion(drag, 0.0, 100.0 - 40.0 * Panel.ROLL_ROW_H)
			.get("relative_key", -1)), 11, "dragging way up parks on B, it does not wrap")
	_assert_eq(int(Panel.drag_motion(drag, 0.0, 100.0 + 40.0 * Panel.ROLL_ROW_H)
			.get("relative_key", -1)), 0, "dragging way down parks on C")

	# The gesture is only ARMED on a note bar in roll mode. A rest has no key (its gesture
	# is the paint), and a lanes-mode press can never become one.
	var view: Dictionary = PairModel.pair_view(_make_roll_bank(), 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 1200.0, {"roll": true})
	var note_bar := {}
	var rest_bar := {}
	for bar in lay.get("span_bars", []):
		if int(bar.get("track", -1)) != 0:
			continue
		if bool(bar.get("rest", false)):
			rest_bar = bar
		elif note_bar.is_empty():
			note_bar = bar
	_assert_false(note_bar.is_empty(), "the fixture places a note bar")
	_assert_false(rest_bar.is_empty(), "the fixture places a rest bar")
	var d_note: Dictionary = Panel.drag_target(view, lay, (note_bar["rect"] as Rect2).get_center())
	_assert_true(bool(d_note.get("can_key", false)), "a note bar in the roll CAN be re-keyed")
	_assert_eq(int(d_note.get("start_key", -1)), int(note_bar.get("relative_key", -2)),
			"the drag's start key is read off the BAR, never off the cursor's y — a BORROWED "
			+ "bar is drawn where it is HEARD, on a row belonging to the wrong track")
	var d_rest: Dictionary = Panel.drag_target(view, lay, (rest_bar["rect"] as Rect2).get_center())
	_assert_false(bool(d_rest.get("can_key", false)),
			"a REST cannot be dragged to a pitch — silence has no key, and its own gesture "
			+ "is the paint")
	var lanes_lay: Dictionary = Panel.layout(view, 1200.0, {})
	var lanes_note := {}
	for bar in lanes_lay.get("span_bars", []):
		if int(bar.get("track", -1)) == 0 and not bool(bar.get("rest", false)):
			lanes_note = bar
			break
	var d_lanes: Dictionary = Panel.drag_target(view, lanes_lay,
			(lanes_note["rect"] as Rect2).get_center())
	_assert_false(bool(d_lanes.get("can_key", false)),
			"in LANES mode no press can become a key drag — there is no key axis to read")
	# The ADDRESS: the note EVENT's head is its velocity byte, and the key rides the next
	# one. The drag and the inspector's "Note key" dropdown therefore write through ONE
	# address, not two that can drift.
	var key_ref: Dictionary = Page._pair_key_ref(d_note)
	_assert_eq(str(key_ref.get("kind", "")), "note_key", "the drag lowers to the note_key kind")
	_assert_eq(int(key_ref.get("offset", -1)), int(d_note.get("at", -1)) + 1,
			"it addresses the DATA byte, one past the event head")
	var sel_view: Dictionary = view.duplicate()
	sel_view["selected"] = {"track": int(d_note["track"]),
			"event_index": int(d_note["event_index"])}
	var proj_ref: Dictionary = {}
	for sec in PairProjector.sections(Target.pair(0), null, {"feds_pairs": [sel_view]}):
		for f in (sec as Dictionary).get("fields", []):
			if str((f as Dictionary).get("name", "")) == "Note key":
				proj_ref = (f as Dictionary).get("field_ref", {})
	_assert_false(proj_ref.is_empty(), "the inspector offers a Note key cell for that note")
	_assert_eq(proj_ref, key_ref,
			"the drag's address IS the dropdown's address — one byte, one field_ref")


func _test_the_roll_ladder_prints_the_octave_the_row_cannot() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	# In LANES mode the ladder drops the pitch and keeps the ordinal. In ROLL mode it is the
	# other way round, and for the same reason that ordered the first one: each rung drops
	# the token most recoverable elsewhere. The KEY is on the row (free). The OCTAVE is not —
	# the Opcodes lane only carries an Oct chip where an Octave opcode actually fires.
	var bar := {"ordinal": 8, "label": "C3 · v0", "key_label": "C3", "octave": 3, "velocity": 0}
	var rungs: Array = Panel.span_text_rungs(bar, true)
	_assert_eq(str(rungs[0]), "8 C3 · v0", "a wide bar still prints everything")
	_assert_eq(str(rungs[1]), "8 C3", "velocity goes first — 97.3% of the corpus is 96")
	_assert_eq(str(rungs[2]), "8 3", "then the KEY goes: the ROW says it, better than ink can")
	_assert_eq(str(rungs[3]), "3", "then the ordinal — the octave digit is what survives")
	_assert_eq(str(rungs[4]), "", "the last rung is silence")
	# A v96 note has no velocity token to drop, so its ladder is one rung shorter — the same
	# property the lanes ladder has.
	_assert_eq(Panel.span_text_rungs(
			{"ordinal": 8, "label": "C3", "key_label": "C3", "octave": 3,
			"velocity": Panel.CORPUS_VELOCITY}, true).size(), 4,
			"with no velocity token there is no velocity rung")
	# A REST lives on the Rest row, so "Rest" is redundant there exactly as the key is.
	var rest_rungs: Array = Panel.span_text_rungs(
			{"ordinal": 4, "label": "Rest", "key_label": "Rest", "rest": true}, true)
	_assert_eq(str(rest_rungs[0]), "4", "a rest's roll ladder is its ordinal alone")
	_assert_eq(str(rest_rungs[rest_rungs.size() - 1]), "", "and then silence")
	# The LANES ladder is untouched — this is a second reading, not a rewrite.
	_assert_eq(str(Panel.span_text_rungs(bar)[1]), "8 C3",
			"lanes mode still drops velocity then PITCH, keeping the ordinal")
	_assert_eq(str(Panel.span_text_rungs(bar)[2]), "8", "lanes mode's last inked rung")


func _test_every_span_boundary_gets_one_separator_per_ROLL_row() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	# The boundary hairline is a PER-ROW fact once the bars leave the shared centre line:
	# two neighbouring spans on DIFFERENT rows no longer share an edge on screen, so the
	# N+1 count is per row, not per lane. And the stroke is the BAR's height, not
	# NOTE_BAR_H — a 16 px stroke on a 10 px bar would be the lane rule this replaced.
	var view: Dictionary = PairModel.pair_view(_make_roll_bank(), 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 1200.0, {"roll": true})
	var bars_per_y := {}
	for bar in lay.get("span_bars", []):
		var r: Rect2 = bar["rect"]
		bars_per_y[r.position.y] = int(bars_per_y.get(r.position.y, 0)) + 1
	var seps_per_y := {}
	for sep in lay.get("span_seps", []):
		seps_per_y[float(sep["y"])] = int(seps_per_y.get(float(sep["y"]), 0)) + 1
		_assert_true(absf(float(sep["h"]) - Panel.ROLL_BAR_H) < 0.01,
				"the hairline is the ROLL bar's height, read off the bar")
	_assert_true(not seps_per_y.is_empty(), "the roll draws separators at all")
	for y in bars_per_y.keys():
		# One row, one span: 1 bar owns 2 boundaries. Where a row holds N spans that touch,
		# shared edges dedupe and the count drops toward N+1 — never 2N.
		_assert_true(int(seps_per_y.get(y, 0)) <= int(bars_per_y[y]) + 1,
				"row at y=%.1f draws at most N+1 hairlines for its N spans" % float(y))
		_assert_true(int(seps_per_y.get(y, 0)) >= 2,
				"a row with a span draws both of its outer boundaries")


func _test_the_roll_fits_the_band_on_a_full_height_window() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	# §4.2 was "13 rows at what px?", and the answer is arithmetic, not taste: the pair band
	# is a contended budget (Page._editor_band), so a row height is a claim about whether the
	# roll fits WHOLE or is scrolled inside its own panel. Measured on a maximised window on
	# a 1440-tall display, the page body is ~1219 px and the band grants the panel ~654.
	#
	# This is also why the roll DROPS the energy band, the no-op tell and the joint mix band
	# (§4.3): they cost 142 px, which is exactly the difference between fitting and not.
	var per_track: float = Panel.SECTION_H \
			+ float(Panel.ROLL_ROWS) * Panel.ROLL_ROW_H + Panel.LANE_GAP \
			+ (Panel.LANE_H + 2.0 * (Panel.CHIP_H + Panel.CHIP_ROW_GAP) + Panel.LANE_GAP) \
			+ (Panel.LANE_H + Panel.LANE_GAP)
	var want: float = Panel.HEADER_H + Panel.RULER_H + 2.0 * per_track + Panel.CONTENT_PAD_Y
	var band: Dictionary = Page._editor_band(1219.0, 355.0, want, true)
	_assert_true(float(band["panel_h"]) >= want,
			"a two-track roll with three opcode rows a track fits WHOLE in the band "
			+ "(%d px wanted, %d granted)" % [int(want), int(float(band["panel_h"]))])
	# And the corroboration rows really are gone in roll mode — keeping them is what would
	# blow the budget above.
	var view: Dictionary = PairModel.pair_view(_make_roll_bank(), 0, {}, null)
	var roll_lay: Dictionary = Panel.layout(view, 1200.0, {"roll": true})
	_assert_true((roll_lay.get("energy_bands", []) as Array).is_empty(),
			"the roll drops the per-track energy band — it answers the OPCODE question")
	_assert_true((roll_lay.get("noop_tells", []) as Array).is_empty(),
			"and the no-op A/B tell")
	_assert_true((roll_lay.get("joint_band", {}) as Dictionary).is_empty(),
			"and the joint mix band")
	# Every other lane SURVIVES, re-projected: the roll replaces the Time lane only.
	var kinds_roll := {}
	var kinds_lanes := {}
	for lane in roll_lay.get("lanes", []):
		kinds_roll["%d:%s" % [int(lane["track"]), str(lane["kind"])]] = true
	for lane in Panel.layout(view, 1200.0, {}).get("lanes", []):
		kinds_lanes["%d:%s" % [int(lane["track"]), str(lane["kind"])]] = true
	_assert_eq(kinds_roll.keys(), kinds_lanes.keys(),
			"the same lanes are present in both readings — only the Time lane's SHAPE differs")
	_assert_eq((roll_lay.get("chips", []) as Array).size(),
			(Panel.layout(view, 1200.0, {}).get("chips", []) as Array).size(),
			"and the same chips")


func _test_the_roll_toggle_is_opt_in_and_routes_from_the_header() -> void:
	var Panel = load("res://src/effects/studio/FedsPairLanePanel.gd")
	# Decision 5 stays intact precisely BECAUSE the roll is opt-in: the lane view is what a
	# pair opens as, and the roll is a second reading you ask for.
	var view: Dictionary = PairModel.pair_view(_make_roll_bank(), 0, {}, null)
	var lay: Dictionary = Panel.layout(view, 1200.0, {})
	_assert_false(bool(lay.get("roll", true)), "no `roll` in the state means LANES")
	var header: Dictionary = lay["header"]
	var rr: Rect2 = header["roll_rect"]
	_assert_false(bool(header.get("roll", true)), "the chip says which reading is in force")
	_assert_eq(str(Panel.hit_in(lay, rr.get_center()).get("kind", "")), "toggle_roll",
			"a click on the chip routes to the toggle")
	# It is a SIBLING of the unwind-all chip, not on top of it: both stay clickable.
	var ua: Rect2 = header["unwind_all_rect"]
	_assert_false(rr.intersects(ua), "the two header chips do not overlap")
	_assert_eq(str(Panel.hit_in(lay, ua.get_center()).get("kind", "")), "toggle_all",
			"the unwind-all chip still routes to its own verb")
	_assert_true(bool(Panel.layout(view, 1200.0, {"roll": true})["header"]["roll"]),
			"and in roll mode the chip says so")
