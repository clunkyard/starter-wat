;; A starter robot for rules v2, in WebAssembly text on ABI 4: it calls the
;; robot core through the clunkyard.* imports, which the SDK block at the top
;; of the module declares. It sweeps a medium scan to find a robot, narrows
;; the scan to hold it, leads it with shots whose power suits the range,
;; fires only when the turret is on target, keeps battery back for driving,
;; looks again where it last saw one, follows a passive cue when it has
;; nothing better and steps out of the storm.
;;
;; The trade-offs (the imports answer with the numbers the hello set):
;;   scan     a narrow arc reaches further; a wide one finds robots nearby
;;   power    heavy shots hit harder for less battery, but fly slowly
;;   battery  shots and driving share it, and it refills slowly
;;   turret   it turns at a limited rate; $cy_gun_aim_now is where it points now
;;   fuel     every import costs fuel, so read each fact once a turn
;; A cue ($cy_tracker_cue) says roughly where a robot is, within its
;; bearing error: good for where to look, not where to shoot.
;;
;; Each import writes its answer into memory and returns a status; a record
;; field is at the record's address plus its offset global, as
;; (f64.load (i32.add (global.get $TARGET) (global.get $CY_CONTACT_BEARING))).
;; Clunkyard WebAssembly ABI 4: the robot calls the core through imports
;; from "clunkyard", declared in clunkyard.h. Export memory and, through
;; CY_ROBOT(start, turn), clunkyard_start and clunkyard_turn. Each import
;; returns a status (CY_OK 0, CY_NONE 1 for absent) and writes results
;; through pointers; each costs fuel. In C each import is cy_<name>, as
;; cy_sensors_nearest(&contact).
;; match: match_mode match_ruleset match_control match_robots match_is_3d
;;   match_tick_rate match_max_ticks robot_id robot_seed
;; clock: clock_tick clock_seconds clock_remaining_ticks
;; arena: arena_size arena_gravity arena_terrain_kind arena_ground_height
;; me: me_health me_position me_velocity me_heading me_pitch me_roll
;;   me_angular_velocity me_attitude me_grounded me_altitude me_applied
;; battery: battery_charge battery_capacity battery_regen
;;   battery_sustainable_drive battery_compute battery_drive_cost
;; drive: drive_hover_lift drive_throttle drive_turn drive_pitch_turn
;;   drive_thrust drive_strafe drive_lift drive_yaw_torque
;;   drive_pitch_torque drive_roll_torque drive_brake drive_get_throttle
;;   drive_get_turn drive_get_pitch_turn drive_get_thrust drive_get_strafe
;;   drive_get_lift drive_get_yaw_torque drive_get_pitch_torque
;;   drive_get_roll_torque drive_get_brake
;; gun: gun_aim_now gun_cooldown_ticks gun_spread gun_max_power
;;   gun_damage_scale gun_can_fire gun_shot_speed gun_shot_cost
;;   gun_reload_ticks gun_shot_damage gun_power_for_speed
;;   gun_power_for_flight_time gun_lead gun_lead_point gun_aim_heading
;;   gun_aim_pitch gun_fire gun_power gun_get_aim_heading gun_get_aim_pitch
;;   gun_get_fire gun_get_power
;; scanner: scanner_last scanner_proximity_range scanner_reach
;;   scanner_arc_for_reach scanner_heading scanner_arc scanner_pitch
;;   scanner_get_heading scanner_get_arc scanner_get_pitch
;; sensors: sensors_contacts sensors_nearest sensors_cues sensors_contact
;;   sensors_position_of
;; tracker: tracker_cue tracker_nearest_bearing_rate tracker_velocity
;;   tracker_position tracker_last_seen tracker_configure
;; nav: nav_zone nav_zone_margin nav_zone_contains nav_zone_distance_from
;;   nav_storm nav_storm_margin nav_storm_contains nav_storm_distance_from
;;   nav_hill nav_hill_margin nav_hill_contains nav_hill_distance_from
;;   nav_pickups nav_nearest_pickup nav_field_distance
;; score: score_me score_best score_armour
;; angles: angles_normalize angles_angle_diff angles_bearing_to
;;   angles_elevation_to angles_direction angles_distance angles_clamp
;; status: status_text status_value status_get_text status_get_value
;; raw: raw_number raw_text raw_has raw_flag raw_count raw_line raw_extra
;; session: session_log
;; Records: cy_contact, cy_vec3, cy_direction and the rest, in clunkyard.h.
;; Angles are degrees from the +x axis; pitch is positive up.
;; Manual: https://clunkyard.com/manual#wasm
(module
  ;; Generated from protocol/v2/api.json by protocol/v2/codegen/wasm-surfaces.js; do not edit. Run `make api`.
  ;;
  ;; Clunkyard WebAssembly ABI 4 for WAT: the clunkyard.* imports, as
  ;; $cy_<name> (and $cy_sensors_nearest for the latest version), then the
  ;; constants and each record field's offset as i32 globals ($CY_OK,
  ;; $CY_CONTACT_BEARING, $CY_CONTACT_SIZE). Imports come before any other
  ;; definition, so this goes first in the module. Each import returns a
  ;; status ($CY_OK, $CY_NONE for absent) and writes through pointers into
  ;; memory; each costs fuel. The module exports memory, clunkyard_start and
  ;; clunkyard_turn, each () -> i32 and 0 to play on.
  (import "clunkyard" "match_mode" (func $cy_match_mode (param i32) (result i32)))
  (import "clunkyard" "match_ruleset" (func $cy_match_ruleset (param i32) (result i32)))
  (import "clunkyard" "match_control" (func $cy_match_control (param i32) (result i32)))
  (import "clunkyard" "match_robots" (func $cy_match_robots (param i32) (result i32)))
  (import "clunkyard" "match_is_3d" (func $cy_match_is_3d (param i32) (result i32)))
  (import "clunkyard" "match_tick_rate" (func $cy_match_tick_rate (param i32) (result i32)))
  (import "clunkyard" "match_max_ticks" (func $cy_match_max_ticks (param i32) (result i32)))
  (import "clunkyard" "robot_id" (func $cy_robot_id (param i32 i32 i32 i32) (result i32)))
  (import "clunkyard" "clock_tick" (func $cy_clock_tick (param i32) (result i32)))
  (import "clunkyard" "clock_seconds" (func $cy_clock_seconds (param i32) (result i32)))
  (import "clunkyard" "clock_remaining_ticks" (func $cy_clock_remaining_ticks (param i32) (result i32)))
  (import "clunkyard" "arena_size" (func $cy_arena_size (param i32) (result i32)))
  (import "clunkyard" "arena_gravity" (func $cy_arena_gravity (param i32) (result i32)))
  (import "clunkyard" "arena_terrain_kind" (func $cy_arena_terrain_kind (param i32) (result i32)))
  (import "clunkyard" "arena_ground_height" (func $cy_arena_ground_height (param f64 f64 i32) (result i32)))
  (import "clunkyard" "me_health" (func $cy_me_health (param i32) (result i32)))
  (import "clunkyard" "me_position" (func $cy_me_position (param i32) (result i32)))
  (import "clunkyard" "me_velocity" (func $cy_me_velocity (param i32) (result i32)))
  (import "clunkyard" "me_heading" (func $cy_me_heading (param i32) (result i32)))
  (import "clunkyard" "me_pitch" (func $cy_me_pitch (param i32) (result i32)))
  (import "clunkyard" "me_roll" (func $cy_me_roll (param i32) (result i32)))
  (import "clunkyard" "me_angular_velocity" (func $cy_me_angular_velocity (param i32) (result i32)))
  (import "clunkyard" "me_attitude_v1" (func $cy_me_attitude_v1 (param i32) (result i32)))
  (import "clunkyard" "me_attitude_v1" (func $cy_me_attitude (param i32) (result i32)))
  (import "clunkyard" "me_grounded" (func $cy_me_grounded (param i32) (result i32)))
  (import "clunkyard" "me_altitude" (func $cy_me_altitude (param i32) (result i32)))
  (import "clunkyard" "me_applied_v1" (func $cy_me_applied_v1 (param i32) (result i32)))
  (import "clunkyard" "me_applied_v1" (func $cy_me_applied (param i32) (result i32)))
  (import "clunkyard" "battery_charge" (func $cy_battery_charge (param i32) (result i32)))
  (import "clunkyard" "battery_capacity" (func $cy_battery_capacity (param i32) (result i32)))
  (import "clunkyard" "battery_regen" (func $cy_battery_regen (param i32) (result i32)))
  (import "clunkyard" "battery_sustainable_drive" (func $cy_battery_sustainable_drive (param i32) (result i32)))
  (import "clunkyard" "battery_compute_v1" (func $cy_battery_compute_v1 (param i32) (result i32)))
  (import "clunkyard" "battery_compute_v1" (func $cy_battery_compute (param i32) (result i32)))
  (import "clunkyard" "battery_drive_cost" (func $cy_battery_drive_cost (param f64 i32) (result i32)))
  (import "clunkyard" "drive_hover_lift" (func $cy_drive_hover_lift (param i32) (result i32)))
  (import "clunkyard" "drive_throttle" (func $cy_drive_throttle (param f64) (result i32)))
  (import "clunkyard" "drive_turn" (func $cy_drive_turn (param f64) (result i32)))
  (import "clunkyard" "drive_pitch_turn" (func $cy_drive_pitch_turn (param f64) (result i32)))
  (import "clunkyard" "drive_thrust" (func $cy_drive_thrust (param f64) (result i32)))
  (import "clunkyard" "drive_strafe" (func $cy_drive_strafe (param f64) (result i32)))
  (import "clunkyard" "drive_lift" (func $cy_drive_lift (param f64) (result i32)))
  (import "clunkyard" "drive_yaw_torque" (func $cy_drive_yaw_torque (param f64) (result i32)))
  (import "clunkyard" "drive_pitch_torque" (func $cy_drive_pitch_torque (param f64) (result i32)))
  (import "clunkyard" "drive_roll_torque" (func $cy_drive_roll_torque (param f64) (result i32)))
  (import "clunkyard" "drive_brake" (func $cy_drive_brake (param f64) (result i32)))
  (import "clunkyard" "drive_get_throttle" (func $cy_drive_get_throttle (param i32) (result i32)))
  (import "clunkyard" "drive_get_turn" (func $cy_drive_get_turn (param i32) (result i32)))
  (import "clunkyard" "drive_get_pitch_turn" (func $cy_drive_get_pitch_turn (param i32) (result i32)))
  (import "clunkyard" "drive_get_thrust" (func $cy_drive_get_thrust (param i32) (result i32)))
  (import "clunkyard" "drive_get_strafe" (func $cy_drive_get_strafe (param i32) (result i32)))
  (import "clunkyard" "drive_get_lift" (func $cy_drive_get_lift (param i32) (result i32)))
  (import "clunkyard" "drive_get_yaw_torque" (func $cy_drive_get_yaw_torque (param i32) (result i32)))
  (import "clunkyard" "drive_get_pitch_torque" (func $cy_drive_get_pitch_torque (param i32) (result i32)))
  (import "clunkyard" "drive_get_roll_torque" (func $cy_drive_get_roll_torque (param i32) (result i32)))
  (import "clunkyard" "drive_get_brake" (func $cy_drive_get_brake (param i32) (result i32)))
  (import "clunkyard" "gun_aim_now" (func $cy_gun_aim_now (param i32) (result i32)))
  (import "clunkyard" "gun_cooldown_ticks" (func $cy_gun_cooldown_ticks (param i32) (result i32)))
  (import "clunkyard" "gun_spread" (func $cy_gun_spread (param i32) (result i32)))
  (import "clunkyard" "gun_max_power" (func $cy_gun_max_power (param i32) (result i32)))
  (import "clunkyard" "gun_damage_scale" (func $cy_gun_damage_scale (param i32) (result i32)))
  (import "clunkyard" "gun_can_fire" (func $cy_gun_can_fire (param f64 f64 i32) (result i32)))
  (import "clunkyard" "gun_shot_speed" (func $cy_gun_shot_speed (param f64 i32) (result i32)))
  (import "clunkyard" "gun_shot_cost" (func $cy_gun_shot_cost (param f64 i32) (result i32)))
  (import "clunkyard" "gun_reload_ticks" (func $cy_gun_reload_ticks (param f64 i32) (result i32)))
  (import "clunkyard" "gun_shot_damage" (func $cy_gun_shot_damage (param f64 i32) (result i32)))
  (import "clunkyard" "gun_power_for_speed" (func $cy_gun_power_for_speed (param f64 i32) (result i32)))
  (import "clunkyard" "gun_power_for_flight_time" (func $cy_gun_power_for_flight_time (param f64 f64 i32) (result i32)))
  (import "clunkyard" "gun_lead_v1" (func $cy_gun_lead_v1 (param i32 f64 i32) (result i32)))
  (import "clunkyard" "gun_lead_v1" (func $cy_gun_lead (param i32 f64 i32) (result i32)))
  (import "clunkyard" "gun_lead_point_v1" (func $cy_gun_lead_point_v1 (param i32 i32 f64 i32) (result i32)))
  (import "clunkyard" "gun_lead_point_v1" (func $cy_gun_lead_point (param i32 i32 f64 i32) (result i32)))
  (import "clunkyard" "gun_aim_heading" (func $cy_gun_aim_heading (param f64) (result i32)))
  (import "clunkyard" "gun_aim_pitch" (func $cy_gun_aim_pitch (param f64) (result i32)))
  (import "clunkyard" "gun_fire" (func $cy_gun_fire (result i32)))
  (import "clunkyard" "gun_power" (func $cy_gun_power (param f64) (result i32)))
  (import "clunkyard" "gun_get_aim_heading" (func $cy_gun_get_aim_heading (param i32) (result i32)))
  (import "clunkyard" "gun_get_aim_pitch" (func $cy_gun_get_aim_pitch (param i32) (result i32)))
  (import "clunkyard" "gun_get_fire" (func $cy_gun_get_fire (param i32) (result i32)))
  (import "clunkyard" "gun_get_power" (func $cy_gun_get_power (param i32) (result i32)))
  (import "clunkyard" "scanner_last_v1" (func $cy_scanner_last_v1 (param i32) (result i32)))
  (import "clunkyard" "scanner_last_v1" (func $cy_scanner_last (param i32) (result i32)))
  (import "clunkyard" "scanner_proximity_range" (func $cy_scanner_proximity_range (param i32) (result i32)))
  (import "clunkyard" "scanner_reach" (func $cy_scanner_reach (param f64 i32) (result i32)))
  (import "clunkyard" "scanner_arc_for_reach" (func $cy_scanner_arc_for_reach (param f64 i32) (result i32)))
  (import "clunkyard" "scanner_heading" (func $cy_scanner_heading (param f64) (result i32)))
  (import "clunkyard" "scanner_arc" (func $cy_scanner_arc (param f64) (result i32)))
  (import "clunkyard" "scanner_pitch" (func $cy_scanner_pitch (param f64) (result i32)))
  (import "clunkyard" "scanner_get_heading" (func $cy_scanner_get_heading (param i32) (result i32)))
  (import "clunkyard" "scanner_get_arc" (func $cy_scanner_get_arc (param i32) (result i32)))
  (import "clunkyard" "scanner_get_pitch" (func $cy_scanner_get_pitch (param i32) (result i32)))
  (import "clunkyard" "sensors_contacts_v1" (func $cy_sensors_contacts_v1 (param i32 i32 i32) (result i32)))
  (import "clunkyard" "sensors_contacts_v1" (func $cy_sensors_contacts (param i32 i32 i32) (result i32)))
  (import "clunkyard" "sensors_nearest_v1" (func $cy_sensors_nearest_v1 (param i32) (result i32)))
  (import "clunkyard" "sensors_nearest_v1" (func $cy_sensors_nearest (param i32) (result i32)))
  (import "clunkyard" "sensors_cues_v1" (func $cy_sensors_cues_v1 (param i32 i32 i32) (result i32)))
  (import "clunkyard" "sensors_cues_v1" (func $cy_sensors_cues (param i32 i32 i32) (result i32)))
  (import "clunkyard" "sensors_contact_v1" (func $cy_sensors_contact_v1 (param i32 i32) (result i32)))
  (import "clunkyard" "sensors_contact_v1" (func $cy_sensors_contact (param i32 i32) (result i32)))
  (import "clunkyard" "sensors_position_of_v1" (func $cy_sensors_position_of_v1 (param i32 i32) (result i32)))
  (import "clunkyard" "sensors_position_of_v1" (func $cy_sensors_position_of (param i32 i32) (result i32)))
  (import "clunkyard" "tracker_cue_v1" (func $cy_tracker_cue_v1 (param i32) (result i32)))
  (import "clunkyard" "tracker_cue_v1" (func $cy_tracker_cue (param i32) (result i32)))
  (import "clunkyard" "tracker_nearest_bearing_rate" (func $cy_tracker_nearest_bearing_rate (param i32) (result i32)))
  (import "clunkyard" "tracker_velocity" (func $cy_tracker_velocity (param i32 i32) (result i32)))
  (import "clunkyard" "tracker_position" (func $cy_tracker_position (param i32 i32) (result i32)))
  (import "clunkyard" "tracker_last_seen" (func $cy_tracker_last_seen (param i32 i32) (result i32)))
  (import "clunkyard" "tracker_configure" (func $cy_tracker_configure (param f64 i32 i32) (result i32)))
  (import "clunkyard" "nav_zone_v1" (func $cy_nav_zone_v1 (param i32) (result i32)))
  (import "clunkyard" "nav_zone_v1" (func $cy_nav_zone (param i32) (result i32)))
  (import "clunkyard" "nav_zone_margin" (func $cy_nav_zone_margin (param i32 i32) (result i32)))
  (import "clunkyard" "nav_zone_contains" (func $cy_nav_zone_contains (param i32 f64 i32) (result i32)))
  (import "clunkyard" "nav_zone_distance_from" (func $cy_nav_zone_distance_from (param i32 i32) (result i32)))
  (import "clunkyard" "nav_storm_v1" (func $cy_nav_storm_v1 (param i32) (result i32)))
  (import "clunkyard" "nav_storm_v1" (func $cy_nav_storm (param i32) (result i32)))
  (import "clunkyard" "nav_storm_margin" (func $cy_nav_storm_margin (param i32 i32) (result i32)))
  (import "clunkyard" "nav_storm_contains" (func $cy_nav_storm_contains (param i32 f64 i32) (result i32)))
  (import "clunkyard" "nav_storm_distance_from" (func $cy_nav_storm_distance_from (param i32 i32) (result i32)))
  (import "clunkyard" "nav_hill_v1" (func $cy_nav_hill_v1 (param i32) (result i32)))
  (import "clunkyard" "nav_hill_v1" (func $cy_nav_hill (param i32) (result i32)))
  (import "clunkyard" "nav_hill_margin" (func $cy_nav_hill_margin (param i32 i32) (result i32)))
  (import "clunkyard" "nav_hill_contains" (func $cy_nav_hill_contains (param i32 f64 i32) (result i32)))
  (import "clunkyard" "nav_hill_distance_from" (func $cy_nav_hill_distance_from (param i32 i32) (result i32)))
  (import "clunkyard" "nav_pickups_v1" (func $cy_nav_pickups_v1 (param i32 i32 i32) (result i32)))
  (import "clunkyard" "nav_pickups_v1" (func $cy_nav_pickups (param i32 i32 i32) (result i32)))
  (import "clunkyard" "nav_nearest_pickup_v1" (func $cy_nav_nearest_pickup_v1 (param i32 i32) (result i32)))
  (import "clunkyard" "nav_nearest_pickup_v1" (func $cy_nav_nearest_pickup (param i32 i32) (result i32)))
  (import "clunkyard" "nav_field_distance" (func $cy_nav_field_distance (param i32 i32 i32) (result i32)))
  (import "clunkyard" "score_me" (func $cy_score_me (param i32) (result i32)))
  (import "clunkyard" "score_best" (func $cy_score_best (param i32) (result i32)))
  (import "clunkyard" "score_armour" (func $cy_score_armour (param i32) (result i32)))
  (import "clunkyard" "angles_normalize" (func $cy_angles_normalize (param f64 i32) (result i32)))
  (import "clunkyard" "angles_angle_diff" (func $cy_angles_angle_diff (param f64 f64 i32) (result i32)))
  (import "clunkyard" "angles_bearing_to" (func $cy_angles_bearing_to (param i32 i32 i32) (result i32)))
  (import "clunkyard" "angles_elevation_to" (func $cy_angles_elevation_to (param i32 i32 i32) (result i32)))
  (import "clunkyard" "angles_direction" (func $cy_angles_direction (param f64 f64 i32) (result i32)))
  (import "clunkyard" "angles_distance" (func $cy_angles_distance (param i32 i32 i32) (result i32)))
  (import "clunkyard" "angles_clamp" (func $cy_angles_clamp (param f64 f64 f64 i32) (result i32)))
  (import "clunkyard" "status_text" (func $cy_status_text (param i32 i32) (result i32)))
  (import "clunkyard" "status_value" (func $cy_status_value (param f64) (result i32)))
  (import "clunkyard" "status_get_text" (func $cy_status_get_text (param i32 i32 i32) (result i32)))
  (import "clunkyard" "status_get_value" (func $cy_status_get_value (param i32) (result i32)))
  (import "clunkyard" "raw_number" (func $cy_raw_number (param i32 i32 i32) (result i32)))
  (import "clunkyard" "raw_text" (func $cy_raw_text (param i32 i32 i32 i32 i32) (result i32)))
  (import "clunkyard" "raw_has" (func $cy_raw_has (param i32 i32 i32) (result i32)))
  (import "clunkyard" "raw_flag" (func $cy_raw_flag (param i32 i32 i32) (result i32)))
  (import "clunkyard" "raw_count" (func $cy_raw_count (param i32 i32 i32) (result i32)))
  (import "clunkyard" "raw_line" (func $cy_raw_line (param i32 i32 i32) (result i32)))
  (import "clunkyard" "raw_extra" (func $cy_raw_extra (param i32 i32) (result i32)))
  (import "clunkyard" "session_log" (func $cy_session_log (param i32 i32) (result i32)))
  (import "clunkyard" "robot_seed" (func $cy_robot_seed (param i32) (result i32)))
  (global $CY_OK i32 (i32.const 0))
  (global $CY_NONE i32 (i32.const 1))
  (global $CY_SHORT i32 (i32.const 2))
  (global $CY_E_NOT_FINITE i32 (i32.const -1))
  (global $CY_E_RANGE i32 (i32.const -2))
  (global $CY_E_ARGUMENT i32 (i32.const -3))
  (global $CY_E_PHASE i32 (i32.const -4))
  (global $CY_E_VERSION i32 (i32.const -5))
  (global $CY_E_INTERNAL i32 (i32.const -6))
  (global $CY_SOURCE_NONE i32 (i32.const 0))
  (global $CY_SOURCE_SCAN i32 (i32.const 1))
  (global $CY_SOURCE_PROXIMITY i32 (i32.const 2))
  (global $CY_SOURCE_FAINT i32 (i32.const 3))
  (global $CY_SOURCE_BEAM i32 (i32.const 4))
  (global $CY_SOURCE_MUZZLE i32 (i32.const 5))
  (global $CY_SOURCE_MOTION i32 (i32.const 6))
  (global $CY_SOURCE_PING i32 (i32.const 7))
  (global $CY_MODE_NONE i32 (i32.const 0))
  (global $CY_MODE_TWO_D i32 (i32.const 1))
  (global $CY_MODE_THREE_D i32 (i32.const 2))
  (global $CY_RULESET_NONE i32 (i32.const 0))
  (global $CY_RULESET_CLASSIC i32 (i32.const 1))
  (global $CY_RULESET_INERTIAL_2D i32 (i32.const 2))
  (global $CY_RULESET_GRAVITY_FLAT i32 (i32.const 3))
  (global $CY_RULESET_GRAVITY_HILLS i32 (i32.const 4))
  (global $CY_RULESET_ZERO_G i32 (i32.const 5))
  (global $CY_CONTROL_NONE i32 (i32.const 0))
  (global $CY_CONTROL_DIRECT i32 (i32.const 1))
  (global $CY_CONTROL_FORCES i32 (i32.const 2))
  (global $CY_TERRAIN_KIND_NONE i32 (i32.const 1))
  (global $CY_TERRAIN_KIND_FLAT i32 (i32.const 2))
  (global $CY_TERRAIN_KIND_HILLS i32 (i32.const 3))
  (global $CY_SHAPE_NONE i32 (i32.const 0))
  (global $CY_SHAPE_CIRCLE i32 (i32.const 1))
  (global $CY_SHAPE_SPHERE i32 (i32.const 2))
  (global $CY_SHAPE_COLUMN i32 (i32.const 3))
  (global $CY_PICKUP_KIND_ANY i32 (i32.const 0))
  (global $CY_PICKUP_KIND_ENERGY i32 (i32.const 1))
  (global $CY_PICKUP_KIND_HEALTH i32 (i32.const 2))
  (global $CY_PICKUP_KIND_ARMOUR i32 (i32.const 3))
  (global $CY_COMPUTE_UNIT_NONE i32 (i32.const 0))
  (global $CY_COMPUTE_UNIT_OPERATIONS i32 (i32.const 1))
  (global $CY_COMPUTE_UNIT_FUEL i32 (i32.const 2))
  (global $CY_COMPUTE_UNIT_CPU_MS i32 (i32.const 3))
  (global $CY_EVENT_NONE i32 (i32.const 0))
  (global $CY_EVENT_HELLO i32 (i32.const 1))
  (global $CY_EVENT_STATE i32 (i32.const 2))
  (global $CY_EVENT_END i32 (i32.const 3))
  (global $CY_VEC3_SIZE i32 (i32.const 24))
  (global $CY_VEC3_X i32 (i32.const 0))
  (global $CY_VEC3_Y i32 (i32.const 8))
  (global $CY_VEC3_Z i32 (i32.const 16))
  (global $CY_ROTATION_SIZE i32 (i32.const 24))
  (global $CY_ROTATION_YAW i32 (i32.const 0))
  (global $CY_ROTATION_PITCH i32 (i32.const 8))
  (global $CY_ROTATION_ROLL i32 (i32.const 16))
  (global $CY_DIRECTION_SIZE i32 (i32.const 16))
  (global $CY_DIRECTION_HEADING i32 (i32.const 0))
  (global $CY_DIRECTION_PITCH i32 (i32.const 8))
  (global $CY_ATTITUDE_SIZE i32 (i32.const 72))
  (global $CY_ATTITUDE_FORWARD_X i32 (i32.const 0))
  (global $CY_ATTITUDE_FORWARD_Y i32 (i32.const 8))
  (global $CY_ATTITUDE_FORWARD_Z i32 (i32.const 16))
  (global $CY_ATTITUDE_RIGHT_X i32 (i32.const 24))
  (global $CY_ATTITUDE_RIGHT_Y i32 (i32.const 32))
  (global $CY_ATTITUDE_RIGHT_Z i32 (i32.const 40))
  (global $CY_ATTITUDE_UP_X i32 (i32.const 48))
  (global $CY_ATTITUDE_UP_Y i32 (i32.const 56))
  (global $CY_ATTITUDE_UP_Z i32 (i32.const 64))
  (global $CY_APPLIED_SIZE i32 (i32.const 56))
  (global $CY_APPLIED_FORCE_X i32 (i32.const 0))
  (global $CY_APPLIED_FORCE_Y i32 (i32.const 8))
  (global $CY_APPLIED_FORCE_Z i32 (i32.const 16))
  (global $CY_APPLIED_TORQUE_YAW i32 (i32.const 24))
  (global $CY_APPLIED_TORQUE_PITCH i32 (i32.const 32))
  (global $CY_APPLIED_TORQUE_ROLL i32 (i32.const 40))
  (global $CY_APPLIED_BRAKE i32 (i32.const 48))
  (global $CY_SCAN_SIZE i32 (i32.const 32))
  (global $CY_SCAN_HEADING i32 (i32.const 0))
  (global $CY_SCAN_PITCH i32 (i32.const 8))
  (global $CY_SCAN_ARC i32 (i32.const 16))
  (global $CY_SCAN_RANGE i32 (i32.const 24))
  (global $CY_CONTACT_SIZE i32 (i32.const 72))
  (global $CY_CONTACT_SLOT i32 (i32.const 0))
  (global $CY_CONTACT_SOURCE i32 (i32.const 4))
  (global $CY_CONTACT_RANGE i32 (i32.const 8))
  (global $CY_CONTACT_BEARING i32 (i32.const 16))
  (global $CY_CONTACT_ELEVATION i32 (i32.const 24))
  (global $CY_CONTACT_BEARING_ERROR i32 (i32.const 32))
  (global $CY_CONTACT_RANGE_ERROR i32 (i32.const 40))
  (global $CY_CONTACT_POSITION_X i32 (i32.const 48))
  (global $CY_CONTACT_POSITION_Y i32 (i32.const 56))
  (global $CY_CONTACT_POSITION_Z i32 (i32.const 64))
  (global $CY_CUE_SIZE i32 (i32.const 40))
  (global $CY_CUE_SOURCE i32 (i32.const 0))
  (global $CY_CUE_TICK i32 (i32.const 4))
  (global $CY_CUE_BEARING_ERROR i32 (i32.const 8))
  (global $CY_CUE_POSITION_X i32 (i32.const 16))
  (global $CY_CUE_POSITION_Y i32 (i32.const 24))
  (global $CY_CUE_POSITION_Z i32 (i32.const 32))
  (global $CY_SOLUTION_SIZE i32 (i32.const 24))
  (global $CY_SOLUTION_HEADING i32 (i32.const 0))
  (global $CY_SOLUTION_PITCH i32 (i32.const 8))
  (global $CY_SOLUTION_TIME i32 (i32.const 16))
  (global $CY_ZONE_SIZE i32 (i32.const 40))
  (global $CY_ZONE_SHAPE i32 (i32.const 0))
  (global $CY_ZONE_RESERVED i32 (i32.const 4))
  (global $CY_ZONE_RADIUS i32 (i32.const 8))
  (global $CY_ZONE_CENTER_X i32 (i32.const 16))
  (global $CY_ZONE_CENTER_Y i32 (i32.const 24))
  (global $CY_ZONE_CENTER_Z i32 (i32.const 32))
  (global $CY_STORM_SIZE i32 (i32.const 72))
  (global $CY_STORM_SHAPE i32 (i32.const 0))
  (global $CY_STORM_RESERVED i32 (i32.const 4))
  (global $CY_STORM_RADIUS i32 (i32.const 8))
  (global $CY_STORM_DPS i32 (i32.const 16))
  (global $CY_STORM_CENTER_X i32 (i32.const 24))
  (global $CY_STORM_CENTER_Y i32 (i32.const 32))
  (global $CY_STORM_CENTER_Z i32 (i32.const 40))
  (global $CY_STORM_VELOCITY_X i32 (i32.const 48))
  (global $CY_STORM_VELOCITY_Y i32 (i32.const 56))
  (global $CY_STORM_VELOCITY_Z i32 (i32.const 64))
  (global $CY_HILL_SIZE i32 (i32.const 80))
  (global $CY_HILL_SHAPE i32 (i32.const 0))
  (global $CY_HILL_HOLDER i32 (i32.const 4))
  (global $CY_HILL_CONTESTED i32 (i32.const 8))
  (global $CY_HILL_MOVES_TICK i32 (i32.const 12))
  (global $CY_HILL_HELD_TICKS i32 (i32.const 16))
  (global $CY_HILL_BEST_HELD_TICKS i32 (i32.const 20))
  (global $CY_HILL_RADIUS i32 (i32.const 24))
  (global $CY_HILL_CENTER_X i32 (i32.const 32))
  (global $CY_HILL_CENTER_Y i32 (i32.const 40))
  (global $CY_HILL_CENTER_Z i32 (i32.const 48))
  (global $CY_HILL_NEXT_X i32 (i32.const 56))
  (global $CY_HILL_NEXT_Y i32 (i32.const 64))
  (global $CY_HILL_NEXT_Z i32 (i32.const 72))
  (global $CY_PICKUP_SIZE i32 (i32.const 40))
  (global $CY_PICKUP_KIND i32 (i32.const 0))
  (global $CY_PICKUP_EXPIRES_TICK i32 (i32.const 4))
  (global $CY_PICKUP_AMOUNT i32 (i32.const 8))
  (global $CY_PICKUP_POSITION_X i32 (i32.const 16))
  (global $CY_PICKUP_POSITION_Y i32 (i32.const 24))
  (global $CY_PICKUP_POSITION_Z i32 (i32.const 32))
  (global $CY_COMPUTE_SIZE i32 (i32.const 16))
  (global $CY_COMPUTE_K i32 (i32.const 0))
  (global $CY_COMPUTE_QUANTA i32 (i32.const 8))
  (global $CY_COMPUTE_UNIT i32 (i32.const 12))

  (memory (export "memory") 1)
  ;; Where the imports write: one number, one whole number, then the records.
  (global $NUMBER i32 (i32.const 0))
  (global $WHOLE i32 (i32.const 8))
  (global $ME i32 (i32.const 16))
  (global $LAST i32 (i32.const 40))
  (global $STILL i32 (i32.const 64)) ;; a zero vector, never written
  (global $GRAVITY i32 (i32.const 88))
  (global $TARGET i32 (i32.const 128))
  (global $AIM i32 (i32.const 200))
  (global $NOW i32 (i32.const 224))
  (global $CUE i32 (i32.const 240))
  (global $SCAN i32 (i32.const 280))
  (global $STORM i32 (i32.const 312))
  (global $ZONE i32 (i32.const 384))

  ;; Enough to turn against the brake in the force rulesets.
  (global $search_turn f64 (f64.const 0.33))
  ;; How long to look again where a robot was last seen.
  (global $memory_ticks i32 (i32.const 60))
  (global $free (mut i32) (i32.const 0)) ;; flying free, robots may be above or below
  (global $last_slot (mut i32) (i32.const 0)) ;; the robot seen most recently, 0 for none yet

  ;; The number or whole number an import just wrote; ok is its status.
  (func $number (param $ok i32) (result f64) (f64.load (global.get $NUMBER)))
  (func $whole (param $ok i32) (result i32) (i32.load (global.get $WHOLE)))
  (func $field (param $record i32) (param $offset i32) (result f64)
    (f64.load (i32.add (local.get $record) (local.get $offset))))
  (func $angle_diff (param $target f64) (param $current f64) (result f64)
    (call $number (call $cy_angles_angle_diff (local.get $target) (local.get $current) (global.get $NUMBER))))
  (func $bearing_to (param $from i32) (param $to i32) (result f64)
    (call $number (call $cy_angles_bearing_to (local.get $from) (local.get $to) (global.get $NUMBER))))
  (func $elevation_to (param $from i32) (param $to i32) (result f64)
    (call $number (call $cy_angles_elevation_to (local.get $from) (local.get $to) (global.get $NUMBER))))
  (func $unit (param $value f64) (result f64)
    (f64.max (f64.const -1) (f64.min (f64.const 1) (local.get $value))))

  ;; Drives towards a heading and an elevation, turning harder the smaller gain is.
  (func $steer (param $throttle f64) (param $heading f64) (param $elevation f64) (param $gain f64)
    (param $my_heading f64) (param $my_pitch f64)
    (drop (call $cy_drive_throttle (local.get $throttle)))
    (drop (call $cy_drive_turn (call $unit (f64.div (call $angle_diff (local.get $heading) (local.get $my_heading)) (local.get $gain)))))
    (drop (call $cy_drive_pitch_turn (call $unit (f64.div (f64.sub (local.get $elevation) (local.get $my_pitch)) (local.get $gain))))))

  ;; Sweeps the scan: heading, arc and pitch.
  (func $scan (param $heading f64) (param $arc f64) (param $pitch f64)
    (drop (call $cy_scanner_heading (local.get $heading)))
    (drop (call $cy_scanner_arc (local.get $arc)))
    (drop (call $cy_scanner_pitch (local.get $pitch))))

  (func (export "clunkyard_start") (result i32)
    (drop (call $cy_arena_gravity (global.get $GRAVITY)))
    (global.set $free (i32.and (i32.eq (call $whole (call $cy_match_is_3d (global.get $WHOLE))) (i32.const 1))
      (f64.eq (call $field (global.get $GRAVITY) (global.get $CY_VEC3_Z)) (f64.const 0))))
    (i32.const 0))

  (func (export "clunkyard_turn") (result i32)
    (local $heading f64) (local $pitch f64) (local $tick i32)
    (local $range f64) (local $bearing f64) (local $elevation f64) (local $power f64)
    (local $error f64) (local $away f64) (local $drift f64) (local $climb f64)
    (drop (call $cy_me_position (global.get $ME)))
    (local.set $heading (call $number (call $cy_me_heading (global.get $NUMBER))))
    (local.set $pitch (call $number (call $cy_me_pitch (global.get $NUMBER))))
    (local.set $tick (call $whole (call $cy_clock_tick (global.get $WHOLE))))
    (drop (call $cy_drive_brake (f64.const 0.2)))

    (if (i32.eq (call $cy_sensors_nearest (global.get $TARGET)) (global.get $CY_OK))
      (then
        (global.set $last_slot (i32.load (i32.add (global.get $TARGET) (global.get $CY_CONTACT_SLOT))))
        (local.set $range (call $field (global.get $TARGET) (global.get $CY_CONTACT_RANGE)))
        (local.set $bearing (call $field (global.get $TARGET) (global.get $CY_CONTACT_BEARING)))
        (local.set $elevation (call $field (global.get $TARGET) (global.get $CY_CONTACT_ELEVATION)))
        (call $steer
          (select (f64.const 0.7) (select (f64.const -0.4) (f64.const 0.2) (f64.lt (local.get $range) (f64.const 200)))
            (f64.gt (local.get $range) (f64.const 350)))
          (local.get $bearing) (local.get $elevation) (f64.const 45) (local.get $heading) (local.get $pitch))
        (call $scan (local.get $bearing) (f64.const 20) (local.get $elevation)) ;; narrow: holds it, reaching about 735
        ;; The heaviest shot that still covers the range in about a second,
        ;; aimed where the target will be, lobbed under gravity; straight at
        ;; it when no shot reaches it.
        (f64.store (global.get $NUMBER) (f64.const 1))
        (local.set $power (call $number (call $cy_gun_power_for_flight_time (local.get $range) (f64.const 1) (global.get $NUMBER))))
        (if (i32.eq (call $cy_gun_lead (global.get $TARGET) (local.get $power) (global.get $AIM)) (global.get $CY_OK))
          (then
            (local.set $bearing (call $field (global.get $AIM) (global.get $CY_SOLUTION_HEADING)))
            (local.set $elevation (call $field (global.get $AIM) (global.get $CY_SOLUTION_PITCH)))))
        (drop (call $cy_gun_aim_heading (local.get $bearing)))
        (drop (call $cy_gun_aim_pitch (local.get $elevation)))
        (drop (call $cy_gun_aim_now (global.get $NOW)))
        ;; Fire once the turret is on target and the battery covers the shot
        ;; with 10 to spare.
        (if (i32.and (i32.and
              (f64.lt (f64.abs (call $angle_diff (local.get $bearing) (call $field (global.get $NOW) (global.get $CY_DIRECTION_HEADING)))) (f64.const 3))
              (f64.lt (f64.abs (f64.sub (local.get $elevation) (call $field (global.get $NOW) (global.get $CY_DIRECTION_PITCH)))) (f64.const 3)))
              (i32.eq (call $whole (call $cy_gun_can_fire (local.get $power) (f64.const 10) (global.get $WHOLE))) (i32.const 1)))
          (then
            (drop (call $cy_gun_fire))
            (drop (call $cy_gun_power (local.get $power))))))
      (else (if (i32.and (i32.and (i32.ne (global.get $last_slot) (i32.const 0))
              (i32.eq (call $cy_tracker_last_seen (global.get $last_slot) (global.get $WHOLE)) (global.get $CY_OK)))
            (i32.and (i32.lt_s (i32.sub (local.get $tick) (i32.load (global.get $WHOLE))) (global.get $memory_ticks))
              (i32.eq (call $cy_tracker_position (global.get $last_slot) (global.get $LAST)) (global.get $CY_OK))))
      (then
        ;; Head for where it was, sweeping a narrow scan across that bearing.
        (local.set $bearing (call $bearing_to (global.get $ME) (global.get $LAST)))
        (local.set $elevation (select (call $elevation_to (global.get $ME) (global.get $LAST)) (f64.const 0) (global.get $free)))
        (call $steer (f64.const 0.7) (local.get $bearing) (local.get $elevation) (f64.const 45) (local.get $heading) (local.get $pitch))
        (call $scan
          (f64.add (local.get $bearing) (f64.mul (f64.convert_i32_s (i32.sub (i32.rem_s (local.get $tick) (i32.const 5)) (i32.const 2))) (f64.const 8)))
          (f64.const 30) (local.get $elevation)))
      (else (if (i32.eq (call $cy_tracker_cue (global.get $CUE)) (global.get $CY_OK))
      (then
        ;; Head the way the cue points, sweeping the scan across its error.
        (local.set $bearing (call $bearing_to (global.get $ME) (i32.add (global.get $CUE) (global.get $CY_CUE_POSITION_X))))
        (local.set $elevation (select (call $elevation_to (global.get $ME) (i32.add (global.get $CUE) (global.get $CY_CUE_POSITION_X)))
          (f64.const 0) (global.get $free)))
        (local.set $error (f64.min (call $field (global.get $CUE) (global.get $CY_CUE_BEARING_ERROR)) (f64.const 30)))
        (call $steer (f64.const 0.6) (local.get $bearing) (local.get $elevation) (f64.const 45) (local.get $heading) (local.get $pitch))
        (call $scan
          (f64.add (local.get $bearing)
            (f64.mul (f64.div (f64.convert_i32_s (i32.sub (i32.rem_s (local.get $tick) (i32.const 5)) (i32.const 2))) (f64.const 2)) (local.get $error)))
          (f64.const 30) (local.get $elevation)))
      (else
        (call $steer (f64.const 0.5) (local.get $heading) (f64.const 0) (f64.const 45) (local.get $heading) (local.get $pitch))
        (drop (call $cy_drive_turn (global.get $search_turn)))
        ;; Sweeps the circle in half a second, flying free at three heights in turn.
        (drop (call $cy_scanner_last (global.get $SCAN)))
        (call $scan (f64.add (call $field (global.get $SCAN) (global.get $CY_SCAN_HEADING)) (f64.const 36)) (f64.const 40)
          (select (f64.mul (f64.convert_i32_s (i32.sub (i32.rem_s (i32.div_s (local.get $tick) (i32.const 10)) (i32.const 3)) (i32.const 1))) (f64.const 35))
            (f64.const 0) (global.get $free)))))))))

    ;; Low battery: drive gently so the shots can still be paid for.
    (if (f64.lt (call $number (call $cy_battery_charge (global.get $NUMBER)))
          (f64.div (call $number (call $cy_battery_capacity (global.get $NUMBER))) (f64.const 4)))
      (then (drop (call $cy_drive_throttle (f64.mul (call $number (call $cy_drive_get_throttle (global.get $NUMBER))) (f64.const 0.5))))))

    ;; The storm drifts across the arena and hurts anything inside it. Near
    ;; its edge, step out across its path: at right angles to its drift, on
    ;; the side this robot is already on, so it passes by.
    (if (i32.eq (call $cy_nav_storm (global.get $STORM)) (global.get $CY_OK))
      (then (if (i32.and (i32.eq (call $cy_nav_storm_margin (global.get $ME) (global.get $NUMBER)) (global.get $CY_OK))
            (f64.gt (f64.load (global.get $NUMBER)) (f64.const -60)))
        (then
          (local.set $away (call $bearing_to (i32.add (global.get $STORM) (global.get $CY_STORM_CENTER_X)) (global.get $ME)))
          (local.set $drift (call $bearing_to (global.get $STILL) (i32.add (global.get $STORM) (global.get $CY_STORM_VELOCITY_X))))
          (call $steer (f64.const 1)
            (f64.add (local.get $drift) (select (f64.const -90) (f64.const 90) (f64.lt (call $angle_diff (local.get $away) (local.get $drift)) (f64.const 0))))
            (f64.const 0) (f64.const 30) (local.get $heading) (local.get $pitch))))))

    ;; Sudden death: head back inside the safe zone.
    (if (i32.eq (call $cy_nav_zone (global.get $ZONE)) (global.get $CY_OK))
      (then (if (i32.and (i32.eq (call $cy_nav_zone_margin (global.get $ME) (global.get $NUMBER)) (global.get $CY_OK))
            (f64.lt (f64.load (global.get $NUMBER)) (f64.const 60)))
        (then
          (local.set $climb (select
            (call $elevation_to (global.get $ME) (i32.add (global.get $ZONE) (global.get $CY_ZONE_CENTER_X)))
            (f64.const 0)
            (i32.eq (i32.load (i32.add (global.get $ZONE) (global.get $CY_ZONE_SHAPE))) (global.get $CY_SHAPE_SPHERE))))
          (call $steer (f64.const 0.8)
            (call $bearing_to (global.get $ME) (i32.add (global.get $ZONE) (global.get $CY_ZONE_CENTER_X)))
            (local.get $climb) (f64.const 30) (local.get $heading) (local.get $pitch))))))
    (i32.const 0))
)
