;; Sweep for contacts, then narrow the beam to get a firing bearing.
;; Clunkyard guide: https://clunkyard.com/sdk/wasm
(module
  ;; @include clunkyard

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
  (global $CUES i32 (i32.const 432)) ;; room for 8 contacts

  ;; Enough to turn against the brake in the force rulesets.
  (global $search_turn f64 (f64.const 0.33))
  ;; How long to look again where a robot was last seen.
  (global $memory_ticks i32 (i32.const 60))
  ;; How long a dodge lasts: half a second.
  (global $dodge_ticks i32 (i32.const 10))
  ;; Degrees: the search beam, and the beam of a look.
  (global $search_arc f64 (f64.const 40))
  ;; Degrees: the narrowest the beam holds.
  (global $min_arc f64 (f64.const 6))
  ;; Ticks between looks around the target, for a nearer robot.
  (global $look_every i32 (i32.const 40))
  ;; Units across the line of sight a shot may be off by.
  (global $precise f64 (f64.const 12))
  (global $dodge_until (mut i32) (i32.const 0)) ;; the tick the dodge ends
  (global $dodges (mut i32) (i32.const 0)) ;; how many dodges so far
  (global $free (mut i32) (i32.const 0)) ;; flying free, robots may be above or below
  (global $forces (mut i32) (i32.const 0)) ;; the force rulesets: push the hull, not steer it
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

  ;; The angle, in degrees, of a beam 60 units across at this range: atan by a
  ;; rational fit, cheaper in fuel than a series.
  (func $hold_arc (param $range f64) (result f64)
    (local $x f64) (local $flip i32) (local $angle f64)
    (local.set $x (f64.div (f64.const 30) (local.get $range)))
    (local.set $flip (f64.gt (local.get $x) (f64.const 1)))
    (if (local.get $flip) (then (local.set $x (f64.div (f64.const 1) (local.get $x)))))
    (local.set $angle (f64.div (local.get $x)
      (f64.add (f64.const 1) (f64.mul (f64.const 0.28125) (f64.mul (local.get $x) (local.get $x))))))
    (f64.mul (f64.mul (f64.const 2)
      (select (f64.sub (f64.const 1.5707963) (local.get $angle)) (local.get $angle) (local.get $flip)))
      (f64.const 57.29578)))

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
    (global.set $forces (i32.eq (call $whole (call $cy_match_control (global.get $WHOLE))) (global.get $CY_CONTROL_FORCES)))
    (i32.const 0))

  (func (export "clunkyard_turn") (result i32)
    (local $heading f64) (local $pitch f64) (local $tick i32)
    (local $range f64) (local $bearing f64) (local $elevation f64) (local $power f64)
    (local $error f64) (local $away f64) (local $drift f64) (local $climb f64)
    (local $i i32) (local $side f64) (local $arc f64) (local $sensed f64)
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
        ;; Halve the beam each tick until it is 60 units across at the target:
        ;; narrow enough for a precise bearing, wide enough to keep it in.
        ;; Every 40 ticks widen it for a tick, so a nearer robot can be found.
        (local.set $sensed (call $field (global.get $TARGET) (global.get $CY_CONTACT_BEARING_ERROR)))
        (drop (call $cy_scanner_last (global.get $SCAN)))
        (local.set $arc
          (select (global.get $search_arc)
            (f64.max (f64.max (global.get $min_arc) (call $hold_arc (local.get $range)))
              (f64.min (global.get $search_arc) (f64.div (call $field (global.get $SCAN) (global.get $CY_SCAN_ARC)) (f64.const 2))))
            (i32.eqz (i32.rem_s (local.get $tick) (global.get $look_every)))))
        (call $scan (local.get $bearing) (local.get $arc) (local.get $elevation))
        ;; The heaviest shot that still covers the range in about a second,
        ;; aimed where the target will be, lobbed under gravity; straight at
        ;; it when no shot reaches it. An exact contact: the lead is the
        ;; intercept if the target holds its course. A noisy one is aimed at
        ;; as sensed, never led.
        (f64.store (global.get $NUMBER) (f64.const 1))
        (local.set $power (call $number (call $cy_gun_power_for_flight_time (local.get $range) (f64.const 1) (global.get $NUMBER))))
        (if (f64.eq (local.get $sensed) (f64.const 0))
          (then (if (i32.eq (call $cy_gun_lead (global.get $TARGET) (local.get $power) (global.get $AIM)) (global.get $CY_OK))
            (then
              (local.set $bearing (call $field (global.get $AIM) (global.get $CY_SOLUTION_HEADING)))
              (local.set $elevation (call $field (global.get $AIM) (global.get $CY_SOLUTION_PITCH)))))))
        (drop (call $cy_gun_aim_heading (local.get $bearing)))
        (drop (call $cy_gun_aim_pitch (local.get $elevation)))
        (drop (call $cy_gun_aim_now (global.get $NOW)))
        ;; Fire once the turret is on target, one reading is precise (its
        ;; bearing error across the line of sight under 12 units) and the
        ;; battery covers the shot with 10 to spare.
        (if (i32.and (f64.lt (f64.div (f64.mul (local.get $range) (local.get $sensed)) (f64.const 57.3)) (global.get $precise))
            (i32.and (i32.and
              (f64.lt (f64.abs (call $angle_diff (local.get $bearing) (call $field (global.get $NOW) (global.get $CY_DIRECTION_HEADING)))) (f64.const 3))
              (f64.lt (f64.abs (f64.sub (local.get $elevation) (call $field (global.get $NOW) (global.get $CY_DIRECTION_PITCH)))) (f64.const 3)))
              (i32.eq (call $whole (call $cy_gun_can_fire (local.get $power) (f64.const 10) (global.get $WHOLE))) (i32.const 1))))
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

    ;; A simple dodge: vary it, or predict the shooter. A muzzle cue means a
    ;; robot fired; for half a second swerve off the line of fire, left and
    ;; right in turn. More cues than the array holds ($CY_SHORT) count as
    ;; none heard.
    (if (i32.ge_s (local.get $tick) (global.get $dodge_until))
      (then (if (i32.eq (call $cy_sensors_cues (global.get $CUES) (i32.const 8) (global.get $WHOLE)) (global.get $CY_OK))
        (then
          (block $heard
            (loop $next
              (br_if $heard (i32.ge_u (local.get $i) (i32.load (global.get $WHOLE))))
              (if (i32.eq (i32.load (i32.add (i32.add (global.get $CUES) (i32.mul (local.get $i) (global.get $CY_CONTACT_SIZE)))
                    (global.get $CY_CONTACT_SOURCE))) (global.get $CY_SOURCE_MUZZLE))
                (then
                  (global.set $dodge_until (i32.add (local.get $tick) (global.get $dodge_ticks)))
                  (global.set $dodges (i32.add (global.get $dodges) (i32.const 1)))
                  (br $heard)))
              (local.set $i (i32.add (local.get $i) (i32.const 1)))
              (br $next)))))))
    (if (i32.lt_s (local.get $tick) (global.get $dodge_until))
      (then
        ;; Left on odd dodges: turn is positive left, strafe positive right.
        (local.set $side (select (f64.const 1) (f64.const -1) (i32.and (global.get $dodges) (i32.const 1))))
        (if (global.get $forces)
          (then
            (drop (call $cy_drive_throttle (f64.const 0.5)))
            (drop (call $cy_drive_strafe (f64.neg (local.get $side)))))
          (else
            (drop (call $cy_drive_throttle (f64.const 1)))
            (drop (call $cy_drive_turn (local.get $side)))))))

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
