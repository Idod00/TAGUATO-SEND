// TAGUATO-SEND Panel Application
const App = (() => {
  let currentUser = null;
  let instances = [];

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

    if (section === 'instances') loadInstances();
    if (section === 'messages') loadInstanceSelect();
    if (section === 'docs') renderDocs();
    if (section === 'admin') loadUsers();
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
    if (currentUser.role === 'admin') {
      show(adminNav);
    } else {
      hide(adminNav);
    }
    navigate('instances');
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
  function loadInstanceSelect() {
    const sel = $('#msg-instance');
    sel.innerHTML = '<option value="">Seleccionar instancia...</option>';
    instances.forEach(inst => {
      const name = inst.instance?.instanceName || inst.name || inst.instanceName || '';
      if (name) {
        sel.innerHTML += `<option value="${esc(name)}">${esc(name)}</option>`;
      }
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
    $('#create-user-form').addEventListener('submit', handleCreateUser);
    $('#edit-user-form').addEventListener('submit', handleUpdateUser);
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
    closeModal,
    toggleDocsGroup,
    toggleEndpoint,
    copyCode,
  };
})();
