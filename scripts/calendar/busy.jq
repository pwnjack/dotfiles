# Day-of-month numbers in $month that any event covers. Date-only arithmetic
# in UTC days is safe: no time of day is involved. A timed event ending at
# 00:00 does not touch its end day.
def day: strptime("%Y-%m-%d") | mktime;
def lastday($e):
    if $e.allDay then ($e.end | day)
    elif ($e.end[11:16] == "00:00") then (($e.end[0:10] | day) - 86400)
    else ($e.end[0:10] | day) end;
[ .[] | . as $e
  | range(($e.start[0:10] | day); lastday($e) + 1; 86400)
  | strftime("%Y-%m-%d") | select(startswith($month)) | .[8:10] | tonumber ]
| unique | {busy: .}
