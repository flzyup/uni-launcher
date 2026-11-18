#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 u_size;
uniform float u_radius;
uniform float u_depth;
uniform float u_press;
uniform vec2 u_touch;
uniform sampler2D u_texture;
out vec4 fragColor;

vec4 sampleAt(vec2 p) {
  vec2 uv = clamp(p / u_size, vec2(0.001), vec2(0.999));
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return texture(u_texture, uv);
}
void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 halfSize = u_size * 0.5;
  float radius = min(u_radius, min(halfSize.x, halfSize.y));
  vec2 q = abs(p - halfSize) - (halfSize - radius);
  float distance = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
  vec2 gradient = max(q, vec2(0.0));
  vec2 normal = length(gradient) > 0.001 ? normalize(gradient) : (q.x > q.y ? vec2(1,0) : vec2(0,1));
  normal *= sign(p - halfSize);
  float lens = 1.0 - smoothstep(0.0, max(10.0, min(radius, 28.0)), -distance);
  vec2 displacement = normal * lens * lens * u_depth;
  vec2 touchPull = (u_touch * u_size - p) * 0.018 * u_press;
  vec2 refracted = p - displacement + touchPull;
  vec4 base = sampleAt(refracted);
  // Dispersion is confined to the curved edge, not the text/content layer.
  float dispersion = lens * 0.65;
  base.r = sampleAt(refracted - normal * dispersion).r;
  base.b = sampleAt(refracted + normal * dispersion).b;
  fragColor = base;
}
