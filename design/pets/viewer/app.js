// FreeAPet pet library viewer. Static site: serve design/pets and open /viewer/.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { RoomEnvironment } from 'three/addons/environments/RoomEnvironment.js';

const $ = (id) => document.getElementById(id);
const el = (tag, cls, text) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text != null) n.textContent = text;
  return n;
};
const MARKER_COLORS = { release: '#5fe3ff', impact: '#ff6fb1', ground: '#ffc56f' };
const markerColor = (name) => MARKER_COLORS[name] || '#8f7dff';
const RARITY = {
  Common: { pt: 'Comum', c: '#a7adbf' }, Uncommon: { pt: 'Incomum', c: '#58e0a3' }, Rare: { pt: 'Raro', c: '#4fa8ff' },
  Epic: { pt: 'Épico', c: '#b56bff' }, Legendary: { pt: 'Lendário', c: '#ffb547' }, Mythic: { pt: 'Mítico', c: '#ff5fa2' },
};
const BIOME_PT = { Forest: 'Floresta', Desert: 'Deserto', SafeZone: 'Zona Segura', Snow: 'Neve', Ocean: 'Oceano', Volcano: 'Vulcão', Cave: 'Caverna' };
const rarityOf = (p) => RARITY[p.rarity] || null;
const biomeName = (b) => BIOME_PT[b] || b;
const filters = { rarity: null, biome: null };
const FAMILY_PT = { slash: 'corte', pulse: 'pulso', geyser: 'géiser', projectile: 'projétil', slam: 'esmagar', radial: 'radial', beam: 'raio' };

// ---------------------------------------------------------------- scene
const canvas = $('canvas');
const viewport = $('viewport');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, preserveDrawingBuffer: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 2));
renderer.outputColorSpace = THREE.SRGBColorSpace;
renderer.toneMapping = THREE.ACESFilmicToneMapping;
renderer.toneMappingExposure = 0.95;
renderer.shadowMap.enabled = true;
renderer.shadowMap.type = THREE.PCFSoftShadowMap;

const scene = new THREE.Scene();
const pmrem = new THREE.PMREMGenerator(renderer);
scene.environment = pmrem.fromScene(new RoomEnvironment(), 0.04).texture;
scene.environmentIntensity = 0.55;

const camera = new THREE.PerspectiveCamera(32, 1, 0.05, 200);
const controls = new OrbitControls(camera, canvas);
controls.enableDamping = true;
controls.dampingFactor = 0.08;
controls.autoRotateSpeed = 1.1;
controls.maxPolarAngle = Math.PI * 0.52;

scene.add(new THREE.HemisphereLight(0xbfc8ff, 0x1a1530, 0.9));
const key = new THREE.DirectionalLight(0xffffff, 2.6);
key.castShadow = true;
key.shadow.mapSize.set(2048, 2048);
key.shadow.bias = -0.0004;
key.shadow.normalBias = 0.02;
scene.add(key, key.target);
const rim = new THREE.DirectionalLight(0x9a86ff, 2.2);
scene.add(rim);
const fill = new THREE.DirectionalLight(0x5fe3ff, 0.55);
scene.add(fill);

// ground: soft glow disc, shadow catcher and rings
const ground = new THREE.Group();
scene.add(ground);
function glowTexture() {
  const c = document.createElement('canvas');
  c.width = c.height = 512;
  const g = c.getContext('2d');
  const grad = g.createRadialGradient(256, 256, 0, 256, 256, 256);
  grad.addColorStop(0, 'rgba(150,132,255,0.42)');
  grad.addColorStop(0.45, 'rgba(110,100,230,0.16)');
  grad.addColorStop(1, 'rgba(90,90,200,0)');
  g.fillStyle = grad;
  g.fillRect(0, 0, 512, 512);
  g.strokeStyle = 'rgba(170,180,255,0.20)';
  g.lineWidth = 1.5;
  for (const r of [70, 130, 190, 248]) { g.beginPath(); g.arc(256, 256, r, 0, Math.PI * 2); g.stroke(); }
  g.strokeStyle = 'rgba(170,180,255,0.08)';
  for (let i = 0; i < 24; i++) {
    const a = (i / 24) * Math.PI * 2;
    g.beginPath(); g.moveTo(256 + Math.cos(a) * 70, 256 + Math.sin(a) * 70);
    g.lineTo(256 + Math.cos(a) * 248, 256 + Math.sin(a) * 248); g.stroke();
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}
const disc = new THREE.Mesh(
  new THREE.CircleGeometry(1, 96),
  new THREE.MeshBasicMaterial({ map: glowTexture(), transparent: true, depthWrite: false }));
disc.rotation.x = -Math.PI / 2;
const shadowCatcher = new THREE.Mesh(new THREE.CircleGeometry(1, 64), new THREE.ShadowMaterial({ opacity: 0.5 }));
shadowCatcher.rotation.x = -Math.PI / 2;
shadowCatcher.position.y = 0.001;
shadowCatcher.receiveShadow = true;
ground.add(disc, shadowCatcher);

// marker pulse rings (a hint of where VFX would fire)
const pulses = [];
function pulse(color, radius) {
  const ring = new THREE.Mesh(
    new THREE.RingGeometry(0.92, 1, 96),
    new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.9, depthWrite: false, side: THREE.DoubleSide, blending: THREE.AdditiveBlending }));
  ring.rotation.x = -Math.PI / 2;
  ring.position.y = 0.004;
  scene.add(ring);
  pulses.push({ ring, age: 0, radius });
}

// ---------------------------------------------------------------- state
const state = {
  pets: [], pet: null, root: null, mixer: null, actions: {}, clips: {}, meta: null,
  current: null, paused: false, speed: 1, size: 1, skeleton: null, lastTime: 0, scrubbing: false,
  home: null, token: 0,
};
const toggles = { rotate: true, skeleton: false, grid: true, wire: false };

function resize() {
  const w = viewport.clientWidth, h = viewport.clientHeight;
  renderer.setSize(w, h, false);
  camera.aspect = w / Math.max(1, h);
  camera.updateProjectionMatrix();
}
new ResizeObserver(resize).observe(viewport);

function frameCamera(box) {
  const size = box.getSize(new THREE.Vector3());
  const centre = box.getCenter(new THREE.Vector3());
  const radius = Math.max(size.x, size.y, size.z) * 0.62;
  const dist = radius / Math.sin(THREE.MathUtils.degToRad(camera.fov) / 2);
  const dir = new THREE.Vector3(0.62, 0.3, 0.72).normalize();
  controls.target.set(centre.x, size.y * 0.46, centre.z);
  camera.position.copy(controls.target).addScaledVector(dir, dist);
  camera.near = dist / 100;
  camera.far = dist * 20;
  camera.updateProjectionMatrix();
  controls.minDistance = dist * 0.35;
  controls.maxDistance = dist * 2.6;
  controls.update();
  state.home = { pos: camera.position.clone(), target: controls.target.clone() };
  state.size = Math.max(size.x, size.z);
  const r = state.size * 1.25;
  disc.scale.setScalar(r);
  shadowCatcher.scale.setScalar(r);
  key.position.set(centre.x + r * 0.9, size.y * 2.4, centre.z + r * 1.1);
  key.target.position.copy(controls.target);
  const s = r * 1.2;
  Object.assign(key.shadow.camera, { left: -s, right: s, top: s, bottom: -s, near: 0.1, far: size.y * 8 });
  key.shadow.camera.updateProjectionMatrix();
  rim.position.set(centre.x - r, size.y * 1.3, centre.z - r * 1.4);
  fill.position.set(centre.x - r * 1.2, size.y * 0.6, centre.z + r);
}

// ---------------------------------------------------------------- library
function prettyClip(name) {
  return name.replace(/^Attack_/, '').replace(/([a-z])([A-Z])/g, '$1 $2').replace(/_/g, ' ');
}
function clipGroup(name) {
  if (/^Attack_/.test(name)) return 'Ataques';
  if (/^(Idle|Walk|Run)/.test(name)) return 'Movimento';
  return 'Estado';
}

function renderLibrary(filter = '') {
  const list = $('pet-list');
  list.textContent = '';
  const q = filter.trim().toLowerCase();
  renderFilters();
  const shown = state.pets.filter((p) =>
    (!q || [p.name, p.rarity, p.biome, rarityOf(p) && rarityOf(p).pt, p.biome && biomeName(p.biome), ...(p.tags || [])]
      .join(' ').toLowerCase().includes(q))
    && (!filters.rarity || p.rarity === filters.rarity) && (!filters.biome || p.biome === filters.biome));
  $('pet-count').textContent = String(state.pets.length);
  if (!shown.length) list.append(el('div', 'pet-empty', state.pets.length ? 'Nenhum pet com estes filtros.' : 'Ainda não há pets na biblioteca.'));
  for (const pet of shown) {
    const card = el('button', 'pet-card' + (state.pet && state.pet.id === pet.id ? ' is-active' : ''));
    const r = rarityOf(pet);
    if (r) card.style.setProperty('--rar', r.c);
    if (pet.rarity === 'Mythic') card.classList.add('is-mythic');
    card.setAttribute('role', 'listitem');
    const thumb = el('div', 'pet-thumb', pet.name.slice(0, 1));
    const src = pet.thumb ? `${pet.thumb}?v=${pet.version || 0}` : pet.snapshot;
    if (src) {
      const img = new Image();
      img.alt = '';
      img.onload = () => { thumb.textContent = ''; thumb.append(img); };
      img.onerror = () => { pet.thumb = null; if (pet.snapshot && img.src !== pet.snapshot) img.src = pet.snapshot; };
      img.src = src;
    }
    const body = el('div');
    const meta = el('div', 'pet-meta');
    if (r) meta.append(el('span', 'rar-text', r.pt));
    if (pet.biome) meta.append(el('span', 'biome-text', biomeName(pet.biome)));
    if (!r && !pet.biome) meta.textContent = pet.subtitle || (pet.tags || []).join(' · ');
    body.append(el('div', 'pet-title', pet.name), meta);
    card.append(thumb, body);
    card.onclick = () => selectPet(pet);
    list.append(card);
  }
}

function renderFilters() {
  const box = $('filters');
  box.textContent = '';
  const chips = (key, values, label, color) => {
    if (values.length < 1) return;
    const row = el('div', 'filter-row');
    row.append(el('span', 'filter-label', label));
    for (const v of [null, ...values]) {
      const b = el('button', 'chip' + (filters[key] === v ? ' is-on' : ''), v ? (key === 'rarity' ? RARITY[v].pt : biomeName(v)) : 'Todos');
      if (v && color) b.style.setProperty('--rar', color(v));
      b.onclick = () => { filters[key] = v; renderLibrary($('search').value); };
      row.append(b);
    }
    box.append(row);
  };
  const order = state.rarities || Object.keys(RARITY);
  chips('rarity', order.filter((r) => RARITY[r] && state.pets.some((p) => p.rarity === r)).reverse(), 'Raridade', (v) => RARITY[v].c);
  chips('biome', [...new Set(state.pets.map((p) => p.biome).filter(Boolean))].sort(), 'Bioma');
}

async function selectPet(pet, force = false) {
  if (state.pet === pet && state.root && !force) return;
  const token = ++state.token;
  state.pet = pet;
  history.replaceState(null, '', '#' + pet.id);
  renderLibrary($('search').value);
  $('pet-name').textContent = pet.name;
  const tags = $('pet-tags');
  tags.textContent = '';
  const r = rarityOf(pet);
  if (r) {
    const b = el('span', 'tag rarity' + (pet.rarity === 'Mythic' ? ' is-mythic' : ''), r.pt);
    b.style.setProperty('--rar', r.c);
    tags.append(b);
  }
  if (pet.biome) tags.append(el('span', 'tag biome', biomeName(pet.biome)));
  (pet.tags || []).forEach((t, i) => tags.append(el('span', 'tag' + (i % 2 ? ' alt' : ''), t)));
  $('loader').classList.remove('is-hidden');
  $('loader-text').textContent = `A carregar ${pet.name}…`;
  $('loader-fill').style.width = '0%';
  disposePet();

  try {
    const [gltf, meta] = await Promise.all([
      new GLTFLoader().loadAsync(pet.version ? `${pet.model}?v=${pet.version}` : pet.model, (e) => {
        if (e.total) $('loader-fill').style.width = `${Math.round((e.loaded / e.total) * 100)}%`;
        state.bytes = e.total || e.loaded;
      }),
      pet.clips ? fetch(pet.version ? `${pet.clips}?v=${pet.version}` : pet.clips, { cache: 'no-store' }).then((r) => (r.ok ? r.json() : null)).catch(() => null) : null,
    ]);
    if (token !== state.token) return;
    setupPet(gltf, meta || {});
  } catch (err) {
    console.error(err);
    $('loader-text').textContent = `Não foi possível carregar ${pet.model}`;
  }
}

function disposePet() {
  if (state.mixer) state.mixer.stopAllAction();
  if (state.skeleton) { scene.remove(state.skeleton); state.skeleton = null; }
  if (state.root) {
    scene.remove(state.root);
    state.root.traverse((o) => {
      if (o.geometry) o.geometry.dispose();
      if (o.material) for (const m of [].concat(o.material)) {
        for (const k of Object.keys(m)) if (m[k] && m[k].isTexture) m[k].dispose();
        m.dispose();
      }
    });
  }
  Object.assign(state, { root: null, mixer: null, actions: {}, clips: {}, current: null, meta: null });
}

function setupPet(gltf, meta) {
  const root = gltf.scene;
  let tris = 0, verts = 0, bones = 0;
  const textures = new Set();
  root.traverse((o) => {
    if (o.isBone) bones++;
    if (o.isMesh) {
      o.castShadow = true;
      o.frustumCulled = false;
      const g = o.geometry;
      verts += g.attributes.position.count;
      tris += (g.index ? g.index.count : g.attributes.position.count) / 3;
      for (const m of [].concat(o.material)) {
        for (const k of ['map', 'normalMap', 'emissiveMap', 'roughnessMap', 'metalnessMap']) if (m[k]) textures.add(m[k]);
        m.wireframe = toggles.wire;
      }
    }
  });
  scene.add(root);
  root.updateMatrixWorld(true);
  const box = new THREE.Box3().setFromObject(root);
  state.root = root;
  state.meta = meta;
  frameCamera(box);

  state.skeleton = new THREE.SkeletonHelper(root);
  state.skeleton.material.depthTest = false;
  state.skeleton.material.transparent = true;
  state.skeleton.material.opacity = 0.9;
  state.skeleton.visible = toggles.skeleton;
  scene.add(state.skeleton);

  state.mixer = new THREE.AnimationMixer(root);
  state.mixer.addEventListener('finished', onFinished);
  const info = meta.clips || {};
  const order = Object.keys(info);
  const clips = [...gltf.animations].sort((a, b) => {
    const ia = order.indexOf(a.name), ib = order.indexOf(b.name);
    return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib);
  });
  for (const clip of clips) {
    const cfg = info[clip.name] || {};
    const loop = cfg.loop != null ? cfg.loop : /^(Idle|Walk|Run)/.test(clip.name);
    const action = state.mixer.clipAction(clip);
    action.setLoop(loop ? THREE.LoopRepeat : THREE.LoopOnce, Infinity);
    action.clampWhenFinished = true;
    state.actions[clip.name] = action;
    state.clips[clip.name] = { clip, loop, duration: cfg.duration || clip.duration, markers: cfg.markers || {}, family: cfg.family, note: cfg.note };
  }
  renderClips();
  const size = box.getSize(new THREE.Vector3());
  const stats = [
    ['Triângulos', Math.round(tris).toLocaleString('pt-PT')],
    ['Vértices', verts.toLocaleString('pt-PT')],
    ['Ossos', String(bones)],
    ['Clips', String(clips.length)],
    ['Texturas', String(textures.size)],
    ['Ficheiro', state.bytes ? `${(state.bytes / 1048576).toFixed(1)} MB` : '—'],
    ['Altura', `${size.y.toFixed(2)} m`],
    ['FPS dos clips', String(meta.fps || 30)],
  ];
  const dl = $('model-info');
  dl.textContent = '';
  for (const [k, v] of stats) { const d = el('div'); d.append(el('dt', null, k), el('dd', null, v)); dl.append(d); }

  const first = state.actions.Idle ? 'Idle' : clips[0] && clips[0].name;
  if (first) playClip(first, true);
  $('loader').classList.add('is-hidden');
  window.__viewerReady = true;
  requestAnimationFrame(() => requestAnimationFrame(snapshot));
}

function snapshot() {
  if (!state.pet || state.pet.snapshot) return;
  try {
    const side = Math.min(canvas.width, canvas.height);
    const c = document.createElement('canvas');
    c.width = c.height = 128;
    c.getContext('2d').drawImage(canvas, (canvas.width - side) / 2, (canvas.height - side) / 2, side, side, 0, 0, 128, 128);
    state.pet.snapshot = c.toDataURL('image/png');
    if (!state.pet.thumb) renderLibrary($('search').value);  // no thumbs/<id>.png yet: use the live snapshot
  } catch { /* snapshot is optional */ }
}

// ---------------------------------------------------------------- clips
function renderClips() {
  const list = $('clip-list');
  list.textContent = '';
  const names = Object.keys(state.clips);
  $('clip-count').textContent = String(names.length);
  let group = null;
  names.forEach((name, i) => {
    const g = clipGroup(name);
    if (g !== group) { group = g; list.append(el('div', 'clip-group', g.toUpperCase())); }
    const c = state.clips[name];
    const b = el('button', 'clip');
    b.dataset.clip = name;
    const body = el('div');
    body.append(el('div', 'clip-label', prettyClip(name)),
      el('div', 'clip-sub', c.family ? `${FAMILY_PT[c.family] || c.family} · ${c.loop ? 'loop' : 'uma vez'}` : (c.loop ? 'loop' : 'uma vez')));
    b.append(el('span', 'clip-key', String(i + 1)), body, el('span', 'clip-dur', `${c.duration.toFixed(1)}s`));
    b.onclick = () => playClip(name);
    list.append(b);
  });
  if (!names.length) list.append(el('div', 'pet-empty', 'Este modelo não tem animações.'));
}

function playClip(name, instant = false) {
  const next = state.actions[name];
  if (!next) return;
  const prev = state.current && state.actions[state.current];
  next.reset();
  next.enabled = true;
  next.setEffectiveWeight(1);
  next.setEffectiveTimeScale(1);
  if (prev && prev !== next && !instant) { next.crossFadeFrom(prev, 0.18, false); next.play(); }
  else { state.mixer.stopAllAction(); next.reset().play(); }
  state.current = name;
  state.lastTime = 0;
  setPaused(false);
  for (const b of $('clip-list').querySelectorAll('.clip')) b.classList.toggle('is-active', b.dataset.clip === name);
  renderClipInfo(name);
}

function renderClipInfo(name) {
  const c = state.clips[name];
  $('clip-name').textContent = prettyClip(name);
  const box = $('clip-info');
  box.textContent = '';
  box.append(el('div', 'info-title', prettyClip(name)));
  const row = el('div', 'info-row');
  row.append(el('span', 'pill', name), el('span', 'pill', `${c.duration.toFixed(2)} s`),
    el('span', 'pill', `${Math.round(c.duration * (state.meta.fps || 30)) + 1} frames`),
    el('span', 'pill loop', c.loop ? 'loop' : 'uma vez'));
  if (c.family) row.append(el('span', 'pill fam', `VFX: ${FAMILY_PT[c.family] || c.family}`));
  box.append(row);
  if (c.note) box.append(el('p', null, c.note));
  const marks = Object.entries(c.markers);
  const track = $('track-markers');
  track.textContent = '';
  if (marks.length) {
    const wrap = el('div', 'markers');
    for (const [m, t] of marks) {
      const b = el('button', 'marker');
      b.style.setProperty('--c', markerColor(m));
      b.append(el('i'), document.createTextNode(`${m}  ${t.toFixed(2)} s · f${Math.round(t * (state.meta.fps || 30))}`));
      b.onclick = () => seek(t);
      wrap.append(b);
      const tick = el('i');
      tick.style.left = `${(t / c.duration) * 100}%`;
      tick.style.setProperty('--c', markerColor(m));
      tick.title = m;
      track.append(tick);
    }
    box.append(wrap);
  }
}

function onFinished(e) {
  const name = e.action.getClip().name;
  if (name !== state.current) return;
  if ($('auto-idle').checked && /^Attack_/.test(name) && state.actions.Idle) {
    setTimeout(() => { if (state.current === name && !state.paused) playClip('Idle'); }, 350);
  }
}

function setPaused(p) {
  state.paused = p;
  $('play').classList.toggle('is-paused', p);
}

function seek(t) {
  const a = state.actions[state.current];
  if (!a) return;
  const c = state.clips[state.current];
  setPaused(true);
  a.paused = false;
  a.enabled = true;
  a.time = Math.max(0, Math.min(c.duration, t));
  state.mixer.update(0);
  state.lastTime = a.time;
}

function fireMarker(name) {
  const chip = el('div', 'cue-chip', name);
  chip.style.setProperty('--c', markerColor(name));
  $('cue').append(chip);
  setTimeout(() => chip.remove(), 950);
  if (name === 'impact' || name === 'release' || name === 'ground') pulse(markerColor(name), state.size * (name === 'impact' ? 1.25 : 0.7));
}

// ---------------------------------------------------------------- ui
$('search').addEventListener('input', (e) => renderLibrary(e.target.value));
$('play').onclick = () => {
  const a = state.actions[state.current];
  if (!a) return;
  const c = state.clips[state.current];
  if (state.paused && !c.loop && a.time >= c.duration - 1e-3) return playClip(state.current, true);
  setPaused(!state.paused);
};
$('restart').onclick = () => state.current && playClip(state.current, true);
$('scrub').addEventListener('input', (e) => {
  const c = state.clips[state.current];
  if (c) seek((e.target.value / 1000) * c.duration);
});
for (const b of document.querySelectorAll('[data-speed]')) {
  b.onclick = () => {
    state.speed = Number(b.dataset.speed);
    document.querySelectorAll('[data-speed]').forEach((x) => x.classList.toggle('is-on', x === b));
  };
}
function setToggle(name, on) {
  toggles[name] = on;
  const b = document.querySelector(`[data-toggle="${name}"]`);
  if (b) b.classList.toggle('is-on', on);
  if (name === 'skeleton' && state.skeleton) state.skeleton.visible = on;
  if (name === 'grid') ground.visible = on;
  if (name === 'wire' && state.root) state.root.traverse((o) => { if (o.isMesh) for (const m of [].concat(o.material)) m.wireframe = on; });
}
for (const b of document.querySelectorAll('[data-toggle]')) b.onclick = () => setToggle(b.dataset.toggle, !toggles[b.dataset.toggle]);
function resetCamera() {
  if (!state.home) return;
  camera.position.copy(state.home.pos);
  controls.target.copy(state.home.target);
  controls.update();
}
document.querySelector('[data-action="reset"]').onclick = resetCamera;
controls.addEventListener('start', () => { state.dragging = true; });
controls.addEventListener('end', () => { state.dragging = false; });

window.addEventListener('keydown', (e) => {
  if (e.target.matches('input[type="search"]')) return;
  const fps = (state.meta && state.meta.fps) || 30;
  const a = state.actions[state.current];
  if (e.code === 'Space') { e.preventDefault(); $('play').click(); }
  else if (e.key === 'Enter') $('restart').click();
  else if (e.key === 'ArrowRight' && a) { e.preventDefault(); seek(a.time + 1 / fps); }
  else if (e.key === 'ArrowLeft' && a) { e.preventDefault(); seek(a.time - 1 / fps); }
  else if (/^[1-9]$/.test(e.key)) { const n = Object.keys(state.clips)[Number(e.key) - 1]; if (n) playClip(n); }
  else if (e.key === 'r') setToggle('rotate', !toggles.rotate);
  else if (e.key === 's') setToggle('skeleton', !toggles.skeleton);
  else if (e.key === 'g') setToggle('grid', !toggles.grid);
  else if (e.key === 'w') setToggle('wire', !toggles.wire);
  else if (e.key === 'c') resetCamera();
});

// ---------------------------------------------------------------- loop
const clock = new THREE.Clock();
function tick() {
  const dt = Math.min(clock.getDelta(), 0.1);
  const a = state.actions[state.current];
  if (state.mixer && a) {
    if (!state.paused) state.mixer.update(dt * state.speed);
    const c = state.clips[state.current];
    const t = a.time;
    if (!state.paused) {
      for (const [m, mt] of Object.entries(c.markers)) {
        const crossed = t >= state.lastTime ? (state.lastTime < mt && t >= mt) : (mt > state.lastTime || mt <= t);
        if (crossed && /^(release|impact|ground)$/.test(m)) fireMarker(m);
      }
    }
    state.lastTime = t;
    const k = Math.max(0, Math.min(1, t / c.duration));
    $('scrub').value = String(Math.round(k * 1000));
    $('track-fill').style.width = `${k * 100}%`;
    $('clip-time').textContent = `${t.toFixed(2)} / ${c.duration.toFixed(2)} s · f${Math.round(t * ((state.meta && state.meta.fps) || 30))}`;
  }
  for (let i = pulses.length - 1; i >= 0; i--) {
    const p = pulses[i];
    p.age += dt;
    const k = p.age / 0.7;
    p.ring.scale.setScalar(p.radius * (0.15 + 0.85 * (1 - (1 - k) ** 3)));
    p.ring.material.opacity = Math.max(0, 0.9 * (1 - k));
    if (k >= 1) { scene.remove(p.ring); p.ring.geometry.dispose(); p.ring.material.dispose(); pulses.splice(i, 1); }
  }
  controls.autoRotate = toggles.rotate && !state.dragging;
  controls.update();
  renderer.render(scene, camera);
  requestAnimationFrame(tick);
}

// ---------------------------------------------------------------- boot
async function boot() {
  resize();
  tick();
  try {
    const text = await fetch('pets.json', { cache: 'no-store' }).then((r) => r.text());
    const data = JSON.parse(text);
    state.pets = data.pets || data;
    state.rarities = data.rarities;
    state.registry = text;
  } catch (err) {
    console.error(err);
    $('loader-text').textContent = 'Não foi possível ler viewer/pets.json';
    return;
  }
  renderLibrary();
  // ?model=../slug/export/Pet.glb opens a single file without touching pets.json
  const q = new URLSearchParams(location.search).get('model');
  if (q) {
    const pet = { id: 'preview', name: q.split('/').pop().replace(/\.glb$/i, ''), model: q, clips: q.replace(/\.glb$/i, '_clips.json'), tags: ['pré-visualização'] };
    state.pets.unshift(pet);
    return selectPet(pet);
  }
  const wanted = state.pets.find((p) => p.id === location.hash.slice(1)) || state.pets[0];
  if (wanted) selectPet(wanted);
  else { $('loader-text').textContent = 'Ainda não há pets na biblioteca.'; document.querySelector('.loader-ring').remove(); }
}
// Live library: pets.json is rewritten by every pet build; pick up new or rebuilt pets by itself.
async function poll() {
  try {
    const text = await fetch('pets.json', { cache: 'no-store' }).then((r) => (r.ok ? r.text() : null));
    if (!text || text === state.registry) return;
    const data = JSON.parse(text);
    const fresh = data.pets || data;
    const added = fresh.filter((p) => !state.pets.some((o) => o.id === p.id));
    const cur = state.pet && fresh.find((p) => p.id === state.pet.id);
    const rebuilt = cur && cur.version !== state.pet.version;
    for (const p of fresh) {
      const old = state.pets.find((o) => o.id === p.id);
      if (old && old.version === p.version && old.snapshot) p.snapshot = old.snapshot;
    }
    state.pets = fresh;
    state.rarities = data.rarities;
    state.registry = text;
    if (cur) state.pet = cur;
    renderLibrary($('search').value);
    if (rebuilt) selectPet(cur, true);
    else if (!state.pet && fresh[0]) selectPet(fresh[0]);
    for (const p of added) toast(`Novo pet na biblioteca: ${p.name}`);
  } catch { /* server restarting: try again on the next tick */ }
}
function toast(msg) {
  const chip = el('div', 'cue-chip toast', msg);
  $('cue').append(chip);
  setTimeout(() => chip.remove(), 4000);
}
setInterval(poll, 4000);

window.__viewer = { state, playClip, seek, setToggle, controls, camera };
boot();
