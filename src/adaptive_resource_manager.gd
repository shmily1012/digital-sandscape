class_name AdaptiveResourceManager
extends RefCounted
# These are requested targets with scheduling policies, not utilization limits.
const FIXED_DT:=1./30.
const NAMES=["Eco","Focus","Balanced","Beautiful","Showcase"]
const TARGETS=[1,3,5,10,20]
const PHYSICS_HZ=[5.,10.,30.,45.,60.]
const DISPLAY_FPS=[10,15,60,60,60]
const COLOR_HZ=[5.,10.,30.,45.,60.]
var preset:=2
var accumulator:=0.
var target_hz:=30.
var frame_ema:=1./60.
var adjust_elapsed:=0.
var render_fps:=60
var recovery_elapsed:=0.
var visual_accumulator:=0.
func select_preset(index:int)->bool:
 if index<0 or index>=NAMES.size():return false
 preset=index;target_hz=PHYSICS_HZ[index];render_fps=DISPLAY_FPS[index]
 frame_ema=1./render_fps;adjust_elapsed=0.;recovery_elapsed=0.
 # Keep fractional physics debt; changing policy never changes the physical state.
 accumulator=minf(accumulator,1.);visual_accumulator=0.
 return true
func schedule(delta:float,focused:bool,paused:bool)->int:
 if paused:accumulator=0.;return 0
 var bounded:=clampf(delta,0.,.1)
 var base_fps:int=DISPLAY_FPS[preset]
 var floor_fps:=maxi(10,base_fps/2)
 if focused:
  frame_ema=lerpf(frame_ema,bounded,.04)
  if render_fps<base_fps and frame_ema<1.1/render_fps:
   recovery_elapsed+=bounded
   if recovery_elapsed>=10.:
    render_fps=base_fps;recovery_elapsed=0.;frame_ema=1./base_fps
  else:recovery_elapsed=0.
  adjust_elapsed+=bounded
  if adjust_elapsed>=2.:
   adjust_elapsed=0.
   if frame_ema>1.65/render_fps:
    if render_fps>floor_fps:render_fps=floor_fps
    else:target_hz=maxf(PHYSICS_HZ[preset]*.5,target_hz-3.)
   elif frame_ema<1.32/base_fps:target_hz=minf(PHYSICS_HZ[preset],target_hz+1.)
 accumulator=minf(accumulator+bounded*physics_rate(focused),2.)
 var ticks:=mini(int(accumulator),2);accumulator-=ticks;return ticks
func physics_rate(focused:bool)->float:return target_hz if focused else minf(5.,target_hz)
func fps_limit(focused:bool)->int:return render_fps if focused else mini(10,render_fps)
func render_due(delta:float,focused:bool)->bool:
 var rate:float=minf(COLOR_HZ[preset],fps_limit(focused))
 visual_accumulator=minf(visual_accumulator+clampf(delta,0.,.1)*rate,2.)
 if visual_accumulator>=1.-1e-8:visual_accumulator=maxf(0.,visual_accumulator-1.);return true
 return false
