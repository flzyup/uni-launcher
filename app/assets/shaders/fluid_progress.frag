#version 460 core
#include <flutter/runtime_effect.glsl>

// 蓝紫流体进度 —— 原版 WebGL shader 的直译版。
// 与 theme-styles/nocturne/fluid-dock-live.html 的 canvas 复刻同源：
// 唯二的新增 uniform 是 u_fitAmp / u_bladeK，用来把 3.95:1 的原版定标
// 搬到 11:1 的底部胶囊上（等价于 HTML 版里的 fa / BLADE_K）。

uniform vec2 u_resolution;
uniform float u_time;
uniform float u_progress;
uniform float u_seed;
uniform float u_velocity;
uniform float u_impulse;
uniform float u_echo1;
uniform float u_echo2;
uniform float u_echoAct;
uniform float u_fitAmp;
uniform float u_bladeK;
uniform vec3 u_darkRight;
uniform vec3 u_darkLeft;
uniform vec3 u_color0;
uniform vec3 u_color1;
uniform vec3 u_color2;
uniform vec3 u_color3;
uniform vec3 u_color4;

out vec4 fragColor;

float hash21(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + vec2(45.32 + u_seed));
  return fract(p.x * p.y);
}

float noise2(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = hash21(i);
  float b = hash21(i + vec2(1.0, 0.0));
  float c = hash21(i + vec2(0.0, 1.0));
  float d = hash21(i + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
  float v = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    v += a * noise2(p);
    p = mat2(0.80, 0.60, -0.60, 0.80) * p * 2.01 + vec2(7.1, 13.7);
    a *= 0.5;
  }
  return v;
}

float sat(float x) { return clamp(x, 0.0, 1.0); }

// 高斯式包络，写成 q*q 而不是 pow(q, 2.0)：pow 对负数未定义，q 会变号。
float bump(float q) { return exp(-q * q); }

void main() {
  // Flutter 的 y 轴朝下，原版的 uv.y 朝上，这里翻一次。
  vec2 uv = vec2(FlutterFragCoord().x / u_resolution.x,
                 1.0 - FlutterFragCoord().y / u_resolution.y);
  float aspect = u_resolution.x / max(u_resolution.y, 1.0);
  vec2 p = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);
  float t = u_time;
  float y = uv.y;
  float vel = clamp(u_velocity * 12.0, -1.0, 1.0);
  float impulse = clamp(u_impulse, 0.0, 1.0);

  float n = fbm(vec2(y * 4.2 + u_seed, t * 0.16));
  float wave = sin(y * 8.2 + t * 0.72 + u_seed) * 0.010
             + sin(y * 16.4 - t * 0.56 + u_seed * 1.9) * 0.006
             + sin(y * 33.0 + t * 1.06 + vel * 2.0) * 0.0028;

  float dev = vel * 0.010
    + bump((y - 0.50 - vel * 0.08) / 0.19) * vel * 0.030
    + bump((y - 0.50 + vel * 0.12) / 0.30) * (-vel) * 0.018
    + wave
    + (n - 0.5) * 0.036
    + bump((y - 0.69) / 0.088) * sin(t * 0.72 + 1.15) * 0.015
    - bump((y - 0.33) / 0.078) * sin(t * 0.64 + 4.3) * 0.013;

  // u_fitAmp：画布比原版扁多少倍，振幅就压多少倍，否则 11:1 的带子上
  // 同一个波横向摆得比纵向还远，斜率陡 2.8 倍，出来全是折角。
  float edge = u_progress + dev * u_fitAmp;
  float d = uv.x - edge;
  float fillMask = 1.0 - smoothstep(-0.004, 0.005, d);
  float behind = max(edge - uv.x, 0.0);

  vec2 flowP = p * vec2(1.42, 1.86);
  vec2 warp = vec2(
    fbm(flowP * 0.72 + vec2(t * 0.055, -t * 0.036) + vec2(u_seed)),
    fbm(flowP * 0.83 + vec2(-t * 0.042, t * 0.047) + vec2(6.2 + u_seed)));
  vec2 warped = flowP + (warp - 0.5) * (1.10 + impulse * 0.22);
  float smokeA = fbm(warped * 1.16 + vec2(-t * 0.070, t * 0.022));
  float smokeB = fbm(warped * 2.16 + vec2(t * 0.088, -t * 0.054));
  float smoke = smoothstep(0.24, 0.84, smokeA * 0.74 + smokeB * 0.36);

  float nearTrail = exp(-behind * (11.8 - impulse * 2.2));
  float wideTrail = exp(-behind * (4.5 - impulse * 0.9));
  float verticalFade = smoothstep(0.0, 0.12, y) * smoothstep(0.0, 0.12, 1.0 - y);
  float trail = fillMask * verticalFade * (smoke * nearTrail + smokeA * wideTrail * 0.44);

  float echoD1 = uv.x - (u_echo1 + wave * 0.72 * u_fitAmp + (n - 0.5) * 0.018);
  float echoD2 = uv.x - (u_echo2 + wave * 0.48 * u_fitAmp + (n - 0.5) * 0.010);
  float echoGlow1 = exp(-abs(echoD1) * 92.0) * u_echoAct * verticalFade;
  float echoGlow2 = exp(-abs(echoD2) * 58.0) * u_echoAct * verticalFade;

  vec3 color = mix(u_darkRight, u_darkLeft, fillMask * 0.76);
  color += u_color2 * echoGlow2 * 0.22 * 0.42 + u_color3 * echoGlow1 * 0.38 * 0.42;

  float chroma = sat(smoke * 1.16 + nearTrail * 0.35);
  vec3 fluid = mix(u_color0, u_color1, smoothstep(0.16, 0.62, chroma));
  fluid = mix(fluid, u_color2, smoothstep(0.42, 0.90, nearTrail * (0.62 + smoke * 0.74)));
  color = mix(color, fluid, sat(trail * 0.96));

  float aura = exp(-behind * 17.6) * fillMask;
  color += u_color1 * aura * (0.14 + smoke * 0.20);
  color += u_color2 * aura * smoke * smoke * (0.16 + impulse * 0.08);

  // 刀口三层，k 乘 u_bladeK 收细（HTML 版 BLADE_K=1.60）
  float k = u_bladeK;
  float core = exp(-abs(d) * 395.0 * k);
  float inner = exp(-abs(d) * 114.0 * k);
  float outer = exp(-abs(d) * 28.0 * k);
  color += u_color2 * outer * 0.18;
  color += u_color3 * inner * (0.62 + impulse * 0.15);
  color += u_color4 * core * (1.08 + impulse * 0.12);

  float rightMask = smoothstep(0.002, 0.040, d);
  color = mix(color, u_darkRight + u_color3 * outer * 0.03, rightMask * 0.92);

  // 没走到的一侧不留底色：alpha 收到 0，露出胶囊自己的深色背板。
  // 不这么做的话整条右边会浮出一块 #0F1A18 的暗绿，看着像进度条自带绿色背景。
  float keep = 1.0 - smoothstep(0.012, 0.075, d);

  float vignette = 1.0 - smoothstep(0.20, 0.88, length((uv - 0.5) * vec2(0.60, 1.0)));
  color *= 0.90 + vignette * 0.10;
  color = color / (1.0 + color * 0.14);
  color = pow(max(color, vec3(0.0)), vec3(0.94));

  fragColor = vec4(color * keep, keep);
}
