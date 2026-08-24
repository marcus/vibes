<!-- WebGL hero flow — the procedural ribbon backdrop from
     experiments/hero-flow, tuned settings baked in (see the SETTINGS block),
     premultiplied-alpha output so it composites onto the page background in
     both themes. Renders nothing if WebGL is unavailable. At most one
     instance per page. -->
<script>
  import { onMount } from 'svelte';

  let { theme = 'dark' } = $props();

  let canvas;
  let flow;

  onMount(() => {
    if (!canvas) return;
    const gl =
      canvas.getContext('webgl', { alpha: true, antialias: false, powerPreference: 'high-performance' }) ||
      canvas.getContext('experimental-webgl', { alpha: true });
    if (!gl) return;

    let prog, U;
    function initGL() {
      try {
        function compile(type, src) {
          const s = gl.createShader(type);
          gl.shaderSource(s, src);
          gl.compileShader(s);
          if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s));
          return s;
        }
        prog = gl.createProgram();
        gl.attachShader(prog, compile(gl.VERTEX_SHADER, VERT));
        gl.attachShader(prog, compile(gl.FRAGMENT_SHADER, FRAG));
        gl.linkProgram(prog);
        if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(prog));
      } catch (e) {
        return false;
      }
      gl.useProgram(prog);

      const buf = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, buf);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
      const aPos = gl.getAttribLocation(prog, 'aPos');
      gl.enableVertexAttribArray(aPos);
      gl.vertexAttribPointer(aPos, 2, gl.FLOAT, false, 0, 0);

      U = {};
      ['uRes', 'uTime', 'uPar', 'uTurb', 'uGlow', 'uOp', 'uWarm', 'uSoft', 'uCount', 'uMT', 'uMB', 'uWMn', 'uWMx', 'uWB', 'uCore', 'uSeed', 'uLight'].forEach(n => U[n] = gl.getUniformLocation(prog, n));
      return true;
    }
    if (!initGL()) return;

    const SCALES = [1, 0.85, 0.7, 0.55];
    let scaleIdx = 1;
    let W = 0, H = 0;

    const reducedMq = matchMedia('(prefers-reduced-motion: reduce)');
    let reduced = reducedMq.matches;

    let mx = 0, my = 0, tx = 0, ty = 0;
    let lastPointerMove = -10;
    let tAnim = 0, lastT = performance.now() / 1000, dirty = true, frame = 0;
    let emaDt = 1 / 60, lastScaleChange = 0;
    let raf = 0;
    let light = theme === 'light';

    function resize() {
      const dpr = Math.min(devicePixelRatio || 1, 2) * SCALES[scaleIdx];
      const w = Math.max(2, Math.round(canvas.clientWidth * dpr));
      const h = Math.max(2, Math.round(canvas.clientHeight * dpr));
      if (w !== W || h !== H) { W = w; H = h; canvas.width = W; canvas.height = H; }
      gl.viewport(0, 0, W, H);
      dirty = true;
    }

    function onPointerMove(e) {
      if (reduced) return;
      const r = canvas.getBoundingClientRect();
      tx = ((e.clientX - r.left) / r.width) * 2 - 1;
      ty = -(((e.clientY - r.top) / r.height) * 2 - 1);
      lastPointerMove = performance.now() / 1000;
      dirty = true;
    }

    function onReducedChange() {
      reduced = reducedMq.matches;
      if (reduced) {
        cancelAnimationFrame(raf);
        raf = 0;
        drawFrame(0);
      } else if (!raf) {
        lastT = performance.now() / 1000;
        raf = requestAnimationFrame(tick);
      }
    }
    function onVisibility() { lastT = performance.now() / 1000; }

    let dprMq = matchMedia('(resolution: ' + devicePixelRatio + 'dppx)');
    function onDprChange() {
      dprMq.removeEventListener ? dprMq.removeEventListener('change', onDprChange) : dprMq.removeListener(onDprChange);
      dprMq = matchMedia('(resolution: ' + devicePixelRatio + 'dppx)');
      watchDpr();
      resize();
    }
    function watchDpr() {
      dprMq.addEventListener ? dprMq.addEventListener('change', onDprChange) : dprMq.addListener(onDprChange);
    }

    function uploadUniforms(t) {
      gl.uniform2f(U.uRes, W, H);
      gl.uniform1f(U.uTime, t);
      gl.uniform2f(U.uPar, mx * SETTINGS.par, my * SETTINGS.par);
      gl.uniform1f(U.uTurb, SETTINGS.turb);
      gl.uniform1f(U.uGlow, SETTINGS.glow);
      gl.uniform1f(U.uOp, SETTINGS.op);
      gl.uniform1f(U.uWarm, SETTINGS.warm);
      gl.uniform1f(U.uSoft, SETTINGS.soft);
      gl.uniform1f(U.uCount, SETTINGS.count);
      gl.uniform1f(U.uMT, SETTINGS.mtop);
      gl.uniform1f(U.uMB, SETTINGS.mbot);
      gl.uniform1f(U.uWMn, SETTINGS.wmin);
      gl.uniform1f(U.uWMx, SETTINGS.wmax);
      gl.uniform1f(U.uWB, SETTINGS.wbias);
      gl.uniform1f(U.uCore, SETTINGS.core);
      gl.uniform1f(U.uSeed, SETTINGS.seed);
      gl.uniform1f(U.uLight, light ? 1 : 0);
    }

    function drawFrame(t) {
      uploadUniforms(t);
      gl.drawArrays(gl.TRIANGLES, 0, 3);
      dirty = false;
    }

    function tick() {
      raf = requestAnimationFrame(tick);
      const now = performance.now() / 1000;
      const dt = Math.min(now - lastT, 0.1);
      lastT = now;
      frame++;
      tAnim += dt * SETTINGS.speed;

      const idle = now - lastPointerMove > 4;
      const ax = idle ? 0.42 * Math.sin(tAnim * 0.05 + 1.3) : tx;
      const ay = idle ? 0.26 * Math.sin(tAnim * 0.037) : ty;
      const me = 1 - Math.exp(-dt * 3.6);
      mx += (ax - mx) * me;
      my += (ay - my) * me;

      emaDt += (dt - emaDt) * 0.05;
      if (frame > 90 && now - lastScaleChange > 2.0) {
        if (emaDt > 0.024 && scaleIdx < SCALES.length - 1) { scaleIdx++; resize(); lastScaleChange = now; }
        else if (emaDt < 0.013 && scaleIdx > 0) { scaleIdx--; resize(); lastScaleChange = now; }
      }

      drawFrame(tAnim);
    }

    function onContextLost(e) {
      e.preventDefault();
      cancelAnimationFrame(raf);
      raf = 0;
    }
    function onContextRestored() {
      if (!initGL()) return;
      resize();
      if (reduced) drawFrame(0);
      else if (!raf) { lastT = performance.now() / 1000; raf = requestAnimationFrame(tick); }
    }

    function start() {
      resize();
      watchDpr();
      addEventListener('resize', resize);
      addEventListener('pointermove', onPointerMove, { passive: true });
      document.addEventListener('visibilitychange', onVisibility);
      canvas.addEventListener('webglcontextlost', onContextLost, false);
      canvas.addEventListener('webglcontextrestored', onContextRestored, false);
      reducedMq.addEventListener ? reducedMq.addEventListener('change', onReducedChange) : reducedMq.addListener(onReducedChange);
      if (reduced) {
        drawFrame(0);
      } else {
        raf = requestAnimationFrame(tick);
      }
    }

    function stop() {
      cancelAnimationFrame(raf);
      removeEventListener('resize', resize);
      removeEventListener('pointermove', onPointerMove);
      document.removeEventListener('visibilitychange', onVisibility);
      canvas.removeEventListener('webglcontextlost', onContextLost);
      canvas.removeEventListener('webglcontextrestored', onContextRestored);
      dprMq.removeEventListener ? dprMq.removeEventListener('change', onDprChange) : dprMq.removeListener(onDprChange);
      reducedMq.removeEventListener ? reducedMq.removeEventListener('change', onReducedChange) : reducedMq.removeListener(onReducedChange);
      gl.getExtension('WEBGL_lose_context')?.loseContext();
    }

    flow = {
      setTheme(l) {
        if (light === l) return;
        light = l;
        dirty = true;
        if (reduced) drawFrame(0);
      }
    };
    start();
    return stop;
  });

  $effect(() => {
    flow?.setTheme(theme === 'light');
  });

  const SETTINGS = {
    speed: 0.05,
    turb: 0.36,
    par: 0.57,
    glow: 0.85,
    op: 0.33,
    warm: 1.91,
    soft: 0.10,
    count: 5,
    mtop: 0.45,
    mbot: 0.32,
    wmin: 0.54,
    wmax: 15.0,
    core: 1.0,
    wbias: 0.76,
    seed: 7.31
  };

  const VERT = `
attribute vec2 aPos;
void main(){ gl_Position = vec4(aPos, 0.0, 1.0); }
`;

  // Same fragment shader as experiments/hero-flow, with the opaque
  // darkBase/lightBase tail replaced by premultiplied-alpha output: dark mode
  // composites the tonemapped emission over the page background; light mode
  // lays the averaged ink down at its coverage alpha (the experiment's
  // lightBase mix, minus the base).
  const FRAG = `
precision highp float;

uniform vec2 uRes;
uniform float uTime;
uniform vec2 uPar;
uniform float uTurb;
uniform float uGlow;
uniform float uOp;
uniform float uWarm;
uniform float uSoft;
uniform float uCount;
uniform float uMT;
uniform float uMB;
uniform float uWMn;
uniform float uWMx;
uniform float uWB;
uniform float uCore;
uniform float uSeed;
uniform float uLight;

const int MAX_LAYERS = 14;

float hash(vec2 p){
  p = fract(p * vec2(127.1, 311.7) + uSeed);
  p += dot(p, p + 34.23);
  return fract(p.x * p.y);
}
float vnoise(vec2 p){
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
    mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
    u.y);
}
float fbm(vec2 p){
  float s = 0.0, a = 0.55;
  for (int i = 0; i < 4; i++) {
    s += a * vnoise(p);
    p = p * 2.07 + vec2(19.7, 7.3);
    a *= 0.52;
  }
  return s;
}

vec3 palStop(float k){
  vec3 c0 = vec3(0.643, 0.447, 1.000);
  vec3 c1 = vec3(1.000, 0.302, 0.553);
  vec3 c2 = vec3(1.000, 0.478, 0.239);
  vec3 c3 = vec3(0.271, 0.831, 1.000);
  vec3 c4 = vec3(0.435, 0.549, 1.000);
  if (k < 0.5) return c0;
  if (k < 1.5) return c1;
  if (k < 2.5) return c2;
  if (k < 3.5) return c3;
  return c4;
}
vec3 spectrum(float u){
  float seg = fract(u) * 4.0;
  float i = floor(seg);
  float f = smoothstep(0.0, 1.0, fract(seg));
  return mix(palStop(i), palStop(min(i + 1.0, 4.0)), f);
}

float wavePhase(float x, float seed, float t, float k1, float k2){
  return sin(x * k1 + t * 0.60 + seed * 12.9) + sin(x * k2 - t * 0.42 + seed * 27.3);
}

void main(){
  vec2 frag = gl_FragCoord.xy;
  vec2 p = (frag - 0.5 * uRes) / uRes.y;
  float aspect = uRes.x / uRes.y;
  float vfit = mix(0.78, 1.0, smoothstep(0.6, 1.4, aspect));

  float t = uTime;

  vec3 emissive = vec3(0.0);
  vec3 wsum = vec3(0.0);
  float cov = 0.0;

  for (int li = 0; li < MAX_LAYERS; li++) {
    if (float(li) >= uCount) break;
    float fi = float(li);
    float dn = fi / max(uCount - 1.0, 1.0);
    float seed = fi * 0.618 + floor(uSeed) * 0.113;

    float lt = t * mix(1.0, 0.42, dn);

    float px = p.x + uPar.x * mix(0.085, 0.018, dn);
    float py = p.y - uPar.y * mix(0.042, 0.009, dn);

    float yTop = (0.5 - uMT) / max(vfit, 1e-3);
    float yBot = -(0.5 - uMB) / max(vfit, 1e-3);
    if (yBot > yTop) { float m = yBot; yBot = yTop; yTop = m; }

    float b0 = fract(sin(fi * 12.9898 + floor(uSeed) * 78.233) * 43758.5453);
    float baseY = mix(yBot, yTop, b0);

    float wr = fract(sin(fi * 7.77 + floor(uSeed) * 53.17) * 3157.83);
    float wCurve = pow(clamp(wr, 0.0, 1.0), uWB);
    float bandW = mix(uWMn, max(uWMx, uWMn), wCurve);

    float k1 = mix(0.95, 1.55, fract(seed * 3.7));
    float k2 = mix(0.36, 0.60, fract(seed * 5.1));
    float ph = wavePhase(px, seed, lt, k1, k2);
    float amp = mix(0.165, 0.115, dn) * (0.65 + 0.7 * uTurb);
    float c = (baseY + ph * amp
      + (fbm(vec2(px * 0.80 + seed * 7.0, lt * 0.26 + seed * 3.1)) - 0.5) * 2.0 * 0.17 * uTurb
      + 0.028 * sin(lt * 0.16 + seed * 9.0)) * vfit;

    float slope = cos(px * k1 + lt * 0.60 + seed * 12.9) * k1
                - cos(px * k2 - lt * 0.42 + seed * 27.3) * k2;

    float taper = 0.55 + 0.95 * vnoise(vec2(px * 1.7 + seed * 9.0, lt * 0.18));
    float coreBase = 0.0072 * bandW * mix(0.95, 1.65, dn) * taper * (0.7 + 0.6 * uTurb) * uSoft;
    float coreW = max(coreBase * uCore, 1e-4);
    float haloW = max(coreBase, 1e-4) * mix(8.0, 13.0, dn) * mix(1.0, uSoft, 0.65);

    float d = py - c;
    float gCore = exp(-d * d / (coreW * coreW));
    float gHalo = exp(-d * d / (haloW * haloW));

    float shimmer = 0.86 + 0.28 * fbm(vec2(px * 1.9 - lt * 0.30, seed * 3.0 + lt * 0.19));
    float spec = clamp(0.74 + slope * 0.32, 0.5, 1.16);

    float hu = px * 0.16 + seed * 0.83 + t * 0.010 + (d / haloW) * 0.09 + uWarm * 0.12;
    vec3 rc = spectrum(hu);
    float rl = dot(rc, vec3(0.299, 0.587, 0.114));
    rc = mix(vec3(rl), rc, 1.0 + 0.6 * uWarm);

    float edgeComp = pow(clamp(uSoft, 0.12, 1.8), -0.3);
    float haloGain = mix(0.185, 0.068, dn) * edgeComp;
    float coreGain = mix(0.80, 0.38, dn) * edgeComp;

    vec3 haloCol = rc * gHalo * haloGain * shimmer * spec * uGlow;
    vec3 coreCol = mix(rc, vec3(1.0), 0.24) * gCore * coreGain * shimmer * uGlow;

    emissive += (haloCol + coreCol) * uOp;

    float wgt = (gHalo * haloGain + gCore * coreGain) * uOp;
    vec3 inkCol = mix(rc * mix(0.9, 0.55, dn), mix(rc, vec3(1.0), 0.35), gCore * 0.6);
    wsum += inkCol * wgt * (shimmer * 0.6 + 0.5);
    cov += wgt * mix(1.0, 0.8, dn);
  }

  vec2 q = p * vec2(0.82, 1.25);
  float vig = exp(-dot(q, q) * 0.55);

  vec3 e = 1.0 - exp(-emissive * 1.15);
  float att = mix(1.0, 0.72, 1.0 - vig);
  vec3 ink = clamp(wsum / max(cov, 1e-4), 0.0, 1.0);
  float cover = clamp(cov * 1.5, 0.0, 0.92);

  vec3 prem = mix(e * att, ink * cover, uLight);
  float a = mix(max(prem.r, max(prem.g, prem.b)), cover, uLight);
  prem += (hash(frag + fract(t) * 61.7) - 0.5) / 255.0 * 1.6;
  gl_FragColor = vec4(clamp(prem, vec3(0.0), vec3(a)), a);
}
`;
</script>

<canvas class="hero-flow" bind:this={canvas} aria-hidden="true"></canvas>

<style>
  .hero-flow {
    /* Full-bleed: the hero section is a centered .shell, so pull the canvas
       out to the viewport edges while keeping its height tied to the section. */
    position: absolute; top: 0; bottom: 0;
    left: calc(50% - 50vw); width: 100vw;
    z-index: -1; pointer-events: none;
    -webkit-mask-image: linear-gradient(to bottom, transparent 0%, #000 12%, #000 86%, transparent 100%);
    mask-image: linear-gradient(to bottom, transparent 0%, #000 12%, #000 86%, transparent 100%);
  }
</style>
