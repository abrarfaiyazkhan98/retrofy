#version 460 core

// Living artwork glow: a dark base with soft colour fields from the cover
// that drift and breathe slowly, plus a halo around the artwork's frame.
// One pass, no blur and no textures, so it costs about the same as a
// gradient fill.

#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;
// Seconds, wrapped by the caller so precision stays high.
uniform float uTime;
// 0..1: how strongly the fields show over the base.
uniform float uIntensity;
// 3 (balanced) or 5 (high) colour fields.
uniform float uFields;
// Artwork frame in pixels (left, top, width, height); zero width: no halo.
uniform vec4 uHalo;
uniform float uHaloRadius;
// 0..1: pulls the glow back toward the base behind lyrics.
uniform float uCalm;
uniform vec3 uBase;
uniform vec3 uPrimary;
uniform vec3 uSecondary;
uniform vec3 uAccent;

out vec4 fragColor;

float field(vec2 p, vec2 centre, float radius) {
  vec2 d = p - centre;
  return exp(-dot(d, d) / (radius * radius));
}

float roundedBox(vec2 p, vec2 halfSize, float radius) {
  vec2 q = abs(p) - halfSize + radius;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

// Interleaved gradient noise: breaks up 8-bit banding in slow gradients.
float dither(vec2 frag) {
  return fract(52.9829189 * fract(dot(frag, vec2(0.06711056, 0.00583715))));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  float aspect = uSize.x / max(uSize.y, 1.0);
  vec2 p = frag / uSize;
  p.x *= aspect;
  float t = uTime;
  float breathe = 1.0 + 0.07 * sin(t * 0.39);

  vec3 colour = uBase;
  float k = uIntensity;

  // Slow Lissajous drifts with unrelated periods (roughly 60-150 s), so the
  // pattern never visibly repeats.
  vec2 c1 = vec2((0.28 + 0.10 * sin(t * 0.061)) * aspect,
                 0.26 + 0.09 * cos(t * 0.047));
  vec2 c2 = vec2((0.74 + 0.09 * cos(t * 0.053)) * aspect,
                 0.40 + 0.10 * sin(t * 0.041));
  vec2 c3 = vec2((0.46 + 0.12 * sin(t * 0.043 + 1.7)) * aspect,
                 0.80 + 0.07 * cos(t * 0.059));
  colour = mix(colour, uPrimary, field(p, c1, 0.46 * breathe) * 0.80 * k);
  colour = mix(colour, uSecondary, field(p, c2, 0.42 * breathe) * 0.70 * k);
  colour = mix(colour, mix(uPrimary, uSecondary, 0.5),
               field(p, c3, 0.50 * breathe) * 0.55 * k);
  if (uFields > 3.5) {
    vec2 c4 = vec2((0.84 + 0.06 * sin(t * 0.037 + 0.6)) * aspect,
                   0.08 + 0.06 * cos(t * 0.051));
    vec2 c5 = vec2((0.10 + 0.07 * cos(t * 0.049 + 2.3)) * aspect,
                   0.62 + 0.08 * sin(t * 0.033));
    colour = mix(colour, uAccent, field(p, c4, 0.30 * breathe) * 0.28 * k);
    colour = mix(colour, uSecondary, field(p, c5, 0.36 * breathe) * 0.45 * k);
  }

  if (uHalo.z > 0.0) {
    vec2 halfSize = uHalo.zw * 0.5;
    vec2 local = frag - (uHalo.xy + halfSize);
    float d = roundedBox(local, halfSize, uHaloRadius);
    float spread = min(uHalo.z, uHalo.w) * 0.32;
    float glow = exp(-max(d, 0.0) / spread) * step(0.0, d);
    float angle = atan(local.y, local.x);
    vec3 haloColour = mix(uPrimary, uSecondary, 0.5 + 0.5 * sin(angle + t * 0.12));
    haloColour = mix(haloColour, uAccent, 0.25);
    colour = mix(colour, haloColour, glow * 0.75 * k * breathe);
  }

  // Gentle vignette keeps edges and text areas calm.
  vec2 v = frag / uSize - 0.5;
  colour *= 1.0 - 0.35 * dot(v, v);
  colour = mix(colour, uBase, uCalm * 0.65);
  colour += (dither(frag) - 0.5) / 255.0;
  fragColor = vec4(clamp(colour, 0.0, 1.0), 1.0);
}
