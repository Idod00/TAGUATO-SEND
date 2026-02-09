// API Client for TAGUATO-SEND Panel
const API = (() => {
  function getToken() {
    return localStorage.getItem('taguato_token');
  }

  function setSession(token, user) {
    localStorage.setItem('taguato_token', token);
    localStorage.setItem('taguato_user', JSON.stringify(user));
  }

  function clearSession() {
    localStorage.removeItem('taguato_token');
    localStorage.removeItem('taguato_user');
  }

  function getStoredUser() {
    try {
      return JSON.parse(localStorage.getItem('taguato_user'));
    } catch {
      return null;
    }
  }

  async function request(method, path, body) {
    const headers = { 'Content-Type': 'application/json' };
    const token = getToken();
    if (token) {
      headers['apikey'] = token;
    }
    const opts = { method, headers };
    if (body) {
      opts.body = JSON.stringify(body);
    }
    const res = await fetch(path, opts);
    const data = await res.json();
    if (!res.ok) {
      throw { status: res.status, message: data.error || 'Request failed' };
    }
    return data;
  }

  // Auth
  async function login(username, password) {
    const data = await request('POST', '/api/auth/login', { username, password });
    setSession(data.token, data.user);
    return data;
  }

  async function getProfile() {
    return await request('GET', '/api/auth/me');
  }

  async function changePassword(currentPassword, newPassword) {
    return await request('POST', '/api/auth/change-password', {
      current_password: currentPassword,
      new_password: newPassword,
    });
  }

  function logout() {
    clearSession();
  }

  // Instances
  async function fetchInstances() {
    return await request('GET', '/instance/fetchInstances');
  }

  async function createInstance(instanceName) {
    return await request('POST', '/instance/create', {
      instanceName,
      integration: 'WHATSAPP-BAILEYS',
    });
  }

  async function deleteInstance(instanceName) {
    return await request('DELETE', '/instance/delete/' + instanceName);
  }

  async function connectInstance(instanceName) {
    return await request('GET', '/instance/connect/' + instanceName);
  }

  async function getInstanceStatus(instanceName) {
    return await request('GET', '/instance/connectionState/' + instanceName);
  }

  // Messages
  async function sendText(instanceName, number, text) {
    return await request('POST', '/message/sendText/' + instanceName, {
      number,
      text,
    });
  }

  // Admin
  async function listUsers() {
    return await request('GET', '/admin/users');
  }

  async function createUser(username, password, role, maxInstances) {
    return await request('POST', '/admin/users', {
      username,
      password,
      role,
      max_instances: maxInstances,
    });
  }

  async function updateUser(id, fields) {
    return await request('PUT', '/admin/users/' + id, fields);
  }

  async function deleteUser(id) {
    return await request('DELETE', '/admin/users/' + id);
  }

  return {
    getToken, getStoredUser, setSession, clearSession,
    login, logout, getProfile, changePassword,
    fetchInstances, createInstance, deleteInstance, connectInstance, getInstanceStatus,
    sendText,
    listUsers, createUser, updateUser, deleteUser,
  };
})();
