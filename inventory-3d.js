(function () {
  'use strict';

  let modulePromise = null;
  let view = null;
  let lifecycleToken = 0;

  function loadModules() {
    if (!modulePromise) {
      modulePromise = Promise.all([
        import('three'),
        import('three/addons/controls/OrbitControls.js')
      ]).then(([THREE, controlsModule]) => ({ THREE, OrbitControls: controlsModule.OrbitControls }));
    }
    return modulePromise;
  }

  async function open(options) {
    const token = ++lifecycleToken;
    disposeView();
    const { THREE, OrbitControls } = await loadModules();
    if (token !== lifecycleToken) throw new Error('3D表示はキャンセルされました。');

    const host = document.getElementById('inventory3dCanvas');
    if (!host) throw new Error('3D表示領域が見つかりません。');
    host.replaceChildren();

    const cooler = options.cooler;
    const rows = Math.max(1, Number(cooler.rowCount || 1));
    const cols = Math.max(1, Number(cooler.colCount || 1));
    const levels = Math.max(1, Number(cooler.maxLevel || 1));
    const unitY = 0.82;
    const locations = locationMap(options.locations || [], cooler.coolerId);
    const placementMap = new Map((options.placements || []).map(item => [item.locationId, item]));
    const palletMap = new Map((options.pallets || []).map(item => [item.palletNo, item]));
    const scene = new THREE.Scene();
    scene.background = new THREE.Color(0xf4f7f5);
    const camera = new THREE.PerspectiveCamera(42, 1, 0.03, Math.max(rows, cols, levels) * 40 + 40);
    const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.75));
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.domElement.setAttribute('aria-label', `${cooler.coolerName || cooler.coolerId} 3D配置`);
    renderer.domElement.tabIndex = 0;
    host.appendChild(renderer.domElement);

    const entranceMarker = document.querySelector('.inventory-3d-entrance');
    let modelBounds = null;
    let renderQueued = false;
    function resize() {
      const width = Math.max(1, host.clientWidth);
      const height = Math.max(1, host.clientHeight);
      const canvas = renderer.domElement;
      const ratio = Math.min(window.devicePixelRatio || 1, 1.75);
      if (canvas.width !== Math.floor(width * ratio) || canvas.height !== Math.floor(height * ratio)) {
        renderer.setSize(width, height, false);
        camera.aspect = width / height;
        camera.updateProjectionMatrix();
      }
    }

    function requestRender() {
      if (renderQueued) return;
      renderQueued = true;
      requestAnimationFrame(() => {
        renderQueued = false;
        resize();
        renderer.render(scene, camera);
        positionEntranceMarker();
      });
    }

    function positionEntranceMarker() {
      if (!entranceMarker || !modelBounds || modelBounds.isEmpty()) return;
      const rect = host.getBoundingClientRect();
      const min = modelBounds.min;
      const max = modelBounds.max;
      const corners = [
        [min.x, min.y, min.z], [min.x, min.y, max.z],
        [min.x, max.y, min.z], [min.x, max.y, max.z],
        [max.x, min.y, min.z], [max.x, min.y, max.z],
        [max.x, max.y, min.z], [max.x, max.y, max.z]
      ];
      let minX = Infinity;
      let maxX = -Infinity;
      let maxY = -Infinity;
      let visiblePoints = 0;
      corners.forEach(values => {
        const projected = new THREE.Vector3(...values).project(camera);
        if (![projected.x, projected.y, projected.z].every(Number.isFinite) || projected.z < -1 || projected.z > 1) return;
        const x = rect.left + (projected.x + 1) * rect.width / 2;
        const y = rect.top + (1 - projected.y) * rect.height / 2;
        minX = Math.min(minX, x);
        maxX = Math.max(maxX, x);
        maxY = Math.max(maxY, y);
        visiblePoints += 1;
      });
      if (visiblePoints < 2) {
        entranceMarker.style.visibility = 'hidden';
        return;
      }
      entranceMarker.style.left = `${(minX + maxX) / 2}px`;
      entranceMarker.style.top = `${maxY + 10}px`;
      entranceMarker.style.visibility = 'visible';
    }

    const center = new THREE.Vector3(0, ((levels - 1) * unitY) / 2, 0);
    const sceneSize = Math.max(cols, rows, levels * 1.35, 3);
    const viewportAspect = Math.max(0.35, host.clientWidth / Math.max(1, host.clientHeight));
    const portraitFit = Math.max(1, 0.72 / viewportAspect);
    const distance = (sceneSize * 1.75 + 2.6) * portraitFit;
    const yaw = 0.72;
    const pitch = 0.52;
    const horizontal = Math.cos(pitch) * distance;
    camera.position.set(
      center.x + Math.sin(yaw) * horizontal,
      center.y + Math.sin(pitch) * distance,
      center.z + Math.cos(yaw) * horizontal
    );

    const controls = new OrbitControls(camera, renderer.domElement);
    controls.target.copy(center);
    controls.enableDamping = false;
    controls.enablePan = true;
    controls.enableRotate = true;
    controls.enableZoom = true;
    controls.zoomToCursor = true;
    controls.screenSpacePanning = true;
    controls.minDistance = 0.08;
    controls.maxDistance = sceneSize * 5 + 10;
    controls.maxPolarAngle = Math.PI * 0.96;
    controls.update();
    controls.saveState();
    controls.addEventListener('change', requestRender);

    const slotGeometry = new THREE.BoxGeometry(0.96, 0.72, 0.96);
    const slotEdges = new THREE.EdgesGeometry(slotGeometry);
    const usableLineMaterial = new THREE.LineBasicMaterial({ color: 0x728379, transparent: true, opacity: 0.34 });
    const blockedLineMaterial = new THREE.LineBasicMaterial({ color: 0x9b5960, transparent: true, opacity: 0.2 });
    const palletGeometry = new THREE.BoxGeometry(0.82, 0.6, 0.82);
    const palletEdges = new THREE.EdgesGeometry(palletGeometry);
    const palletLineMaterial = new THREE.LineBasicMaterial({ color: 0x174f3f, transparent: true, opacity: 0.95 });
    const selectedLineMaterial = new THREE.LineBasicMaterial({ color: 0x8a5a00, transparent: true, opacity: 1 });
    const meshes = [];
    const palletMaterials = [];
    const labelMaterials = [];
    const labelTextures = [];
    const palletObjects = [];
    let selectedPalletNo = options.selectedPalletNo || '';
    let transparency = clamp(Number(options.transparency ?? 45), 10, 85);

    const floor = new THREE.GridHelper(Math.max(cols, rows) + 1, Math.max(cols, rows) + 1, 0x7b8c82, 0xc4cec8);
    floor.position.y = -0.39;
    scene.add(floor);

    for (let level = 1; level <= levels; level += 1) {
      for (let row = 1; row <= rows; row += 1) {
        for (let col = 1; col <= cols; col += 1) {
          const locationId = makeLocationId(cooler.coolerId, level, row, col);
          const location = locations.get(locationId) || { locationId, coolerId: cooler.coolerId, level, row, col, available: false };
          const position = cellPosition(col, row, level, cols, rows, unitY);
          const slot = new THREE.LineSegments(slotEdges, location.available === false ? blockedLineMaterial : usableLineMaterial);
          slot.position.copy(position);
          scene.add(slot);

          const placement = placementMap.get(locationId);
          if (!placement || !placement.palletNo) continue;
          const pallet = palletMap.get(placement.palletNo) || { palletNo: placement.palletNo };
          const selected = placement.palletNo === selectedPalletNo;
          const material = new THREE.MeshBasicMaterial({
            color: selected ? 0xf2b84b : 0x2f9473,
            transparent: true,
            opacity: 1 - transparency / 100,
            depthWrite: false,
            side: THREE.DoubleSide
          });
          palletMaterials.push(material);
          const mesh = new THREE.Mesh(palletGeometry, material);
          mesh.position.copy(position);
          mesh.userData = { palletNo: placement.palletNo, location, pallet };
          scene.add(mesh);
          meshes.push(mesh);

          const edges = new THREE.LineSegments(palletEdges, selected ? selectedLineMaterial : palletLineMaterial);
          edges.position.copy(position);
          scene.add(edges);

          const label = createPalletLabel(THREE, placement.palletNo);
          label.sprite.position.set(position.x, position.y + 0.01, position.z);
          scene.add(label.sprite);
          labelMaterials.push(label.material);
          labelTextures.push(label.texture);
          palletObjects.push({ mesh, edges, label: label.sprite, palletNo: placement.palletNo });
        }
      }
    }

    modelBounds = new THREE.Box3();
    if (meshes.length) {
      meshes.forEach(mesh => {
        modelBounds.expandByPoint(new THREE.Vector3(mesh.position.x - 0.41, mesh.position.y - 0.3, mesh.position.z - 0.41));
        modelBounds.expandByPoint(new THREE.Vector3(mesh.position.x + 0.41, mesh.position.y + 0.3, mesh.position.z + 0.41));
      });
    } else {
      modelBounds.set(
        new THREE.Vector3(-cols / 2, -0.36, -rows / 2),
        new THREE.Vector3(cols / 2, (levels - 1) * unitY + 0.36, rows / 2)
      );
    }

    const raycaster = new THREE.Raycaster();
    const pointer = new THREE.Vector2();
    const abortController = new AbortController();
    const pointerStarts = new Map();
    let multiPointerGesture = false;

    function selectAt(clientX, clientY) {
      const rect = renderer.domElement.getBoundingClientRect();
      pointer.x = ((clientX - rect.left) / rect.width) * 2 - 1;
      pointer.y = -((clientY - rect.top) / rect.height) * 2 + 1;
      raycaster.setFromCamera(pointer, camera);
      const hit = raycaster.intersectObjects(meshes, false)[0];
      if (hit) selectPallet(hit.object.userData.palletNo, true);
    }

    function selectPallet(palletNo, notify) {
      selectedPalletNo = palletNo || '';
      palletObjects.forEach(item => {
        const selected = item.palletNo === selectedPalletNo;
        item.mesh.material.color.setHex(selected ? 0xf2b84b : 0x2f9473);
        item.edges.material = selected ? selectedLineMaterial : palletLineMaterial;
        item.label.scale.set(selected ? 0.76 : 0.68, selected ? 0.19 : 0.17, 1);
      });
      const selectedObject = palletObjects.find(item => item.palletNo === selectedPalletNo);
      renderInfo(selectedObject ? selectedObject.mesh.userData : null);
      requestRender();
      if (notify && selectedPalletNo && typeof options.onSelect === 'function') options.onSelect(selectedPalletNo);
    }

    function renderInfo(data) {
      const info = document.getElementById('inventory3dInfo');
      if (!info) return;
      if (!data) {
        info.classList.add('hidden');
        info.textContent = '';
        return;
      }
      const location = data.location || {};
      const pallet = data.pallet || {};
      info.textContent = `${data.palletNo}  ${Number(pallet.weight || 0).toLocaleString('ja-JP')}kg\n${location.level || ''}段目 / ${location.row || ''}行 / ${location.col || ''}列`;
      info.classList.remove('hidden');
    }

    const canvas = renderer.domElement;
    const signal = abortController.signal;
    canvas.addEventListener('pointerdown', event => {
      pointerStarts.set(event.pointerId, { x: event.clientX, y: event.clientY, moved: false });
      if (pointerStarts.size > 1) multiPointerGesture = true;
    }, { signal });
    canvas.addEventListener('pointermove', event => {
      const start = pointerStarts.get(event.pointerId);
      if (start && Math.hypot(event.clientX - start.x, event.clientY - start.y) > 5) start.moved = true;
    }, { signal });
    canvas.addEventListener('pointerup', event => {
      const start = pointerStarts.get(event.pointerId);
      const shouldSelect = start && !start.moved && !multiPointerGesture && pointerStarts.size === 1;
      pointerStarts.delete(event.pointerId);
      if (!pointerStarts.size) multiPointerGesture = false;
      if (shouldSelect) selectAt(event.clientX, event.clientY);
    }, { signal });
    canvas.addEventListener('pointercancel', event => {
      pointerStarts.delete(event.pointerId);
      if (!pointerStarts.size) multiPointerGesture = false;
    }, { signal });

    const resizeObserver = typeof ResizeObserver === 'function' ? new ResizeObserver(requestRender) : null;
    if (resizeObserver) resizeObserver.observe(host);
    else window.addEventListener('resize', requestRender, { signal });

    view = {
      scene,
      renderer,
      host,
      controls,
      palletMaterials,
      labelMaterials,
      labelTextures,
      geometries: [slotGeometry, slotEdges, palletGeometry, palletEdges, floor.geometry],
      lineMaterials: [usableLineMaterial, blockedLineMaterial, palletLineMaterial, selectedLineMaterial, floor.material],
      abortController,
      resizeObserver,
      setTransparency(value) {
        transparency = clamp(Number(value), 10, 85);
        palletMaterials.forEach(material => { material.opacity = 1 - transparency / 100; });
        requestRender();
      },
      reset() {
        controls.reset();
        requestRender();
      }
    };
    selectPallet(selectedPalletNo, false);
    requestRender();
    return { palletCount: palletObjects.length };
  }

  function createPalletLabel(THREE, palletNo) {
    return createTextLabel(THREE, palletNo, {
      color: '#ffffff',
      fontSize: 60,
      depthTest: true,
      width: 0.68,
      height: 0.17,
      shadow: true
    });
  }

  function createTextLabel(THREE, text, options) {
    const canvas = document.createElement('canvas');
    canvas.width = 512;
    canvas.height = 128;
    const context = canvas.getContext('2d');
    context.clearRect(0, 0, canvas.width, canvas.height);
    context.fillStyle = options.color;
    context.font = `700 ${options.fontSize}px sans-serif`;
    context.textAlign = 'center';
    context.textBaseline = 'middle';
    if (options.shadow) {
      context.shadowColor = 'rgba(0, 0, 0, 0.75)';
      context.shadowBlur = 5;
      context.shadowOffsetX = 1;
      context.shadowOffsetY = 1;
    }
    context.fillText(String(text || ''), 256, 66, 480);
    const texture = new THREE.CanvasTexture(canvas);
    texture.colorSpace = THREE.SRGBColorSpace;
    texture.minFilter = THREE.LinearFilter;
    const material = new THREE.SpriteMaterial({ map: texture, transparent: true, depthTest: options.depthTest, depthWrite: false });
    const sprite = new THREE.Sprite(material);
    sprite.scale.set(options.width, options.height, 1);
    return { sprite, material, texture };
  }

  function close() {
    lifecycleToken += 1;
    disposeView();
  }

  function disposeView() {
    if (!view) return;
    view.abortController.abort();
    if (view.resizeObserver) view.resizeObserver.disconnect();
    view.controls.dispose();
    view.scene.clear();
    view.geometries.forEach(item => item.dispose());
    view.palletMaterials.forEach(item => item.dispose());
    view.labelMaterials.forEach(item => item.dispose());
    view.labelTextures.forEach(item => item.dispose());
    view.lineMaterials.forEach(item => item.dispose());
    view.renderer.dispose();
    view.renderer.forceContextLoss();
    view.host.replaceChildren();
    view = null;
  }

  function reset() {
    if (view) view.reset();
  }

  function setTransparency(value) {
    if (view) view.setTransparency(value);
  }

  function makeLocationId(coolerId, level, row, col) {
    return `${coolerId}-${level}-R${String(row).padStart(2, '0')}-C${String(col).padStart(2, '0')}`;
  }

  function locationMap(locations, coolerId) {
    return new Map(locations.filter(item => item.coolerId === coolerId).map(item => [item.locationId, item]));
  }

  function cellPosition(col, row, level, cols, rows, unitY) {
    return { x: col - (cols + 1) / 2, y: (level - 1) * unitY, z: row - (rows + 1) / 2 };
  }

  function clamp(value, min, max) {
    return Math.min(max, Math.max(min, Number.isFinite(value) ? value : min));
  }

  window.GarlicInventory3D = { open, close, reset, setTransparency };
}());
