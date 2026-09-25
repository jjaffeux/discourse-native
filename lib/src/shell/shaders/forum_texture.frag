#include <flutter/runtime_effect.glsl>

// The mockup's simplex-noise 2D grain and 4D topographic renderer, evaluated
// on the GPU. See simplex-noise.LICENSE for the original algorithm's license.
uniform vec2 uSize;
uniform float uTime;
uniform float uIntensity;
uniform float uLava;
uniform vec3 uAccent;
uniform sampler2D uPermutation;
out vec4 fragColor;

float perm(float x) {
  return floor(texture(uPermutation, vec2((mod(x, 256.0) + 0.5) / 256.0, 0.5)).r * 255.0 + 0.5);
}

float corner2(vec2 cell, vec2 p) {
  float h = mod(perm(cell.x + perm(cell.y)), 12.0);
  vec2 g;
  if (h < 4.0) {
    g = vec2(mod(h, 2.0) == 0.0 ? 1.0 : -1.0, h < 2.0 ? 1.0 : -1.0);
  } else if (h < 8.0) {
    g = vec2(mod(h, 2.0) == 0.0 ? 1.0 : -1.0, 0.0);
  } else {
    g = vec2(0.0, mod(h, 2.0) == 0.0 ? 1.0 : -1.0);
  }
  float t = max(0.5 - dot(p, p), 0.0);
  return t * t * t * t * dot(g, p);
}

float noise2(vec2 p) {
  const float F = 0.3660254037844386;
  const float G = 0.21132486540518713;
  vec2 cell = floor(p + (p.x + p.y) * F);
  vec2 a = p - cell + (cell.x + cell.y) * G;
  vec2 rank = a.x > a.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
  return 70.0 * (corner2(cell, a) + corner2(cell + rank, a - rank + G)
      + corner2(cell + 1.0, a - 1.0 + 2.0 * G));
}

float corner4(vec4 cell, vec4 p) {
  float h = mod(perm(cell.x + perm(cell.y + perm(cell.z + perm(cell.w)))), 32.0);
  float bits = mod(h, 8.0);
  vec3 signs = vec3(bits < 4.0 ? 1.0 : -1.0,
      mod(bits, 4.0) < 2.0 ? 1.0 : -1.0, mod(bits, 2.0) == 0.0 ? 1.0 : -1.0);
  vec4 g;
  if (h < 8.0) g = vec4(0.0, signs);
  else if (h < 16.0) g = vec4(signs.x, 0.0, signs.yz);
  else if (h < 24.0) g = vec4(signs.xy, 0.0, signs.z);
  else g = vec4(signs, 0.0);
  float t = max(0.6 - dot(p, p), 0.0);
  return t * t * t * t * dot(g, p);
}

float noise4(vec4 p) {
  const float F = 0.30901699437494745;
  const float G = 0.1381966011250105;
  vec4 cell = floor(p + dot(p, vec4(F)));
  vec4 a = p - cell + dot(cell, vec4(G));
  vec4 rank = vec4(0.0);
  if (a.x > a.y) rank.x++; else rank.y++;
  if (a.x > a.z) rank.x++; else rank.z++;
  if (a.x > a.w) rank.x++; else rank.w++;
  if (a.y > a.z) rank.y++; else rank.z++;
  if (a.y > a.w) rank.y++; else rank.w++;
  if (a.z > a.w) rank.z++; else rank.w++;
  vec4 b = step(vec4(3.0), rank);
  vec4 c = step(vec4(2.0), rank);
  vec4 d = step(vec4(1.0), rank);
  return 27.0 * (corner4(cell, a)
      + corner4(cell + b, a - b + G)
      + corner4(cell + c, a - c + 2.0 * G)
      + corner4(cell + d, a - d + 3.0 * G)
      + corner4(cell + 1.0, a - 1.0 + 4.0 * G));
}

void main() {
  // CSS canvas pixels are logical pixels, independent of the device ratio.
  vec2 pixel = floor(FlutterFragCoord().xy);
  if (uLava > 0.5) {
    float n = (noise4(vec4(pixel / 600.0, 0.0, uTime * 0.018)) + 1.0) / 2.0;
    float distance = abs(n - floor(n * 4.0) / 4.0);
    float alpha = (0.18 + max(0.0, 1.0 - distance / 0.1) * 0.4) * uIntensity;
    fragColor = vec4(uAccent * alpha, alpha);
  } else {
    float scale = 0.3 * min(uSize.x, uSize.y) / 1080.0;
    float n = noise2(pixel / max(scale, 0.0001));
    // Keep the full Paper slider within the former 25% range.
    float alpha = min(abs(n) * uIntensity * 0.105, 0.105);
    fragColor = vec4(vec3(n > 0.0 ? alpha : 0.0), alpha);
  }
}
