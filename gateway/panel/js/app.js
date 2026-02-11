// TAGUATO-SEND Panel Application
const App = (() => {
  let currentUser = null;
  let instances = [];
  let dashboardTimer = null;
  let cachedTemplates = [];
  let cachedContactLists = [];
  let currentMsgType = 'text';
  let historyPage = 1;
  let auditPage = 1;
  let cachedAuditLogs = [];
  let emojiPickerTarget = null;
  let emojiPickerCategory = 0;

  const EMOJI_DATA = [
    { icon: '\u{1F600}', name: 'Caras', emojis: ['\u{1F600}','\u{1F603}','\u{1F604}','\u{1F601}','\u{1F606}','\u{1F605}','\u{1F602}','\u{1F923}','\u{1F60A}','\u{1F607}','\u{1F642}','\u{1F643}','\u{1F609}','\u{1F60C}','\u{1F60D}','\u{1F970}','\u{1F618}','\u{1F617}','\u{1F619}','\u{1F61A}','\u{1F60B}','\u{1F61B}','\u{1F61C}','\u{1F92A}','\u{1F61D}','\u{1F911}','\u{1F917}','\u{1F92D}','\u{1F92B}','\u{1F914}','\u{1F910}','\u{1F928}','\u{1F610}','\u{1F611}','\u{1F636}','\u{1F60F}','\u{1F612}','\u{1F644}','\u{1F62C}','\u{1F925}','\u{1F614}','\u{1F61E}','\u{1F61F}','\u{1F615}','\u{1F641}','\u{2639}','\u{1F623}','\u{1F616}','\u{1F62B}','\u{1F629}','\u{1F622}','\u{1F62D}','\u{1F624}','\u{1F620}','\u{1F621}','\u{1F973}','\u{1F974}','\u{1F976}','\u{1F975}'] },
    { icon: '\u{1F44D}', name: 'Gestos', emojis: ['\u{1F44D}','\u{1F44E}','\u{1F44A}','\u{270A}','\u{1F91B}','\u{1F91C}','\u{1F44F}','\u{1F64C}','\u{1F450}','\u{1F932}','\u{1F91D}','\u{1F64F}','\u{270D}','\u{1F485}','\u{1F933}','\u{1F4AA}','\u{1F44B}','\u{1F91A}','\u{1F590}','\u{270B}','\u{1F596}','\u{1F44C}','\u{270C}','\u{1F91E}','\u{1F91F}','\u{1F918}','\u{1F448}','\u{1F449}','\u{1F446}','\u{1F447}','\u{261D}','\u{1F595}'] },
    { icon: '\u{2764}', name: 'Simbolos', emojis: ['\u{2764}','\u{1F9E1}','\u{1F49B}','\u{1F49A}','\u{1F499}','\u{1F49C}','\u{1F5A4}','\u{1F494}','\u{2763}','\u{1F495}','\u{1F49E}','\u{1F493}','\u{1F497}','\u{1F496}','\u{1F498}','\u{1F49D}','\u{2B50}','\u{1F31F}','\u{1F4AB}','\u{2728}','\u{1F525}','\u{1F4A5}','\u{1F389}','\u{1F388}','\u{1F381}','\u{1F3C6}','\u{1F947}','\u{1F4AF}','\u{2705}','\u{274C}','\u{2757}','\u{2753}'] },
    { icon: '\u{1F436}', name: 'Animales', emojis: ['\u{1F436}','\u{1F431}','\u{1F42D}','\u{1F439}','\u{1F430}','\u{1F98A}','\u{1F43B}','\u{1F43C}','\u{1F428}','\u{1F42F}','\u{1F981}','\u{1F42E}','\u{1F437}','\u{1F438}','\u{1F435}','\u{1F414}','\u{1F427}','\u{1F426}','\u{1F985}','\u{1F98B}','\u{1F41B}','\u{1F41D}','\u{1F422}','\u{1F40D}'] },
    { icon: '\u{1F34E}', name: 'Comida', emojis: ['\u{1F34E}','\u{1F34F}','\u{1F350}','\u{1F34A}','\u{1F34B}','\u{1F34C}','\u{1F349}','\u{1F347}','\u{1F353}','\u{1F348}','\u{1F352}','\u{1F351}','\u{1F34D}','\u{1F965}','\u{1F951}','\u{1F35E}','\u{1F950}','\u{1F32E}','\u{1F355}','\u{1F354}','\u{1F37F}','\u{1F366}','\u{1F370}','\u{1F382}','\u{2615}','\u{1F37A}','\u{1F377}'] }
  ];

  // --- Helpers ---
  function $(sel) { return document.querySelector(sel); }
  function $$(sel) { return document.querySelectorAll(sel); }

  function show(el) { el.classList.remove('hidden'); }
  function hide(el) { el.classList.add('hidden'); }

  function showToast(msg, type = 'success') {
    const toast = $('#toast');
    toast.textContent = msg;
    toast.className = 'toast toast-' + type;
    show(toast);
    setTimeout(() => hide(toast), 3500);
  }

  // --- Dark Mode ---
  function initTheme() {
    const saved = localStorage.getItem('taguato_theme');
    if (saved === 'dark') {
      document.documentElement.setAttribute('data-theme', 'dark');
    }
    updateThemeButton();
  }

  function toggleTheme() {
    const current = document.documentElement.getAttribute('data-theme');
    if (current === 'dark') {
      document.documentElement.removeAttribute('data-theme');
      localStorage.setItem('taguato_theme', 'light');
    } else {
      document.documentElement.setAttribute('data-theme', 'dark');
      localStorage.setItem('taguato_theme', 'dark');
    }
    updateThemeButton();
  }

  function updateThemeButton() {
    const btn = $('#btn-theme-toggle');
    if (!btn) return;
    const isDark = document.documentElement.getAttribute('data-theme') === 'dark';
    btn.innerHTML = isDark ? '\u2600\uFE0F Tema Claro' : '\uD83C\uDF19 Tema Oscuro';
  }

  // --- Navigation ---
  function navigate(section) {
    $$('.section').forEach(s => hide(s));
    $$('.nav-link').forEach(n => n.classList.remove('active'));
    const target = $('#section-' + section);
    if (target) show(target);
    const navLink = $(`.nav-link[data-section="${section}"]`);
    if (navLink) navLink.classList.add('active');

    // Clear dashboard auto-refresh when leaving
    if (dashboardTimer) { clearInterval(dashboardTimer); dashboardTimer = null; }

    if (section === 'dashboard') {
      loadDashboard();
      dashboardTimer = setInterval(loadDashboard, 30000);
    }
    if (section === 'instances') loadInstances();
    if (section === 'messages') loadMessageSection();
    if (section === 'templates') loadTemplates();
    if (section === 'contacts') loadContactLists();
    if (section === 'history') { historyPage = 1; loadHistory(); }
    if (section === 'sessions') loadSessions();
    if (section === 'docs') renderDocs();
    if (section === 'admin') loadUsers();
    if (section === 'audit') { auditPage = 1; loadAuditLogs(); }
    if (section === 'backup') loadBackups();
    if (section === 'status') loadStatusSection();
  }

  // --- Auth ---
  async function handleLogin(e) {
    e.preventDefault();
    const btn = $('#login-btn');
    btn.disabled = true;
    btn.textContent = 'Ingresando...';
    try {
      const data = await API.login($('#login-user').value, $('#login-pass').value);
      currentUser = data.user;
      if (currentUser.must_change_password) {
        showChangePassword();
      } else {
        showApp();
      }
    } catch (err) {
      showToast(err.message || 'Error al iniciar sesion', 'error');
    } finally {
      btn.disabled = false;
      btn.textContent = 'Ingresar';
    }
  }

  function logout() {
    API.logout();
    currentUser = null;
    instances = [];
    docsRendered = false;
    showLogin();
  }

  function showLogin() {
    hide($('#app'));
    hide($('#change-password-screen'));
    show($('#login-screen'));
    $('#login-user').value = '';
    $('#login-pass').value = '';
    $('#login-user').focus();
  }

  function showChangePassword() {
    hide($('#login-screen'));
    hide($('#app'));
    show($('#change-password-screen'));
    $('#cp-current').value = '';
    $('#cp-new').value = '';
    $('#cp-confirm').value = '';
    $('#cp-current').focus();
  }

  async function handleChangePassword(e) {
    e.preventDefault();
    const currentPass = $('#cp-current').value;
    const newPass = $('#cp-new').value;
    const confirmPass = $('#cp-confirm').value;

    if (newPass !== confirmPass) {
      showToast('Las contrasenas nuevas no coinciden', 'error');
      return;
    }

    if (newPass.length < 6) {
      showToast('La nueva contrasena debe tener al menos 6 caracteres', 'error');
      return;
    }

    const btn = $('#cp-btn');
    btn.disabled = true;
    btn.textContent = 'Cambiando...';
    try {
      await API.changePassword(currentPass, newPass);
      currentUser.must_change_password = false;
      showToast('Contrasena cambiada exitosamente');
      showApp();
    } catch (err) {
      showToast(err.message || 'Error al cambiar contrasena', 'error');
    } finally {
      btn.disabled = false;
      btn.textContent = 'Cambiar Contrasena';
    }
  }

  function showApp() {
    hide($('#login-screen'));
    hide($('#change-password-screen'));
    show($('#app'));
    $('#user-display').textContent = currentUser.username;

    // Show/hide admin nav
    const adminNav = $('#nav-admin');
    const statusNav = $('#nav-status');
    const dashboardNav = $('#nav-dashboard');
    const auditNav = $('#nav-audit');
    const backupNav = $('#nav-backup');
    if (currentUser.role === 'admin') {
      show(adminNav);
      show(statusNav);
      show(dashboardNav);
      show(auditNav);
      show(backupNav);
    } else {
      hide(adminNav);
      hide(statusNav);
      hide(dashboardNav);
      hide(auditNav);
      hide(backupNav);
    }
    navigate(currentUser.role === 'admin' ? 'dashboard' : 'instances');
  }

  // --- Instances ---
  async function loadInstances() {
    const list = $('#instances-list');
    list.innerHTML = '<div class="loading">Cargando instancias...</div>';
    try {
      const data = await API.fetchInstances();
      // Evolution API returns an array of instances
      instances = Array.isArray(data) ? data : [];
      renderInstances();
    } catch (err) {
      list.innerHTML = '<div class="empty">Error al cargar instancias</div>';
    }
  }

  function renderInstances() {
    const list = $('#instances-list');
    if (instances.length === 0) {
      list.innerHTML = '<div class="empty">No hay instancias. Crea una nueva.</div>';
      return;
    }
    list.innerHTML = instances.map(inst => {
      const name = inst.instance?.instanceName || inst.name || inst.instanceName || 'Unknown';
      const state = inst.instance?.state || inst.connectionStatus || inst.state || 'unknown';
      const stateClass = state === 'open' ? 'connected' : (state === 'connecting' ? 'connecting' : 'disconnected');
      const stateLabel = state === 'open' ? 'Conectado' : (state === 'connecting' ? 'Conectando' : 'Desconectado');
      return `
        <div class="card instance-card">
          <div class="instance-info">
            <h3>${esc(name)}</h3>
            <span class="badge badge-${stateClass}">${stateLabel}</span>
          </div>
          <div class="instance-actions">
            ${state !== 'open' ? `<button class="btn btn-sm btn-primary" onclick="App.connectInstance('${esc(name)}')">Conectar</button>` : ''}
            <button class="btn btn-sm btn-danger" onclick="App.confirmDeleteInstance('${esc(name)}')">Eliminar</button>
          </div>
        </div>`;
    }).join('');
  }

  async function handleCreateInstance(e) {
    e.preventDefault();
    const input = $('#new-instance-name');
    const name = input.value.trim();
    if (!name) return;
    try {
      await API.createInstance(name);
      input.value = '';
      showToast('Instancia creada');
      loadInstances();
    } catch (err) {
      showToast(err.message || 'Error al crear instancia', 'error');
    }
  }

  async function connectInstance(name) {
    const modal = $('#qr-modal');
    const content = $('#qr-content');
    content.innerHTML = '<div class="loading">Obteniendo QR...</div>';
    show(modal);
    try {
      const data = await API.connectInstance(name);
      if (data.base64) {
        content.innerHTML = `
          <p>Escanea el QR con WhatsApp:</p>
          <img src="${data.base64}" alt="QR Code" class="qr-img" />
          <p class="hint">El QR expira en ~40 segundos</p>`;
      } else if (data.pairingCode) {
        content.innerHTML = `
          <p>Codigo de vinculacion:</p>
          <div class="pairing-code">${esc(data.pairingCode)}</div>`;
      } else if (data.instance?.state === 'open') {
        content.innerHTML = '<p class="success-msg">Instancia ya conectada</p>';
      } else {
        content.innerHTML = `<pre>${esc(JSON.stringify(data, null, 2))}</pre>`;
      }
    } catch (err) {
      content.innerHTML = `<p class="error-msg">${esc(err.message || 'Error al conectar')}</p>`;
    }
  }

  function confirmDeleteInstance(name) {
    if (confirm('Eliminar instancia "' + name + '"? Esta accion no se puede deshacer.')) {
      deleteInstance(name);
    }
  }

  async function deleteInstance(name) {
    try {
      await API.deleteInstance(name);
      showToast('Instancia eliminada');
      loadInstances();
    } catch (err) {
      showToast(err.message || 'Error al eliminar', 'error');
    }
  }

  // --- Messages ---
  function loadMessageSection() {
    loadInstanceSelect();
    loadTemplateSelects();
    // Reset bulk progress on section load
    hide($('#bulk-progress-zone'));
  }

  function loadInstanceSelect() {
    const selectors = ['#msg-instance', '#bulk-instance'];
    selectors.forEach(selId => {
      const sel = $(selId);
      if (!sel) return;
      sel.innerHTML = '<option value="">Seleccionar instancia...</option>';
      instances.forEach(inst => {
        const name = inst.instance?.instanceName || inst.name || inst.instanceName || '';
        if (name) {
          sel.innerHTML += `<option value="${esc(name)}">${esc(name)}</option>`;
        }
      });
    });
  }

  function setMsgType(type) {
    currentMsgType = type;
    $$('.msg-type-btn').forEach(b => {
      b.classList.toggle('active', b.dataset.type === type);
      b.classList.toggle('btn-primary', b.dataset.type === type);
      b.classList.toggle('btn-secondary', b.dataset.type !== type);
    });
    const mediaFields = $('#msg-media-fields');
    const textLabelSpan = $('#msg-text-label-text');
    if (type === 'media') {
      show(mediaFields);
      textLabelSpan.textContent = 'Caption (opcional)';
      $('#msg-text').removeAttribute('required');
    } else {
      hide(mediaFields);
      textLabelSpan.textContent = 'Mensaje';
      $('#msg-text').setAttribute('required', 'required');
    }
  }

  function readFileAsBase64(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result);
      reader.onerror = reject;
      reader.readAsDataURL(file);
    });
  }

  async function handleSendMessage(e) {
    e.preventDefault();
    const instanceName = $('#msg-instance').value;
    const number = $('#msg-number').value.trim();
    const text = $('#msg-text').value.trim();

    if (!instanceName || !number) {
      showToast('Completa instancia y numero', 'error');
      return;
    }

    const btn = $('#msg-send-btn');
    btn.disabled = true;

    try {
      if (currentMsgType === 'media') {
        const mediaType = $('#msg-media-type').value;
        let media = $('#msg-media-url').value.trim();
        const fileInput = $('#msg-media-file');
        const fileName = $('#msg-media-filename').value.trim();

        if (!media && fileInput.files.length > 0) {
          const file = fileInput.files[0];
          if (file.size > 10 * 1024 * 1024) {
            showToast('Archivo demasiado grande (max 10MB)', 'error');
            btn.disabled = false;
            return;
          }
          media = await readFileAsBase64(file);
        }

        if (!media) {
          showToast('Ingresa una URL o sube un archivo', 'error');
          btn.disabled = false;
          return;
        }

        await API.sendMedia(instanceName, number, mediaType, media, text, fileName || undefined);
        showToast('Media enviado');
        API.logMessage(instanceName, number, mediaType, 'sent').catch(() => {});
      } else {
        if (!text) {
          showToast('Escribe un mensaje', 'error');
          btn.disabled = false;
          return;
        }
        await API.sendText(instanceName, number, text);
        showToast('Mensaje enviado');
        API.logMessage(instanceName, number, 'text', 'sent').catch(() => {});
      }
      $('#msg-text').value = '';
      $('#msg-media-url').value = '';
      $('#msg-media-file').value = '';
      $('#msg-media-filename').value = '';
    } catch (err) {
      showToast(err.message || 'Error al enviar', 'error');
      const msgType = currentMsgType === 'media' ? $('#msg-media-type').value : 'text';
      API.logMessage(instanceName, number, msgType, 'failed', err.message).catch(() => {});
    } finally {
      btn.disabled = false;
    }
  }

  // --- Bulk Messaging ---
  async function handleBulkMessage(e) {
    e.preventDefault();
    const instanceName = $('#bulk-instance').value;
    const numbersRaw = $('#bulk-numbers').value.trim();
    const text = $('#bulk-text').value.trim();

    if (!instanceName || !numbersRaw || !text) {
      showToast('Completa todos los campos', 'error');
      return;
    }

    const numbers = numbersRaw.split('\n').map(n => n.trim()).filter(n => n);
    if (numbers.length === 0) {
      showToast('Ingresa al menos un numero', 'error');
      return;
    }
    if (numbers.length > 500) {
      showToast('Maximo 500 numeros permitidos', 'error');
      return;
    }

    const btn = $('#bulk-send-btn');
    btn.disabled = true;
    btn.textContent = 'Enviando...';

    const progressZone = $('#bulk-progress-zone');
    const progressFill = $('#bulk-progress-fill');
    const progressText = $('#bulk-progress-text');
    const resultsDiv = $('#bulk-results');
    const failedDiv = $('#bulk-failed-details');
    const cancelBtn = $('#bulk-cancel-btn');
    cancelBtn.disabled = false;
    cancelBtn.textContent = 'Cancelar';
    show(progressZone);
    progressFill.style.width = '0%';
    progressText.textContent = '0 / ' + numbers.length;
    resultsDiv.innerHTML = '';
    failedDiv.innerHTML = '';

    try {
      const results = await API.sendBulkText(instanceName, numbers, text, (sent, res) => {
        const pct = Math.round((sent / numbers.length) * 100);
        progressFill.style.width = pct + '%';
        progressText.textContent = sent + ' / ' + numbers.length;

        const sentCount = res.filter(r => r.status === 'sent').length;
        const failedCount = res.filter(r => r.status === 'failed').length;
        const cancelledCount = res.filter(r => r.status === 'cancelled').length;
        const skippedCount = res.filter(r => r.status === 'skipped').length;
        resultsDiv.innerHTML =
          `<span class="bulk-sent">Enviados: ${sentCount}</span>` +
          `<span class="bulk-failed">Fallidos: ${failedCount}</span>` +
          (cancelledCount > 0 ? `<span class="bulk-skipped">Cancelados: ${cancelledCount}</span>` : '') +
          (skippedCount > 0 ? `<span class="bulk-skipped">Omitidos: ${skippedCount}</span>` : '');
      });

      const failed = results.filter(r => r.status === 'failed');
      if (failed.length > 0) {
        failedDiv.innerHTML = `
          <details class="bulk-failed-details">
            <summary>Ver ${failed.length} numero(s) fallido(s)</summary>
            <ul class="failed-list">
              ${failed.map(f => `<li><strong>${esc(f.number)}</strong>: ${esc(f.error)}</li>`).join('')}
            </ul>
          </details>`;
      }

      // Log bulk results
      for (const r of results) {
        if (r.status !== 'skipped') {
          API.logMessage(instanceName, r.number, 'text', r.status === 'sent' ? 'sent' : (r.status === 'cancelled' ? 'cancelled' : 'failed'), r.error || null).catch(() => {});
        }
      }

      const sentCount = results.filter(r => r.status === 'sent').length;
      const wasCancelled = results.some(r => r.status === 'cancelled');
      showToast(`Envio masivo ${wasCancelled ? 'cancelado' : 'completado'}: ${sentCount}/${numbers.length} enviados`);
    } catch (err) {
      showToast(err.message || 'Error en envio masivo', 'error');
    } finally {
      btn.disabled = false;
      btn.textContent = 'Enviar Masivo';
      cancelBtn.disabled = true;
    }
  }

  // --- Templates ---
  async function loadTemplates() {
    const list = $('#templates-list');
    list.innerHTML = '<div class="loading">Cargando plantillas...</div>';
    try {
      const data = await API.listTemplates();
      cachedTemplates = data.templates || [];
      renderTemplates();
    } catch (err) {
      list.innerHTML = '<div class="empty">Error al cargar plantillas</div>';
    }
  }

  function renderTemplates() {
    const list = $('#templates-list');
    if (cachedTemplates.length === 0) {
      list.innerHTML = '<div class="empty">No hay plantillas. Crea una nueva.</div>';
      return;
    }
    list.innerHTML = cachedTemplates.map(t => `
      <div class="card instance-card" style="flex-direction:column;align-items:stretch;gap:0.5rem;">
        <div style="display:flex;justify-content:space-between;align-items:center;">
          <h3 style="font-size:0.95rem;">${esc(t.name)}</h3>
          <div class="instance-actions">
            <button class="btn btn-sm btn-secondary" onclick="App.editTemplate(${t.id})">Editar</button>
            <button class="btn btn-sm btn-danger" onclick="App.confirmDeleteTemplate(${t.id}, '${esc(t.name).replace(/'/g, "\\'")}')">Eliminar</button>
          </div>
        </div>
        <div style="font-size:0.85rem;color:var(--text-light);white-space:pre-wrap;">${esc(t.content)}</div>
      </div>
    `).join('');
  }

  async function handleCreateTemplate(e) {
    e.preventDefault();
    const name = $('#new-tpl-name').value.trim();
    const content = $('#new-tpl-content').value.trim();
    if (!name || !content) return;
    try {
      await API.createTemplate(name, content);
      showToast('Plantilla creada');
      $('#new-tpl-name').value = '';
      $('#new-tpl-content').value = '';
      loadTemplates();
    } catch (err) {
      showToast(err.message || 'Error al crear plantilla', 'error');
    }
  }

  function editTemplate(id) {
    const tpl = cachedTemplates.find(t => t.id === id);
    if (!tpl) return;
    $('#edit-tpl-id').value = id;
    $('#edit-tpl-name').value = tpl.name;
    $('#edit-tpl-content').value = tpl.content;
    show($('#edit-template-modal'));
  }

  async function handleUpdateTemplate(e) {
    e.preventDefault();
    const id = $('#edit-tpl-id').value;
    const name = $('#edit-tpl-name').value.trim();
    const content = $('#edit-tpl-content').value.trim();
    if (!name || !content) {
      showToast('Nombre y contenido son requeridos', 'error');
      return;
    }
    try {
      await API.updateTemplate(id, { name, content });
      showToast('Plantilla actualizada');
      closeModal('edit-template-modal');
      loadTemplates();
    } catch (err) {
      showToast(err.message || 'Error al actualizar', 'error');
    }
  }

  function confirmDeleteTemplate(id, name) {
    if (confirm('Eliminar plantilla "' + name + '"?')) {
      API.deleteTemplate(id)
        .then(() => { showToast('Plantilla eliminada'); loadTemplates(); })
        .catch(err => showToast(err.message || 'Error', 'error'));
    }
  }

  async function loadTemplateSelects() {
    try {
      const data = await API.listTemplates();
      cachedTemplates = data.templates || [];
    } catch { cachedTemplates = []; }

    const selectors = ['#msg-template', '#bulk-template'];
    selectors.forEach(selId => {
      const sel = $(selId);
      if (!sel) return;
      sel.innerHTML = '<option value="">Sin plantilla</option>';
      cachedTemplates.forEach(t => {
        sel.innerHTML += `<option value="${t.id}">${esc(t.name)}</option>`;
      });
    });
  }

  function handleTemplateSelect(selectId, textareaId) {
    const sel = $(selectId);
    if (!sel) return;
    sel.addEventListener('change', () => {
      const tpl = cachedTemplates.find(t => t.id === parseInt(sel.value));
      if (tpl) {
        $(textareaId).value = tpl.content;
      }
    });
  }

  // --- Contacts ---
  async function loadContactLists() {
    const container = $('#contact-lists-container');
    container.innerHTML = '<div class="loading">Cargando listas...</div>';
    try {
      const data = await API.listContactLists();
      cachedContactLists = data.lists || [];
      renderContactLists();
    } catch (err) {
      container.innerHTML = '<div class="empty">Error al cargar listas</div>';
    }
  }

  function renderContactLists() {
    const container = $('#contact-lists-container');
    if (cachedContactLists.length === 0) {
      container.innerHTML = '<div class="empty">No hay listas de contactos. Crea una nueva.</div>';
      return;
    }
    container.innerHTML = cachedContactLists.map(cl => `
      <div class="card instance-card">
        <div class="instance-info">
          <h3>${esc(cl.name)}</h3>
          <span class="badge badge-user">${cl.item_count || 0} contactos</span>
        </div>
        <div class="instance-actions">
          <button class="btn btn-sm btn-primary" onclick="App.viewContactList(${cl.id})">Ver</button>
          <button class="btn btn-sm btn-secondary" onclick="App.renameContactList(${cl.id}, '${esc(cl.name).replace(/'/g, "\\'")}')">Renombrar</button>
          <button class="btn btn-sm btn-danger" onclick="App.confirmDeleteContactList(${cl.id}, '${esc(cl.name).replace(/'/g, "\\'")}')">Eliminar</button>
        </div>
      </div>
    `).join('');
  }

  async function handleCreateContactList(e) {
    e.preventDefault();
    const name = $('#new-list-name').value.trim();
    if (!name) return;
    try {
      await API.createContactList(name);
      showToast('Lista creada');
      $('#new-list-name').value = '';
      loadContactLists();
    } catch (err) {
      showToast(err.message || 'Error al crear lista', 'error');
    }
  }

  async function viewContactList(id) {
    const container = $('#contact-lists-container');
    container.innerHTML = '<div class="loading">Cargando contactos...</div>';
    try {
      const data = await API.getContactList(id);
      const list = data.list;
      const items = list.items || [];
      container.innerHTML = `
        <div style="margin-bottom:1rem;">
          <button class="btn btn-sm btn-secondary" onclick="App.loadContactLists()">Volver a listas</button>
          <h3 style="display:inline;margin-left:0.5rem;">${esc(list.name)}</h3>
        </div>
        <form id="add-contact-form" class="inline-form" style="margin-bottom:1rem;">
          <input type="text" id="add-contact-phone" class="form-control" placeholder="595981123456" required>
          <input type="text" id="add-contact-label" class="form-control" placeholder="Etiqueta (opcional)">
          <button type="submit" class="btn btn-primary">Agregar</button>
        </form>
        <div id="contact-items-list">
          ${items.length === 0 ? '<div class="empty">Lista vacia. Agrega contactos.</div>' :
            '<table class="table"><thead><tr><th>Numero</th><th>Etiqueta</th><th>Acciones</th></tr></thead><tbody>' +
            items.map(item => `
              <tr>
                <td>${esc(item.phone_number)}</td>
                <td>${esc(item.label || '')}</td>
                <td><button class="btn btn-sm btn-danger" onclick="App.removeContactItem(${list.id}, ${item.id})">Quitar</button></td>
              </tr>`).join('') +
            '</tbody></table>'}
        </div>`;
      // Bind add contact form
      const addForm = $('#add-contact-form');
      if (addForm) {
        addForm.addEventListener('submit', async (e) => {
          e.preventDefault();
          const phone = $('#add-contact-phone').value.trim();
          if (!phone) return;
          const label = $('#add-contact-label').value.trim();
          try {
            await API.addContactItems(list.id, [{ phone_number: phone, label }]);
            showToast('Contacto agregado');
            viewContactList(list.id);
          } catch (err) {
            showToast(err.message || 'Error', 'error');
          }
        });
      }
    } catch (err) {
      container.innerHTML = '<div class="empty">Error al cargar lista</div>';
    }
  }

  function renameContactList(id, currentName) {
    const newName = prompt('Nuevo nombre:', currentName);
    if (!newName || newName === currentName) return;
    API.updateContactList(id, newName)
      .then(() => { showToast('Lista renombrada'); loadContactLists(); })
      .catch(err => showToast(err.message || 'Error', 'error'));
  }

  function confirmDeleteContactList(id, name) {
    if (confirm('Eliminar lista "' + name + '" y todos sus contactos?')) {
      API.deleteContactList(id)
        .then(() => { showToast('Lista eliminada'); loadContactLists(); })
        .catch(err => showToast(err.message || 'Error', 'error'));
    }
  }

  async function removeContactItem(listId, itemId) {
    try {
      await API.deleteContactItem(listId, itemId);
      showToast('Contacto eliminado');
      viewContactList(listId);
    } catch (err) {
      showToast(err.message || 'Error', 'error');
    }
  }

  async function openLoadContactsModal() {
    const list = $('#load-contacts-list');
    list.innerHTML = '<div class="loading">Cargando listas...</div>';
    show($('#load-contacts-modal'));
    try {
      const data = await API.listContactLists();
      const lists = data.lists || [];
      if (lists.length === 0) {
        list.innerHTML = '<div class="empty">No hay listas de contactos</div>';
        return;
      }
      list.innerHTML = lists.map(cl => `
        <div class="card instance-card" style="cursor:pointer;" onclick="App.loadContactsIntoNumbers(${cl.id})">
          <div class="instance-info">
            <h3>${esc(cl.name)}</h3>
            <span class="badge badge-user">${cl.item_count || 0} contactos</span>
          </div>
        </div>
      `).join('');
    } catch {
      list.innerHTML = '<div class="empty">Error al cargar listas</div>';
    }
  }

  async function loadContactsIntoNumbers(listId) {
    try {
      const data = await API.getContactList(listId);
      const items = data.list.items || [];
      const numbers = items.map(i => i.phone_number).join('\n');
      const textarea = $('#bulk-numbers');
      if (textarea.value.trim()) {
        textarea.value += '\n' + numbers;
      } else {
        textarea.value = numbers;
      }
      closeModal('load-contacts-modal');
      showToast(items.length + ' contactos cargados');
    } catch (err) {
      showToast(err.message || 'Error al cargar contactos', 'error');
    }
  }

  // --- History ---
  async function loadHistory() {
    const list = $('#history-list');
    const pagination = $('#history-pagination');
    list.innerHTML = '<div class="loading">Cargando historial...</div>';
    pagination.innerHTML = '';

    const params = { page: historyPage, limit: 50 };
    const status = $('#hist-status').value;
    const type = $('#hist-type').value;
    const from = $('#hist-from').value;
    const to = $('#hist-to').value;
    if (status) params.status = status;
    if (type) params.message_type = type;
    if (from) params.date_from = from + 'T00:00:00';
    if (to) params.date_to = to + 'T23:59:59';

    try {
      const data = await API.getMessageLogs(params);
      const logs = data.logs || [];
      if (logs.length === 0) {
        list.innerHTML = '<div class="empty">No hay registros</div>';
        return;
      }

      list.innerHTML = `
        <table class="table">
          <thead>
            <tr>
              <th>Fecha</th><th>Instancia</th><th>Numero</th><th>Tipo</th><th>Estado</th><th>Error</th>
            </tr>
          </thead>
          <tbody>
            ${logs.map(l => `
              <tr>
                <td>${formatDate(l.created_at)}</td>
                <td>${esc(l.instance_name)}</td>
                <td>${esc(l.phone_number)}</td>
                <td>${esc(l.message_type)}</td>
                <td><span class="badge badge-${l.status === 'sent' ? 'connected' : 'disconnected'}">${esc(l.status)}</span></td>
                <td style="max-width:150px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${esc(l.error_message || '')}</td>
              </tr>`).join('')}
          </tbody>
        </table>`;

      // Pagination
      if (data.pages > 1) {
        let html = '';
        for (let p = 1; p <= data.pages; p++) {
          html += `<button class="btn btn-sm ${p === data.page ? 'btn-primary' : 'btn-secondary'}" onclick="App.goHistoryPage(${p})">${p}</button>`;
        }
        pagination.innerHTML = html;
      }
    } catch (err) {
      list.innerHTML = '<div class="empty">Error al cargar historial</div>';
    }
  }

  function goHistoryPage(page) {
    historyPage = page;
    loadHistory();
  }

  // --- Sessions ---
  async function loadSessions() {
    const list = $('#sessions-list');
    list.innerHTML = '<div class="loading">Cargando sesiones...</div>';
    try {
      let sessions;
      if (currentUser && currentUser.role === 'admin') {
        const data = await API.listAllSessions();
        sessions = data.sessions || [];
      } else {
        const data = await API.listSessions();
        sessions = data.sessions || [];
      }
      if (sessions.length === 0) {
        list.innerHTML = '<div class="empty">No hay sesiones activas</div>';
        return;
      }
      const isAdmin = currentUser && currentUser.role === 'admin';
      list.innerHTML = `
        <table class="table">
          <thead>
            <tr>
              ${isAdmin ? '<th>Usuario</th>' : ''}
              <th>IP</th><th>User Agent</th><th>Ultima actividad</th><th>Acciones</th>
            </tr>
          </thead>
          <tbody>
            ${sessions.map(s => `
              <tr>
                ${isAdmin ? '<td>' + esc(s.username || '') + '</td>' : ''}
                <td>${esc(s.ip_address || '')}</td>
                <td style="max-width:200px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${esc(s.user_agent || '')}</td>
                <td>${formatDate(s.last_active)}</td>
                <td>
                  <button class="btn btn-sm btn-danger" onclick="App.revokeSessionAction(${s.id}, ${isAdmin})">Revocar</button>
                </td>
              </tr>`).join('')}
          </tbody>
        </table>`;
    } catch (err) {
      list.innerHTML = '<div class="empty">Error al cargar sesiones</div>';
    }
  }

  async function revokeSessionAction(id, isAdmin) {
    if (!confirm('Revocar esta sesion?')) return;
    try {
      if (isAdmin) {
        await API.revokeAnySession(id);
      } else {
        await API.revokeSession(id);
      }
      showToast('Sesion revocada');
      loadSessions();
    } catch (err) {
      showToast(err.message || 'Error al revocar sesion', 'error');
    }
  }

  // --- Dashboard ---
  async function loadDashboard() {
    if (!currentUser || currentUser.role !== 'admin') return;
    const cardsContainer = $('#dashboard-cards');
    const activityContainer = $('#dashboard-activity');
    cardsContainer.innerHTML = '<div class="loading">Cargando...</div>';
    activityContainer.innerHTML = '';

    try {
      const data = await API.getDashboard();

      cardsContainer.innerHTML = `
        <div class="dashboard-card">
          <div class="dash-value">${data.users.total}</div>
          <div class="dash-label">Usuarios</div>
          <div class="dash-sub">${data.users.active} activos</div>
        </div>
        <div class="dashboard-card">
          <div class="dash-value">${data.instances.connected}</div>
          <div class="dash-label">Instancias Conectadas</div>
          <div class="dash-sub">de ${data.instances.total_evolution} en Evolution</div>
        </div>
        <div class="dashboard-card dash-green">
          <div class="dash-value">${data.uptime_30d}%</div>
          <div class="dash-label">Uptime Global</div>
          <div class="dash-sub">ultimos 30 dias</div>
        </div>
        <div class="dashboard-card">
          <div class="dash-value">${data.instances.total_registered}</div>
          <div class="dash-label">Instancias Registradas</div>
          <div class="dash-sub">en base de datos</div>
        </div>`;

      const activity = data.recent_activity || [];
      if (activity.length === 0) {
        activityContainer.innerHTML = '<div class="empty">No hay actividad reciente</div>';
      } else {
        activityContainer.innerHTML = activity.map(a => {
          const isUser = a.type === 'user_created';
          const iconClass = isUser ? 'activity-icon-user' : 'activity-icon-instance';
          const iconText = isUser ? 'U' : 'I';
          const label = isUser ? 'Usuario creado' : 'Instancia creada';
          return `
            <div class="recent-activity-item">
              <div class="activity-icon ${iconClass}">${iconText}</div>
              <div class="activity-name">${esc(a.name)} <span style="color:var(--text-light);font-size:0.75rem;">(${label})</span></div>
              <div class="activity-time">${formatDate(a.created_at)}</div>
            </div>`;
        }).join('');
      }
      // Reconnections
      const reconnections = data.recent_reconnections || [];
      if (reconnections.length > 0) {
        activityContainer.innerHTML += `
          <div style="margin-top:1rem;padding-top:0.75rem;border-top:1px solid var(--border);">
            <div style="font-size:0.85rem;font-weight:600;color:var(--text-light);margin-bottom:0.5rem;">Reconexiones Recientes</div>
            ${reconnections.map(r => `
              <div class="recent-activity-item">
                <div class="activity-icon ${r.result === 'reconnected' ? 'activity-icon-instance' : 'activity-icon-user'}">R</div>
                <div class="activity-name">${esc(r.instance_name)} <span style="color:var(--text-light);font-size:0.75rem;">(${esc(r.result)})</span></div>
                <div class="activity-time">${formatDate(r.created_at)}</div>
              </div>`).join('')}
          </div>`;
      }
    } catch (err) {
      cardsContainer.innerHTML = '<div class="empty">Error al cargar dashboard</div>';
    }
  }

  // --- Audit ---
  async function loadAuditLogs() {
    if (!currentUser || currentUser.role !== 'admin') return;
    const list = $('#audit-list');
    const pagination = $('#audit-pagination');
    list.innerHTML = '<div class="loading">Cargando auditoria...</div>';
    pagination.innerHTML = '';

    const params = { page: auditPage, limit: 50 };
    const action = $('#audit-action').value;
    const username = $('#audit-username').value.trim();
    if (action) params.action = action;
    if (username) params.username = username;

    try {
      const data = await API.getAuditLogs(params);
      const logs = data.logs || [];
      if (logs.length === 0) {
        list.innerHTML = '<div class="empty">No hay registros de auditoria</div>';
        return;
      }

      // Store logs for detail modal access
      cachedAuditLogs = logs;

      list.innerHTML = `
        <table class="table">
          <thead>
            <tr>
              <th>Fecha</th><th>Usuario</th><th>Accion</th><th>Recurso</th><th>IP</th><th>Detalles</th>
            </tr>
          </thead>
          <tbody>
            ${logs.map((l, i) => `
              <tr>
                <td>${formatDate(l.created_at)}</td>
                <td>${esc(l.username || '-')}</td>
                <td><span class="badge badge-user">${esc(l.action)}</span></td>
                <td>${esc(l.resource_type || '')} ${l.resource_id ? '#' + esc(l.resource_id) : ''}</td>
                <td>${esc(l.ip_address || '')}</td>
                <td>${l.details ? `<span class="audit-detail-cell" onclick="App.showAuditDetail(${i})">${esc(JSON.stringify(l.details))}</span>` : ''}</td>
              </tr>`).join('')}
          </tbody>
        </table>`;

      if (data.pages > 1) {
        let html = '';
        for (let p = 1; p <= data.pages; p++) {
          html += `<button class="btn btn-sm ${p === data.page ? 'btn-primary' : 'btn-secondary'}" onclick="App.goAuditPage(${p})">${p}</button>`;
        }
        pagination.innerHTML = html;
      }
    } catch (err) {
      list.innerHTML = '<div class="empty">Error al cargar auditoria</div>';
    }
  }

  function showAuditDetail(index) {
    const log = cachedAuditLogs[index];
    if (!log) return;
    const content = $('#audit-detail-content');
    content.innerHTML = `
      <div class="audit-detail-grid">
        <span class="audit-detail-label">Fecha</span>
        <span class="audit-detail-value">${formatDate(log.created_at)}</span>
        <span class="audit-detail-label">Usuario</span>
        <span class="audit-detail-value">${esc(log.username || '-')}</span>
        <span class="audit-detail-label">Accion</span>
        <span class="audit-detail-value"><span class="badge badge-user">${esc(log.action)}</span></span>
        <span class="audit-detail-label">Recurso</span>
        <span class="audit-detail-value">${esc(log.resource_type || '')} ${log.resource_id ? '#' + esc(log.resource_id) : ''}</span>
        <span class="audit-detail-label">IP</span>
        <span class="audit-detail-value">${esc(log.ip_address || '')}</span>
      </div>
      ${log.details ? '<div class="audit-detail-json">' + esc(JSON.stringify(log.details, null, 2)) + '</div>' : ''}`;
    show($('#audit-detail-modal'));
  }

  function goAuditPage(page) {
    auditPage = page;
    loadAuditLogs();
  }

  // --- Backups ---
  async function loadBackups() {
    if (!currentUser || currentUser.role !== 'admin') return;
    const list = $('#backup-list');
    list.innerHTML = '<div class="loading">Cargando backups...</div>';
    try {
      const data = await API.listBackups();
      const backups = data.backups || [];
      if (backups.length === 0) {
        list.innerHTML = '<div class="empty">No hay backups disponibles</div>';
        return;
      }
      list.innerHTML = `
        <table class="table">
          <thead>
            <tr><th>Archivo</th><th>Tamano</th><th>Fecha</th></tr>
          </thead>
          <tbody>
            ${backups.map(b => `
              <tr>
                <td>${esc(b.filename)}</td>
                <td>${esc(b.size)}</td>
                <td>${esc(b.date)}</td>
              </tr>`).join('')}
          </tbody>
        </table>`;
    } catch (err) {
      list.innerHTML = '<div class="empty">Error al cargar backups</div>';
    }
  }

  async function handleCreateBackup() {
    const btn = $('#backup-create-btn');
    btn.disabled = true;
    btn.textContent = 'Creando backup...';
    try {
      const data = await API.createBackup();
      showToast('Backup creado: ' + data.filename);
      loadBackups();
    } catch (err) {
      showToast(err.message || 'Error al crear backup', 'error');
    } finally {
      btn.disabled = false;
      btn.textContent = 'Crear Backup Ahora';
    }
  }

  // --- Admin ---
  async function loadUsers() {
    if (!currentUser || currentUser.role !== 'admin') return;
    const list = $('#users-list');
    list.innerHTML = '<div class="loading">Cargando usuarios...</div>';
    try {
      const data = await API.listUsers();
      renderUsers(data.users || []);
    } catch (err) {
      list.innerHTML = '<div class="empty">Error al cargar usuarios</div>';
    }
  }

  function renderUsers(users) {
    const list = $('#users-list');
    if (users.length === 0) {
      list.innerHTML = '<div class="empty">No hay usuarios</div>';
      return;
    }
    list.innerHTML = `
      <table class="table">
        <thead>
          <tr>
            <th>ID</th><th>Usuario</th><th>Rol</th><th>Max Inst.</th><th>Rate Limit</th><th>Activo</th><th>Acciones</th>
          </tr>
        </thead>
        <tbody>
          ${users.map(u => `
            <tr>
              <td>${u.id}</td>
              <td>${esc(u.username)}</td>
              <td><span class="badge badge-${u.role === 'admin' ? 'admin' : 'user'}">${u.role}</span></td>
              <td>${u.max_instances}</td>
              <td>${u.rate_limit ? u.rate_limit + '/s' : '-'}</td>
              <td>${u.is_active ? 'Si' : 'No'}</td>
              <td>
                <button class="btn btn-sm btn-secondary" onclick="App.editUser(${u.id}, '${esc(u.username)}', '${u.role}', ${u.max_instances}, ${u.is_active}, ${u.rate_limit || 'null'})">Editar</button>
                ${u.id !== currentUser.id ? `<button class="btn btn-sm btn-danger" onclick="App.confirmDeleteUser(${u.id}, '${esc(u.username)}')">Eliminar</button>` : ''}
              </td>
            </tr>`).join('')}
        </tbody>
      </table>`;
  }

  async function handleCreateUser(e) {
    e.preventDefault();
    const username = $('#new-user-name').value.trim();
    const password = $('#new-user-pass').value.trim();
    const role = $('#new-user-role').value;
    const maxInst = parseInt($('#new-user-max').value) || 1;
    const rateVal = $('#new-user-rate').value.trim();
    const rateLimit = rateVal ? parseInt(rateVal) : null;
    if (!username || !password) {
      showToast('Username y password son requeridos', 'error');
      return;
    }
    try {
      await API.createUser(username, password, role, maxInst, rateLimit);
      showToast('Usuario creado');
      $('#new-user-name').value = '';
      $('#new-user-pass').value = '';
      $('#new-user-max').value = '1';
      $('#new-user-rate').value = '';
      loadUsers();
    } catch (err) {
      showToast(err.message || 'Error al crear usuario', 'error');
    }
  }

  function editUser(id, username, role, maxInstances, isActive, rateLimit) {
    const modal = $('#edit-user-modal');
    $('#edit-user-id').value = id;
    $('#edit-user-title').textContent = 'Editar: ' + username;
    $('#edit-user-role').value = role;
    $('#edit-user-max').value = maxInstances;
    $('#edit-user-rate').value = rateLimit || '';
    $('#edit-user-active').checked = isActive;
    $('#edit-user-pass').value = '';
    show(modal);
  }

  async function handleUpdateUser(e) {
    e.preventDefault();
    const id = $('#edit-user-id').value;
    const rateVal = $('#edit-user-rate').value.trim();
    const fields = {
      role: $('#edit-user-role').value,
      max_instances: parseInt($('#edit-user-max').value) || 1,
      is_active: $('#edit-user-active').checked,
      rate_limit: rateVal ? parseInt(rateVal) : null,
    };
    const newPass = $('#edit-user-pass').value.trim();
    if (newPass) fields.password = newPass;
    try {
      await API.updateUser(id, fields);
      showToast('Usuario actualizado');
      closeModal('edit-user-modal');
      loadUsers();
    } catch (err) {
      showToast(err.message || 'Error al actualizar', 'error');
    }
  }

  function confirmDeleteUser(id, username) {
    if (confirm('Eliminar usuario "' + username + '"?')) {
      doDeleteUser(id);
    }
  }

  async function doDeleteUser(id) {
    try {
      await API.deleteUser(id);
      showToast('Usuario eliminado');
      loadUsers();
    } catch (err) {
      showToast(err.message || 'Error al eliminar', 'error');
    }
  }

  // --- Status Admin ---
  async function loadStatusSection() {
    if (!currentUser || currentUser.role !== 'admin') return;
    loadStatusHealth();
    loadIncidentServices();
    loadIncidents();
    loadMaintenanceServices();
    loadMaintenances();
  }

  async function loadStatusHealth() {
    const container = $('#status-health-overview');
    container.innerHTML = '<div class="loading">Verificando servicios...</div>';
    try {
      const data = await API.getPublicStatus();
      container.innerHTML = (data.services || []).map(svc => {
        const st = svc.status || 'unknown';
        const label = st === 'operational' ? 'Operativo' :
                      st === 'degraded' ? 'Degradado' :
                      st === 'partial_outage' ? 'Parcial' : 'Caido';
        return `
          <div class="status-health-card">
            <span class="status-dot status-dot-${esc(st)}"></span>
            <div>
              <div class="svc-name">${esc(svc.name)}</div>
              <div class="svc-detail">${label} &middot; ${svc.response_time}ms</div>
            </div>
          </div>`;
      }).join('');
    } catch {
      container.innerHTML = '<div class="empty">Error al verificar servicios</div>';
    }
  }

  async function loadIncidentServices() {
    const container = $('#inc-services-checkboxes');
    try {
      const data = await API.listIncidentServices();
      container.innerHTML = (data.services || []).map(svc => `
        <label>
          <input type="checkbox" name="inc-svc" value="${svc.id}">
          ${esc(svc.name)}
        </label>
      `).join('');
    } catch {
      container.innerHTML = '<span style="color:var(--text-light);font-size:0.85rem;">Error cargando servicios</span>';
    }
  }

  async function loadIncidents() {
    const activeList = $('#active-incidents-list');
    const pastList = $('#past-incidents-list');
    activeList.innerHTML = '<div class="loading">Cargando...</div>';
    pastList.innerHTML = '';
    try {
      const data = await API.listIncidents();
      const incidents = data.incidents || [];
      const active = incidents.filter(i => i.status !== 'resolved');
      const past = incidents.filter(i => i.status === 'resolved');

      if (active.length === 0) {
        activeList.innerHTML = '<div class="empty">No hay incidentes activos</div>';
      } else {
        activeList.innerHTML = active.map(renderIncidentCard).join('');
      }

      if (past.length === 0) {
        pastList.innerHTML = '<div class="empty">No hay incidentes resueltos</div>';
      } else {
        pastList.innerHTML = past.map(renderIncidentCard).join('');
      }
    } catch {
      activeList.innerHTML = '<div class="empty">Error al cargar incidentes</div>';
    }
  }

  function renderIncidentCard(inc) {
    const svcs = (inc.affected_services || []).map(s =>
      `<span class="incident-svc-tag">${esc(s.name)}</span>`
    ).join('');

    const updates = (inc.updates || []).map(u => `
      <div class="incident-timeline-item">
        <div class="tl-header">
          <span class="badge badge-status-${esc(u.status)}">${esc(u.status)}</span>
          <span class="tl-time">${formatDate(u.created_at)}${u.created_by_name ? ' - ' + esc(u.created_by_name) : ''}</span>
        </div>
        <div class="tl-message">${esc(u.message)}</div>
      </div>
    `).join('');

    const actions = inc.status !== 'resolved' ? `
      <button class="btn btn-sm btn-primary" onclick="App.openIncidentUpdate(${inc.id})">Agregar Update</button>
      <button class="btn btn-sm btn-danger" onclick="App.confirmDeleteIncident(${inc.id}, '${esc(inc.title)}')">Eliminar</button>
    ` : `
      <button class="btn btn-sm btn-danger" onclick="App.confirmDeleteIncident(${inc.id}, '${esc(inc.title)}')">Eliminar</button>
    `;

    return `
      <div class="incident-card">
        <div class="incident-card-header">
          <h4>${esc(inc.title)}</h4>
          <div class="incident-card-meta">
            <span class="badge badge-severity-${esc(inc.severity)}">${esc(inc.severity)}</span>
            <span class="badge badge-status-${esc(inc.status)}">${esc(inc.status)}</span>
          </div>
        </div>
        ${svcs ? '<div class="incident-services-tags">' + svcs + '</div>' : ''}
        <div class="incident-timeline">${updates}</div>
        <div class="incident-card-actions">${actions}</div>
      </div>`;
  }

  function formatDate(dateStr) {
    if (!dateStr) return '';
    const d = new Date(dateStr);
    return d.toLocaleDateString('es', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });
  }

  async function handleCreateIncident(e) {
    e.preventDefault();
    const title = $('#inc-title').value.trim();
    const severity = $('#inc-severity').value;
    const status = $('#inc-status').value;
    const message = $('#inc-message').value.trim();
    const serviceIds = Array.from($$('input[name="inc-svc"]:checked')).map(cb => parseInt(cb.value));

    if (!title || !message) {
      showToast('Titulo y mensaje son requeridos', 'error');
      return;
    }

    try {
      await API.createIncident(title, severity, status, message, serviceIds);
      showToast('Incidente creado');
      $('#inc-title').value = '';
      $('#inc-message').value = '';
      $$('input[name="inc-svc"]:checked').forEach(cb => { cb.checked = false; });
      loadIncidents();
      loadStatusHealth();
    } catch (err) {
      showToast(err.message || 'Error al crear incidente', 'error');
    }
  }

  function openIncidentUpdate(incidentId) {
    $('#iu-incident-id').value = incidentId;
    $('#iu-status').value = 'investigating';
    $('#iu-message').value = '';
    show($('#incident-update-modal'));
  }

  async function handleIncidentUpdate(e) {
    e.preventDefault();
    const incidentId = $('#iu-incident-id').value;
    const status = $('#iu-status').value;
    const message = $('#iu-message').value.trim();
    if (!message) {
      showToast('El mensaje es requerido', 'error');
      return;
    }
    try {
      await API.addIncidentUpdate(incidentId, status, message);
      showToast('Update agregado');
      closeModal('incident-update-modal');
      loadIncidents();
      if (status === 'resolved') loadStatusHealth();
    } catch (err) {
      showToast(err.message || 'Error al agregar update', 'error');
    }
  }

  function confirmDeleteIncident(id, title) {
    if (confirm('Eliminar incidente "' + title + '"? Esta accion no se puede deshacer.')) {
      doDeleteIncident(id);
    }
  }

  async function doDeleteIncident(id) {
    try {
      await API.deleteIncident(id);
      showToast('Incidente eliminado');
      loadIncidents();
    } catch (err) {
      showToast(err.message || 'Error al eliminar', 'error');
    }
  }

  // --- Maintenance Admin ---
  async function loadMaintenanceServices() {
    const container = $('#maint-services-checkboxes');
    try {
      const data = await API.listIncidentServices();
      container.innerHTML = (data.services || []).map(svc => `
        <label>
          <input type="checkbox" name="maint-svc" value="${svc.id}">
          ${esc(svc.name)}
        </label>
      `).join('');
    } catch {
      container.innerHTML = '<span style="color:var(--text-light);font-size:0.85rem;">Error cargando servicios</span>';
    }
  }

  async function loadMaintenances() {
    const list = $('#maintenance-list');
    list.innerHTML = '<div class="loading">Cargando...</div>';
    try {
      const data = await API.listMaintenances();
      const items = data.maintenances || [];
      if (items.length === 0) {
        list.innerHTML = '<div class="empty">No hay mantenimientos programados</div>';
        return;
      }
      list.innerHTML = items.map(renderMaintenanceCard).join('');
    } catch {
      list.innerHTML = '<div class="empty">Error al cargar mantenimientos</div>';
    }
  }

  function renderMaintenanceCard(m) {
    const svcs = (m.affected_services || []).map(s =>
      `<span class="incident-svc-tag">${esc(s.name)}</span>`
    ).join('');

    const statusLabel = m.status === 'scheduled' ? 'Programado' :
                        m.status === 'in_progress' ? 'En progreso' : 'Completado';

    let actions = '';
    if (m.status === 'scheduled') {
      actions += `<button class="btn btn-sm btn-primary" onclick="App.startMaintenance(${m.id})">Iniciar</button>`;
    }
    if (m.status === 'in_progress') {
      actions += `<button class="btn btn-sm btn-primary" onclick="App.completeMaintenance(${m.id})">Completar</button>`;
    }
    actions += `<button class="btn btn-sm btn-danger" onclick="App.confirmDeleteMaintenance(${m.id}, '${esc(m.title)}')">Eliminar</button>`;

    return `
      <div class="maintenance-card">
        <div class="maintenance-card-header">
          <h4>${esc(m.title)}</h4>
          <div class="maintenance-card-meta">
            <span class="badge badge-maint-${esc(m.status)}">${esc(statusLabel)}</span>
          </div>
        </div>
        <div class="maintenance-card-details">
          ${m.description ? '<p>' + esc(m.description) + '</p>' : ''}
          <div class="maint-dates">Inicio: ${formatDate(m.scheduled_start)} &mdash; Fin: ${formatDate(m.scheduled_end)}</div>
        </div>
        ${svcs ? '<div class="incident-services-tags">' + svcs + '</div>' : ''}
        <div class="maintenance-card-actions">${actions}</div>
      </div>`;
  }

  async function handleCreateMaintenance(e) {
    e.preventDefault();
    const title = $('#maint-title').value.trim();
    const description = $('#maint-desc').value.trim();
    const scheduledStart = $('#maint-start').value;
    const scheduledEnd = $('#maint-end').value;
    const serviceIds = Array.from($$('input[name="maint-svc"]:checked')).map(cb => parseInt(cb.value));

    if (!title || !scheduledStart || !scheduledEnd) {
      showToast('Titulo, fecha inicio y fecha fin son requeridos', 'error');
      return;
    }

    try {
      await API.createMaintenance(title, description, scheduledStart, scheduledEnd, serviceIds);
      showToast('Mantenimiento creado');
      $('#maint-title').value = '';
      $('#maint-desc').value = '';
      $('#maint-start').value = '';
      $('#maint-end').value = '';
      $$('input[name="maint-svc"]:checked').forEach(cb => { cb.checked = false; });
      loadMaintenances();
    } catch (err) {
      showToast(err.message || 'Error al crear mantenimiento', 'error');
    }
  }

  async function startMaintenance(id) {
    try {
      await API.updateMaintenance(id, { status: 'in_progress' });
      showToast('Mantenimiento iniciado');
      loadMaintenances();
    } catch (err) {
      showToast(err.message || 'Error al iniciar mantenimiento', 'error');
    }
  }

  async function completeMaintenance(id) {
    try {
      await API.updateMaintenance(id, { status: 'completed' });
      showToast('Mantenimiento completado');
      loadMaintenances();
    } catch (err) {
      showToast(err.message || 'Error al completar mantenimiento', 'error');
    }
  }

  function confirmDeleteMaintenance(id, title) {
    if (confirm('Eliminar mantenimiento "' + title + '"?')) {
      doDeleteMaintenance(id);
    }
  }

  async function doDeleteMaintenance(id) {
    try {
      await API.deleteMaintenance(id);
      showToast('Mantenimiento eliminado');
      loadMaintenances();
    } catch (err) {
      showToast(err.message || 'Error al eliminar', 'error');
    }
  }

  // --- API Docs ---
  let docsRendered = false;

  function renderDocs() {
    if (docsRendered) return;
    docsRendered = true;

    $('#docs-base-url').textContent = window.location.origin;

    const container = $('#docs-content');
    const isAdmin = currentUser && currentUser.role === 'admin';

    container.innerHTML = DOCS_DATA
      .filter(group => !group.adminOnly || isAdmin)
      .map((group, gi) => `
        <div class="docs-group">
          <div class="docs-group-header" onclick="App.toggleDocsGroup(this)">
            <div>
              <h3>${esc(group.tag)}</h3>
              <p>${esc(group.description)}</p>
            </div>
            <span class="docs-chevron">&#9660;</span>
          </div>
          <div class="docs-group-body">
            ${group.endpoints.map((ep, ei) => renderEndpoint(ep, gi, ei)).join('')}
          </div>
        </div>
      `).join('');
  }

  function renderEndpoint(ep, gi, ei) {
    const methodClass = ep.method.toLowerCase();
    const id = `docs-ep-${gi}-${ei}`;
    const hasParams = ep.params && ep.params.length > 0;
    const hasBody = ep.body;
    const hasResponse = ep.response;

    return `
      <div class="docs-endpoint docs-method-${methodClass}">
        <div class="docs-endpoint-header" onclick="App.toggleEndpoint('${id}')">
          <span class="docs-method-badge docs-badge-${methodClass}">${ep.method}</span>
          <span class="docs-path">${esc(ep.path)}</span>
          <span class="docs-summary">${esc(ep.summary)}</span>
          ${ep.auth ? '<span class="docs-lock" title="Requiere autenticacion">&#128274;</span>' : ''}
          ${ep.adminOnly ? '<span class="docs-admin-tag">admin</span>' : ''}
        </div>
        <div id="${id}" class="docs-endpoint-body docs-collapsed">
          <p class="docs-desc">${esc(ep.description)}</p>

          ${ep.auth ? `
          <div class="docs-auth-note">
            <strong>Autenticacion:</strong> Header <code>apikey: &lt;tu_token&gt;</code>
          </div>` : ''}

          ${hasParams ? `
          <h4>Parametros</h4>
          <table class="docs-params-table">
            <thead><tr><th>Nombre</th><th>En</th><th>Requerido</th><th>Descripcion</th></tr></thead>
            <tbody>
              ${ep.params.map(p => `
                <tr>
                  <td><code>${esc(p.name)}</code></td>
                  <td>${esc(p.in)}</td>
                  <td>${p.required ? 'Si' : 'No'}</td>
                  <td>${esc(p.description)}</td>
                </tr>`).join('')}
            </tbody>
          </table>` : ''}

          ${hasBody ? `
          <h4>Request Body</h4>
          <div class="docs-code-block">
            <button class="docs-copy-btn" onclick="App.copyCode(this)" title="Copiar">&#128203;</button>
            <pre>${esc(JSON.stringify(ep.body, null, 2))}</pre>
          </div>` : ''}

          ${hasResponse ? `
          <h4>Response</h4>
          <div class="docs-code-block">
            <button class="docs-copy-btn" onclick="App.copyCode(this)" title="Copiar">&#128203;</button>
            <pre>${esc(JSON.stringify(ep.response, null, 2))}</pre>
          </div>` : ''}

          ${renderCurlExample(ep)}
        </div>
      </div>`;
  }

  function renderCurlExample(ep) {
    const base = window.location.origin;
    let curl = `curl -X ${ep.method} '${base}${ep.path}'`;
    if (ep.auth) {
      curl += ` \\\n  -H 'apikey: TU_TOKEN'`;
    }
    if (ep.body) {
      curl += ` \\\n  -H 'Content-Type: application/json'`;
      curl += ` \\\n  -d '${JSON.stringify(ep.body)}'`;
    }
    return `
      <h4>Ejemplo cURL</h4>
      <div class="docs-code-block docs-curl">
        <button class="docs-copy-btn" onclick="App.copyCode(this)" title="Copiar">&#128203;</button>
        <pre>${esc(curl)}</pre>
      </div>`;
  }

  function toggleDocsGroup(el) {
    const body = el.nextElementSibling;
    const chevron = el.querySelector('.docs-chevron');
    body.classList.toggle('docs-collapsed');
    chevron.classList.toggle('docs-rotated');
  }

  function toggleEndpoint(id) {
    const el = document.getElementById(id);
    el.classList.toggle('docs-collapsed');
  }

  function copyCode(btn) {
    const pre = btn.nextElementSibling;
    navigator.clipboard.writeText(pre.textContent).then(() => {
      btn.textContent = '\u2713';
      setTimeout(() => { btn.innerHTML = '&#128203;'; }, 1500);
    });
  }

  // --- Emoji Picker ---
  function initEmojiPicker() {
    // Event delegation for trigger buttons
    document.addEventListener('click', (e) => {
      const trigger = e.target.closest('.btn-emoji-trigger');
      if (trigger) {
        e.preventDefault();
        e.stopPropagation();
        toggleEmojiPicker(trigger, trigger.dataset.target);
        return;
      }
      // Click on emoji item
      const emojiItem = e.target.closest('.emoji-picker-item');
      if (emojiItem) {
        insertEmojiAtCursor(emojiItem.textContent);
        return;
      }
      // Click on tab
      const tab = e.target.closest('.emoji-picker-tab');
      if (tab) {
        emojiPickerCategory = parseInt(tab.dataset.index);
        $$('.emoji-picker-tab').forEach(t => t.classList.remove('active'));
        tab.classList.add('active');
        renderEmojiGrid();
        return;
      }
      // Click outside closes picker
      const picker = $('#emoji-picker');
      if (!picker.classList.contains('hidden') && !picker.contains(e.target)) {
        closeEmojiPicker();
      }
    });

    // Escape closes picker
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') closeEmojiPicker();
    });

    // Render tabs once
    const tabsContainer = $('#emoji-picker-tabs');
    tabsContainer.innerHTML = EMOJI_DATA.map((cat, i) =>
      `<button type="button" class="emoji-picker-tab${i === 0 ? ' active' : ''}" data-index="${i}" title="${esc(cat.name)}">${cat.icon}</button>`
    ).join('');
  }

  function toggleEmojiPicker(btn, targetId) {
    const picker = $('#emoji-picker');
    if (!picker.classList.contains('hidden') && emojiPickerTarget === targetId) {
      closeEmojiPicker();
      return;
    }
    emojiPickerTarget = targetId;
    emojiPickerCategory = 0;
    $$('.emoji-picker-tab').forEach((t, i) => t.classList.toggle('active', i === 0));
    renderEmojiGrid();
    positionEmojiPicker(btn);
    show(picker);
  }

  function positionEmojiPicker(btn) {
    const picker = $('#emoji-picker');
    const rect = btn.getBoundingClientRect();
    let top = rect.bottom + 4;
    let left = rect.left;

    // Keep within viewport
    const pickerWidth = 280;
    const pickerHeight = 280;
    if (left + pickerWidth > window.innerWidth) {
      left = window.innerWidth - pickerWidth - 8;
    }
    if (left < 4) left = 4;
    if (top + pickerHeight > window.innerHeight) {
      top = rect.top - pickerHeight - 4;
    }

    picker.style.top = top + 'px';
    picker.style.left = left + 'px';
  }

  function closeEmojiPicker() {
    hide($('#emoji-picker'));
    emojiPickerTarget = null;
  }

  function renderEmojiGrid() {
    const grid = $('#emoji-picker-grid');
    const emojis = EMOJI_DATA[emojiPickerCategory].emojis;
    grid.innerHTML = emojis.map(e =>
      `<button type="button" class="emoji-picker-item">${e}</button>`
    ).join('');
  }

  function insertEmojiAtCursor(emoji) {
    if (!emojiPickerTarget) return;
    const textarea = $('#' + emojiPickerTarget);
    if (!textarea) return;
    textarea.focus();
    const start = textarea.selectionStart;
    const end = textarea.selectionEnd;
    const val = textarea.value;
    textarea.value = val.substring(0, start) + emoji + val.substring(end);
    const newPos = start + emoji.length;
    textarea.setSelectionRange(newPos, newPos);
  }

  // --- Text Formatting (WhatsApp style) ---
  function initFormatToolbar() {
    document.addEventListener('click', (e) => {
      const btn = e.target.closest('.btn-format');
      if (!btn) return;
      e.preventDefault();
      const targetId = btn.dataset.target;
      const wrap = btn.dataset.wrap;
      if (targetId && wrap) formatText(targetId, wrap);
    });
  }

  function formatText(targetId, wrap) {
    const textarea = $('#' + targetId);
    if (!textarea) return;
    textarea.focus();
    const start = textarea.selectionStart;
    const end = textarea.selectionEnd;
    const val = textarea.value;
    const selected = val.substring(start, end);

    if (selected) {
      // Wrap selected text
      const replacement = wrap + selected + wrap;
      textarea.value = val.substring(0, start) + replacement + val.substring(end);
      textarea.setSelectionRange(start + wrap.length, start + wrap.length + selected.length);
    } else {
      // Insert wrap chars and place cursor between them
      textarea.value = val.substring(0, start) + wrap + wrap + val.substring(end);
      const cursorPos = start + wrap.length;
      textarea.setSelectionRange(cursorPos, cursorPos);
    }
  }

  // --- Modals ---
  function closeModal(id) {
    hide($('#' + id));
  }

  // --- Escape HTML ---
  function esc(str) {
    const d = document.createElement('div');
    d.textContent = str;
    return d.innerHTML;
  }

  // --- Init ---
  function on(sel, event, handler) {
    const el = $(sel);
    if (el) el.addEventListener(event, handler);
  }

  async function init() {
    // Event listeners
    on('#login-form', 'submit', handleLogin);
    on('#change-password-form', 'submit', handleChangePassword);
    on('#create-instance-form', 'submit', handleCreateInstance);
    on('#send-message-form', 'submit', handleSendMessage);
    on('#bulk-message-form', 'submit', handleBulkMessage);
    on('#bulk-cancel-btn', 'click', () => {
      API.cancelBulk();
      $('#bulk-cancel-btn').disabled = true;
      $('#bulk-cancel-btn').textContent = 'Cancelando...';
    });
    on('#create-template-form', 'submit', handleCreateTemplate);
    on('#edit-template-form', 'submit', handleUpdateTemplate);
    on('#create-contact-list-form', 'submit', handleCreateContactList);
    on('#bulk-load-contacts-btn', 'click', openLoadContactsModal);
    handleTemplateSelect('#msg-template', '#msg-text');
    handleTemplateSelect('#bulk-template', '#bulk-text');
    on('#hist-filter-btn', 'click', () => { historyPage = 1; loadHistory(); });
    on('#audit-filter-btn', 'click', () => { auditPage = 1; loadAuditLogs(); });
    on('#backup-create-btn', 'click', handleCreateBackup);
    on('#btn-theme-toggle', 'click', toggleTheme);
    initEmojiPicker();
    initFormatToolbar();
    on('#create-user-form', 'submit', handleCreateUser);
    on('#edit-user-form', 'submit', handleUpdateUser);
    on('#create-incident-form', 'submit', handleCreateIncident);
    on('#incident-update-form', 'submit', handleIncidentUpdate);
    on('#create-maintenance-form', 'submit', handleCreateMaintenance);
    on('#btn-logout', 'click', logout);
    initTheme();

    $$('.nav-link').forEach(link => {
      link.addEventListener('click', (e) => {
        e.preventDefault();
        navigate(link.dataset.section);
      });
    });

    $$('.modal-close').forEach(btn => {
      btn.addEventListener('click', () => {
        closeModal(btn.closest('.modal').id);
      });
    });

    // Check existing session
    const token = API.getToken();
    if (token) {
      try {
        const data = await API.getProfile();
        currentUser = data.user;
        if (currentUser.must_change_password) {
          showChangePassword();
        } else {
          showApp();
        }
      } catch {
        API.clearSession();
        showLogin();
      }
    } else {
      showLogin();
    }
  }

  document.addEventListener('DOMContentLoaded', init);

  return {
    connectInstance,
    confirmDeleteInstance,
    editTemplate,
    confirmDeleteTemplate,
    loadContactLists,
    viewContactList,
    renameContactList,
    confirmDeleteContactList,
    removeContactItem,
    openLoadContactsModal,
    loadContactsIntoNumbers,
    setMsgType,
    goHistoryPage,
    revokeSessionAction,
    goAuditPage,
    showAuditDetail,
    editUser,
    confirmDeleteUser,
    openIncidentUpdate,
    confirmDeleteIncident,
    startMaintenance,
    completeMaintenance,
    confirmDeleteMaintenance,
    handleCreateTemplate,
    closeModal,
    toggleDocsGroup,
    toggleEndpoint,
    copyCode,
  };
})();
