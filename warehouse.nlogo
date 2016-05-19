extensions [table]
globals [
  folklift-road-xcors ; list of the x-coordinates where the folklift road travels N<->S
  folklift-road-ycors ; list of the y-coordinates where the folklift road travels E<->W
  total-wait-time ; total wait time of all trucks that have been served
  port
  comboTable
  orders-combo-list
  max-combo-name
  max-combo-score
]

breed [containers container]
containers-own [
  dis-to-port
  birth-time
  waiting
  plan-to-load?
  picking-distance
]

breed [folklifts folklift]
folklifts-own [
  current-task   ; i.e. [ (container 18) (container 1) (container 23) ]
  joblist
  path
  working?
  job-done?
  time-counter
  total-moving-distance
]

patches-own [f g h parent-patch]     ; a-star function variables


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;                    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;         GO         ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;                    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

to go
  if count containers with [label != ""] > 40
  [
    print "WARNING: TOO MANY CONTAINERS TO GO!"
    stop
  ]
  order-emerging
  order-waiting

  ask folklifts
  [
    if patch-here = port
    [ ifelse job-done? [ picking-new-plan ] [ unload ] ]

    if working?  [ move-load ]
  ]

  tick
end


; folklifts procudure
to picking-new-plan
;  (foreach table:keys comboTable
;  [ let ks ?
;    foreach ks [ if container ? = nobody [table:remove comboTable ks]]
;  ])

  if table:length comboTable > 0
  [
    set current-task first max-combo
    (foreach table:keys comboTable
    [ let ks ?
      foreach ks [ if member? ? current-task [table:remove comboTable ks]]
    ])

    set joblist (turtle-set map [container ?] current-task)
    let f1 min-one-of joblist [dis-to-port]
    set joblist sort-on [distance f1] (turtle-set joblist)
    foreach joblist [ask ? [set plan-to-load? true]]
    set path find-container-path first joblist
    set job-done? false
    set working? true
  ]
end


to move-load
  if working? and not job-done?
  [
    ifelse not empty? path
    [
      move-to first path
      set path but-first path
      set total-moving-distance total-moving-distance + 1
    ]
    [
      if not empty? joblist
      [ load ]
    ]
  ]
end

to load
  set time-counter time-counter + 1
  if time-counter = load-time [
    set time-counter 0
    let moved-box first joblist
    set joblist but-first joblist
    ifelse not empty? joblist
    [ set path find-container-path first joblist ]
    [ set path find-path patch-here port ]
    ask moved-box [die]
  ]
end

to unload
  set time-counter time-counter + 1
  if time-counter = unload-time [
    set time-counter 0
    set path find-path patch-here port
    set job-done? true
    set working? false
  ]
end




to-report max-combo
  let combolist table:to-list comboTable  ;[[[20 21 25] 82] [[20 25 48] 64] [[20 25 123] 76] [[20 21 48 123] 81]]
  let scoremax max map [last ?] combolist
  report first filter [last ? = scoremax] combolist
end


to update-combo-score [key tset]
  let score-reduce combo-score tset
  table:put comboTable key score-reduce
  if score-reduce > max-combo-score
  [
    set max-combo-name key
    set max-combo-score score-reduce
    print (word "update max combo with name: " key " and value: " score-reduce)
  ]
end

; report the total cutting-distance of the containers asking
; use approximation by calculate the x and y side length of the total area which covers the containers
to-report combo-score [nameset]
  let xrange (max [xcor] of nameset) - (min [xcor] of nameset)
  let yrange (max [ycor] of nameset ) - (min [ycor] of nameset)
  let dislist map [[dis-to-port] of ?] sort-on [dis-to-port] nameset
  if length dislist = 4 [
    report round (first dislist + item 1 dislist + (item 2 dislist) * 2 + (last dislist) * 2 - (xrange * yrange) ^ 0.5 )]
  if length dislist = 3 [
    report round (first dislist + item 1 dislist + (item 2 dislist) * 2 - (xrange * yrange) ^ 0.5 )]
  if length dislist = 2 [
    report round (first dislist + item 1 dislist - (xrange * yrange) ^ 0.5) ]
  if length nameset < 2 or length nameset > 4 [user-message "error input list length"]
end


; combo-key function - input [(container 1)(container 2)] output "(container 1)(container2)"
to-report combo-key [nameset]
  let namelist sort nameset
  if length namelist = 4 [report (list ([who] of first namelist) ([who] of item 1 namelist) ([who] of item 2 namelist) ([who] of last namelist))]
  if length namelist = 3 [report (list ([who] of first namelist) ([who] of item 1 namelist) ([who] of item 2 namelist) )]
  if length namelist = 2 [report (list ([who] of first namelist) ([who] of item 1 namelist) )]
  if length namelist < 2 or length namelist > 4 [user-message "error input list length"]
end









to order-emerging
  if random 100 < order-arrival-rate [
    ask one-of containers with [label = ""]
    [
      scale-waiting-color
      set waiting 1
      set label waiting
      set label-color black
      let l1 sort other containers with [size = 0.25 and waiting > 0 and not plan-to-load? ]
      let l2 sort other containers with [size = 0.5 and waiting > 0 and not plan-to-load? ]

      if size = 0.5 and not empty? l2
      [
        (foreach l2
        [
          if [size] of ? + size = 1
          [
            let key combo-key (turtle-set ? self)
            if not table:has-key? comboTable key [ update-combo-score key (turtle-set ? self) ]
          ]
        ])
      ]

      if size = 0.25 and not empty? l2 and not empty? l1
      [
        (foreach l1
        [
          let q1 ?
          (foreach l2
          [
            if [size] of q1 + [size] of ? + size = 1
            [
              let key combo-key (turtle-set q1 ? self)
              if not table:has-key? comboTable key [ update-combo-score key (turtle-set q1 ? self) ]
            ]
          ])
        ])
      ]

      while [size = 0.25 and length l1 >= 3]    ; l1 = [1 2 3 4 5]
      [
        let ll first l1
        set l1 but-first l1
        set l2 l1                             ; l1 = l2 = [2 3 4 5]
        while [length l2 >= 2]
        [
          let lll first l2
          set l2 but-first l2                 ; l3 = l2 = [3 4 5]
          let l3 l2
          (foreach l3
          [
            if ([size] of ? + [size] of lll + [size] of ll + size = 1)
            [
              let key combo-key (turtle-set ll lll ? self)
              if not table:has-key? comboTable key [ update-combo-score key (turtle-set ll lll ? self) ]
            ]
          ])
        ]
      ]
    ]
  ]

  if any? patches with [pcolor = white and not any? turtles-here]
  [
    create-containers 1 [ container-init ]
  ]
end








to order-waiting
  ask containers with [label != ""]
  [
    set waiting waiting + 1
    set label waiting
    scale-waiting-color
  ]
end





to scale-waiting-color
  if label != "" [set color scale-color 15 0 waiting order-wait-time ] ; scaled-red
end






to-report right-patch-of [thisturtle]
  report patch ([xcor] of thisturtle + 1) [ycor] of thisturtle
end



to-report path-to-port [thispatch]
  report find-path thispatch port
end


to-report find-container-path [ destination-container ]
  report find-path patch-here right-patch-of destination-container
end

to-report find-path [ source-patch destination-patch]
  let search-done? false
  let search-path [ ]
  let current-patch 0
  let open [ ]
  let closed [ ]
  ; add source patch in the open list
  set open lput source-patch open
  ; loop until we reach the destination or the open list becomes empty
  while [ search-done? != true ]
  [
    ifelse length open != 0
    [
      set open sort-by [ [f] of ?1 < [f] of ?2 ] open
      set current-patch first open
      set open but-first open
      set closed lput current-patch closed
      ask current-patch
      [
        ifelse any? neighbors4 with [ (pxcor = [pxcor] of destination-patch) and (pycor = [pycor] of destination-patch)]
        [ set search-done? true ]
        [
          ask neighbors4 with [ pcolor != white and (not member? self closed) and (self != parent-patch) ]
          [
            if not member? self open and self != source-patch and self != destination-patch
            [
              set open lput self open
              set parent-patch current-patch
              set g [g] of parent-patch  + 1
              set h distance destination-patch
              set f (g + h)
            ]
          ]
        ]
      ]
    ]
    [ report [ ] ]
  ]
  set search-path lput current-patch search-path
  let temp first search-path
  while [ temp != source-patch ]
  [
    set search-path lput [parent-patch] of temp search-path
    set temp [parent-patch] of temp
  ]
  set search-path fput destination-patch search-path
  report reverse search-path
end





;================================================================================================
;================================================================================================
;setup

to setup
  clear-all
  set max-combo-score 0
  set max-combo-name 0
  set comboTable table:make
  set orders-combo-list []

  set folklift-road-xcors (list 0 2 4 6 8 10 12 14 16)
  set folklift-road-ycors (list 5 15)
  ask patches [set pcolor white]

  ;the road in which the folklift travels is grey
  ask patches with [member? pxcor folklift-road-xcors][set pcolor grey]
  ask patches with [member? pycor folklift-road-ycors][set pcolor grey]
  set port patch 0 5
  ask port [set pcolor 107]

  create-containers count patches with [pcolor = white] [ container-init ]

  create-folklifts num-folklifts [
    set shape "arrow"
    set size 0.8
    set heading 0
    set color orange
    set working? false
    set job-done? true
    move-to patch 0 5
  ]
  reset-ticks
end

to container-init
    set shape "square"
    set color blue
    set plan-to-load? false
    set size set-size-based-on-list
    move-to one-of patches with [pcolor = white and not any? turtles-here]
    set dis-to-port length find-path patch-here port
    ;set picking-distance length (path (patch (xcor + 1) ycor) port)
end

to-report set-size-based-on-list
  let random-size-list map [random ?] read-from-string percentage-of-boxes-1-2-4
  report item (position (max random-size-list) random-size-list) [0.25 0.5 1]
end
@#$#@#$#@
GRAPHICS-WINDOW
222
13
561
432
-1
-1
19.4
1
10
1
1
1
0
0
0
1
0
16
0
19
1
1
1
ticks
30.0

BUTTON
138
14
201
47
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
74
14
137
47
NIL
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
1
92
218
125
order-arrival-rate
order-arrival-rate
0
10
10
1
1
orders/100ticks
HORIZONTAL

PLOT
566
15
763
165
total-waiting-time
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -16777216 true "" "plot sum [waiting] of containers"

INPUTBOX
16
358
183
418
percentage-of-boxes-1-2-4
[60 30 10]
1
0
String

SLIDER
2
58
174
91
num-folklifts
num-folklifts
0
10
2
1
1
NIL
HORIZONTAL

SLIDER
2
133
218
166
order-wait-time
order-wait-time
0
100
100
1
1
NIL
HORIZONTAL

BUTTON
6
14
72
47
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

MONITOR
566
190
902
235
NIL
max-combo-name
17
1
11

MONITOR
567
294
902
339
NIL
sort [current-task] of first sort folklifts
17
1
11

INPUTBOX
79
242
157
302
unload-time
5
1
0
Number

INPUTBOX
7
243
76
303
load-time
5
1
0
Number

MONITOR
567
347
902
392
path of 1st crane
[path] of first sort folklifts
17
1
11

MONITOR
566
245
902
290
NIL
[joblist] of first sort folklifts
17
1
11

PLOT
769
15
969
165
total-moving-distance
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"lift_0" 1.0 0 -955883 true "" "plot [total-moving-distance] of first sort folklifts"
"lift_1" 1.0 0 -13345367 true "" "if count folklifts > 1[plot [total-moving-distance] of item 1 sort folklifts]"

@#$#@#$#@
# Container Port Simulation

## WHAT IS IT?
A simulation of a container warehoust. Model the movement of the folklifts using various utility functions to determine what is the best strategy for the warehouse.

## CREDITS
inspired by Jose M Vidal and Nathan Huynh http://jmvidal.cse.sc.edu/netlogomas/port/index.html

Jihe Gao jihe.gao@jiejiaotech.com
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
0
Rectangle -7500403 true true 151 225 180 285
Rectangle -7500403 true true 47 225 75 285
Rectangle -7500403 true true 15 75 210 225
Circle -7500403 true true 135 75 150
Circle -16777216 true false 165 76 116

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270

@#$#@#$#@
NetLogo 5.3.1
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180

@#$#@#$#@
0
@#$#@#$#@
