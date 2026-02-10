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

  // Templates
  async function listTemplates() {
    return await request('GET', '/api/templates');
  }

  async function createTemplate(name, content) {
    return await request('POST', '/api/templates', { name, content });
  }

  async function updateTemplate(id, fields) {
    return await request('PUT', '/api/templates/' + id, fields);
  }

  async function deleteTemplate(id) {
    return await request('DELETE', '/api/templates/' + id);
  }

  // Contacts
  async function listContactLists() {
    return await request('GET', '/api/contacts');
  }

  async function getContactList(id) {
    return await request('GET', '/api/contacts/' + id);
  }

  async function createContactList(name) {
    return await request('POST', '/api/contacts', { name });
  }

  async function updateContactList(id, name) {
    return await request('PUT', '/api/contacts/' + id, { name });
  }

  async function deleteContactList(id) {
    return await request('DELETE', '/api/contacts/' + id);
  }

  async function addContactItems(listId, items) {
    return await request('POST', '/api/contacts/' + listId + '/items', { items });
  }

  async function deleteContactItem(listId, itemId) {
    return await request('DELETE', '/api/contacts/' + listId + '/items/' + itemId);
  }

  // Sessions
  async function listSessions() {
    return await request('GET', '/api/sessions');
  }

  async function revokeSession(id) {
    return await request('DELETE', '/api/sessions/' + id);
  }

  async function listAllSessions() {
    return await request('GET', '/admin/sessions');
  }

  async function revokeAnySession(id) {
    return await request('DELETE', '/admin/sessions/' + id);
  }

  // Media
  async function sendMedia(instanceName, number, mediatype, media, caption, fileName) {
    const body = { number, mediatype, media };
    if (caption) body.caption = caption;
    if (fileName) body.fileName = fileName;
    return await request('POST', '/message/sendMedia/' + instanceName, body);
  }

  // Message Logs
  async function logMessage(instanceName, phoneNumber, messageType, status, errorMessage) {
    return await request('POST', '/api/messages/log', {
      instance_name: instanceName,
      phone_number: phoneNumber,
      message_type: messageType,
      status,
      error_message: errorMessage,
    });
  }

  async function getMessageLogs(params) {
    const qs = new URLSearchParams(params).toString();
    return await request('GET', '/api/messages/log' + (qs ? '?' + qs : ''));
  }

  // Dashboard
  async function getDashboard() {
    return await request('GET', '/admin/dashboard');
  }

  // Bulk messaging
  let bulkCancelled = false;

  function cancelBulk() {
    bulkCancelled = true;
  }

  async function sendBulkText(instanceName, numbers, text, onProgress) {
    bulkCancelled = false;
    const results = [];
    for (let i = 0; i < numbers.length; i++) {
      if (bulkCancelled) {
        // Mark remaining as skipped
        for (let j = i; j < numbers.length; j++) {
          results.push({ number: numbers[j].trim(), status: 'cancelled' });
        }
        if (onProgress) onProgress(numbers.length, results);
        break;
      }
      const number = numbers[i].trim();
      if (!number) {
        results.push({ number, status: 'skipped' });
        if (onProgress) onProgress(i + 1, results);
        continue;
      }
      try {
        await sendText(instanceName, number, text);
        results.push({ number, status: 'sent' });
      } catch (err) {
        results.push({ number, status: 'failed', error: err.message || 'Error' });
      }
      if (onProgress) onProgress(i + 1, results);
      // 500ms delay between sends
      if (i < numbers.length - 1) {
        await new Promise(r => setTimeout(r, 500));
      }
    }
    return results;
  }

  // Admin
  async function listUsers() {
    return await request('GET', '/admin/users');
  }

  async function createUser(username, password, role, maxInstances, rateLimit) {
    const body = { username, password, role, max_instances: maxInstances };
    if (rateLimit !== null && rateLimit !== undefined) body.rate_limit = rateLimit;
    return await request('POST', '/admin/users', body);
  }

  async function updateUser(id, fields) {
    return await request('PUT', '/admin/users/' + id, fields);
  }

  async function deleteUser(id) {
    return await request('DELETE', '/admin/users/' + id);
  }

  // Status & Incidents
  async function getPublicStatus() {
    const res = await fetch('/api/status');
    return await res.json();
  }

  async function listIncidents() {
    return await request('GET', '/admin/incidents');
  }

  async function listIncidentServices() {
    return await request('GET', '/admin/incidents/services');
  }

  async function createIncident(title, severity, status, message, serviceIds) {
    return await request('POST', '/admin/incidents', {
      title,
      severity,
      status,
      message,
      service_ids: serviceIds,
    });
  }

  async function addIncidentUpdate(incidentId, status, message) {
    return await request('POST', '/admin/incidents/' + incidentId + '/updates', {
      status,
      message,
    });
  }

  async function updateIncident(id, fields) {
    return await request('PUT', '/admin/incidents/' + id, fields);
  }

  async function deleteIncident(id) {
    return await request('DELETE', '/admin/incidents/' + id);
  }

  // Maintenance
  async function listMaintenances() {
    return await request('GET', '/admin/maintenance');
  }

  async function createMaintenance(title, description, scheduledStart, scheduledEnd, serviceIds) {
    return await request('POST', '/admin/maintenance', {
      title,
      description,
      scheduled_start: scheduledStart,
      scheduled_end: scheduledEnd,
      service_ids: serviceIds,
    });
  }

  async function updateMaintenance(id, fields) {
    return await request('PUT', '/admin/maintenance/' + id, fields);
  }

  async function deleteMaintenance(id) {
    return await request('DELETE', '/admin/maintenance/' + id);
  }

  return {
    getToken, getStoredUser, setSession, clearSession,
    login, logout, getProfile, changePassword,
    fetchInstances, createInstance, deleteInstance, connectInstance, getInstanceStatus,
    sendText, sendMedia, sendBulkText, cancelBulk,
    logMessage, getMessageLogs,
    listTemplates, createTemplate, updateTemplate, deleteTemplate,
    listContactLists, getContactList, createContactList, updateContactList, deleteContactList,
    addContactItems, deleteContactItem,
    listSessions, revokeSession, listAllSessions, revokeAnySession,
    getDashboard,
    listUsers, createUser, updateUser, deleteUser,
    getPublicStatus, listIncidents, listIncidentServices,
    createIncident, addIncidentUpdate, updateIncident, deleteIncident,
    listMaintenances, createMaintenance, updateMaintenance, deleteMaintenance,
  };
})();
