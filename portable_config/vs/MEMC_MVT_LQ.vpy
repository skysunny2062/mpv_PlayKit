import vapoursynth as vs
from vapoursynth import core
import k7sfunc as k7f
clip = video_in

H_Pre = 2160
Recal = True
Block = True
Lk_Fmt = False

## 整数，预降低处理源高度（填你的显示器高度）
## <True|False> 是否使用二次分析
## <True|False> 是否使用Block模式
## <True|False> 锁定像素格式为yuv420p8

ret = k7f.FPS_CTRL(clip, fps_in=container_fps, fps_ret=True)
clip = k7f.FMT_CTRL(clip, h_max=H_Pre, fmt_pix=1 if Lk_Fmt else 0)
clip = k7f.MVT_LQ(clip, fps_in=container_fps, fps_out=display_fps, recal=Recal, block=Block)
clip.set_output()