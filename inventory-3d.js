(function () {
  'use strict';

  const THREE_URL = 'https://cdn.jsdelivr.net/npm/three@0.185.1/build/three.module.min.js';
  let threePromise = null;
  let view = null;
  let lifecycleToken = 0;

  function loadThree() {
    if (!threePromise) threePromise = import(THREE_URL);
    return threePromise;
  }

  async function open(options) {
    const token = ++lifecycleToken;
    disposeView();
    const THREE = await loadThree();
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
    const camera = new THREE.PerspectiveCamera(42, 1, 0.1, Math.max(rows, cols, levels) * 40 + 40);
    const renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: 'high-performance' });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.75));
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.domElement.setAttribute('aria-label', `${cooler.coolerName || cooler.coolerId} 3D配置`);
    renderer.domElement.tabIndex = 0;
    host.appendChild(renderer.domElement);

    const center = new THREE.Vector3(0, ((levels - 1) * unitY) / 2, 0);
    const sceneSize = Math.max(cols, rows, levels * 1.35, 3);
    const controls = {
      target: center.clone(),
      initialTarget: center.clone(),
      yaw: 0.72,
      pitch: 0.52,
      distance: sceneSize * 1.75 + 2.6,
      initialYaw: 0.72,
      initialPitch: 0.52,
      initialDistance: sceneSize * 1.75 + 2.6,
      minDistance: Math.max(2.5, sceneSize * 0.55),
      maxDistance: sceneSize * 5 + 10
    };

    const slotGeometry = new THREE.BoxGeometry(0.96, 0.72, 0.96);
    const slotEdges = new THREE.EdgesGeometry(slotGeometry);
    const usableLineMaterial = new THREE.LineBasicMaterial({ color: 0x728379, transparent: true, opacity: 0.34 });
    const blockedLineMaterial = new THREE.LineBasicMaterial({ color: 0x9b5960, transparent: true, opacity: 0.2 });
    const palletGeometry = new THREE.BoxGeometry(0.82, 0.6, 0.82);
    const palletEdges = new THREE.EdgesGeometry(palletGeometry);
    const palletLineMaterial = new THREE.LineBasicMaterial({ color: 0x174f3f, transparent: true, opacity: 0.95 });
    const selectedLineMaterial = new THREE.LineBasicMaterial({ color: 0x8a5a00, transparent: true, opacity: 1 });
    const meshes = [];
    const materials = [];
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
          const location = locations.get(locationId) || {
            locationId,
            coolerId: cooler.coolerId,
            level,
            row,
            col,
            available: false
          };
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
          materials.push(material);
          const mesh = new THREE.Mesh(palletGeometry, material);
          mesh.position.copy(position);
          mesh.userData = { palletNo: placement.palletNo, location, pallet };
          scene.add(mesh);
          meshes.push(mesh);

          const edges = new THREE.LineSegments(palletEdges, selected ? selectedLineMaterial : palletLineMaterial);
          edges.position.copy(position);
          edges.userData.palletNo = placement.palletNo;
          scene.add(edges);
          palletObjects.push({ mesh, edges, palletNo: placement.palletNo });
        }
      }
    }

    const raycaster = new THREE.Raycaster();
    const pointer = new THREE.Vector2();
    const abortController = new AbortController();
    const pointerState = new Map();
    let touchGesture = null;
    let mouseDrag = null;
    let hoverPoint = null;
    let renderQueued = false;

    function requestRender() {
      if (renderQueued) return;
      renderQueued = true;
      requestAnimationFrame(() => {
        renderQueued = false;
        resize();
        renderer.render(scene, camera);
      });
    }

    function resize() {
      const width = Math.max(1, host.clientWidth);
      const height = Math.max(1, host.clientHeight);
      const canvas = renderer.domElement;
      const targetWidth = Math.floor(width * Math.min(window.devicePixelRatio || 1, 1.75));
      const targetHeight = Math.floor(height * Math.min(window.devicePixelRatio || 1, 1.75));
      if (canvas.width !== targetWidth || canvas.height !== targetHeight) {
        renderer.setSize(width, height, false);
        camera.aspect = width / height;
        camera.updateProjectionMatrix();
      }
    }

    function updateCamera() {
      controls.pitch = clamp(controls.pitch, -0.05, 1.38);
      controls.distance = clamp(controls.distance, controls.minDistance, controls.maxDistance);
      const horizontal = Math.cos(controls.pitch) * controls.distance;
      camera.position.set(
        controls.target.x + Math.sin(controls.yaw) * horizontal,
        controls.target.y + Math.sin(controls.pitch) * controls.distance,
        controls.target.z + Math.cos(controls.yaw) * horizontal
      );
      camera.lookAt(controls.target);
      requestRender();
    }

    function rotateBy(dx, dy) {
      controls.yaw -= dx * 0.008;
      controls.pitch += dy * 0.006;
      updateCamera();
    }

    function panBy(dx, dy) {
      const scale = controls.distance * 0.0017;
      const right = new THREE.Vector3(1, 0, 0).applyQuaternion(camera.quaternion);
      const up = new THREE.Vector3(0, 1, 0).applyQuaternion(camera.quaternion);
      controls.target.addScaledVector(right, -dx * scale);
      controls.target.addScaledVector(up, dy * scale);
      updateCamera();
    }

    function zoomBy(factor) {
      controls.distance *= factor;
      updateCamera();
    }

    function selectAt(clientX, clientY) {
      const rect = renderer.domElement.getBoundingClientRect();
      pointer.x = ((clientX - rect.left) / rect.width) * 2 - 1;
      pointer.y = -((clientY - rect.top) / rect.height) * 2 + 1;
      raycaster.setFromCamera(pointer, camera);
      const hit = raycaster.intersectObjects(meshes, false)[0];
      if (!hit) return;
      selectPallet(hit.object.userData.palletNo, true);
    }

    function selectPallet(palletNo, notify) {
      selectedPalletNo = palletNo || '';
      palletObjects.forEach(item => {
        const selected = item.palletNo === selectedPalletNo;
        item.mesh.material.color.setHex(selected ? 0xf2b84b : 0x2f9473);
        item.edges.material = selected ? selectedLineMaterial : palletLineMaterial;
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

    function pairMetrics() {
      const points = Array.from(pointerState.values()).slice(0, 2);
      if (points.length < 2) return null;
      return {
        cx: (points[0].x + points[1].x) / 2,
        cy: (points[0].y + points[1].y) / 2,
        distance: Math.hypot(points[0].x - points[1].x, points[0].y - points[1].y)
      };
    }

    const canvas = renderer.domElement;
    const signal = abortController.signal;
    function capturePointer(pointerId) {
      try {
        canvas.setPointerCapture(pointerId);
      } catch (_) {
        // Some embedded browsers defer pointer capture; gesture tracking still works.
      }
    }
    canvas.addEventListener('pointerdown', event => {
      if (event.pointerType === 'mouse') {
        if (event.button !== 0) return;
        mouseDrag = { x: event.clientX, y: event.clientY, startX: event.clientX, startY: event.clientY, moved: false };
        capturePointer(event.pointerId);
        return;
      }
      capturePointer(event.pointerId);
      pointerState.set(event.pointerId, { x: event.clientX, y: event.clientY, startX: event.clientX, startY: event.clientY, moved: false });
      if (pointerState.size === 2) {
        pointerState.forEach(point => { point.moved = true; });
        touchGesture = pairMetrics();
      }
    }, { signal });

    canvas.addEventListener('pointermove', event => {
      if (event.pointerType === 'mouse') {
        if (mouseDrag && (event.buttons & 1)) {
          const dx = event.clientX - mouseDrag.x;
          const dy = event.clientY - mouseDrag.y;
          mouseDrag.x = event.clientX;
          mouseDrag.y = event.clientY;
          if (Math.hypot(event.clientX - mouseDrag.startX, event.clientY - mouseDrag.startY) > 4) mouseDrag.moved = true;
          panBy(dx, dy);
        } else if (!mouseDrag) {
          if (hoverPoint) rotateBy(event.clientX - hoverPoint.x, event.clientY - hoverPoint.y);
          hoverPoint = { x: event.clientX, y: event.clientY };
        }
        return;
      }
      const point = pointerState.get(event.pointerId);
      if (!point) return;
      const dx = event.clientX - point.x;
      const dy = event.clientY - point.y;
      point.x = event.clientX;
      point.y = event.clientY;
      if (Math.hypot(event.clientX - point.startX, event.clientY - point.startY) > 5) point.moved = true;
      if (pointerState.size === 1) {
        rotateBy(dx, dy);
        return;
      }
      const nextGesture = pairMetrics();
      if (nextGesture && touchGesture) {
        panBy(nextGesture.cx - touchGesture.cx, nextGesture.cy - touchGesture.cy);
        if (touchGesture.distance > 1 && nextGesture.distance > 1) zoomBy(touchGesture.distance / nextGesture.distance);
      }
      touchGesture = nextGesture;
    }, { signal });

    function endPointer(event) {
      if (event.pointerType === 'mouse') {
        if (mouseDrag && !mouseDrag.moved) selectAt(event.clientX, event.clientY);
        mouseDrag = null;
        hoverPoint = { x: event.clientX, y: event.clientY };
        return;
      }
      const point = pointerState.get(event.pointerId);
      if (point && pointerState.size === 1 && !point.moved) selectAt(event.clientX, event.clientY);
      pointerState.delete(event.pointerId);
      touchGesture = pointerState.size === 2 ? pairMetrics() : null;
    }
    canvas.addEventListener('pointerup', endPointer, { signal });
    canvas.addEventListener('pointercancel', endPointer, { signal });
    canvas.addEventListener('pointerleave', event => {
      if (event.pointerType === 'mouse' && !mouseDrag) hoverPoint = null;
    }, { signal });
    canvas.addEventListener('wheel', event => {
      event.preventDefault();
      zoomBy(Math.exp(event.deltaY * 0.0012));
    }, { passive: false, signal });
    canvas.addEventListener('contextmenu', event => event.preventDefault(), { signal });

    const resizeObserver = typeof ResizeObserver === 'function' ? new ResizeObserver(requestRender) : null;
    if (resizeObserver) resizeObserver.observe(host);
    else window.addEventListener('resize', requestRender, { signal });

    view = {
      THREE,
      scene,
      camera,
      renderer,
      host,
      controls,
      materials,
      geometries: [slotGeometry, slotEdges, palletGeometry, palletEdges],
      lineMaterials: [usableLineMaterial, blockedLineMaterial, palletLineMaterial, selectedLineMaterial, floor.material],
      helperGeometries: [floor.geometry],
      abortController,
      resizeObserver,
      selectPallet,
      setTransparency(value) {
        transparency = clamp(Number(value), 10, 85);
        materials.forEach(material => { material.opacity = 1 - transparency / 100; });
        requestRender();
      },
      reset() {
        controls.target.copy(controls.initialTarget);
        controls.yaw = controls.initialYaw;
        controls.pitch = controls.initialPitch;
        controls.distance = controls.initialDistance;
        updateCamera();
      }
    };
    updateCamera();
    selectPallet(selectedPalletNo, false);
    return { palletCount: palletObjects.length };
  }

  function close() {
    lifecycleToken += 1;
    disposeView();
  }

  function disposeView() {
    if (!view) return;
    view.abortController.abort();
    if (view.resizeObserver) view.resizeObserver.disconnect();
    view.scene.clear();
    view.geometries.forEach(item => item.dispose());
    view.helperGeometries.forEach(item => item.dispose());
    view.materials.forEach(item => item.dispose());
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
    return {
      x: col - (cols + 1) / 2,
      y: (level - 1) * unitY,
      z: row - (rows + 1) / 2
    };
  }

  function clamp(value, min, max) {
    return Math.min(max, Math.max(min, Number.isFinite(value) ? value : min));
  }

  window.GarlicInventory3D = { open, close, reset, setTransparency };
}());
