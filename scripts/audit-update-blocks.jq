# Input: output of `nomad job inspect -json <job>`. Emits one TSV row per task group.
(.Job // .) as $j
| select(($j.Type // "service") == "service")
| $j.TaskGroups[]
| (.Update // $j.Update // {}) as $u
| ( [ (if ($u | length) == 0 then "NO_UPDATE_BLOCK" else empty end),
      (if ($u.AutoRevert // false) != true then "NO_AUTO_REVERT" else empty end),
      (if ($u.Canary // 0) == 0 then "NO_CANARY" else empty end),
      (if (.Count // 1) < 2 then "SINGLE_INSTANCE" else empty end),
      (if ($u.HealthCheck // "checks") != "checks" then "HEALTH_CHECK=" + $u.HealthCheck else empty end),
      (if ($u | length) > 0 and ($u.ProgressDeadline // 0) == 0 then "NO_PROGRESS_DEADLINE" else empty end)
    ] | if length == 0 then "ok" else join(",") end ) as $flags
| [ $j.ID, .Name, (.Count // 1), ($u.Canary // 0), ($u.AutoRevert // false), ($u.AutoPromote // false),
    ($u.HealthCheck // "n/a"), (($u.MinHealthyTime // 0) / 1e9), (($u.HealthyDeadline // 0) / 1e9),
    (($u.ProgressDeadline // 0) / 1e9), $flags ]
| @tsv
