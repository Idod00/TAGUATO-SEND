// TAGUATO-SEND Panel Application
const App = (() => {
  let currentUser = null;
  let instances = [];
  let dashboardTimer = null;

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
    if (section === 'docs') renderDocs();
    if (section === 'admin') loadUsers();
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
    if (currentUser.role === 'admin') {
      show(adminNav);
      show(statusNav);
      show(dashboardNav);
    } else {
      hide(adminNav);
      hide(statusNav);
      hide(dashboardNav);
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

  async function handleSendMessage(e) {
    e.preventDefault();
    const instanceName = $('#msg-instance').value;
    const number = $('#msg-number').value.trim();
    const text = $('#msg-text').value.trim();
    if (!instanceName || !number || !text) {
      showToast('Completa todos los campos', 'error');
      return;
    }
    const btn = $('#msg-send-btn');
    btn.disabled = true;
    try {
      await API.sendText(instanceName, number, text);
      showToast('Mensaje enviado');
      $('#msg-text').value = '';
    } catch (err) {
      showToast(err.message || 'Error al enviar', 'error');
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
    } catch (err) {
      cardsContainer.innerHTML = '<div class="empty">Error al cargar dashboard</div>';
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
            <th>ID</th><th>Usuario</th><th>Rol</th><th>Max Inst.</th><th>Activo</th><th>Acciones</th>
          </tr>
        </thead>
        <tbody>
          ${users.map(u => `
            <tr>
              <td>${u.id}</td>
              <td>${esc(u.username)}</td>
              <td><span class="badge badge-${u.role === 'admin' ? 'admin' : 'user'}">${u.role}</span></td>
              <td>${u.max_instances}</td>
              <td>${u.is_active ? 'Si' : 'No'}</td>
              <td>
                <button class="btn btn-sm btn-secondary" onclick="App.editUser(${u.id}, '${esc(u.username)}', '${u.role}', ${u.max_instances}, ${u.is_active})">Editar</button>
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
    if (!username || !password) {
      showToast('Username y password son requeridos', 'error');
      return;
    }
    try {
      await API.createUser(username, password, role, maxInst);
      showToast('Usuario creado');
      $('#new-user-name').value = '';
      $('#new-user-pass').value = '';
      $('#new-user-max').value = '1';
      loadUsers();
    } catch (err) {
      showToast(err.message || 'Error al crear usuario', 'error');
    }
  }

  function editUser(id, username, role, maxInstances, isActive) {
    const modal = $('#edit-user-modal');
    $('#edit-user-id').value = id;
    $('#edit-user-title').textContent = 'Editar: ' + username;
    $('#edit-user-role').value = role;
    $('#edit-user-max').value = maxInstances;
    $('#edit-user-active').checked = isActive;
    $('#edit-user-pass').value = '';
    show(modal);
  }

  async function handleUpdateUser(e) {
    e.preventDefault();
    const id = $('#edit-user-id').value;
    const fields = {
      role: $('#edit-user-role').value,
      max_instances: parseInt($('#edit-user-max').value) || 1,
      is_active: $('#edit-user-active').checked,
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
  async function init() {
    // Event listeners
    $('#login-form').addEventListener('submit', handleLogin);
    $('#change-password-form').addEventListener('submit', handleChangePassword);
    $('#create-instance-form').addEventListener('submit', handleCreateInstance);
    $('#send-message-form').addEventListener('submit', handleSendMessage);
    $('#bulk-message-form').addEventListener('submit', handleBulkMessage);
    $('#bulk-cancel-btn').addEventListener('click', () => {
      API.cancelBulk();
      $('#bulk-cancel-btn').disabled = true;
      $('#bulk-cancel-btn').textContent = 'Cancelando...';
    });
    $('#create-user-form').addEventListener('submit', handleCreateUser);
    $('#edit-user-form').addEventListener('submit', handleUpdateUser);
    $('#create-incident-form').addEventListener('submit', handleCreateIncident);
    $('#incident-update-form').addEventListener('submit', handleIncidentUpdate);
    $('#create-maintenance-form').addEventListener('submit', handleCreateMaintenance);
    $('#btn-logout').addEventListener('click', logout);

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
    editUser,
    confirmDeleteUser,
    openIncidentUpdate,
    confirmDeleteIncident,
    startMaintenance,
    completeMaintenance,
    confirmDeleteMaintenance,
    closeModal,
    toggleDocsGroup,
    toggleEndpoint,
    copyCode,
  };
})();
