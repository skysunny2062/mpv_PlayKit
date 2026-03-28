# Zack Ver.260307

import vapoursynth as vs
from vapoursynth import core
import k7sfunc as k7f
core.num_threads = k7f.vs_t_dft
clip = video_in

H_Pre = 2160
Fps_Num = 60
Fps_Den = 24
Gpu = 0
Gpu_T = 2
Lk_Fmt = False

# H_Pre整数，预降低处理源高度（填你的显示器高度）
# Fps_Num/Fps_Den 的值即帧率倍数
# Gpu使用的显卡序号 0=第一張顯卡
# Gpu_T显卡线程数<1|2|3>
# Lk_Fmt是否锁定像素格式为yuv420p8 False=不鎖定格式，保留10bit

ret = k7f.FPS_CTRL(clip, fps_in=container_fps, fps_ret=True)
clip = k7f.FMT_CTRL(clip, h_max=H_Pre, fmt_pix=1 if Lk_Fmt else 0)
clip = k7f.DRBA_DML(clip, model=1, turbo=2, fps_in=container_fps, fps_num=Fps_Num, fps_den=Fps_Den, sc_mode=0, gpu=Gpu, gpu_t=Gpu_T)
clip.set_output()